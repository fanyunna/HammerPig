extends SceneTree

## 临时截图工具：开真实窗口，摆出几种状态各存一张 PNG，看排版与画面状态。

var game

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
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	Input.warp_mouse(Vector2(1180, 760))
	await snap("tmp_p1_intro.png")

	game.intro_open = false
	game.gamble_used = true
	game.score = 620
	game.broken = 31
	game.stamina = 168.0
	game.combo_count = 9
	game.combo_timer = 1.2
	game.game_day = 5
	game.next_card = 370
	for i in range(5):
		if i < game.bills.size():
			game.bills[i]["overdue"] = true
	Input.warp_mouse(game.pigs[3].position)
	await snap("tmp_p1_play.png")

	# 蓄满重锤：准心旁应浮出「重锤」两个字
	game.charging = true
	game.charge_t = 0.5
	await snap("tmp_p1_charge.png")
	game.charging = false
	game.charge_t = 0.0

	game.phase = "finished"
	game.end_reason = "target"
	game.paid_count = 3
	game.meta_shards = 33
	await snap("tmp_p1_result.png")

	game.phase = "playing"
	game.reset_game()
	await process_frame
	game.intro_open = false
	game.score = 400
	game.open_card()
	await snap("tmp_p1_card.png")

	game.phase = "playing"
	game.bill_open = true
	await snap("tmp_p1_ledger.png")
	quit()
