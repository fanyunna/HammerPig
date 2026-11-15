extends SubViewport
class_name Challenge3D

## 账单考核的 3D 舞台：一张被灯照着的酒馆柜台，金币从上面掉下来（凑钱），
## 或者一群戴礼帽的催债人从四周包过来（躲债）。两种玩法共用这一个视口。
##
## 和 pig3d / desk3d 同一套路：不依赖任何外部模型，全部用 Godot 内置图元现场拼。
##
## 关键设计：玩法逻辑仍然跑在 main.gd 的 2D 坐标里（点击判定、生成、计时都不动），
## 这里只"照着那份状态摆 3D 道具"。屏幕坐标通过**射线与地面 y=0 求交**反投影成世界坐标，
## 所以一枚 2D 里位于 (400, 420) 的金币，3D 里就正好画在那儿 —— 看得见就点得到，
## 不会出现"明明点到了却没反应"。渲染出问题也影响不到玩法，headless 下直接不建实例。

## 相机俯角 / 距离 / 视野：长焦近距离看桌面，透视很轻（远处的金币不会缩成一点）。
const PITCH := 1.10
const CAM_DIST := 15.0
const FOV := 22.0
const GRAVITY := 12.0

var _built := false
var _origin := Vector2.ZERO # 舞台在屏幕上的左上角：视口坐标 = 屏幕坐标 - _origin
var _cam: Camera3D
var _coins_root: Node3D
var _dodgers_root: Node3D
var _sparks_root: Node3D
var _cursor: Node3D
var _cursor_ring: MeshInstance3D
var _cursor_disc: MeshInstance3D
var _cursor_ring_mat: StandardMaterial3D
var _cursor_disc_mat: StandardMaterial3D

var _px_unit := 64.0 # 屏幕像素 / 世界单位（在相机注视点处）
var _font: SystemFont

var _gold: StandardMaterial3D
var _gold_rim: StandardMaterial3D
var _fake: StandardMaterial3D
var _fake_rim: StandardMaterial3D
var _fake_glow: StandardMaterial3D
var _coat: StandardMaterial3D
var _skin: StandardMaterial3D
var _hat: StandardMaterial3D

var _time := 0.0
var _mouse := Vector2.ZERO
var _mode := ""
var _invincible := 0.0
var _danger := 0.0

var _coins: Dictionary = {} # key -> 状态字典（见 _spawn_coin）
var _dodgers: Dictionary = {} # key -> 状态字典（见 _spawn_dodger）
var _dying: Array[Dictionary] = [] # 正在消散的道具：让人看见"它没了"，而不是凭空消失
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	# 3D 里的「¥」「假」也要中文/符号字体：系统字体，和 2D 用同一套族名
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans SC", "Noto Sans CJK SC"])


## rect：舞台在屏幕上的矩形。视口像素与屏幕像素 1:1，映射就不用再算缩放。
func build(rect: Rect2) -> void:
	_origin = rect.position
	size = Vector2i(int(rect.size.x), int(rect.size.y))
	_build_scene()
	_built = true


## 屏幕像素 → 世界单位
func _u(px: float) -> float:
	return px / _px_unit


## 屏幕点 → 柜台平面（y=0）上的世界点。这是整个 3D 化能对得上的地基：
## 无论相机怎么摆，只要物体站在 y=0 上，它渲染出来的位置就正好落在这个屏幕点上。
func _screen_to_floor(p: Vector2) -> Vector3:
	var local := p - _origin
	var origin := _cam.project_ray_origin(local)
	var dir := _cam.project_ray_normal(local)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, 0.0, origin.z)
	return origin + dir * (-origin.y / dir.y)


func _build_scene() -> void:
	_px_unit = float(size.y) / (2.0 * CAM_DIST * tan(deg_to_rad(FOV * 0.5)))

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = FOV
	_cam.near = 0.1
	_cam.far = 60.0
	_cam.position = Vector3(0.0, CAM_DIST * sin(PITCH), CAM_DIST * cos(PITCH))
	_cam.look_at_from_position(_cam.position, Vector3.ZERO, Vector3.UP)
	_cam.current = true
	add_child(_cam)
	_cam.force_update_transform() # 反投影要用相机矩阵，必须先刷一遍

	# 环境：Compatibility 渲染器没有默认环境光，金属材质没有环境反射就是一坨黑。
	# 背景直接给暗暖色（舞台本来就整块盖住面板，不需要透明）。
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#171009")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#93816b")
	env.ambient_light_energy = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# 主光：暖色侧上方，投影关掉的是"氛围"，投影开着的是"东西真的立在桌上"
	var key := DirectionalLight3D.new()
	key.position = Vector3(4.0, 8.0, 6.0)
	key.look_at_from_position(key.position, Vector3.ZERO, Vector3.UP)
	key.light_color = Color("#ffd9a8")
	key.light_energy = 1.45
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 30.0
	add_child(key)

	# 补光：冷色从反方向压一点，死黑的阴影会让人看不出圆
	var fill := DirectionalLight3D.new()
	fill.position = Vector3(-6.0, 4.0, -5.0)
	fill.look_at_from_position(fill.position, Vector3.ZERO, Vector3.UP)
	fill.light_color = Color("#8fa6c0")
	fill.light_energy = 0.55
	add_child(fill)

	# 顶灯：一盏吊灯把光聚在台面中央，四周自然暗下去 —— 这是"舞台感"最省钱的来源
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0.0, 7.0, 1.6)
	lamp.look_at_from_position(lamp.position, Vector3(0.0, 0.0, 0.6), Vector3.UP)
	lamp.light_color = Color("#ffcf94")
	lamp.light_energy = 6.0
	lamp.spot_range = 18.0
	lamp.spot_angle = 48.0
	lamp.spot_attenuation = 1.2
	add_child(lamp)

	_build_materials()
	_build_counter()
	_build_props()

	_coins_root = Node3D.new()
	add_child(_coins_root)
	_dodgers_root = Node3D.new()
	add_child(_dodgers_root)
	_sparks_root = Node3D.new()
	add_child(_sparks_root)
	_build_cursor()


func _mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _emissive(color: Color, energy: float, albedo := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


func _build_materials() -> void:
	_gold = _mat(Color("#dca83e"), 0.32, 0.55) # 金属度别拉满：没有环境反射贴图时拉满只会发黑
	_gold_rim = _mat(Color("#f3d288"), 0.24, 0.7)
	# 假币是铁的不是金的：更暗、更脏、有一点冷光
	_fake = _mat(Color("#3a4147"), 0.5, 0.45)
	_fake_rim = _mat(Color("#767e85"), 0.42, 0.5)
	_fake_glow = _emissive(Color("#8f2f2a"), 1.6, Color("#2b1414"))
	_coat = _mat(Color("#242b33"), 0.75)
	_skin = _mat(Color("#bd977a"), 0.7)
	_hat = _mat(Color("#16191d"), 0.6)


## 台面木纹：沿 x 的年轮 + 高频纤维 + 几道划痕。现场生成，不依赖贴图文件。
static var _wood_tex: ImageTexture

func _wood_texture() -> ImageTexture:
	if _wood_tex != null:
		return _wood_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.035
	var warp_n := FastNoiseLite.new()
	warp_n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp_n.frequency = 0.012
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var dark := Color("#3a2417")
	var light := Color("#6a4529")
	for y in range(size):
		for x in range(size):
			# 木纹调参记：warp=2.2 → 迷彩；freq=0.52 → 灯芯绒（~10px 条纹）；
			# freq=0.30 → 还是偏密。0.12 让年轮约 28px 一道，接近真木板
			var warp := warp_n.get_noise_2d(float(x) * 0.6, float(y) * 0.4) * 0.6
			var rings := pow(sin(float(y) * 0.12 + warp) * 0.5 + 0.5, 1.6)
			var grain := n.get_noise_2d(float(x) * 0.5, float(y) * 3.0) * 0.10
			img.set_pixel(x, y, dark.lerp(light, clampf(rings * 0.72 + grain, 0.0, 1.0)))
	# 划痕：旧柜台不可能没有伤。但亮度必须压到"凑近才看得出"，一高就像裂缝
	for i in range(8):
		var px := randf() * size
		var py := randf() * size
		var a := randf() * TAU
		for s in range(int(randf_range(18.0, 46.0))):
			px += cos(a) * 1.6 + randf_range(-0.7, 0.7)
			py += sin(a) * 1.6 + randf_range(-0.7, 0.7)
			var ix := posmod(int(px), size) # 负数取模在 GDScript 里还是负的，必须用 posmod，否则划痕越界
			var iy := posmod(int(py), size)
			img.set_pixel(ix, iy, img.get_pixel(ix, iy).lightened(0.05))
	_wood_tex = ImageTexture.create_from_image(img)
	return _wood_tex


func _build_counter() -> void:
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_node.mesh = plane
	# 注意：PlaneMesh 默认就是平躺、法线朝 +Y 的，不要像普通平面那样再转 -90°，
	# 转了它就立起来了，从俯视相机看是一条线（第一版就是这么把台面弄没的）。
	var m := StandardMaterial3D.new()
	m.albedo_texture = _wood_texture()
	m.uv1_scale = Vector3(9.0, 9.0, 1.0) # 平铺：木纹要密到 200px/米才不像塑料
	m.roughness = 0.64
	m.metallic = 0.0
	floor_node.material_override = m
	add_child(floor_node)


## 柜台上的静物：远处一叠催缴单和半杯酒，近处一小撮散钱。
## 全部摆在金币/催债人不会经过的边缘（屏幕上下各一条窄带），纯粹用来交代"这是张真桌子"。
func _build_props() -> void:
	var paper := _mat(Color("#e4d8bd"), 0.9)
	var paper_dark := _mat(Color("#b9a789"), 0.92)
	var red := _mat(Color("#a8402f"), 0.8)
	var glass := _mat(Color("#4a3a26"), 0.35, 0.15)

	for i in range(3):
		var p := _screen_to_floor(Vector2(140.0 + float(i) * 16.0, 42.0 + float(i) * 9.0))
		var sheet := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(_u(74.0), _u(2.0), _u(52.0))
		sheet.mesh = box
		sheet.material_override = paper_dark if i == 0 else paper
		sheet.position = p + Vector3(0.0, _u(1.0 + float(i) * 2.0), 0.0)
		sheet.rotation.y = -0.14 + float(i) * 0.10
		add_child(sheet)
	var stripe := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(_u(48.0), _u(1.0), _u(5.0))
	stripe.mesh = sbox
	stripe.material_override = red
	var sp := _screen_to_floor(Vector2(146.0, 44.0))
	stripe.position = sp + Vector3(0.0, _u(7.2), 0.0)
	stripe.rotation.y = -0.14
	add_child(stripe)

	# 半杯威士忌：杯身 + 里面一截琥珀色
	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = _u(17.0)
	cup_mesh.bottom_radius = _u(14.0)
	cup_mesh.height = _u(34.0)
	cup_mesh.radial_segments = 18
	cup.mesh = cup_mesh
	var glass_m := StandardMaterial3D.new()
	glass_m.albedo_color = Color(0.82, 0.88, 0.9, 0.34)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_m.roughness = 0.12
	cup.material_override = glass_m
	cup.position = _screen_to_floor(Vector2(1040.0, 46.0)) + Vector3(0.0, _u(17.0), 0.0)
	add_child(cup)
	var liquor := MeshInstance3D.new()
	var lq := CylinderMesh.new()
	lq.top_radius = _u(14.0)
	lq.bottom_radius = _u(12.0)
	lq.height = _u(14.0)
	lq.radial_segments = 18
	liquor.mesh = lq
	liquor.material_override = glass
	liquor.position = cup.position + Vector3(0.0, -_u(8.0), 0.0)
	add_child(liquor)

	# 近处：随手推在台边的几枚钱，暗示"上一位客人留下的"
	for i in range(5):
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = _u(13.0)
		cm.bottom_radius = _u(13.0)
		cm.height = _u(5.0)
		cm.radial_segments = 22
		c.mesh = cm
		c.material_override = _gold
		var at := _screen_to_floor(Vector2(96.0 + float(i) * 26.0, 352.0 + float(i % 2) * 12.0))
		c.position = at + Vector3(0.0, _u(2.5), 0.0)
		c.rotation.y = randf() * TAU
		add_child(c)


## 光标环：凑钱时是一圈淡金（提示"这里能点"），躲债时是一圈冷蓝（你就站这儿）。
func _build_cursor() -> void:
	_cursor = Node3D.new()
	add_child(_cursor)
	_cursor_ring_mat = _emissive(Color("#7fd4ff"), 2.2, Color("#123040"))
	_cursor_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _u(15.0)
	torus.outer_radius = _u(19.0)
	torus.rings = 28
	torus.ring_segments = 8
	_cursor_ring.mesh = torus
	_cursor_ring.material_override = _cursor_ring_mat
	_cursor_ring.rotation.x = PI / 2.0
	_cursor.add_child(_cursor_ring)

	_cursor_disc_mat = StandardMaterial3D.new()
	_cursor_disc_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.18)
	_cursor_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = _u(17.0)
	disc.bottom_radius = _u(17.0)
	disc.height = _u(0.6)
	disc.radial_segments = 24
	_cursor_disc.mesh = disc
	_cursor_disc.material_override = _cursor_disc_mat
	_cursor.add_child(_cursor_disc)
	_cursor.visible = false


# ---------------------------------------------------------------- 金币

func _spawn_coin(fake: bool) -> Dictionary:
	var root := Node3D.new()
	_coins_root.add_child(root)
	var spinner := Node3D.new()
	root.add_child(spinner)

	# 币身：假币做成八边形，剪影上就和金币不是一类东西
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = _u(26.0)
	mesh.bottom_radius = _u(26.0)
	mesh.height = _u(9.0)
	mesh.radial_segments = 8 if fake else 30
	body.mesh = mesh
	body.material_override = _fake if fake else _gold
	spinner.add_child(body)

	# 币面的一圈浮雕：没有它，俯视下的圆片就是一坨颜色
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _u(13.0 if fake else 16.0)
	torus.outer_radius = _u(21.0)
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _fake_glow if fake else _gold_rim
	ring.position.y = _u(4.4)
	ring.rotation.x = PI / 2.0
	spinner.add_child(ring)

	var lbl := Label3D.new()
	lbl.text = "假" if fake else "¥"
	lbl.font = _font
	lbl.font_size = 120
	lbl.pixel_size = _u(24.0) / 120.0
	lbl.modulate = Color("#ff8a7a") if fake else Color("#8a5a1c")
	lbl.shaded = false # 币面符号要永远清晰：不受光影响，暗处也能认出真假
	lbl.position.y = _u(4.8)
	lbl.rotation.x = -PI / 2.0 # 平躺、字头朝画面的上方（-Z = 远）
	spinner.add_child(lbl)

	return {
		"node": root, "spinner": spinner,
		"y": _u(150.0), "vy": 0.0,
		"spin": randf() * TAU, "spin_speed": randf_range(7.0, 12.0),
		"hover": 0.0, "px": Vector2.ZERO, "fake": fake,
		"seed": randf() * TAU, "landed": false,
	}


func _animate_coins(delta: float) -> void:
	for key in _coins.keys():
		var st: Dictionary = _coins[key]
		var y: float = float(st["y"])
		var vy: float = float(st["vy"])
		var seed_v: float = float(st["seed"])
		var bob := _u(9.0) + sin(_time * 2.3 + seed_v) * _u(2.4)
		if not bool(st["landed"]):
			vy -= GRAVITY * delta
			y += vy * delta
			if y <= bob and vy < 0.0: # 落地：弹一下，弹不动就停
				y = bob
				vy = -vy * 0.40
				if vy < _u(22.0):
					vy = 0.0
					st["landed"] = true
		else:
			y = lerpf(y, bob, clampf(delta * 8.0, 0.0, 1.0))
		st["y"] = y
		st["vy"] = vy

		# 旋转：空中转得飞快，落地后收到最近的整圈停住 —— 币面「¥」必须回到正对上方的角度，
		# 不然字转到侧面就认不出真假了（第一版一直以 1.1 rad/s 慢转，就是这个问题）
		if bool(st["landed"]):
			var settle: float = round(float(st["spin"]) / TAU) * TAU
			st["spin"] = lerpf(float(st["spin"]), settle, clampf(delta * 6.0, 0.0, 1.0))
		else:
			st["spin"] = float(st["spin"]) + float(st["spin_speed"]) * delta
			st["spin_speed"] = lerpf(float(st["spin_speed"]), 1.1, clampf(delta * 1.8, 0.0, 1.0))

		var hover := 0.0
		if _mode == "collect":
			var px: Vector2 = st["px"]
			if _mouse.distance_to(px) <= 34.0:
				hover = 1.0
		st["hover"] = lerpf(float(st["hover"]), hover, clampf(delta * 14.0, 0.0, 1.0))
		var hv: float = st["hover"]

		var node: Node3D = st["node"]
		var spinner: Node3D = st["spinner"]
		spinner.rotation.y = float(st["spin"])
		spinner.rotation.x = 0.14 + sin(_time * 1.7 + seed_v) * 0.05 + hv * 0.10
		node.position.y = y + hv * _u(7.0)
		var s := 1.0 + hv * 0.12
		node.scale = Vector3(s, s, s)
		if not bool(st["landed"]): # 空中不接鼠标：还没落稳就高亮会很跳
			node.scale = Vector3.ONE


# ---------------------------------------------------------------- 催债人

func _spawn_dodger() -> Dictionary:
	var root := Node3D.new()
	_dodgers_root.add_child(root)

	var shoe := _mat(Color("#0d0f12"), 0.55)
	var tie := _mat(Color("#9c2f2c"), 0.7)
	var paper := _mat(Color("#ded2b8"), 0.9)
	var eye := _emissive(Color("#ff4433"), 2.4, Color("#3a0c0a"))

	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = _u(4.6)
		lm.bottom_radius = _u(4.2)
		lm.height = _u(20.0)
		lm.radial_segments = 10
		leg.mesh = lm
		leg.material_override = _coat
		leg.position = Vector3(_u(6.0) * side, _u(10.0), 0.0)
		root.add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(_u(13.0), _u(6.0), _u(21.0))
		foot.mesh = fm
		foot.material_override = shoe
		foot.position = Vector3(_u(6.0) * side, _u(3.0), _u(4.0))
		root.add_child(foot)

	# 大衣：上窄下宽的锥体，俯视时能看出"肩膀比腰宽"
	var coat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = _u(12.0)
	cm.bottom_radius = _u(17.0)
	cm.height = _u(34.0)
	cm.radial_segments = 16
	coat.mesh = cm
	coat.material_override = _coat
	coat.position.y = _u(40.0)
	root.add_child(coat)

	var shoulder := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = _u(13.5)
	sm.height = _u(20.0)
	shoulder.mesh = sm
	shoulder.material_override = _coat
	shoulder.position.y = _u(57.0)
	shoulder.scale = Vector3(1.0, 0.62, 0.9)
	root.add_child(shoulder)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = _u(9.0)
	hm.height = _u(18.0)
	head.mesh = hm
	head.material_override = _skin
	head.position.y = _u(68.0)
	root.add_child(head)

	# 礼帽：一眼就知道是"催收的"，也把脸遮住一半，省得做表情
	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = _u(14.0)
	bm.bottom_radius = _u(14.0)
	bm.height = _u(2.4)
	bm.radial_segments = 20
	brim.mesh = bm
	brim.material_override = _hat
	brim.position.y = _u(75.0)
	root.add_child(brim)
	var crown := MeshInstance3D.new()
	var cr := CylinderMesh.new()
	cr.top_radius = _u(8.6)
	cr.bottom_radius = _u(8.6)
	cr.height = _u(10.0)
	cr.radial_segments = 16
	crown.mesh = cr
	crown.material_override = _hat
	crown.position.y = _u(81.0)
	root.add_child(crown)

	# 帽檐底下两点红光：唯一的辨识色，隔着满屏金币也看得见
	var eyes := Node3D.new()
	eyes.position.y = _u(67.0)
	root.add_child(eyes)
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = _u(2.1)
		em.height = _u(4.2)
		e.mesh = em
		e.material_override = eye
		e.position = Vector3(_u(3.2) * side, 0.0, _u(8.4))
		eyes.add_child(e)

	var tie_item := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(_u(5.0), _u(16.0), _u(1.2))
	tie_item.mesh = tm
	tie_item.material_override = tie
	tie_item.position = Vector3(0.0, _u(48.0), _u(11.6))
	root.add_child(tie_item)

	# 手里那张催缴单：他的"武器"，也是这一关的来由
	var bill := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(_u(11.0), _u(14.0), _u(0.8))
	bill.mesh = blm
	bill.material_override = paper
	bill.position = Vector3(_u(13.0), _u(44.0), _u(7.0))
	bill.rotation = Vector3(0.0, 0.0, -0.24)
	root.add_child(bill)

	# 脚下的警戒圈：贴地的红圈，比任何 UI 都直观地告诉他"别让它碰到你"
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = _u(19.0)
	rm.outer_radius = _u(23.0)
	rm.rings = 24
	rm.ring_segments = 6
	ring.mesh = rm
	ring.material_override = _emissive(Color("#ff3b30"), 1.4, Color("#240505"))
	ring.rotation.x = PI / 2.0
	ring.position.y = _u(1.2)
	root.add_child(ring)

	return {"node": root, "seed": randf() * TAU, "ring": ring}


func _animate_dodgers(delta: float) -> void:
	for key in _dodgers.keys():
		var st: Dictionary = _dodgers[key]
		var seed_v: float = float(st["seed"])
		var node: Node3D = st["node"]
		# 走路：左右晃 + 上下颠。幅度很小，但"活着"和"贴图在平移"就是靠这点差别
		node.rotation.z = sin(_time * 9.0 + seed_v) * 0.07
		node.position.y = _u(2.0) + absf(sin(_time * 9.0 + seed_v)) * _u(3.0)
		var ring: MeshInstance3D = st["ring"]
		var pulse := 1.0 + 0.10 * sin(_time * 6.0 + seed_v)
		ring.scale = Vector3(pulse, 1.0, pulse)


# ---------------------------------------------------------------- 光标 / 特效

func _animate_cursor(delta: float) -> void:
	if _cursor == null:
		return
	_cursor.visible = _mode != ""
	if _mode == "":
		return
	var w := _screen_to_floor(_mouse)
	_cursor.position = Vector3(w.x, _u(1.4), w.z)

	var col := Color("#7fd4ff")
	var energy := 2.2
	if _mode == "collect":
		col = Color("#ffce7a")
		energy = 1.4
		# 悬在金币上时圈收紧、变亮：最便宜的"我瞄到了"反馈
		var near := 0.0
		for key in _coins.keys():
			var st: Dictionary = _coins[key]
			if _mouse.distance_to(Vector2(st["px"])) <= 34.0:
				near = 1.0
				break
		var k := 1.0 - near * 0.22
		_cursor.scale = Vector3(k, 1.0, k)
		energy = 1.4 + near * 2.0
	else:
		_cursor.scale = Vector3.ONE
		if _invincible > 0.0: # 刚被撞：闪绿，等于无敌帧的提示
			col = Color("#a4d007")
			energy = 1.6 + 1.6 * absf(sin(_time * 18.0))
		elif _danger > 0.02: # 越危险越红：不用看 UI 也知道快撞上了
			col = Color("#7fd4ff").lerp(Color("#ff4433"), clampf(_danger, 0.0, 1.0))
			energy = 2.2 + 2.0 * clampf(_danger, 0.0, 1.0)
	_cursor_ring_mat.emission = col
	_cursor_ring_mat.emission_energy_multiplier = energy
	_cursor_disc_mat.albedo_color = Color(col.r, col.g, col.b, 0.16)
	var size_k := 1.0 + 0.06 * sin(_time * 4.0)
	_cursor_ring.scale = Vector3(size_k, 1.0, size_k)


## 一小把火星 / 纸屑：道具消失时得有点东西飞出去，否则就是"啪"地不见了
func _burst(pos: Vector3, count: int, color: Color, kind: String) -> void:
	for i in range(count):
		var node := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = _u(2.6 if kind == "spark" else 1.8)
		m.height = _u(5.2 if kind == "spark" else 3.0)
		m.radial_segments = 8
		m.rings = 4
		node.mesh = m
		node.material_override = _emissive(color, 3.0, color.darkened(0.5))
		node.position = pos + Vector3(0.0, _u(6.0), 0.0)
		_sparks_root.add_child(node)
		var a := randf() * TAU
		var speed := _u(randf_range(70.0, 190.0))
		_sparks.append({
			"node": node, "life": randf_range(0.35, 0.6),
			"v": Vector3(cos(a) * speed, _u(randf_range(60.0, 170.0)), sin(a) * speed),
		})


func _animate_sparks(delta: float) -> void:
	for i in range(_sparks.size() - 1, -1, -1):
		var s: Dictionary = _sparks[i]
		var node: MeshInstance3D = s["node"]
		var v: Vector3 = s["v"]
		v.y -= 9.0 * delta
		node.position += v * delta
		s["v"] = v
		var life: float = float(s["life"]) - delta
		s["life"] = life
		node.scale = Vector3.ONE * clampf(life * 4.0, 0.0, 1.0)
		if life <= 0.0:
			node.queue_free()
			_sparks.remove_at(i)


func _animate_dying(delta: float) -> void:
	for i in range(_dying.size() - 1, -1, -1):
		var d: Dictionary = _dying[i]
		var node: Node3D = d["node"]
		var t: float = float(d["t"]) - delta
		d["t"] = t
		var k := clampf(t / 0.16, 0.0, 1.0) # 0.16 秒缩没：够看清，又不拖泥带水
		node.scale = Vector3(k, k, k)
		if t <= 0.0:
			node.queue_free()
			_dying.remove_at(i)


# ---------------------------------------------------------------- 对外接口

## 每帧把玩法状态喂进来。main.gd 在 phase == "challenge" 时调用。
func sync(coins: Array[Dictionary], dodgers: Array[Dictionary], mouse: Vector2, mode: String, invincible: float) -> void:
	if not _built:
		return
	_mode = mode
	_mouse = mouse
	_invincible = invincible
	_sync_coins(coins)
	_sync_dodgers(dodgers)
	_update_danger()


func _sync_coins(coins: Array[Dictionary]) -> void:
	var seen := {}
	for i in range(coins.size()):
		var c: Dictionary = coins[i]
		var key := _key_of(c, "vcid", i)
		seen[key] = true
		var st: Dictionary = _coins.get(key, {})
		if st.is_empty():
			st = _spawn_coin(bool(c.get("fake", false)))
			_coins[key] = st
		var px: Vector2 = c.get("position", Vector2.ZERO)
		st["px"] = px
		var w := _screen_to_floor(px)
		var node: Node3D = st["node"]
		node.position.x = w.x
		node.position.z = w.z
	for key in _coins.keys():
		if not seen.has(key):
			_retire_coin(key)


func _sync_dodgers(dodgers: Array[Dictionary]) -> void:
	var seen := {}
	for i in range(dodgers.size()):
		var d: Dictionary = dodgers[i]
		var key := _key_of(d, "dcid", i)
		seen[key] = true
		var st: Dictionary = _dodgers.get(key, {})
		if st.is_empty():
			st = _spawn_dodger()
			_dodgers[key] = st
		var px: Vector2 = d.get("position", Vector2.ZERO)
		var w := _screen_to_floor(px)
		var node: Node3D = st["node"]
		node.position.x = w.x
		node.position.z = w.z
		# 面朝玩家：他是来抓你的，不是来路过的
		var dir := _mouse - px
		if dir.length_squared() > 4.0:
			node.rotation.y = atan2(dir.x, dir.y)
	for key in _dodgers.keys():
		if not seen.has(key):
			_retire_dodger(key)


## 危险度：最近的那个催债人有多近（0 = 安全，1 = 已经贴脸）
func _update_danger() -> void:
	var best := 9999.0
	for key in _dodgers.keys():
		var st: Dictionary = _dodgers[key]
		var node: Node3D = st["node"]
		var p := Vector2(node.position.x, node.position.z)
		var m := _screen_to_floor(_mouse)
		best = minf(best, p.distance_to(Vector2(m.x, m.z)))
	if best > 9000.0:
		_danger = 0.0
		return
	# 屏幕 70px 以内开始报警，25px 以内拉满
	var near := 1.0 - clampf((best * _px_unit - 25.0) / 45.0, 0.0, 1.0)
	_danger = lerpf(_danger, near, 0.25)


func _retire_coin(key: String) -> void:
	var st: Dictionary = _coins.get(key, {})
	if st.is_empty():
		return
	_coins.erase(key)
	var node: Node3D = st["node"]
	_burst(node.position, 6, Color("#ffce7a"), "spark")
	_dying.append({"node": node, "t": 0.16})


func _retire_dodger(key: String) -> void:
	var st: Dictionary = _dodgers.get(key, {})
	if st.is_empty():
		return
	_dodgers.erase(key)
	var node: Node3D = st["node"]
	_burst(node.position, 7, Color("#e8ddc4"), "paper")
	_dying.append({"node": node, "t": 0.16})
	node.scale = Vector3(0.001, 0.001, 0.001)


## 进来 / 离开舞台。离开时把道具全部清掉，下次进来是干净的一张桌子。
func set_active(on: bool) -> void:
	if not _built:
		return
	if on:
		if render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		if render_target_update_mode != SubViewport.UPDATE_DISABLED:
			render_target_update_mode = SubViewport.UPDATE_DISABLED
			clear()


func clear() -> void:
	for key in _coins.keys():
		var st: Dictionary = _coins[key]
		var node: Node3D = st["node"]
		node.queue_free()
	_coins.clear()
	for key in _dodgers.keys():
		var st: Dictionary = _dodgers[key]
		var node: Node3D = st["node"]
		node.queue_free()
	_dodgers.clear()
	for d in _dying:
		var node: Node3D = d["node"]
		node.queue_free()
	_dying.clear()
	for s in _sparks:
		var node: MeshInstance3D = s["node"]
		node.queue_free()
	_sparks.clear()
	_mode = ""
	if _cursor != null:
		_cursor.visible = false


func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_animate_coins(delta)
	_animate_dodgers(delta)
	_animate_sparks(delta)
	_animate_dying(delta)
	_animate_cursor(delta)


func _key_of(item: Dictionary, field: String, index: int) -> String:
	if item.has(field):
		return str(item[field])
	return "idx" + str(index)
