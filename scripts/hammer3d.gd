extends SubViewport
class_name Hammer3D

## 第一人称光标锤：单独的透明 3D 视口，随鼠标绘制，局部旋转交给 main.gd。
const VIEW_SIZE := 256

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
	var hammer := Node3D.new()
	# 锤子平放在桌面平面：从上往下看时，锤头在前、锤柄朝玩家方向延伸。
	hammer.rotation.x = PI / 2.0
	hammer.rotation.z = -0.48
	add_child(hammer)
	var wood := _material(Color("#754323"), 0.38)
	var wood_light := _material(Color("#a96b36"), 0.42)
	var steel := _material(Color("#aeb8bd"), 0.24, 0.82)
	var steel_edge := _material(Color("#d5dcdd"), 0.2, 0.75)
	var steel_dark := _material(Color("#4d5a60"), 0.32, 0.65)
	var brass := _material(Color("#bd8738"), 0.28, 0.72)
	# 木柄：中段略细，两端有圆弧过渡，握持区缠深色防滑胶。
	_mesh(hammer, _cylinder(0.105, 1.35), wood, Vector3(0, 0.10, 0))
	_mesh(hammer, _cylinder(0.115, 0.43), wood_light, Vector3(0, 0.22, 0))
	_mesh(hammer, _cylinder(0.13, 0.28), _material(Color("#292522"), 0.78), Vector3(0, 0.67, 0))
	_mesh(hammer, _cylinder(0.14, 0.12), brass, Vector3(0, 0.82, 0))
	# 锤头主体与两端面：钢质长方锤头，倒角亮边和暗侧面拉开体积。
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(1.25, 0.38, 0.46)
	_mesh(hammer, head_mesh, steel, Vector3(0, -0.62, 0))
	var face := _mesh(hammer, _cylinder(0.25, 0.09), steel_edge, Vector3(-0.66, -0.62, 0), Vector3(0.72, 1, 1.08))
	face.rotation.z = PI / 2.0
	var peen := _mesh(hammer, _cylinder(0.25, 0.09), steel_dark, Vector3(0.66, -0.62, 0), Vector3(0.72, 1, 1.08))
	peen.rotation.z = PI / 2.0
	# 锤眼压圈与楔形木楔，让锤头和木柄看起来确实锁在一起。
	_mesh(hammer, _cylinder(0.17, 0.1), brass, Vector3(0, -0.38, 0))
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.12, 0.035, 0.12)
	_mesh(hammer, wedge, steel_dark, Vector3(0, -0.43, 0))
	# 沿锤头上沿留一条窄高光，模拟磨亮的钢面。
	var glint := BoxMesh.new()
	glint.size = Vector3(0.82, 0.018, 0.012)
	_mesh(hammer, glint, steel_edge, Vector3(-0.04, -0.43, 0.235))
	_build_human_hand(hammer)


func _build_human_hand(parent: Node3D) -> void:
	# 一体式手背轮廓：腕部、掌心、四指和外展拇指连成同一个挤出网格，避免木偶式拼接。
	var hand := CSGPolygon3D.new()
	hand.mode = CSGPolygon3D.MODE_DEPTH
	hand.depth = 0.20
	hand.smooth_faces = true
	hand.polygon = PackedVector2Array([
		Vector2(-0.22, 1.23), Vector2(-0.27, 1.08), Vector2(-0.34, 0.94),
		Vector2(-0.35, 0.73), Vector2(-0.33, 0.58),
		# 小指：短而略向内弯
		Vector2(-0.31, 0.39), Vector2(-0.29, 0.31), Vector2(-0.25, 0.28), Vector2(-0.21, 0.31), Vector2(-0.19, 0.43),
		# 无名指
		Vector2(-0.16, 0.30), Vector2(-0.12, 0.26), Vector2(-0.08, 0.28), Vector2(-0.07, 0.43),
		# 中指
		Vector2(-0.035, 0.27), Vector2(0.01, 0.24), Vector2(0.055, 0.27), Vector2(0.06, 0.44),
		# 食指
		Vector2(0.10, 0.30), Vector2(0.15, 0.28), Vector2(0.19, 0.32), Vector2(0.18, 0.49),
		Vector2(0.25, 0.55), Vector2(0.30, 0.51),
		# 拇指根部向外展开，再回扣到握柄上
		Vector2(0.39, 0.59), Vector2(0.43, 0.68), Vector2(0.40, 0.77),
		Vector2(0.34, 0.82), Vector2(0.28, 0.76), Vector2(0.24, 0.68),
		Vector2(0.28, 0.94), Vector2(0.27, 1.09), Vector2(0.23, 1.23)
	])
	hand.position = Vector3(0.0, 0.0, 0.14)
	hand.material = _material(Color("#d99a78"), 0.78)
	parent.add_child(hand)
	# 掌骨与指节的柔和体积：薄椭球贴在一体轮廓上，表现掌丘、四个掌指关节和拇指球。
	var knuckle_mat := _material(Color("#e6ad8b"), 0.72)
	var palm_mat := _material(Color("#cf8c6c"), 0.82)
	_mesh(parent, _capsule(0.18, 0.32), palm_mat, Vector3(-0.16, 0.76, 0.245), Vector3(1.0, 1.0, 0.34))
	_mesh(parent, _capsule(0.18, 0.34), knuckle_mat, Vector3(0.17, 0.78, 0.245), Vector3(1.0, 1.0, 0.34))
	for i in range(4):
		var x := -0.235 + float(i) * 0.145
		_mesh(parent, _capsule(0.052, 0.105), knuckle_mat, Vector3(x, 0.50, 0.265), Vector3(1.0, 1.0, 0.52))
	# 皮肤色指甲按四指自然排布，朝锤头的一端可见。
	var nail_mat := _material(Color("#efcfbb"), 0.52)
	for i in range(4):
		var x := -0.245 + float(i) * 0.145
		_mesh(parent, _capsule(0.022, 0.060), nail_mat, Vector3(x, 0.32, 0.266), Vector3(1.0, 1.0, 0.34))
	_mesh(parent, _capsule(0.045, 0.12), nail_mat, Vector3(0.35, 0.64, 0.267), Vector3(1.0, 1.0, 0.34))
