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

	# 单张放大：旧纸质的催缴通知单（霉斑 / 茶渍 / 折痕 / 装订孔 / 印章）
	game.bill_detail = 0
	await snap("tmp_p1_detail.png")
	game.bill_detail = -1
	game.bill_open = false

	# 账单到期考核：摆钱凑整（三张路子卡 + 桌上那沓钱 + 轮次倒计时）
	game.bill_open = false
	game.phase = "playing"
	print("STEP collect")
	game.card_type = "collect"
	game.bill_amount = 50
	game.start_challenge()
	game.challenge_label = "房租 ¥50"
	game.collected = 15
	game.bill_timer = 8.4
	Input.warp_mouse(Vector2(640, 500))
	await snap("tmp_p1_collect.png")

	# 选了一张：卡面抬起高亮、飘字飞出来（顺手看钱堆变厚）
	game.collected = 33
	game.collect_picked = 1
	game.collect_pick_t = 0.4
	await snap("tmp_p1_collect_pick.png")
	game.collect_picked = -1
	game.collect_pick_t = 0.0

	# 躲催债：逃跑场面（开场演出 + 鼠标自由上下跑）
	print("STEP dodge")
	game.card_type = "dodge"
	game.bill_amount = 560
	game.start_challenge()
	game.challenge_label = "房租 ¥560"
	game.bill_timer = 26.0
	game.escape.mouse_control = false # 截图不跟鼠标：固定构图，画面才可复现
	game.escape.target_y = game.escape._row_y(1)
	game.escape.runner_y = game.escape.target_y
	game.escape.forced_obstacles.assign([{"row": 2, "kind": "bin"}, {"row": 0, "kind": "barrier"},
		{"row": 1, "kind": "bin"}, {"row": 0, "kind": "barrier"}, {"row": 2, "kind": "bin"},
		{"row": 1, "kind": "bin"}, {"row": 0, "kind": "barrier"}, {"row": 2, "kind": "bin"}])
	for i in range(24): # 跳过演出（2.2s）再跑 ~2.6 秒：障碍铺开、催债人吊在身后
		game.escape.update(0.2)
	await snap("tmp_p1_dodge.png")

	# 2D 回退（challenge_3d:false / 老机器）：确认没有 3D 时版面也立得住
	print("STEP fallback")
	var saved_3d = game.challenge3d
	game.challenge3d = null
	await snap("tmp_p1_collect_2d.png")
	game.challenge3d = saved_3d

	# 催收预警板：正常态（还有多远上门 / 还能来几次）
	print("STEP board")
	game.phase = "playing"
	game.reset_game()
	game.game_day = 1 # 别让天数里程碑的小游戏浮层弹出来挡住横梁
	game.day_events._close()
	await process_frame
	game.intro_open = false
	game.gamble_used = true
	game.score = 420
	game.stamina = 190.0
	Input.warp_mouse(Vector2(640, 500))
	await snap("tmp_p1_board.png")

	# 天数里程碑小游戏：当铺 / 赌桌 / 电话
	print("STEP day events")
	game.day_events._open("pawn")
	game.day_events.pawn_t = 0.1 # 摆到中高价区，看指针与三档色带
	await snap("tmp_p1_pawn.png")
	game.day_events._close()

	game.day_events._open("dice")
	game.day_events.forced_deck.assign([10, 13, 8, 6, 6])
	game.day_events.handle_click(Vector2(game.day_events.BET_RECTS[0].get_center()))
	await snap("tmp_p1_dice.png")
	game.day_events.handle_click(Vector2(game.day_events.STAND_RECT.get_center())) # 20 对 20 → 平局结算
	await snap("tmp_p1_dice_result.png")
	game.day_events._close()
	game.day_events.forced_deck.clear()

	game.day_events._open("calls")
	game.day_events.forced_sequence.assign([3, 1, 0, 2])
	for i in range(3):
		game.day_events._process(0.1) # 记忆阶段：第一枚气泡高亮响铃
	await snap("tmp_p1_calls_memo.png")
	for i in range(10):
		game.day_events._process(0.5) # 进入复现阶段
	await snap("tmp_p1_calls_play.png")
	game.day_events._close()
	game.day_events.forced_sequence.clear()

	# 代价型新卡：描述比老卡长，检查会不会溢出卡片
	print("STEP card")
	game.phase = "card"
	game.card_type = "reward"
	game.card_offers.clear()
	game.card_offers.append({"id": "onehand", "name": "断臂求生", "desc": "轻锤不再造成伤害，重锤伤害 ×2", "icon": "✂", "color": "#b06b8a"})
	game.card_offers.append({"id": "glasshunter", "name": "玻璃猎人", "desc": "玻璃猪收益 ×3，其余猪种 -30%", "icon": "◆", "color": "#7fa8b4"})
	game.card_offers.append({"id": "allin", "name": "孤注一掷", "desc": "体力上限 -40%，敲猪收益 +80%", "icon": "!", "color": "#e0503f"})
	await snap("tmp_p1_card_new.png")

	# 传承商店：结算画面上打开，带点碎片和已买等级看档位显示
	print("STEP legacy")
	game.phase = "finished"
	game.end_reason = "exhausted"
	game.meta_shards = 17
	game.meta_shop = {"watch": 1, "ring": 2}
	await snap("tmp_p1_finished_legacy.png") # 结算面板：带传承商店入口按钮
	game.shop_open = true
	await snap("tmp_p1_legacy_shop.png")
	game.shop_open = false
	quit()
