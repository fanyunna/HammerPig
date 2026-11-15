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

	# 账单到期考核：凑钱小游戏（检查标题里的账单名 + 面板排版）
	game.bill_open = false
	game.phase = "playing"
	print("STEP challenge")
	game.card_type = "collect"
	game.bill_amount = 80
	game.start_challenge()
	game.collected = 35
	game.coins.clear()
	game.coins.append({"position": Vector2(320, 430), "velocity": Vector2.ZERO, "value": 5, "fake": false, "life": 5.0})
	game.coins.append({"position": Vector2(520, 500), "velocity": Vector2.ZERO, "value": 5, "fake": false, "life": 5.0})
	game.coins.append({"position": Vector2(760, 420), "velocity": Vector2.ZERO, "value": 5, "fake": false, "life": 5.0})
	game.coins.append({"position": Vector2(940, 520), "velocity": Vector2.ZERO, "value": -5, "fake": true, "life": 5.0})
	game.challenge_label = "房租 ¥560"
	await snap("tmp_p1_challenge.png")

	# 代价型新卡：描述比老卡长，检查会不会溢出卡片
	print("STEP card")
	game.phase = "card"
	game.card_type = "reward"
	game.card_offers.clear()
	game.card_offers.append({"id": "onehand", "name": "断臂求生", "desc": "轻锤不再造成伤害，重锤伤害 ×2", "icon": "✂", "color": "#b06b8a"})
	game.card_offers.append({"id": "glasshunter", "name": "玻璃猎人", "desc": "玻璃猪收益 ×3，其余猪种 -30%", "icon": "◆", "color": "#7fa8b4"})
	game.card_offers.append({"id": "allin", "name": "孤注一掷", "desc": "体力上限 -40%，敲猪收益 +80%", "icon": "!", "color": "#e0503f"})
	await snap("tmp_p1_card_new.png")
	quit()
