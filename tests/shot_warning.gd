extends SceneTree

## 临时截图：考核预告横幅（挂起后 3 秒倒计时）的样子。

var game

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	game.queue_redraw()
	for i in range(3):
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.set_process(false) # 冻结帧更新，摆一个预告中的静止画面
	game.pending_challenge = {"tag": "rent", "kind": "collect"}
	game.challenge_warn_t = 2.4
	await snap("tmp_warning.png")
	quit()
