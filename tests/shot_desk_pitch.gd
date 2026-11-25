extends SceneTree

## 桌面视角对照：镜头更远、机位更低、视野更广，避免极端鸟瞰。
## 用法：Godot --path . --script tests/shot_desk_pitch.gd

var game

# [fov, height, back, tag] —— 目标 30° 低俯角 + 镜头拉远（俯角 = atan((h+0.15)/back)）
const VARIANTS := [
	[42.0, 3.2, 5.8, "a"], # 30.0° 近机位
	[44.0, 3.7, 6.7, "b"], # 29.9° 中距离
	[46.0, 4.2, 7.5, "c"], # 30.1° 远机位
]


func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func rebuild_desk(fov: float, h: float, back: float) -> void:
	if game.desk3d != null:
		game.desk3d.queue_free()
	Desk3D.fov_override = fov
	Desk3D.height_override = h
	Desk3D.back_override = back
	var desk := Desk3D.new()
	game.add_child(desk)
	desk.build(game.DESK_RECT, game.PIG_BOUNDS)
	game.desk3d = desk


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.gamble_used = true
	game.score = 620
	game.broken = 31
	game.stamina = 168.0
	game.combo_count = 9
	game.combo_timer = 1.2
	game.game_day = 5
	game.next_card = 370
	Input.warp_mouse(game.pigs[3].position)
	for v in VARIANTS:
		rebuild_desk(v[0], v[1], v[2])
		var pitch := atan((v[1] + 0.15) / v[2]) # 相机实际俯角（由高度/距离推出）
		for vp in game.pig3d: # 猪同步到桌面俯角（浅 3° 保持一点立体）
			vp.set_cam_pitch(pitch - deg_to_rad(3.0))
		await snap("tmp_desk_v%s.png" % v[3])
	quit()
