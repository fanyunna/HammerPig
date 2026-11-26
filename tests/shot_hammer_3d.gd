extends SceneTree

## 3D 锤款式对照：程序化酒桶锤（use_obj=false）vs models/hammer.obj 网格锤（true）。
## 用法：Godot --path . --script tests/shot_hammer_3d.gd （必须非 headless）

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	Input.warp_mouse(Vector2(860, 520)) # 桌面中间，锤子完整可见且不悬停 UI
	for v in [[false, "barrel"], [true, "obj"]]:
		Hammer3D.use_obj = v[0]
		if game.hammer3d != null:
			game.hammer3d.queue_free()
			game.hammer3d = null
		var h := Hammer3D.new()
		game.add_child(h)
		game.hammer3d = h
		await process_frame
		await process_frame
		await snap("tmp_hammer_%s.png" % v[1])
	quit()
