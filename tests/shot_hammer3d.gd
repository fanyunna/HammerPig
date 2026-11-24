extends SceneTree

## 3D 验证：把程序化生成的 models/hammer.obj 导入 Godot，用真实 3D 相机 + 灯光拍一张。

var world: Node3D

func _initialize() -> void:
	run.call_deferred()


func snap(file: String, angle: Vector3) -> void:
	for child in world.get_children():
		if child is MeshInstance3D:
			child.rotation_degrees = angle
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1b2636")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#93a2b8")
	env.ambient_light_energy = 0.75
	we.environment = env
	world.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0.62, 0.18, 0.62)
	cam.fov = 32.0
	world.add_child(cam)
	cam.look_at(Vector3(0.0, -0.22, 0.0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 38, 0)
	key.light_energy = 1.7
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var mi := MeshInstance3D.new()
	var mesh = load("res://models/hammer.obj")
	if mesh == null:
		push_error("hammer.obj 没导入成功")
		quit(1)
		return
	mi.mesh = mesh
	print("mesh surfaces: ", mesh.get_surface_count())
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		print("  surface ", i, " material: ", mat.resource_name if mat else "none")
	world.add_child(mi)
	await snap("tmp_hammer_3d_a.png", Vector3(-8, 0, -38))   # 游戏里的斜握姿态
	await snap("tmp_hammer_3d_b.png", Vector3(-55, 0, -90))  # 从上方看锤头两端箍
	await snap("tmp_hammer_3d_c.png", Vector3(0, 0, -90))     # 正侧视：锤头/柄比例
	quit()
