extends SceneTree

## 桌面俯角对照：同一帧游戏画面渲染多个俯角，桌面与猪同步改角度，用于和原版截图比对。
## 用法：Godot --path . --script tests/shot_desk_pitch.gd

var game

# 俯角（度）：桌面用的角度；猪比桌面浅 3°，贴近原版里猪略微"立"一点的观感
const PITCHES_DEG := [60, 67, 75]


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
	for deg in PITCHES_DEG:
		var pitch := deg_to_rad(float(deg))
		rebuild_desk(pitch)
		for vp in game.pig3d: # 猪必须跟着桌面同档俯角，否则会像立在桌上
			vp.set_cam_pitch(pitch - deg_to_rad(3.0))
		await snap("tmp_desk_p%d.png" % deg)
	quit()
