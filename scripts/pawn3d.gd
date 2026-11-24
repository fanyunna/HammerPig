extends SubViewport
class_name Pawn3D

## 当铺砍价的 3D 场景层：柜台、老板、待价小猪、拍板木槌、铜钱。
## 只负责"场景"这一条，价格条 / 按钮 / 文案仍是 main 的 2D 画布叠加 —— 混合渲染和 pig3d 一致。
## 渲染进透明 SubViewport，day_events._draw_pawn() 把纹理贴回面板下缘。

const VIEW_W := 680
const VIEW_H := 240
const COUNTER_Y := 0.78 # 柜台上表面高度（世界单位）
const MALLET_OBJ := "res://models/hammer.obj"

var _root3d: Node3D
var _mallet_pivot: Node3D
var _pig: Node3D
var _coins: Node3D
var _boss: Node3D
var _sign: Node3D
var _t := 0.0
var _bang := 0.0
var _state := ""


func _ready() -> void:
	size = Vector2i(VIEW_W, VIEW_H)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_build()


func _process(delta: float) -> void:
	_t += delta
	# 拍板余震 / 招牌轻晃 / 成交后铜钱滚动：全部在这里做，主逻辑只喂状态
	if _mallet_pivot != null:
		var prog := clampf(_bang / 0.35, 0.0, 1.0) # 1 = 刚扬起，0 = 已落定
		_mallet_pivot.position.y = COUNTER_Y + 0.26 + 0.55 * prog # 拍板：跳起再砸回柜台
		_mallet_pivot.rotation.z = 0.55 * prog
	if _sign != null:
		_sign.rotation.z = sin(_t * 1.3) * 0.06
	if _pig != null:
		var squash := 1.0 + 0.06 * sin(_t * 6.0) * (1.0 if _state == "result" else 0.25)
		_pig.scale = Vector3(1.0 / squash, squash, 1.0)
	if _coins != null:
		_coins.visible = _state == "result"
		if _coins.visible:
			_coins.position.y = absf(sin(_t * 3.0)) * 0.03


func set_state(state: String, bang: float) -> void:
	_state = state
	_bang = bang


# ---------------------------------------------------------------- 材质

func _mat(color: Color, rough := 0.72, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	m.metallic_specular = 0.3 if metallic > 0.0 else 0.18
	m.rim = 0.06
	m.rim_tint = 0.5
	return m


func _ceramic(color: Color, rough := 0.55) -> StandardMaterial3D:
	## 陶猪釉面：和 pig3d 同一套参数，保证场里的猪和桌上的猪是一家人
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.0
	m.roughness = rough
	m.metallic_specular = 0.16
	m.rim = 0.07
	m.rim_tint = 0.55
	return m


# ---------------------------------------------------------------- 图元

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	item.rotation = rot
	parent.add_child(item)
	return item


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segs
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	item.rotation = rot
	parent.add_child(item)
	return item


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	item.scale = scl
	parent.add_child(item)
	return item


# ---------------------------------------------------------------- 场景

func _build() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 32.0
	cam.position = Vector3(0.6, 2.75, 8.2)
	cam.look_at_from_position(cam.position, Vector3(0.4, 1.30, 0.0))
	cam.current = true
	add_child(cam)

	var key := DirectionalLight3D.new()
	key.position = Vector3(-3.5, 5.5, 5.0)
	key.look_at_from_position(key.position, Vector3(0, 1.0, 0))
	key.light_energy = 1.35
	key.light_color = Color("#ffd9a8") # 当铺是油灯色温，冷光会让陶猪显脏
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.position = Vector3(4.0, 1.5, 3.0)
	fill.look_at_from_position(fill.position, Vector3(0, 1.0, 0))
	fill.light_energy = 0.45
	fill.light_color = Color("#a8c0ff")
	add_child(fill)

	_root3d = Node3D.new()
	add_child(_root3d)
	_build_room()
	_build_boss()
	_build_pig()
	_build_mallet()
	_build_coins()


func _build_room() -> void:
	var wall := _mat(Color("#2b1d13"), 0.9)
	var wood_top := _mat(Color("#7a5433"), 0.75)
	var wood_front := _mat(Color("#543823"), 0.8)
	var line := _mat(Color("#3a2c20"), 0.85)
	# 背墙：一块暗木板，让柜台和老板有依托，不至于悬在面板底色上
	_box(_root3d, Vector3(9.0, 5.0, 0.3), Vector3(0.4, 2.3, -2.6), wall)
	# 柜台：台面 + 前立面 + 一道压边
	_box(_root3d, Vector3(8.4, 0.16, 1.7), Vector3(0.4, COUNTER_Y, 0.55), wood_top)
	_box(_root3d, Vector3(8.4, 1.25, 0.35), Vector3(0.4, COUNTER_Y - 0.70, 1.25), wood_front)
	_box(_root3d, Vector3(8.4, 0.06, 0.36), Vector3(0.4, COUNTER_Y + 0.02, 1.25), line)


func _build_boss() -> void:
	_boss = Node3D.new()
	_boss.position = Vector3(2.35, COUNTER_Y, -0.35)
	_boss.scale = Vector3.ONE * 0.85 # 整体缩一档：头顶别顶到画面上缘，帽子才有展示空间
	_root3d.add_child(_boss)
	var skin := _mat(Color("#e3b489"), 0.62)
	var hat := _mat(Color("#7d3226"), 0.5) # 瓜皮帽改暗红：黑帽和暗背墙会融成一片
	var knot := _mat(Color("#a5432a"), 0.6)
	var ink := _mat(Color("#3a2c20"), 0.5)
	var cloth := _mat(Color("#4a3122"), 0.85)
	# 身子藏在柜台后
	_sphere(_boss, 1.0, Vector3(0, 0.35, -0.2), cloth, Vector3(1.15, 0.95, 0.85))
	# 脑袋
	_sphere(_boss, 0.78, Vector3(0, 1.42, 0), skin, Vector3(1.0, 1.06, 0.95))
	# 瓜皮帽：扁球帽顶扣在头顶 + 红结（帽心要在头顶之上，只让下半截埋进脑袋才是"扣着"）
	_sphere(_boss, 0.72, Vector3(0, 2.35, 0), hat, Vector3(1.06, 0.50, 1.02))
	_sphere(_boss, 0.10, Vector3(0, 2.74, 0), knot, Vector3(1.0, 1.2, 1.0))
	# 眯成缝的笑眼（两道压扁的深色弧）+ 八字胡
	for side in [-1.0, 1.0]:
		_sphere(_boss, 0.10, Vector3(0.27 * side, 1.50, 0.71), ink, Vector3(1.5, 0.45, 0.5))
		var mustache := _cyl(_boss, 0.045, 0.34, Vector3(0.20 * side, 1.20, 0.72), ink)
		mustache.rotation.z = PI * 0.5 * side
		mustache.rotation.y = -0.35 * side
	# 报着的嘴
	_sphere(_boss, 0.07, Vector3(0, 1.06, 0.73), ink, Vector3(1.6, 0.7, 0.5))


func _build_pig() -> void:
	# 红绸垫 + 待价而沽的小陶猪：造型和 pig3d 同源（陶瓷釉面、圆胖、短鼻、投币口）
	var cushion := _cyl(_root3d, 0.92, 0.14, Vector3(-1.75, COUNTER_Y + 0.07, 0.35), _mat(Color("#8a3a2e"), 0.8), Vector3.ZERO, 28)
	cushion.name = "Cushion"
	_pig = Node3D.new()
	_pig.position = Vector3(-1.75, COUNTER_Y + 0.30, 0.35)
	_root3d.add_child(_pig)
	var pink := _ceramic(Color("#f7c2bf"))
	var deeper := _ceramic(Color("#e8a5a8"))
	var ink := _mat(Color("#3a2620"), 0.5)
	var slot := _mat(Color("#4a2e22"), 0.9)
	_sphere(_pig, 0.60, Vector3.ZERO, pink, Vector3(1.06, 0.86, 0.98))
	# 鼻君：朝镜头的短圆筒 + 两个鼻孔
	_cyl(_pig, 0.23, 0.14, Vector3(0, -0.02, 0.55), deeper, Vector3(PI * 0.5, 0, 0), 18)
	for dx in [-1.0, 1.0]:
		_sphere(_pig, 0.045, Vector3(0.09 * dx, -0.02, 0.63), ink, Vector3(1, 1, 0.5))
	# 耳朵
	for dx in [-1.0, 1.0]:
		_sphere(_pig, 0.17, Vector3(0.38 * dx, 0.44, 0.05), deeper, Vector3(1.0, 0.9, 0.6))
	# 眼
	for dx in [-1.0, 1.0]:
		_sphere(_pig, 0.055, Vector3(0.27 * dx, 0.20, 0.54), ink)
	# 投币口
	_box(_pig, Vector3(0.30, 0.03, 0.07), Vector3(0, 0.50, 0.06), slot)


func _build_mallet() -> void:
	## 复用程序化生成的 hammer.obj：拍板锤平躺在柜台上，拍板时跳起来砸下
	_mallet_pivot = Node3D.new()
	_mallet_pivot.position = Vector3(-0.80, COUNTER_Y + 0.26, 0.85)
	_root3d.add_child(_mallet_pivot)
	_mallet_pivot.rotation.y = -0.7 # 锤头朝左前，柄斜向右后：像随手搁在柜台上
	if ResourceLoader.exists(MALLET_OBJ):
		var mi := MeshInstance3D.new()
		mi.mesh = load(MALLET_OBJ)
		mi.scale = Vector3.ONE * 2.1
		mi.rotation.x = PI * 0.5 # OBJ 是竖直握持，转成平躺
		_mallet_pivot.add_child(mi)
	else:
		_box(_mallet_pivot, Vector3(0.7, 0.22, 0.24), Vector3(0, 0.7, 0), _mat(Color("#b9854e"), 0.7))


func _build_coins() -> void:
	_coins = Node3D.new()
	_coins.position = Vector3(-0.55, COUNTER_Y + 0.10, 0.75)
	_coins.visible = false
	_root3d.add_child(_coins)
	var gold := _mat(Color("#d9a94a"), 0.35, 0.75)
	var hole := _mat(Color("#543823"), 0.8)
	for i in range(4):
		var p := Vector3(0.30 + 0.26 * i, 0.03 * (i % 2), 0.02 * (i % 3))
		_cyl(_coins, 0.15, 0.045, p, gold, Vector3.ZERO, 18)
		_cyl(_coins, 0.05, 0.05, p, hole, Vector3.ZERO, 12)
