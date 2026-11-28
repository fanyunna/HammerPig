extends SubViewport
class_name Pig3D

## 程序化生成的 3D 小猪存钱罐：一个 SubViewport 装一只，main.gd 的 _draw() 把纹理贴到 pig.position。
## 本机没有 Blender，也没有外部 .glb，全部用 Godot 内置图元（球体 / 圆柱 / 方块 / 圆环）拼装。
## 造型要点：陶瓷釉面材质（clearcoat）、圆胖罐体、顶部投币口 + 露出的金币、短鼻小耳短腿、卷尾巴。
## headless 下渲染驱动是 dummy（纹理无像素），main.gd 会自动回退 2D 自绘，不影响冒烟测试。

## 纹理分辨率。小猪在屏幕上约 92px；192px 视口让鼻孔、眼睛和陶瓷高光缩放后仍清楚。
## 24 只 × 192² 约 0.88M 像素/帧，保持在可控范围内。
const VIEW_SIZE := 192

var _root3d: Node3D
var _body: MeshInstance3D
var _body_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D # 鼻 / 耳 / 腿 / 尾：整体换色时一起换，否则会出现粉鼻金身
var _eye_mat: StandardMaterial3D # 眼珠（催债猪靠一双红眼来警告）
var _blush_mat: StandardMaterial3D # 腮红
var _coin: MeshInstance3D # 投币口上插着的那枚币
var _inner: Node3D # 罐子里攒着的那一堆钱（玻璃猪才看得见）
var _hat: Node3D # 西部牛仔帽（pig_types 里 "hat": true 才显示）
var _bandana: Node3D # 红三角巾（"bandana": true）
var _star: Node3D # 胸前警长星（"star": true）
var _body_base_scale := Vector3(1.13, 0.99, 1.04) # 轻微不对称，手工陶器不会是完美椭球
static var _grain_tex: ImageTexture # 釉面颗粒法线贴图（8 只猪共用一份）
var _base_color := Color("#f7c2bf") # 陶瓷粉
var _hurt_color := Color("#d98f95") # 裂了以后暗一号


func _ready() -> void:
	size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	own_world_3d = true # 关键：父节点是 2D，必须自带 3D 世界才会渲染
	_build_scene()


func _build_scene() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.9
	cam.position = Vector3(0.0, 4.7, 3.0) # 约 58° 俯视：从玩家敲击方向看见猪背、鼻子和投币口
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.08, 0.0))
	cam.current = true
	add_child(cam)

	# 注意：节点还没入树，必须用 look_at_from_position（look_at 会报 "Node not inside tree"）
	var key := DirectionalLight3D.new()
	key.position = Vector3(2.0, 3.0, 4.0)
	key.look_at_from_position(key.position, Vector3.ZERO)
	key.light_energy = 1.25
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.position = Vector3(-3.0, -1.0, 2.0)
	fill.look_at_from_position(fill.position, Vector3.ZERO)
	fill.light_energy = 0.5
	add_child(fill)

	_root3d = Node3D.new()
	_root3d.position = Vector3(0.0, -0.05, 0.0)
	add_child(_root3d)
	_build_bank(_root3d)


## 釉面颗粒：用 simplex 噪声的梯度现场算一张法线贴图，让表面不再是完美光滑的塑料感
func _grain_texture() -> ImageTexture:
	if _grain_tex != null:
		return _grain_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.09
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var strength := 1.5 # 越大颗粒越明显；太大会像毛绒/砂纸，失去瓷感
	for y in range(size):
		for x in range(size):
			var h := n.get_noise_2d(float(x), float(y))
			var nx := -(n.get_noise_2d(float(x + 1), float(y)) - h) * strength
			var ny := -(n.get_noise_2d(float(x), float(y + 1)) - h) * strength
			var inv := 1.0 / sqrt(nx * nx + ny * ny + 1.0)
			img.set_pixel(x, y, Color(nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, inv * 0.5 + 0.5))
	_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex


## 哑光釉面：这是一只陶土烧出来的存钱罐，不是电镀的。
## clearcoat 是那道晃眼的清漆高光，metallic_specular 是镜面反射强度 —— 两者都压到最低，
## 只留一点点柔和的漫反射高光和边缘补光（rim），否则哑光之后物体会"糊"进背景里失去体积。
func _ceramic(color: Color, rough := 0.62, grain := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.0 # 陶土没有金属：metallic 一上去就变成"镀了一层金属漆"
	m.roughness = rough
	m.metallic_specular = 0.16
	m.clearcoat = 0.0
	m.clearcoat_roughness = 1.0
	m.rim = 0.07 # 边缘补光：哑光材质靠它把轮廓从背景里拉出来
	m.rim_tint = 0.55
	if grain:
		m.normal_enabled = true
		m.normal_texture = _grain_texture()
		m.normal_scale = 0.28 # 轻微起伏即可，不能盖过釉面高光
		m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return m


## 玻璃罐身：半透明 + 露出里面攒的钱。透明 ≠ 金属反光，光泽靠低 roughness，不靠 metallic
func _glassify(m: StandardMaterial3D, alpha: float) -> void:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = alpha
	m.roughness = 0.18
	m.metallic = 0.0
	m.metallic_specular = 0.1
	m.rim = 0.12 # 玻璃的边缘更亮一点，才像玻璃而不是像雾
	m.normal_enabled = false # 陶土颗粒会把玻璃糊成磨砂，里面的钱就看不见了


## 搪瓷条纹：现场画一张双色条纹贴图，按颜色组合缓存（同一套颜色只生成一次）
static var _stripe_cache: Dictionary

func _stripe_texture(base: Color, stripe: Color) -> ImageTexture:
	var key := base.to_html(false) + "_" + stripe.to_html(false)
	if _stripe_cache.has(key):
		return _stripe_cache[key]
	var size := 128
	var band := 16 # 条纹宽度（像素）：128/16 = 8 段
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, stripe if (x / band) % 2 == 0 else base)
	var tex := ImageTexture.create_from_image(img)
	_stripe_cache[key] = tex
	return tex


## 罐子里攒的钱：一堆歪歪斜斜塞进去的硬币。只有玻璃罐会把它显示出来 —— 一眼看得见里面有货，
## 所以它最诱人；代价是它一锤就碎（碎得快，但你也留不住它）。
func _build_inner_coins(parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.visible = false
	parent.add_child(holder)
	var mat := _ceramic(Color("#eab948"), 0.45, false)
	# 一点点自发光：隔着半透明的罐壁也看得见里面有钱。这不是"反光"，是让暗部的硬币不发灰
	mat.emission_enabled = true
	mat.emission = Color("#7a5a18")
	mat.emission_energy_multiplier = 1.0
	for i in range(9):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.19
		cm.bottom_radius = 0.19
		cm.height = 0.05
		cm.radial_segments = 14
		# 塞在罐子中下部（不是最底）：贴底会被腿和阴影吃掉，看不见就等于白做
		var c := _part(holder, cm, mat, Vector3(
			randf_range(-0.26, 0.26), -0.18 + float(i) * 0.075, randf_range(-0.15, 0.15)))
		c.rotation = Vector3(randf_range(-0.3, 0.3), randf(), randf_range(-0.3, 0.3))
	return holder


func _part(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


func _build_bank(parent: Node3D) -> void:
	_body_mat = _ceramic(_base_color)
	_accent_mat = _ceramic(_hurt_color) # 鼻 / 耳 / 腿 / 尾
	var dark := _accent_mat
	_eye_mat = _ceramic(Color("#2f2a29"), 0.15, false) # 眼珠光滑
	_blush_mat = _ceramic(Color("#f2a0a4"), 0.3)
	var slot_mat := _ceramic(Color("#5a4a48"), 0.55)
	var gold_mat := _ceramic(Color("#e0b552"), 0.4, false) # 金币也别做成电镀的：哑光黄铜，靠颜色认出是钱
	_inner = _build_inner_coins(parent) # 只有玻璃罐才把它打开

	# 罐体：按参考图做成更矮、更宽的圆润存钱罐轮廓
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 1.0
	body_mesh.height = 1.72
	body_mesh.radial_segments = 32
	body_mesh.rings = 20
	_body_base_scale = Vector3(1.19, 0.90, 1.04)
	_body = _part(parent, body_mesh, _body_mat, Vector3(0.0, 0.03, 0.0), _body_base_scale)

	# 顶部投币口：细长凹槽（存钱罐的标志）
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(0.58, 0.1, 0.2)
	_part(parent, slot_mesh, slot_mat, Vector3(0.0, 0.93, 0.1))

	# 投币口上插着的硬币：一眼看出是存钱罐
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.23
	coin_mesh.bottom_radius = 0.23
	coin_mesh.height = 0.05
	coin_mesh.radial_segments = 22
	_coin = _part(parent, coin_mesh, gold_mat, Vector3(0.02, 1.03, 0.1)) # 催债猪要把它藏起来：它不是存钱罐
	_coin.rotation = Vector3(PI / 2.0, 0.0, 0.26)

	# 猪鼻：宽圆鼻盘，朝向镜头；两枚深色鼻孔用椭圆陶瓷点表现
	var snout_mesh := SphereMesh.new()
	snout_mesh.radius = 0.34
	snout_mesh.height = 0.40
	snout_mesh.radial_segments = 24
	var snout := _part(parent, snout_mesh, _accent_mat, Vector3(0.0, -0.10, 1.00), Vector3(1.0, 0.82, 0.52))
	# 鼻盘外沿加一圈浅浮雕，缩小到游戏尺寸后仍能和脸部分开
	var snout_rim_mesh := TorusMesh.new()
	snout_rim_mesh.inner_radius = 0.27
	snout_rim_mesh.outer_radius = 0.32
	snout_rim_mesh.rings = 12
	snout_rim_mesh.ring_segments = 24
	var snout_rim := _part(parent, snout_rim_mesh, _body_mat, Vector3(0.0, -0.10, 1.19), Vector3(1.0, 0.82, 0.5))
	snout_rim.rotation.x = PI / 2.0
	for i in range(2):
		var hole_mesh := SphereMesh.new()
		hole_mesh.radius = 0.065
		hole_mesh.height = 0.11
		_part(parent, hole_mesh, _eye_mat, Vector3(-0.13 + 0.26 * float(i), -0.10, 1.22), Vector3(0.72, 1.0, 0.7))

	# 耳朵：压扁的小球，立在头顶两侧
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var ear_mesh := SphereMesh.new()
		ear_mesh.radius = 0.24
		ear_mesh.height = 0.48
		var ear := _part(parent, ear_mesh, _body_mat, Vector3(0.62 * side, 0.62, 0.02), Vector3(0.88, 1.18, 0.48))
		ear.rotation.z = -0.42 * side
		ear.rotation.y = 0.3 * side
		var inner_ear_mesh := SphereMesh.new()
		inner_ear_mesh.radius = 0.13
		inner_ear_mesh.height = 0.30
		var inner_ear := _part(parent, inner_ear_mesh, _accent_mat, Vector3(0.62 * side, 0.65, 0.205), Vector3(0.72, 1.0, 0.26))
		inner_ear.rotation.z = -0.42 * side

	# 四条短粗小猪腿：腿根埋进圆罐体，露出圆润的小蹄子
	for i in range(4):
		var sx := -0.62 if i % 2 == 0 else 0.62
		var sz := -0.43 if i < 2 else 0.43
		var leg_mesh := SphereMesh.new()
		leg_mesh.radius = 0.22
		leg_mesh.height = 0.38
		_part(parent, leg_mesh, _accent_mat, Vector3(sx, -0.64, sz), Vector3(0.88, 1.0, 0.9))
		var hoof_mesh := SphereMesh.new()
		hoof_mesh.radius = 0.17
		hoof_mesh.height = 0.14
		_part(parent, hoof_mesh, dark, Vector3(sx, -0.79, sz + 0.015), Vector3(0.94, 0.55, 0.9))

	# 眼睛：釉面黑点 + 一点高光白
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.085
		eye_mesh.height = 0.17
		_part(parent, eye_mesh, _eye_mat, Vector3(0.34 * side, 0.25, 0.90))
		var gl_mesh := SphereMesh.new()
		gl_mesh.radius = 0.03
		gl_mesh.height = 0.06
		var glint := _ceramic(Color.WHITE, 0.05, false)
		_part(parent, gl_mesh, glint, Vector3(0.37 * side, 0.29, 0.95))

	# 腮红：两片贴在脸颊上的粉，强化"猪"的辨识
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var blush_mesh := SphereMesh.new()
		blush_mesh.radius = 0.12
		blush_mesh.height = 0.22
		var cheek_mesh := SphereMesh.new()
		cheek_mesh.radius = 0.21
		cheek_mesh.height = 0.32
		_part(parent, cheek_mesh, _body_mat, Vector3(0.54 * side, -0.08, 0.72), Vector3(1.0, 0.9, 0.42))
		_part(parent, blush_mesh, _blush_mat, Vector3(0.64 * side, -0.12, 0.76), Vector3(1.0, 0.75, 0.3))

	# 卷尾巴：立在屁股后面的小圆环
	var tail_mesh := TorusMesh.new()
	tail_mesh.inner_radius = 0.09
	tail_mesh.outer_radius = 0.16
	tail_mesh.rings = 12
	tail_mesh.ring_segments = 14
	var tail := _part(parent, tail_mesh, dark, Vector3(0.0, 0.24, -1.0))
	tail.rotation = Vector3(0.1, 0.0, 0.7)

	_build_western(parent) # 西部配件一次建好、默认全藏，apply_type 按种类开关


## 西部酒馆配件：牛仔帽、红三角巾、警长星。每只猪都在 _build_bank 里建好一份存成成员变量，
## 默认隐藏；apply_type 按 pig_types 的布尔键（hat / bandana / star）开关 —— 换种类不重建网格。
func _build_western(parent: Node3D) -> void:
	var leather := _ceramic(Color("#8a5a2e"), 0.9, false) # 帽子的粗糙皮革
	var leather_dark := _ceramic(Color("#5d3b1e"), 0.9, false) # 帽带
	var fabric := _ceramic(Color("#b8322a"), 0.85, false) # 三角巾红布
	var star_gold := _ceramic(Color("#e0b552"), 0.35, false) # 警长星：哑光黄铜

	# 牛仔帽：压扁球帽冠 + 扁圆柱帽檐 + 一圈帽带，歪一点扣在头顶
	_hat = Node3D.new()
	_hat.visible = false
	_hat.position = Vector3(-0.08, 0.90, -0.24) # 稍往后靠，给鼻子留出生位
	_hat.rotation = Vector3(-0.12, 0.0, 0.16) # 牛仔帽要歪一点才有味道
	parent.add_child(_hat)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.34
	crown_mesh.height = 0.56
	_part(_hat, crown_mesh, leather, Vector3(0.0, 0.16, 0.0), Vector3(1.0, 0.82, 1.0))
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.58
	brim_mesh.bottom_radius = 0.58
	brim_mesh.height = 0.055
	brim_mesh.radial_segments = 28
	_part(_hat, brim_mesh, leather, Vector3(0.0, 0.02, 0.0))
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 0.30
	band_mesh.outer_radius = 0.36
	band_mesh.rings = 10
	band_mesh.ring_segments = 24
	var band := _part(_hat, band_mesh, leather_dark, Vector3(0.0, 0.06, 0.0))
	band.rotation.x = PI / 2.0 # 平放，箍在帽冠根部

	# 红三角巾：鼻子下方绕脖子一圈，前头垂一个尖角
	_bandana = Node3D.new()
	_bandana.visible = false
	parent.add_child(_bandana)
	var neck_mesh := TorusMesh.new()
	neck_mesh.inner_radius = 0.78
	neck_mesh.outer_radius = 0.95
	neck_mesh.rings = 12
	neck_mesh.ring_segments = 28
	var neck := _part(_bandana, neck_mesh, fabric, Vector3(0.0, -0.30, 0.12), Vector3(1.18, 1.0, 1.04))
	neck.rotation.x = PI / 2.0 - 0.25 # 平放再前倾，贴着圆罐体的弧线
	var knot_mesh := CylinderMesh.new()
	knot_mesh.top_radius = 0.0
	knot_mesh.bottom_radius = 0.13
	knot_mesh.height = 0.34
	knot_mesh.radial_segments = 12
	var knot := _part(_bandana, knot_mesh, fabric, Vector3(0.0, -0.50, 0.80), Vector3(1.0, 1.0, 0.5))
	knot.rotation.x = PI # 尖角朝下：三角巾打结后垂下来的那个角

	# 警长星：中心小圆 + 五个小锥体拼出五角星，整体压扁贴在胸口弧面上
	_star = Node3D.new()
	_star.visible = false
	_star.position = Vector3(0.0, -0.38, 0.92)
	_star.rotation.x = -0.42 # 顺着胸口弧度往后仰
	_star.scale = Vector3(1.0, 1.0, 0.4) # 压扁：锥体截面成椭圆，像徽章贴在身上
	parent.add_child(_star)
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.10
	hub_mesh.height = 0.20
	_part(_star, hub_mesh, star_gold, Vector3.ZERO)
	for i in range(5):
		var a := PI / 2.0 + float(i) * TAU / 5.0 # 第一个角指向正上方
		var spike_mesh := CylinderMesh.new()
		spike_mesh.top_radius = 0.0
		spike_mesh.bottom_radius = 0.055
		spike_mesh.height = 0.24
		spike_mesh.radial_segments = 10
		var spike := _part(_star, spike_mesh, star_gold, Vector3(cos(a) * 0.20, sin(a) * 0.20, 0.0))
		spike.rotation.z = a - PI / 2.0 # 锥轴从 +y 转到该角的方向

## 换一身皮：猪重生时会换种类，重建整只太贵（还要重新生成网格），这里只改材质与整体缩放。
## t 是 balance.json 里 pig_types 的一项（空字典 = 用默认的陶瓷粉小猪）。
func apply_type(t: Dictionary) -> void:
	var id := String(t.get("id", "piggy"))
	_base_color = _color(t, "color", "#f7c2bf")
	# 玻璃罐的透明度要写进 _base_color：update_visual 每帧都拿 _base_color 覆盖材质颜色，
	# 只改材质的话第一帧之后就被刷回不透明了
	_base_color.a = float(t.get("alpha", 0.42)) if bool(t.get("glass", false)) else 1.0
	_hurt_color = _base_color.darkened(0.28)
	_body_mat.albedo_color = _base_color
	_body_mat.roughness = float(t.get("rough", 0.62))
	_accent_mat.albedo_color = _color(t, "accent", "#e79aa0")
	_eye_mat.albedo_color = _color(t, "eye", "#2f2a29")
	_blush_mat.albedo_color = _color(t, "blush", "#f2a0a4")
	_root3d.scale = Vector3.ONE * float(t.get("scale", 1.0))

	if bool(t.get("striped", false)): # 搪瓷条纹：贴图乘在底色上，所以贴图里两种颜色都给全
		_body_mat.albedo_texture = _stripe_texture(_base_color, _color(t, "stripe", "#4f7d8c"))
		_body_mat.uv1_scale = Vector3(3.0, 1.2, 1.2) # 横向拉密一点才是条纹，不是色块
	else:
		_body_mat.albedo_texture = null
		_body_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)

	if bool(t.get("glass", false)):
		_glassify(_body_mat, float(t.get("alpha", 0.42)))
	else:
		_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_body_mat.albedo_color.a = 1.0
		_body_mat.metallic_specular = 0.16
		_body_mat.rim = 0.07
	if _inner != null:
		_inner.visible = bool(t.get("glass", false))
	if _coin != null:
		_coin.visible = id != "debt" and not bool(t.get("hat", false)) # 催债猪不插币；牛仔帽会盖住投币口
	if _hat != null:
		_hat.visible = bool(t.get("hat", false))
	if _bandana != null:
		_bandana.visible = bool(t.get("bandana", false))
	if _star != null:
		_star.visible = bool(t.get("star", false))

	# 转盘金猪：金色低粗糙度 + 自发光，和普通陶瓷猪一眼区分（视口复用时也要能关掉）
	if bool(t.get("glow", false)):
		_body_mat.emission_enabled = true
		_body_mat.emission = Color("#a87c14")
		_body_mat.emission_energy_multiplier = 1.1
		_body_mat.metallic = 0.45
		_body_mat.roughness = 0.3
		_body_mat.rim = 0.32
		_body_mat.rim_tint = 0.3
	else:
		_body_mat.emission_enabled = false
		_body_mat.metallic = 0.0


func _color(t: Dictionary, key: String, fallback: String) -> Color:
	var raw: Variant = t.get(key, fallback) # 不能用 := 推断：Dictionary.get 返回 Variant，会被当成警告（本项目警告即错误）
	return Color(String(raw)) if typeof(raw) != TYPE_COLOR else raw


## 每帧刷新：呼吸起伏、受伤变色、被打闪白、朝向随游走速度偏转
func update_visual(pig: Dictionary, elapsed: float) -> void:
	var seed_v := float(pig.seed)
	var breath := 1.0 + 0.04 * sin(elapsed * 2.2 + seed_v)
	_body.scale = _body_base_scale * Vector3(1.0, breath, 1.0)

	var col := _base_color
	var max_hp: float = float(pig.get("max_hp", 2))
	if float(pig.hp) < max_hp: # 挨过锤就暗一号（不能写死 2：金猪是三锤的）
		col = col.lerp(_hurt_color, 0.35)
	var flash := float(pig.flash)
	if flash > 0.0:
		col = col.lerp(Color.WHITE, clampf(flash / 0.14, 0.0, 1.0))
	_body_mat.albedo_color = col
	if _body_mat.emission_enabled: # 金猪自发光持续明暗闪烁
		_body_mat.emission_energy_multiplier = 0.8 + 0.5 * (0.5 + 0.5 * sin(elapsed * 5.0 + seed_v))

	var vel: Vector2 = pig.velocity
	_root3d.rotation.y = clampf(vel.x / 160.0, -0.45, 0.45) + 0.12 * sin(elapsed * 1.6 + seed_v)
	_root3d.rotation.x = -0.05 + clampf(vel.y / 260.0, -0.12, 0.12)
