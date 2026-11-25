extends SceneTree

## 桌面视角对照：镜头更远、机位更低、视野更广，避免极端鸟瞰。
## 用法：Godot --path . --script tests/shot_desk_pitch.gd

var game

# [pitch_deg, fov, dist, area_inset_x, area_inset_top, area_inset_bottom, tag]
const VARIANTS := [
	[36.0, 50.0, 14.0, 70.0, 190.0, 70.0, "a"],
	[32.0, 55.0, 16.0, 80.0, 210.0, 80.0, "b"],
	[40.0, 45.0, 12.0, 60.0, 170.0, 60.0, "c"],
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


func rebuild_desk(pitch: float, fov: float, dist: float, ix: float, it: float, ib: float) -> void:
	if game.desk3d != null:
		game.desk3d.queue_free()
	Desk3D.pitch_override = deg_to_rad(pitch)
	Desk3D.fov_override = fov
	Desk3D.dist_override = dist
	Desk3D.area_override = Rect2(ix, it, Desk3D.VIEW_W - ix * 2.0, Desk3D.VIEW_H - it - ib)
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
		rebuild_desk(v[0], v[1], v[2], v[3], v[4], v[5])
		for vp in game.pig3d: # 猪同步到桌面俯角（浅 3° 保持一点立体）
			vp.set_cam_pitch(deg_to_rad(v[0] - 3.0))
		await snap("tmp_desk_v%s.png" % v[6])
	quit()
