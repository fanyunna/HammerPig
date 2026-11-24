extends SceneTree

## 桌面俯角对照：同一帧游戏画面渲染 5 个俯角，用于和原版《账单必须支付》截图比对。
## 用法：Godot --path . --script tests/shot_desk_pitch.gd

var game

const PITCHES := [0.70, 0.79, 0.87, 0.96, 1.047] # 40° / 45° / 50° / 55° / 60°


func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func rebuild_desk(pitch: float) -> void:
	if game.desk3d != null:
		game.desk3d.queue_free()
	Desk3D.pitch_override = pitch
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
	for pitch in PITCHES:
		rebuild_desk(pitch)
		await snap("tmp_desk_p%d.png" % int(round(rad_to_deg(pitch))))
	quit()
