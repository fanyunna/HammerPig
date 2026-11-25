extends SubViewport
class_name Desk3D

## 3D 赌场赌桌（背景）：全屏 SubViewport，main.gd 在 _draw() 最底层贴它的纹理。
##
## 用**透视**相机（不是正交）：有纵深收敛，看起来是"远处的桌子"，桌腿和地板也进画面。
## 透视下屏幕↔世界的换算不是线性的，用 _screen_to_desk()（project_ray_origin/normal
## 与桌面平面 y=0 求交）把屏幕像素反投影成桌面世界坐标，桌板就照它算尺寸：
## 桌板 = 猪活动区（PIG_BOUNDS）外扩一圈，所以猪始终站在桌上，不会跑出桌沿。
## 桌子是静止的，渲染模式 UPDATE_ONCE（只画一帧）。

const VIEW_W := 1280.0
const VIEW_H := 800.0
const FOV := 40.0 # 透视视野（度）：陡俯角下留一点透视收敛（远边比近边略窄，原版观感）
static var pitch_override := 0.0 # 调试用：>0 时覆盖俯角
static var fov_override := 0.0 # 调试用：>0 时覆盖 FOV
static var height_override := 0.0 # 调试用：>0 时覆盖 CAM_HEIGHT
static var back_override := 0.0 # 调试用：>0 时覆盖 CAM_BACK
## 俯视铺屏相机：接近垂直俯视（约 74°），桌子按屏幕四角反投影铺满整幅画面、桌沿
## 全部延伸出画面——原版观感：整块木桌面就是背景，看不到桌子边界，只看到猪背。
const CAM_HEIGHT := 7.0
const CAM_BACK := 2.0
const LOOK_AHEAD := 0.55 # 桌心向玩家方向前移的视差补偿（单次反投影的固定偏差，手工标定）
const DESK_MARGIN := 0.9 # 桌沿出画余量：桌边在屏幕外再延伸的距离
const DESK_THICK := 0.30 # 桌板厚（桌沿出画后基本不可见，保留给桌腿定位）
const FLOOR_Y := -0.78 # 地板：桌腿立在地板上

var _desk_rect := Rect2()
var _pen_rect := Rect2()
var _cam: Camera3D

## 酒馆木桌由深色木纹台面、胡桃木扶手、黄铜饰线、筹码与扑克牌组成。
## 猪活动区域保持开阔；装饰贴在台面上，不会挡住点击判定。

static var _felt_tex: ImageTexture
static var _wood_tex: ImageTexture


## 台面：酒馆旧木桌 —— 深棕木纹两色 + 高频颗粒（毛糙感）+ 大块深浅（磨损压痕）
func _felt_texture() -> ImageTexture:
	if _felt_tex != null:
		return _felt_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.9
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n2.frequency = 0.02
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dark := Color("#3a2412")
	var light := Color("#5e3d20")
	for y in range(size):
		for x in range(size):
			var fuzz := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5 # 毛绒颗粒
			var soft := n2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5 # 大块深浅，模拟压痕
			img.set_pixel(x, y, dark.lerp(light, clampf(fuzz * 0.45 + soft * 0.55, 0.0, 1.0)))
	_felt_tex = ImageTexture.create_from_image(img)
	return _felt_tex


func _felt_mat(scale_u: float, scale_v: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _felt_texture()
	m.uv1_scale = Vector3(scale_u, scale_v, 1.0)
	m.roughness = 0.75 # 旧木桌：不太反光
	m.metallic = 0.0
	return m


func _plain_mat(color: Color, rough: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


func _gold_mat() -> StandardMaterial3D:
	return _plain_mat(Color("#c9a227"), 0.34, 0.72)


## 桌面上的一个扁圆盘子（筹码/下注圈用），厚度薄到不影响猪的行走视觉
func _add_disc(pos: Vector3, radius: float, thick: float, mat: Material, parent: Node3D = null) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thick
	mesh.radial_segments = 20
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	(parent if parent != null else self).add_child(node)


func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_y := 0.0, parent: Node3D = null) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation.y = rot_y
	(parent if parent != null else self).add_child(node)


func _add_ring(pos: Vector3, radius: float, mat: Material, tube := 0.012, parent: Node3D = null) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - tube)
	mesh.outer_radius = radius
	mesh.rings = 64
	mesh.ring_segments = 8
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation.x = PI / 2.0
	(parent if parent != null else self).add_child(node)


func _add_chip_stack(x: float, z: float, count: int, mats: Array[Material], parent: Node3D = null) -> void:
	for i in range(count):
		var y := 0.045 + float(i) * 0.045
		var mat: Material = mats[i % mats.size()]
		_add_disc(Vector3(x, y, z), 0.15, 0.04, mat, parent)
		_add_box(Vector3(x, y + 0.021, z - 0.09), Vector3(0.055, 0.006, 0.022), _plain_mat(Color("#f2e8ce"), 0.6), 0.0, parent)


func _ready() -> void:
	size = Vector2i(int(VIEW_W), int(VIEW_H))
	transparent_bg = true # 桌子以外露出 2D 背景
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ONCE


## pen_rect：小猪活动区（= main.gd 的 PIG_BOUNDS），桌板尺寸按它反投影算出。
## desk_rect 现在只作参考（2D 回退用的桌面矩形），3D 桌板不按它对齐。
func build(desk_rect: Rect2, pen_rect: Rect2) -> void:
	_desk_rect = desk_rect
	_pen_rect = pen_rect
	_build_scene()
	render_target_update_mode = SubViewport.UPDATE_ONCE


## 屏幕点 → 桌面平面（y=0）上的世界点
func _screen_to_desk(p: Vector2) -> Vector3:
	var origin := _cam.project_ray_origin(p)
	var dir := _cam.project_ray_normal(p)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, 0.0, origin.z)
	return origin + dir * (-origin.y / dir.y)


## 木纹：沿 x 方向的年轮条纹 + 噪声扭曲 + 细纤维，现场生成，不依赖外部贴图
func _wood_texture() -> ImageTexture:
	if _wood_tex != null:
		return _wood_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.03
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dark := Color("#7d5f3c")
	var light := Color("#96774e")
	for y in range(size):
		for x in range(size):
			# 年轮：沿 x 方向的长条，低频噪声缓慢扭曲（扭曲幅度太大就成蛇皮了）
			var warp := n.get_noise_2d(float(x) * 0.03, float(y) * 0.015) * 1.6
			var rings := pow(sin(float(y) * 0.22 + warp) * 0.5 + 0.5, 1.4)
			# 木纤维：沿 x 延伸的细线 —— x 方向低频、y 方向高频才对
			var grain := n.get_noise_2d(float(x) * 0.4, float(y) * 2.5) * 0.06
			img.set_pixel(x, y, dark.lerp(light, clampf(rings + grain, 0.0, 1.0)))
	_wood_tex = ImageTexture.create_from_image(img)
	return _wood_tex


func _wood_mat(scale_u: float, scale_v: float, rough := 0.62) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _wood_texture()
	m.uv1_scale = Vector3(scale_u, scale_v, 1.0)
	m.roughness = rough
	m.metallic = 0.0
	return m


func _build_scene() -> void:
	# 俯视铺屏相机：接近垂直俯视。位置由"高度 + 桌前距离"定义，不用抽象的俯角/半径。
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var h := height_override if height_override > 0.0 else CAM_HEIGHT
	var back := back_override if back_override > 0.0 else CAM_BACK
	var fov := fov_override if fov_override > 0.0 else FOV
	_cam.fov = fov
	# 单次反投影对齐：相机先对 z=0 摆放，取猪活动区反投影中心作为对准中心。
	# （迭代会震荡发散：相机移动后反投影中心跳变，不能反复逼近）
	_cam.position = Vector3(0.0, h, back)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, -0.15, 0.0))
	_cam.current = true
	add_child(_cam)
	_cam.force_update_transform()
	var pen_frame: Dictionary = _desk_frame(_pen_rect)
	var aim_cz: float = pen_frame.cz
	aim_cz += LOOK_AHEAD # 视差补偿：猪群中心贴桌面下沿时的修正量（手工标定）
	# 把相机挪到对准中心
	_cam.position = Vector3(0.0, h, aim_cz + back)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, -0.15, aim_cz))
	_cam.force_update_transform()

	var key := DirectionalLight3D.new()
	key.position = Vector3(4.0, 7.0, 5.0)
	key.look_at_from_position(key.position, Vector3.ZERO)
	key.light_energy = 1.35
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.position = Vector3(-5.0, 3.0, -3.0)
	fill.look_at_from_position(fill.position, Vector3.ZERO)
	fill.light_energy = 0.35
	add_child(fill)

	# 地板：桌子之外的房间地面，避免"桌子浮在虚空里"
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60.0, 60.0)
	floor_node.mesh = floor_mesh
	floor_node.rotation.x = -PI / 2.0
	floor_node.position.y = FLOOR_Y
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#120b07") # 酒馆地板：压到近黑，和高亮木桌拉开对比（原版式构图）
	fm.roughness = 0.9
	floor_node.material_override = fm
	add_child(floor_node)

	# 桌板：反投影铺屏——屏幕四角打到桌面平面，桌子按四角包围盒外扩 DESK_MARGIN 取尺寸，
	# 桌沿全部延伸出画面（原版观感：整块木桌面就是背景，看不到桌子边界）。
	var ca := _screen_to_desk(Vector2(0.0, 0.0))
	var cb := _screen_to_desk(Vector2(VIEW_W, 0.0))
	var cc := _screen_to_desk(Vector2(0.0, VIEW_H))
	var cd := _screen_to_desk(Vector2(VIEW_W, VIEW_H))
	var desk_cz: float = (min(minf(ca.z, cb.z), minf(cc.z, cd.z)) + max(maxf(ca.z, cb.z), maxf(cc.z, cd.z))) / 2.0
	var desk_w: float = max(maxf(ca.x, cb.x), maxf(cc.x, cd.x)) - min(minf(ca.x, cb.x), minf(cc.x, cd.x)) + DESK_MARGIN * 2.0
	var desk_d: float = max(maxf(ca.z, cb.z), maxf(cc.z, cd.z)) - min(minf(ca.z, cb.z), minf(cc.z, cd.z)) + DESK_MARGIN * 2.0
	var thick := DESK_THICK
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(desk_w, thick, desk_d)
	top.mesh = box
	top.material_override = _wood_mat(desk_w / 1.2, desk_d / 1.2, 0.42)
	top.position = Vector3(0.0, -thick / 2.0, desk_cz)
	add_child(top)

	# 深色木质桌沿/扶手，围住整张赌桌。
	var rim := MeshInstance3D.new()
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(desk_w + 0.24, thick * 0.9, desk_d + 0.24)
	rim.mesh = rim_box
	rim.material_override = _wood_mat(desk_w / 1.2, desk_d / 1.2, 0.38)
	rim.position = top.position + Vector3(0.0, -thick * 0.55, 0.0)
	add_child(rim)
	var rail_mat := _wood_mat(desk_w / 1.2, desk_d / 1.2, 0.34)
	var gold := _gold_mat()
	var rail_y := 0.075
	var rail_z := desk_d / 2.0 - 0.05
	var rail_x := desk_w / 2.0 - 0.05
	_add_box(Vector3(0.0, rail_y, desk_cz - rail_z), Vector3(desk_w + 0.06, 0.11, 0.20), rail_mat)
	_add_box(Vector3(0.0, rail_y, desk_cz + rail_z), Vector3(desk_w + 0.06, 0.11, 0.20), rail_mat)
	_add_box(Vector3(-rail_x, rail_y, desk_cz), Vector3(0.20, 0.11, desk_d - 0.20), rail_mat)
	_add_box(Vector3(rail_x, rail_y, desk_cz), Vector3(0.20, 0.11, desk_d - 0.20), rail_mat)
	_add_box(Vector3(0.0, rail_y + 0.058, desk_cz - rail_z + 0.11), Vector3(desk_w - 0.10, 0.010, 0.014), gold)
	_add_box(Vector3(0.0, rail_y + 0.058, desk_cz + rail_z - 0.11), Vector3(desk_w - 0.10, 0.010, 0.014), gold)
	_add_box(Vector3(-rail_x + 0.11, rail_y + 0.058, desk_cz), Vector3(0.014, 0.010, desk_d - 0.30), gold)
	_add_box(Vector3(rail_x - 0.11, rail_y + 0.058, desk_cz), Vector3(0.014, 0.010, desk_d - 0.30), gold)

	_decorate(pen_frame) # 账单纸、筹码堆和扑克牌：锚定猪活动区（桌子本体已延伸出画面，不能拿桌沿当锚点）

	# 桌腿：坐姿视角能看到桌沿以下，得有腿撑着
	var leg_h := -FLOOR_Y - thick
	var leg_mat := _wood_mat(1.5, 1.5, 0.7)
	leg_mat.albedo_color = Color("#7a5a3a")
	for i in range(4):
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sz := -1.0 if i < 2 else 1.0
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.14
		lm.bottom_radius = 0.11
		lm.height = leg_h
		lm.radial_segments = 12
		leg.mesh = lm
		leg.material_override = leg_mat
		leg.position = Vector3(
			sx * (desk_w / 2.0 - 0.45),
			FLOOR_Y + leg_h / 2.0,
			desk_cz + sz * (desk_d / 2.0 - 0.40)
		)
		add_child(leg)


## 给定屏幕矩形反投影到桌面平面（透视下屏幕↔世界非线性，见 _screen_to_desk）。
## 现在只用于取猪活动区的世界中心（cz），桌子本体已改为固定尺寸。
func _desk_frame(area: Rect2) -> Dictionary:
	var tl := _screen_to_desk(area.position)
	var bl := _screen_to_desk(area.position + Vector2(0.0, area.size.y))
	var half_w: float = maxf(absf(tl.x), absf(bl.x))
	return {
		"w": half_w * 2.0,
		"d": absf(bl.z - tl.z),
		"cz": (tl.z + bl.z) / 2.0,
	}


## 赌桌的桌面装饰：沿桌沿一圈金色细线、中央两圈下注环、四角筹码堆、散落的几张牌。
## 全部摆在 y≈0.014 的桌面上，压得很薄，猪走过去不会被穿模。
func _decorate(frame: Dictionary, sc := 1.0) -> void:
	# 装饰整体装进一个 sc 倍缩放容器：局部坐标 = 世界坐标 / sc，尺寸随桌深自动放大
	var decor := Node3D.new()
	decor.scale = Vector3.ONE * sc
	add_child(decor)
	var w: float = frame.w / sc
	var d: float = frame.d / sc
	var cz: float = frame.cz / sc
	var y := 0.018
	var far_z := cz - d / 2.0 + 0.55
	var paper_mat := _plain_mat(Color("#e8ddc4"), 0.88)
	var paper_shadow := _plain_mat(Color("#a58c67"), 0.9)
	var gold_mat := _gold_mat()
	# 中央下注环与靠玩家一侧的下注位：它们是贴面装饰，不会挡住猪的移动或点击。
	_add_ring(Vector3(0.0, y + 0.020, cz), 0.82, gold_mat, 0.014, decor)
	_add_ring(Vector3(0.0, y + 0.020, cz), 1.08, gold_mat, 0.009, decor)
	_add_ring(Vector3(0.0, y + 0.020, cz), 0.20, gold_mat, 0.010, decor)
	for i in range(5):
		var slot_x := lerpf(-1.35, 1.35, float(i) / 4.0)
		_add_ring(Vector3(slot_x, y + 0.020, cz + d * 0.28), 0.12, gold_mat, 0.008, decor)
	# 桌角散叠的催缴单，顶纸印一道项目红线。
	for i in range(3):
		var sheet := MeshInstance3D.new()
		var sheet_mesh := BoxMesh.new()
		sheet_mesh.size = Vector3(0.82, 0.018, 0.56)
		sheet.mesh = sheet_mesh
		sheet.material_override = paper_shadow if i == 0 else paper_mat
		sheet.position = Vector3(-w / 2.0 + 0.72 + float(i) * 0.08, y + float(i) * 0.02, far_z + float(i) * 0.06)
		sheet.rotation.y = -0.12 + float(i) * 0.10
		decor.add_child(sheet)
	_add_box(Vector3(-w / 2.0 + 0.72, y + 0.067, far_z + 0.02), Vector3(0.55, 0.008, 0.045), _plain_mat(Color("#b84d3a"), 0.8), -0.12, decor)
	# 金币与筹码混放，暗示玩家刚押下去的一笔钱。
	var coin_mat := _gold_mat()
	for i in range(4):
		_add_disc(Vector3(w / 2.0 - 0.72 + float(i % 2) * 0.13, y + 0.025 + float(i / 2) * 0.035, far_z + 0.54 + float(i / 2) * 0.10), 0.095, 0.035, coin_mat, decor)
	var chip_mats: Array[Material] = [
		_plain_mat(Color("#a63832"), 0.45),
		_plain_mat(Color("#233e70"), 0.45),
		_plain_mat(Color("#262624"), 0.5),
	]
	_add_chip_stack(w / 2.0 - 0.62, far_z + 1.00, 5, chip_mats, decor)
	_add_chip_stack(w / 2.0 - 1.02, far_z + 1.28, 3, chip_mats, decor)
	# 两张斜放的扑克牌：暖白牌面配红/黑背纹，强化赌场桌的识别度。
	var card_red := _plain_mat(Color("#a83b32"), 0.6)
	var card_black := _plain_mat(Color("#26302d"), 0.7)
	var card_x := w / 2.0 - 1.55
	var card_z := far_z + 0.92
	_add_box(Vector3(card_x - 0.12, y + 0.027, card_z), Vector3(0.44, 0.018, 0.66), card_red, -0.18, decor)
	_add_box(Vector3(card_x + 0.17, y + 0.038, card_z + 0.05), Vector3(0.44, 0.018, 0.66), paper_mat, 0.12, decor)
	_add_box(Vector3(card_x + 0.17, y + 0.050, card_z + 0.05), Vector3(0.20, 0.006, 0.24), card_black, 0.12, decor)
