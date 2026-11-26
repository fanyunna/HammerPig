extends SubViewport
class_name Hammer3D

## 第一人称光标锤：单独的透明 3D 视口，随鼠标绘制，局部旋转交给 main.gd。
const VIEW_SIZE := 256
const OBJ_PATH := "res://models/hammer.obj"
static var use_obj := false # 实验开关：true 时用 OBJ 网格替换程序化酒桶锤（默认关，不影响游戏）

func _ready() -> void:
	size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_build()


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mat.metallic_specular = 0.55 if metallic > 0.0 else 0.2
	return mat


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = mat
	item.position = pos
	item.scale = scl
	parent.add_child(item)
	return item


func _cylinder(radius: float, height: float, segments := 24) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _build() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	camera.position = Vector3(0.0, 7.0, 0.01)
	# 正上方俯视；指定屏幕上方向，避免相机朝下时 up 向量与视线平行。
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.20, 0.0), Vector3(0, 0, -1))
	camera.current = true
	add_child(camera)
	var key := DirectionalLight3D.new()
	key.position = Vector3(-3, 5, 4)
	key.light_energy = 1.5
	key.look_at_from_position(key.position, Vector3.ZERO)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.position = Vector3(3, 1, -4)
	fill.light_energy = 0.65
	fill.look_at_from_position(fill.position, Vector3.ZERO)
	add_child(fill)
	if use_obj and ResourceLoader.exists(OBJ_PATH):
		_build_obj_hammer()
		return
	var hammer := Node3D.new()
	# 锤子平放在桌面平面：从上往下看时，锤头在远端、锤柄朝玩家方向延伸。
	hammer.rotation.x = PI / 2.0
	hammer.rotation.z = -0.48
	add_child(hammer)
	# 对齐原版 Bills Must Be Paid：深藏青低多边形羊角锤 + 红橙短柄 + 粉色拳头黑护腕。
	var navy := _material(Color("#2e3a58"), 0.55) # 锤头藏青：哑光低多边形
	var navy_light := _material(Color("#3b4a72"), 0.5) # 打击面端亮一档，区分方向
	var handle_red := _material(Color("#c4573b"), 0.6) # 红橙短柄
	# 柄：短而直，上段被拳头握住
	_mesh(hammer, _cylinder(0.11, 1.15), handle_red, Vector3(0, 0.32, 0))
	_mesh(hammer, _cylinder(0.125, 0.14), handle_red, Vector3(0, -0.22, 0)) # 柄头防脱的加粗节
	# 锤头：打击面（六棱柱，低多边形棱角）→ 楔形头身 → V 形羊角，头轴垂直于柄。
	var face := _mesh(hammer, _cylinder(0.27, 0.34, 6), navy_light, Vector3(-0.55, -0.30, 0))
	face.rotation.z = PI / 2.0
	_mesh(hammer, _cylinder(0.17, 0.14, 6), navy, Vector3(-0.32, -0.30, 0)) # 面与头身之间的收颈
	var cheek := _mesh(hammer, BoxMesh.new(), navy, Vector3(0.02, -0.30, 0))
	cheek.mesh.size = Vector3(0.80, 0.30, 0.24) # 头身：从打击面向羊角渐宽的楔块
	for side in [-1.0, 1.0]:
		var claw := _mesh(hammer, BoxMesh.new(), navy, Vector3(0.36, -0.30 + side * 0.14, 0))
		claw.mesh.size = Vector3(0.50, 0.14, 0.18) # 两根羊角张开成 V，劈口朝远端
		claw.rotation.z = side * 0.45
	_build_human_hand(hammer)


func _build_obj_hammer() -> void:
	## 实验分支：直接用程序化生成的 models/hammer.obj 当光标锤（锤头 OBJ 自带手套方块，另配 3D 手）
	var pivot := Node3D.new()
	pivot.rotation.x = -PI / 2.0 # 平放桌面：局部 -Y（柄方向）映射为世界 +Z（屏幕下方，朝玩家）
	pivot.rotation.z = -0.48
	pivot.scale = Vector3.ONE * 3.0
	pivot.position = Vector3(0.0, 0.0, -0.30)
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = load(OBJ_PATH)
	pivot.add_child(mi)
	var hand_holder := Node3D.new()
	hand_holder.rotation.x = PI / 2.0
	hand_holder.rotation.z = -0.48
	hand_holder.scale = Vector3.ONE * 0.8 # 手按酒桶锤尺度设计的，缩小到贴合 OBJ 细柄
	hand_holder.position = Vector3(0.0, 0.0, 0.02)
	add_child(hand_holder)
	_build_human_hand(hand_holder)


func _segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	## 两关节之间的一节指骨：胶囊沿 a→b 摆放，长度覆盖两端，接缝由关节球盖住。
	var dir := b - a
	var item := MeshInstance3D.new()
	item.mesh = _capsule(radius, maxf(dir.length(), radius * 2.02))
	item.material_override = mat
	item.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), (a + b) * 0.5)
	parent.add_child(item)
	return item


func _build_human_hand(parent: Node3D) -> void:
	## 攥柄拳头：手背整块 + 四指各三节指骨（关节球做指节凸起）+ 两节斜扣拇指 + 黑护腕。
	## 局部约定：柄轴 = Y（+Y 朝玩家），镜头在 -Z 一侧，锤头在 -X。
	var skin := _material(Color("#eda57f"), 0.75)
	var joint_mat := _material(Color("#e2946e"), 0.8) # 关节略深一档，指节分段才看得清
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	# 手背：压扁椭球，朝镜头一侧隆起成拳背
	_mesh(parent, sphere, skin, Vector3(0.04, 0.58, -0.08), Vector3(0.70, 0.55, 0.36))
	# 四指：指根在 +X 侧，先横跨柄身前侧，再绕过 -X 侧收进柄后；长短按指序递变
	var finger_len := [1.00, 1.06, 1.02, 0.90] # 食/中指长，小指短
	for i in range(4):
		var y := 0.78 - float(i) * 0.105
		var s: float = finger_len[i]
		var knuckle := Vector3(0.22, y, -0.14)
		var pts := [
			Vector3(0.22 - 0.20 * s, y, -0.21), # 近节：跨过柄身前侧
			Vector3(0.22 - 0.34 * s, y - 0.01, -0.07), # 中节：绕到柄左侧
			Vector3(0.22 - 0.40 * s, y - 0.02, 0.09) # 远节：收到柄后（被柄挡住）
		]
		var prev := knuckle
		var r := 0.060
		for p in pts:
			_segment(parent, prev, p, r, skin)
			_mesh(parent, sphere, joint_mat, p, Vector3.ONE * r * 2.1) # 关节球：指节凸起
			prev = p
			r *= 0.88 # 指尖略细
		_mesh(parent, sphere, joint_mat, knuckle, Vector3.ONE * 0.16) # 掌指关节
	# 拇指：两节，从掌侧斜 45° 扣下来压在四指根部
	var t0 := Vector3(0.26, 0.40, -0.12)
	var t1 := Vector3(0.10, 0.34, -0.22)
	var t2 := Vector3(-0.06, 0.31, -0.20)
	_segment(parent, t0, t1, 0.072, skin)
	_segment(parent, t1, t2, 0.058, skin)
	_mesh(parent, sphere, joint_mat, t1, Vector3.ONE * 0.17)
	# 手腕、黑护腕、出画的小臂
	_mesh(parent, _cylinder(0.155, 0.24), skin, Vector3(0.02, 0.90, -0.06))
	_mesh(parent, _cylinder(0.19, 0.15), _material(Color("#26262c"), 0.7), Vector3(0.02, 0.985, -0.06))
	_mesh(parent, _cylinder(0.165, 0.40), skin, Vector3(0.02, 1.15, -0.06))
