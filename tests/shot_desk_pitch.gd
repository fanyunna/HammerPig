extends SceneTree

## 桌面视角对照：45° 高俯视 + 两档透视（宽角近机位 vs 中焦远机位），对照原版截图。
## 用法：Godot --path . --script tests/shot_desk_pitch.gd

var game

# 定稿验证：45° 俯视 + 40° 视野 + 10m 机位（table edge/装饰随桌深比例放大）
const VARIANTS := [
	[45.0, 40.0, 10.0, "a"],
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


func rebuild_desk(pitch: float, fov: float, dist: float) -> void:
	if game.desk3d != null:
		game.desk3d.queue_free()
	Desk3D.pitch_override = deg_to_rad(pitch)
	Desk3D.fov_override = fov
	Desk3D.dist_override = dist
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
		for vp in game.pig3d: # 猪同步到桌面俯角（浅 3° 保持一点立体）
			vp.set_cam_pitch(deg_to_rad(v[0] - 3.0))
		await snap("tmp_desk_v%s.png" % v[3])
	quit()
