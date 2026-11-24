extends SceneTree

## 对比截图：贴图锤 vs 程序化酒桶 3D 锤 vs OBJ 网格锤（实验开关只在脚本里打开，不改游戏默认）

var game

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	game.queue_redraw()
	for i in range(4):
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.phase = "playing"
	game.hammer_position = Vector2(640, 420)
	# 1) 当前游戏内的贴图锤（默认）
	await snap("tmp_hammer_cmp_texture.png")
	# 2) 程序化酒桶 3D 锤（关掉贴图就走 3D 分支）
	var tex = game.hammer_tex
	game.hammer_tex = null
	await snap("tmp_hammer_cmp_barrel.png")
	# 3) OBJ 网格锤：重启一个实例并打开实验开关
	game.queue_free()
	await process_frame
	load("res://scripts/hammer3d.gd").use_obj = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.phase = "playing"
	game.hammer_tex = null
	game.hammer_position = Vector2(640, 420)
	await snap("tmp_hammer_cmp_obj.png")
	load("res://scripts/hammer3d.gd").use_obj = false
	quit()
