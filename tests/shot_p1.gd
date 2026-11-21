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

	# 账单到期考核：3D 舞台（凑钱）—— 金币落定后悬停一枚，看高亮与币面
	game.bill_open = false
	game.phase = "playing"
	print("STEP challenge")
	game.card_type = "collect"
	game.bill_amount = 80
	game.bill_timer = 38.0
	game.start_challenge()
	game.challenge_label = "房租 ¥560"
	game.bill_timer = 38.0
	game.collected = 35
	game.coins.clear()
	var coin_spots := [Vector2(300, 380), Vector2(520, 500), Vector2(700, 360), Vector2(880, 530), Vector2(1040, 410)]
	for i in range(coin_spots.size()):
		game.coin_uid += 1
		game.coins.append({"position": coin_spots[i], "velocity": Vector2.ZERO, "value": 5,
			"fake": i == 3, "life": 9.0, "vcid": game.coin_uid})
	Input.warp_mouse(Vector2(700, 372)) # 停在一枚金币上：看悬停高亮
	for i in range(45):
		game.challenge3d._process(0.04) # 快进物理，让金币落到台面上
	await snap("tmp_p1_challenge.png")

	# 躲催债：一圈礼帽催收员围过来，光标环因危险变红
	print("STEP dodge")
	game.card_type = "dodge"
	game.bill_amount = 560
	game.start_challenge()
	game.challenge_label = "房租 ¥560"
	game.bill_timer = 26.0
	game.dodge_lives = 3
	game.dodgers.clear()
	var dodger_spots := [Vector2(200, 400), Vector2(400, 600), Vector2(640, 660), Vector2(980, 430), Vector2(1120, 620), Vector2(520, 350)]
	for i in range(dodger_spots.size()):
		game.dodger_uid += 1
		game.dodgers.append({"position": dodger_spots[i], "life": 9.0, "seed": float(i), "dcid": game.dodger_uid})
	Input.warp_mouse(Vector2(760, 470))
	for i in range(25):
		game.challenge3d._process(0.04)
	await snap("tmp_p1_dodge.png")

	# 2D 回退（challenge_3d:false / 老机器）：确认没有 3D 时版面也立得住
	print("STEP fallback")
	var saved_3d = game.challenge3d
	game.challenge3d = null
	await snap("tmp_p1_challenge_2d.png")
	game.challenge3d = saved_3d

	# 悬赏板：普通态 + 确认态（黄框脉冲 + "再点一次开打"）
	print("STEP bounty")
	game.phase = "playing"
	game.reset_game()
	await process_frame
	game.intro_open = false
	game.gamble_used = true
	game.score = 420
	game.stamina = 190.0
	Input.warp_mouse(Vector2(640, 500))
	await snap("tmp_p1_bounty.png")
	game.bounty_armed = true
	game.bounty_arm_t = 3.0 # 确认倒计时也要一起给，否则下一帧就被 _process 收回
	await snap("tmp_p1_bounty_armed.png")
	game.bounty_armed = false

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
