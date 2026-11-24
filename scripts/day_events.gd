extends Node

## 第十一轮：天数里程碑小游戏 —— 当铺砍价 / 赌桌比大小 / 催债电话连打。
## 设计案：docs/round11-minigames-design.md。调度 + 三个玩法合并成一个模块：
## 它们共享同一块面板骨架（Rect2 290,84,700,632）和确认按钮，拆三份只会重复。
## 低侵入契约（main 只碰这些）：
##   setup(host) / reset_run() / is_open() / handle_click(point) / handle_key(code)
##   输入转发、整局暂停由 main 负责；动画与调度在本模块自己的 _process 里。

const PANEL_RECT := Rect2(290, 84, 700, 632)
const CONFIRM_RECT := Rect2(545, 648, 190, 50) # 结果态的「收下」，与转盘同位
const SCHEDULE := {2: "pawn", 4: "dice", 6: "calls"} # 天数 → 玩法
const Pawn3DScript := preload("res://scripts/pawn3d.gd")
const MAX_PER_RUN := 3
const GAP_SECONDS := 0.5 # 两场事件之间的最短间隔
const WARN_SECONDS := 1.8 # 开桌前预警：顶部横幅先喊一嗓子，别让弹窗凭空砸脸
const OPEN_GRACE := 0.5 # 入场缓冲：刚弹出的半秒内吞掉点击，防敲猪连点误触

# —— 当铺砍价 ——
const PAWN_BASE := 180
const PAWN_CENTER := 1.45 # 指针中值：区间 0.7 ~ 2.2 的正中
const PAWN_AMP := 0.75
const PAWN_PERIOD := 1.4 # 第一刀的摆动周期（秒）
const PAWN_PERIOD_2 := 1.15 # 第二刀加速 20%
const PAWN_REROLL_RECT := Rect2(325, 648, 190, 50)

# —— 赌桌 ——
const BET_RECTS := [Rect2(320, 560, 170, 54), Rect2(515, 560, 170, 54), Rect2(710, 560, 170, 54)]
const HIT_RECT := Rect2(400, 560, 180, 54)
const STAND_RECT := Rect2(700, 560, 180, 54)
const DEALER_STAND := 17
const POOR_WIN := 80 # 赊账局的赏金
const POOR_FAIL_STAMINA := 20.0

# —— 催债电话 ——
const CALL_SLOTS := [Vector2(400, 250), Vector2(660, 220), Vector2(900, 270), Vector2(430, 440), Vector2(680, 480), Vector2(905, 440)]
const CALL_RADIUS := 56.0
const CALL_COUNTS := [4, 5, 6]
const CALL_MEMO := [1.5, 1.3, 1.1]
const CALL_PLAY := [6.0, 5.5, 5.0]
const CALL_REWARD := 120
const CALL_FAIL_STAMINA := 45.0

var main # 主游戏节点（main.gd），setup() 注入
var pawn3d # 当铺 3D 场景视口（settings.pawn_3d 控制；headless 下为 null，自绘作保底）
var served := 0 # 本局已发的事件数（上限 MAX_PER_RUN）
var last_day := 0 # 已处理到的日历天数：跨天只发新里程碑，不重发
var pending: Array[String] = [] # 排队中的事件：一次只放一场，被打断就顺延
var gap_t := 0.0
var active := "" # "" / pawn / dice / calls
var warn_id := "" # 预警中的事件：横幅先提示，倒计时走完才真正开桌
var warn_t := 0.0
var grace_t := 0.0 # 入场缓冲剩余时间：>0 时吞掉一切点击

# —— 当铺状态 ——
var pawn_state := "" # swing / preview / result
var pawn_t := 0.0 # 指针相位
var pawn_period := PAWN_PERIOD
var pawn_clicks := 0 # 0 = 第一刀待砍，1 = 只剩最后一刀
var pawn_locked_mul := 0.0 # 第一刀锁定的倍率
var pawn_final := false # 已经砍到第二刀（结果不可反悔）
var pawn_item := "" # 典当品名
var open_t := 0.0 # 弹窗入场动画：0→1，"啪"地拍在桌上的弹出感
var pawn_bang := 0.0 # 当铺拍板落锤动画剩余时间
var dice_flip := 0.0 # 赌桌庄家翻牌动画剩余时间（>0 时暗牌还扣着）
var settle_t := 0.0 # 结算演出剩余时间（筹码/电话的胜负表现）

# —— 赌桌状态 ——
var dice_state := "" # bet / player / dealer / result
var dice_bet := 0
var dice_poor := false # 余额不足 ¥50：赊账局
var dice_hand: Array[int] = []
var dice_dealer: Array[int] = []
var dice_outcome := "" # win / lose / push
var forced_deck: Array[int] = [] # 测试专用：非空时发牌只从这里取

# —— 电话状态 ——
var calls_state := "" # memo / play / result
var calls_round := 0 # 第几次触发：难度按它取档
var calls_seq: Array[int] = []
var calls_next := 0 # 玩家点到序列第几位
var calls_done: Array[bool] = []
var calls_t := 0.0 # memo 每个气泡的停留 / play 剩余时间
var calls_memo_i := 0
var calls_win := false
var forced_sequence: Array[int] = [] # 测试专用：非空时直接用它当铃声顺序

func setup(host) -> void:
	main = host
	# 当铺 3D 场景：和 pig3d 同一套做法——透明 SubViewport 贴回画布。
	# headless 渲染驱动是 dummy（纹理无像素），必须回退 2D 自绘，否则冒烟测试会看不见柜台。
	if main != null and not DisplayServer.get_name().contains("headless"):
		if bool(main.settings.get("pawn_3d", true)):
			pawn3d = Pawn3DScript.new()
			add_child(pawn3d)

func is_open() -> bool:
	return active != ""

func reset_run() -> void:
	last_day = 1 if main == null else int(main.game_day)
	served = 0
	pending.clear()
	gap_t = 0.0
	warn_id = ""
	warn_t = 0.0
	active = ""
	pawn_state = ""
	dice_state = ""
	calls_state = ""
	calls_round = 0
	forced_deck.clear()
	forced_sequence.clear()

# ---------------------------------------------------------------- 调度

func _process(delta: float) -> void:
	if main == null:
		return
	gap_t = maxf(0.0, gap_t - delta)
	if warn_id != "": # 预警倒计时：走完才开桌；期间被账单/转盘抢先就退回队列顺延
		warn_t -= delta
		if warn_t <= 0.0:
			if _can_open():
				served += 1
				_open(warn_id)
				gap_t = GAP_SECONDS
			else:
				pending.push_front(warn_id)
			warn_id = ""
	if active != "": # 公共计时
		open_t = minf(1.0, open_t + delta * 4.0)
		pawn_bang = maxf(0.0, pawn_bang - delta)
		dice_flip = maxf(0.0, dice_flip - delta)
		settle_t = maxf(0.0, settle_t - delta)
	if active == "dice" and dice_state == "dealer": # 翻牌动画走完：庄家才补牌结算
		if dice_flip <= 0.0:
			_dealer_play()
	_schedule_check()
	if active == "pawn" and pawn_state == "swing":
		pawn_t += delta
	if active != "":
		grace_t = maxf(0.0, grace_t - delta) # 入场缓冲计时
	if active == "calls" and calls_state == "memo":
		calls_t -= delta
		if calls_t <= 0.0:
			calls_memo_i += 1
			if calls_memo_i >= calls_seq.size():
				calls_state = "play"
				calls_t = float(CALL_PLAY[mini(calls_round, CALL_PLAY.size() - 1)])
			else:
				calls_t = float(CALL_MEMO[mini(calls_round, CALL_MEMO.size() - 1)]) / float(calls_seq.size())
	elif active == "calls" and calls_state == "play":
		calls_t -= delta
		if calls_t <= 0.0:
			_calls_end(false) # 超时：和点错一样判负

func _schedule_check() -> void:
	var day := int(main.game_day)
	if day > last_day: # 跨过的里程碑全部入队（advance_calendar 一帧可能跨多天）
		for m in range(last_day + 1, day + 1):
			if SCHEDULE.has(m) and served < MAX_PER_RUN:
				pending.append(String(SCHEDULE[m]))
		last_day = day
	if warn_id != "":
		return # 预警中：等倒计时走完
	if pending.is_empty() or active != "" or gap_t > 0.0:
		return
	if not _can_open():
		return # 账单考核 / 转盘 / 弹窗在场：顺延，不丢弃
	# 不直接开桌：先在顶部喊一嗓子，给玩家收尾手里活的时间
	warn_id = pending.pop_front()
	warn_t = WARN_SECONDS

func _can_open() -> bool:
	return main.phase == "playing" and not main.intro_open \
		and not main.wheel.is_open() and not main.build.panel_open \
		and not main.bill_open and main.bill_detail < 0 \
		and not main.quick_bill_hover() and not main.help_open \
		and main.pending_challenge.is_empty() \
		and main.gamble_state != "flip" and main.gamble_state != "result"

func _open(id: String) -> void:
	active = id
	open_t = 0.0 # 重新起播入场动画
	pawn_bang = 0.0
	dice_flip = 0.0
	settle_t = 0.0
	match id:
		"pawn":
			pawn_state = "ready" # 先待命：指针不摆、点哪都不算，明确点「开砍」才开始
			pawn_t = -PAWN_PERIOD * 0.25 # 显示位置贴着 0.7x
			pawn_period = PAWN_PERIOD
			pawn_clicks = 0
			pawn_locked_mul = 0.0
			pawn_final = false
			pawn_item = _pawn_pick_item()
			Sound.play("card")
		"dice":
			dice_poor = int(main.score) < 50
			dice_state = "bet"
			dice_hand.clear()
			dice_dealer.clear()
			dice_outcome = ""
			Sound.play("card")
		"calls":
			calls_round += 1
			var count := int(CALL_COUNTS[mini(calls_round - 1, CALL_COUNTS.size() - 1)])
			calls_seq.clear()
			if not forced_sequence.is_empty():
				for i in range(mini(count, forced_sequence.size())):
					calls_seq.append(int(forced_sequence[i]))
			else:
				var bag: Array[int] = []
				for i in range(count):
					bag.append(i)
				while bag.size() > 0: # 洗牌
					var pick := randi() % bag.size()
					calls_seq.append(bag[pick])
					bag.remove_at(pick)
			calls_next = 0
			calls_done.clear()
			for i in range(count):
				calls_done.append(false)
			calls_memo_i = 0
			calls_win = false
			calls_state = "memo"
			calls_t = float(CALL_MEMO[mini(calls_round - 1, CALL_MEMO.size() - 1)]) / float(calls_seq.size())
			Sound.play("stamp", 0.7)
	grace_t = OPEN_GRACE # 入场缓冲：吞掉弹窗瞬间玩家手上还没停下的连点

func _pawn_pick_item() -> String:
	var types: Array = main.settings.get("pig_types", [])
	if types.is_empty():
		return "旧陶猪"
	var t: Dictionary = types[randi() % types.size()]
	return String(t.get("label", "陶猪")) + " ×3"

func pawn_mul_now() -> float:
	return clampf(PAWN_CENTER + PAWN_AMP * sin(TAU * pawn_t / pawn_period), 0.7, 2.2)

func _close() -> void:
	active = ""
	gap_t = GAP_SECONDS
	main.queue_redraw()

# ---------------------------------------------------------------- 输入

func handle_click(point: Vector2) -> bool:
	if active == "":
		return false
	if grace_t > 0.0:
		return true # 入场缓冲：刚弹出的半秒内只吞点击，不产生任何效果
	match active:
		"pawn":
			_pawn_click(point)
		"dice":
			_dice_click(point)
		"calls":
			_calls_click(point)
	return true

func handle_key(keycode: int) -> bool:
	if active == "":
		return false
	if active == "calls" and calls_state == "play" and keycode >= KEY_1 and keycode <= KEY_6:
		_calls_pick(int(keycode - KEY_1))
		return true
	if keycode == KEY_SPACE or keycode == KEY_ENTER:
		if active == "pawn":
			if pawn_state == "ready":
				_pawn_begin() # 空格 = 开砍，和按钮等效
				return true
			if pawn_state == "preview":
				_pawn_accept() # 空格 = 接受第一刀的开价
				return true
			if pawn_state == "result":
				_close()
				return true
		if active == "dice" and dice_state == "result":
			_close()
			return true
		if active == "calls" and calls_state == "result":
			_close()
			return true
	return true # 弹窗开着时其余按键一律吞掉

# ---------------------------------------------------------------- 当铺砍价

func _pawn_begin() -> void:
	## 「开砍」确认：从待命进入摆针，起点固定贴着 0.7x
	pawn_state = "swing"
	pawn_t = -PAWN_PERIOD * 0.25
	Sound.play("click")

func _pawn_click(point: Vector2) -> void:
	if pawn_state == "ready": # 待命态：只有「开砍」按钮有效，其余点击一律不算
		if CONFIRM_RECT.has_point(point):
			_pawn_begin()
		return
	if pawn_state == "swing":
		if not PANEL_RECT.grow(-10).has_point(point):
			return # 点面板外不算：防止误触把刀砍下去
		var mul := pawn_mul_now()
		if pawn_final: # 第二刀：锁定即成交
			_pawn_apply(mul)
			return
		pawn_locked_mul = mul
		pawn_state = "preview"
		pawn_bang = 0.35 # 拍板一锤：柜台上的小猪震一晃
		Sound.play("click")
		return
	if pawn_state == "preview":
		if CONFIRM_RECT.has_point(point):
			_pawn_accept()
		elif PAWN_REROLL_RECT.has_point(point): # 再砍一次：更快，也更高风险
			pawn_clicks = 1
			pawn_final = true
			pawn_period = PAWN_PERIOD_2
			pawn_t = -pawn_period * 0.25
			pawn_state = "swing"
			Sound.play("click")
	elif pawn_state == "result" and CONFIRM_RECT.has_point(point):
		_close()

func _pawn_accept() -> void:
	_pawn_apply(pawn_locked_mul)

func _pawn_apply(mul: float) -> void:
	var price := int(round(PAWN_BASE * mul))
	main.score += price
	pawn_state = "result"
	pawn_locked_mul = mul
	pawn_bang = 0.35
	settle_t = 0.9 # 柜台上滚铜钱的演出
	main.popups.append({"position": Vector2(640, 420), "life": 1.4,
		"text": "典当成交 +¥" + str(price)})
	Sound.play("cash", 1.0 if mul < 1.6 else 1.1)
	if mul >= 1.6:
		main.shake = 0.1 # 高价区：给一记小小的到手震

# ---------------------------------------------------------------- 赌桌比大小

func _draw_card() -> int:
	if not forced_deck.is_empty():
		return int(forced_deck.pop_front())
	return randi_range(1, 13)

func hand_value(hand: Array[int]) -> int:
	var total := 0
	var aces := 0
	for r in hand:
		if r == 1:
			total += 1
			aces += 1
		else:
			total += mini(r, 10)
	while aces > 0 and total + 10 <= 21: # A 先按 1 算，塞得下就升到 11
		total += 10
		aces -= 1
	return total

func _dice_click(point: Vector2) -> void:
	if dice_state == "bet":
		if dice_poor:
			if CONFIRM_RECT.has_point(point):
				_dice_deal(0)
			return
		for i in range(BET_RECTS.size()):
			if BET_RECTS[i].has_point(point):
				var bet := 0
				match i:
					0: bet = 50
					1: bet = 120
					2: bet = clampi(int(main.score) * 3 / 10, 50, int(main.score) * 35 / 100) # 30% 余额，硬上限 35%
				_dice_deal(bet)
				return
	elif dice_state == "player":
		if HIT_RECT.has_point(point):
			dice_hand.append(_draw_card())
			Sound.play("card")
			if hand_value(dice_hand) > 21:
				_dice_settle()
			elif dice_hand.size() >= 5: # 五张即封顶：自动停牌
				_dice_stand()
		elif STAND_RECT.has_point(point):
			_dice_stand()
	elif dice_state == "result" and CONFIRM_RECT.has_point(point):
		_close()

func _dice_deal(bet: int) -> void:
	dice_bet = bet
	dice_hand.clear()
	dice_dealer.clear()
	dice_hand.append(_draw_card())
	dice_hand.append(_draw_card())
	dice_dealer.append(_draw_card())
	dice_dealer.append(_draw_card()) # 庄家第二张背面朝下，摊牌才翻开
	dice_state = "player"
	Sound.play("card")

func _dice_stand() -> void:
	dice_state = "dealer" # 先播翻牌演出：庄家翻开暗牌，动画走完才补牌
	dice_flip = 0.55
	Sound.play("card")

func _dealer_play() -> void:
	while hand_value(dice_dealer) < DEALER_STAND: # 庄家 17 点停牌（可预期，不作弊）
		dice_dealer.append(_draw_card())
	_dice_settle()

func _dice_settle() -> void:
	dice_state = "result"
	settle_t = 0.9 # 筹码的胜负演出
	var pv := hand_value(dice_hand)
	var dv := hand_value(dice_dealer)
	if pv > 21:
		dice_outcome = "lose"
	elif dv > 21 or pv > dv:
		dice_outcome = "win"
	elif pv < dv:
		dice_outcome = "lose"
	else:
		dice_outcome = "push"
	match dice_outcome:
		"win":
			main.gamble_wins += 1 # 结算高光：赌桌战绩
			if dice_poor:
				main.score += POOR_WIN
				main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "赊账局赢了 +¥" + str(POOR_WIN)})
			else:
				main.score += dice_bet
				main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "赌桌赢钱 +¥" + str(dice_bet)})
			Sound.play("cash", 1.05)
		"lose":
			main.gamble_losses += 1 # 结算高光：赌桌战绩
			if dice_poor:
				main.stamina = maxf(6.0, main.stamina - POOR_FAIL_STAMINA)
				main.stamina_flash = 0.6
				main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "赊账局输了 · 力竭"})
			else:
				main.score = maxi(0, int(main.score) - dice_bet)
				main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "赌桌输掉 -¥" + str(dice_bet)})
			Sound.play("stamp", 0.7)
		"push":
			main.popups.append({"position": Vector2(640, 420), "life": 1.2, "text": "平局 · 押注退回"})

# ---------------------------------------------------------------- 催债电话连打

func _calls_click(point: Vector2) -> void:
	if calls_state == "result":
		# 结果态的「收下/认了」按钮：当铺和赌桌各自处理了自己的结果点击，电话这里此前漏了
		if CONFIRM_RECT.has_point(point):
			_close()
		return
	if calls_state != "play":
		return
	for i in range(mini(calls_seq.size(), CALL_SLOTS.size())):
		var c: Vector2 = CALL_SLOTS[i]
		# 电话跳起来时点击判定跟着跳：照着当前腾空位置算，否则跳起来就点不中
		if (c + _call_offset(i, not calls_done[i])).distance_to(point) <= CALL_RADIUS + 10.0 and not calls_done[i]:
			_calls_pick(i)
			return

func _calls_pick(i: int) -> void:
	if i >= calls_seq.size() or calls_done[i]:
		return
	if i == calls_seq[calls_next]: # 顺序对：挂掉一个
		calls_done[i] = true
		calls_next += 1
		Sound.play("click", 1.0 + 0.06 * calls_next)
		if calls_next >= calls_seq.size():
			_calls_end(true)
	else: # 点错：立即判负，不重试
		_calls_end(false)

func _calls_end(win: bool) -> void:
	calls_state = "result"
	calls_win = win
	settle_t = 0.9 # 电话的胜负演出
	if win:
		main.score += CALL_REWARD
		# 顺手把房东的下一轮催收往后推一个门槛：这一单算你把催收员打发掉了
		main.bills_fx.collection_next += main.bills_fx.number("collection", "progress_threshold", 100.0)
		main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "全部挂断 +¥" + str(CALL_REWARD)})
		Sound.play("cash", 1.05)
	else:
		main.stamina = maxf(6.0, main.stamina - CALL_FAIL_STAMINA)
		main.stamina_flash = 0.6
		main.popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "没挂完 · 力竭 -" + str(int(CALL_FAIL_STAMINA)) + " 体力"})
		Sound.play("stamp", 0.7)

# ---------------------------------------------------------------- 绘制

func draw(p) -> void:
	## 由 main 在自己的 _draw() 末尾调用：text/panel/button 都画在 main 的画布上。
	if main == null:
		return
	if warn_id != "":
		_draw_warn() # 开桌预警横幅：游戏不暂停，玩家可以收完手里这一锤
	if active == "":
		return
	p.panel(PANEL_RECT, Color("#37251a"), 18)
	p.draw_rect(PANEL_RECT.grow(-4), Color("#e0b552"), false, 2.0) # 暖黄描边，和转盘一个基调
	if open_t < 1.0: # 入场弹出：一圈渐隐的金光，像弹窗"砕"地拍在桌上
		p.draw_rect(PANEL_RECT.grow(6.0 + 10.0 * (1.0 - open_t)), Color(1.0, 0.88, 0.55, 0.55 * (1.0 - open_t)), false, 3.0)
	match active:
		"pawn":
			_draw_pawn()
		"dice":
			_draw_dice()
		"calls":
			_draw_calls()

func _draw_warn() -> void:
	## 顶部预警横幅：金框 + 呼吸灯边线，提示马上要来的是哪个小游戏
	var p = main
	var label := ""
	match warn_id:
		"pawn": label = "当铺砍价"
		"dice": label = "赌桌比大小"
		"calls": label = "催债电话"
		_: label = warn_id
	var rect := Rect2(410, 22, 460, 44)
	var pulse := 0.5 + 0.5 * sin(main.elapsed * 8.0)
	p.panel(rect, Color("#37251a"), 12)
	p.draw_rect(rect.grow(-3), Color(1.0, 0.72, 0.35, 0.45 + 0.4 * pulse), false, 2.0)
	p.text_center("⚠ " + label + "：老板驾到，马上开桌（" + str(int(ceil(warn_t))) + "s）", rect.get_center().x, rect.get_center().y + 2, 16, Color("#ffe092"))

func _panel_title(title: String, hint: String) -> void:
	var p = main
	p.text_center(title, PANEL_RECT.get_center().x, PANEL_RECT.position.y + 44, 26, Color("#efbc72"))
	p.text_center(hint, PANEL_RECT.get_center().x, PANEL_RECT.position.y + 78, 15, Color("#b59a7c"))

func _draw_pawn() -> void:
	var p = main
	_panel_title("当铺砍价", "老板眯着眼：「这猪成色一般，你看着办。」")
	var cx := PANEL_RECT.get_center().x
	var dy := (1.0 - _ease_out()) * 24.0 # 入场时场景从底下浮上来落定
	_draw_pawn_sign(p)
	p.text_center("典当品：" + pawn_item, cx, 240, 20, Color("#e7c98a"))
	var bar := Rect2(360, 300, 560, 46)
	# 三档价格区：灰 0.7~1.0 / 黄 1.0~1.6 / 红 1.6~2.2
	var zones := [[0.7, 1.0, Color("#554636")], [1.0, 1.6, Color("#8a6a2c")], [1.6, 2.2, Color("#a5432a")]]
	for z in zones:
		var x0 := bar.position.x + bar.size.x * (float(z[0]) - 0.7) / 1.5
		var x1 := bar.position.x + bar.size.x * (float(z[1]) - 0.7) / 1.5
		p.panel(Rect2(x0, bar.position.y, x1 - x0, bar.size.y), z[2], 4)
	for i in range(4): # 刻度：0.7 / 1.2 / 1.7 / 2.2
		var mul := 0.7 + 0.5 * i
		var x := bar.position.x + bar.size.x * (mul - 0.7) / 1.5
		p.draw_line(Vector2(x, bar.end.y), Vector2(x, bar.end.y + 8), Color("#b59a7c"), 1.5)
		p.text_center(("%.1f" % mul) + "x", x, bar.end.y + 22, 13, Color("#b59a7c"))
	var mul_now := 0.7 # 待命态：还没下刀，显示起始档 0.7x
	if pawn_state == "swing":
		mul_now = pawn_mul_now()
	elif pawn_state != "ready":
		mul_now = pawn_locked_mul
	var needle_x := bar.position.x + bar.size.x * (mul_now - 0.7) / 1.5
	var hot := mul_now >= 1.6
	p.draw_line(Vector2(needle_x, bar.position.y - 14), Vector2(needle_x, bar.end.y + 4),
		Color("#ffe092") if hot else Color("#f4e0b8"), 4.0)
	p.draw_polygon(PackedVector2Array([Vector2(needle_x - 10, bar.position.y - 26), Vector2(needle_x + 10, bar.position.y - 26),
		Vector2(needle_x, bar.position.y - 10)]), PackedColorArray([Color("#ffe092"), Color("#ffe092"), Color("#ffe092")]))
	var price := int(round(PAWN_BASE * mul_now))
	var tag := "当前开价"
	if pawn_state == "swing" and pawn_clicks == 1:
		tag = "最后一刀"
	p.text_center(tag + "：¥" + str(price), cx, 420, 30, Color("#ffe092") if hot else Color("#efbc72"))
	# —— 场景：柜台后眯眼算价的老板 + 柜台上待价而沽的小猪 ——
	var scene_rect := Rect2(300, 446, 680, 268)
	if pawn3d != null: # 3D 场景层：老板/小猪/木槌/铜钱全在里面，价格条与按钮仍是 2D 叠在上面
		pawn3d.set_state(pawn_state, pawn_bang)
		p.draw_texture_rect(pawn3d.get_texture(), scene_rect, false)
	else:
		var counter_y := 548.0
		_draw_boss(p, Vector2(824, 498) + Vector2(0, dy * 0.4), 34)
		_draw_pawn_pig(p, Vector2(448, 520) + Vector2(0, dy * 0.6), 44)
		if pawn_bang > 0.0: # 拍板落锤：锤子从扬起到砸下
			_draw_mallet(p, Vector2(520, 452), pawn_bang / 0.35)
		if pawn_state == "result": # 成交：柜台上滚出一把铜钱
			for i in range(4):
				var coin := Vector2(566 + 27 * i, counter_y - 10 - (i % 2) * 7)
				p.draw_circle(coin, 11, Color("#d9a94a"))
				p.draw_circle(coin, 5, Color("#543823"))
		# 柜台最后画：正好挡住老板的身子和小猪垫子的底
		p.panel(Rect2(310, counter_y, 660, 18), Color("#7a5433"), 3)
		p.panel(Rect2(310, counter_y + 18, 660, 64), Color("#543823"), 0)
		p.draw_line(Vector2(310, counter_y + 18), Vector2(970, counter_y + 18), Color("#3a2c20"), 2.0)
	if pawn3d != null: # 3D 场景作底时，给提示文字垫一条半透明底，避免压在木纹上看不清
		p.panel(Rect2(cx - 250, 448, 500, 26), Color(0.08, 0.05, 0.03, 0.62), 8)
	match pawn_state:
		"ready":
			p.text_center("老板已就位 —— 点「开砍！」或按空格，指针摆起来后再点面板下刀", cx, 470, 15, Color("#b59a7c"))
			p.button(CONFIRM_RECT, "开砍！")
		"swing":
			p.text_center("点面板内任意位置下刀" + ("（就这一锤子买卖了）" if pawn_final else "（第一刀，砍完还能再砍一次）"),
				cx, 470, 15, Color("#b59a7c"))
		"preview":
			p.text_center("第一刀就值这个价 —— 收下，还是赌第二刀更快但更险？", cx, 470, 15, Color("#b59a7c"))
			p.button(PAWN_REROLL_RECT, "再砍一次", true, Color("#a5432a"))
			p.button(CONFIRM_RECT, "收下 ¥" + str(price))
		"result":
			p.text_center("成交！钱已入账，拿去还债吧。", cx, 470, 15, Color("#b59a7c"))
			p.button(CONFIRM_RECT, "知道了")

func _card_face(r: int, rect: Rect2, face_up: bool) -> void:
	var p = main
	p.panel(rect, Color("#241a10") if not face_up else Color("#f2e8d5"), 6)
	if not face_up:
		p.text_center("?", rect.get_center().x, rect.get_center().y, 24, Color("#8a6a42"))
		return
	var suit := r % 4
	var suit_char: String = ["♠", "♥", "♦", "♣"][suit]
	var red := suit == 1 or suit == 2
	var label := str(r)
	match r:
		1: label = "A"
		11: label = "J"
		12: label = "Q"
		13: label = "K"
	p.text_center(label, rect.get_center().x, rect.position.y + 30, 26, Color("#c94b4b") if red else Color("#3a2c20"))
	p.text_center(suit_char, rect.get_center().x, rect.end.y - 26, 22, Color("#c94b4b") if red else Color("#3a2c20"))

func _draw_dice() -> void:
	var p = main
	_panel_title("赌桌比大小", "余额 ¥" + str(int(main.score)) + " · 黑猪庄家推来一摞筹码：「押多少，朋友？」")
	var cx := PANEL_RECT.get_center().x
	# 绿呢赌台：金线镶边，呢面上有一道弧形的押注线
	var felt := Rect2(312, 136, 656, 372)
	p.panel(felt, Color("#2e523b"), 14)
	p.draw_rect(felt.grow(-5), Color("#e0b552"), false, 1.8)
	p.draw_arc(felt.get_center() + Vector2(0, 44), 236.0, PI + 0.4, TAU - 0.4, 48, Color(1.0, 0.9, 0.7, 0.15), 1.5)
	p.text_center("·  二 十 一 点  ·", cx, 168, 14, Color("#c9d8b0"))
	# 庄家：戴遮阳帽檐的黑猪 + 台面右侧一摞备用筹码
	_draw_dealer_pig(p, Vector2(398, 210), 30)
	_draw_chip_stack(p, Vector2(916, 236), 3, Color("#d9a94a"))
	match dice_state:
		"bet":
			if dice_poor:
				p.text_center("兜里不足 ¥50 —— 庄家摆摆手：「赊账玩一把，赢了 ¥" + str(POOR_WIN) + "，输了掉体力。」", cx, 260, 17, Color("#e7c98a"))
				p.button(CONFIRM_RECT, "赊账开局")
			else:
				p.text_center("选个押注额（押注有硬上限：余额 35%，不许梭哈破产）", cx, 240, 16, Color("#e7c98a"))
				var bet3 := clampi(int(main.score) * 3 / 10, 50, int(main.score) * 35 / 100)
				p.button(BET_RECTS[0], "押 ¥50")
				p.button(BET_RECTS[1], "押 ¥120")
				p.button(BET_RECTS[2], "押 ¥" + str(bet3))
		"player", "dealer", "result":
			# 庄家一手（暗牌在翻牌动画走完前一直扣着）
			var dn := dice_dealer.size()
			for i in range(dn):
				var rect := Rect2(cx - (dn * 86) / 2.0 + i * 86 - 35, 190, 70, 100)
				_card_face(dice_dealer[i], rect, dice_state == "result" or i == 0)
			p.text_center("庄家 " + (str(hand_value(dice_dealer)) if dice_state == "result" else "?"), cx, 320, 17, Color("#c9d8b0"))
			# 玩家一手
			var pn := dice_hand.size()
			for i in range(pn):
				var rect := Rect2(cx - (pn * 86) / 2.0 + i * 86 - 35, 360, 70, 100)
				_card_face(dice_hand[i], rect, true)
			var pv := hand_value(dice_hand)
			var pv_color := Color("#e06c5c") if pv > 21 else Color("#efbc72")
			p.text_center("你 " + str(pv) + ("（爆了！）" if pv > 21 else ""), cx, 490, 20, pv_color)
			# 你押出去的筹码堆：摆在手牌左下，输赢各有表现
			var chip_col := Color("#a5432a")
			var chip_n := 3
			if dice_state == "result":
				match dice_outcome:
					"win":
						chip_col = Color("#d9a94a") # 赢了：涨成金色的两倍堆
						chip_n = 5
					"lose":
						chip_col = Color("#5a5148") # 输了：灰扑扑地只剩一枚
						chip_n = 1
					"push":
						chip_col = Color("#8a6a42")
			_draw_chip_stack(p, Vector2(396, 466), chip_n, chip_col)
			var chip_label := "赊账局" if dice_poor else "押注 ¥" + str(dice_bet)
			p.text_center(chip_label, 396, 494, 13, Color("#c9d8b0"))
			var wager := POOR_WIN if dice_poor else dice_bet
			match dice_state:
				"player":
					p.text_center(("赊账局：" if dice_poor else "押注 ¥" + str(dice_bet) + "：") + "要牌，还是停牌？（最多五张）", cx, 530, 15, Color("#b59a7c"))
					p.button(HIT_RECT, "要牌 [1]")
					p.button(STAND_RECT, "停牌 [2]")
				"dealer":
					p.text_center("庄家翻牌……", cx, 530, 15, Color("#b59a7c"))
				"result":
					var line := ""
					match dice_outcome:
						"win": line = "你赢了 +¥" + str(wager)
						"lose": line = "庄家收走了你的钱" if not dice_poor else "输了 · 力竭"
						"push": line = "平局，押注退回"
					p.text_center(line, cx, 530, 20, Color("#ffe092") if dice_outcome == "win" else Color("#e7c98a"))
					p.button(CONFIRM_RECT, "离开赌桌")

func _call_ringing(i: int, dimmed: bool) -> bool:
	if calls_state == "memo":
		return calls_seq[mini(calls_memo_i, maxi(0, calls_seq.size() - 1))] == i
	if calls_state == "play":
		return not dimmed # 限时阶段：没挂的都在响
	return false


func _call_offset(i: int, ringing: bool) -> Vector2:
	if not ringing:
		return Vector2.ZERO
	var ph: float = main.elapsed * 9.0 + float(i) * 1.3
	return Vector2(sin(main.elapsed * 42.0 + float(i) * 1.7) * 2.0, -absf(sin(ph)) * 20.0)


func _draw_call_phone(p, base: Vector2, num: int, ringing: bool, done: bool) -> void:
	## 复古转盘电话（棕木色）：宽底座 + 金字塔机身 + 正面大转盘 + 顶架听筒。
	## 响铃时整台跳起来：起跳拉长、落地压扁（卡通跳法），挂断后听筒搁在一旁、机身变暗。
	var ph: float = main.elapsed * 9.0 + float(num - 1) * 1.3
	var hop: float = absf(sin(ph)) * 20.0 if ringing else 0.0
	var st: float = 0.12 * sin(ph) if ringing else 0.0 # 拉长(+) / 压扁(-)
	var cc: Vector2 = base + _call_offset(num - 1, ringing)
	# 影子留在地上：跳得越高影子越小
	var sh_rx: float = 56.0 * (1.0 - 0.45 * hop / 20.0)
	_ellipse(p, base + Vector2(0, 8), sh_rx, 10.0, Color(0.05, 0.03, 0.02, 0.4))
	var body := Color("#5f4227") if not done else Color("#41301d")
	var face := Color("#6d4d2e") if not done else Color("#4a3722")
	var dark := Color("#3a2817") if not done else Color("#2a1e12")
	var dial := Color("#2b1d10") if not done else Color("#1f150b")
	var brass := Color("#b58c54") if not done else Color("#6e5638")
	# 以落点为原点缩放：跳起时拉长、落地压扁
	p.draw_set_transform_matrix(Transform2D(0.0, cc) * Transform2D(0.0, Vector2(1.0 - st * 0.6, 1.0 + st)))
	# 底座：宽垫脚 + 金字塔机身（下宽上窄）
	p.panel(Rect2(-52, -2, 104, 12), dark, 6)
	p.draw_colored_polygon(PackedVector2Array([Vector2(-46, -2), Vector2(46, -2), Vector2(32, -32), Vector2(-32, -32)]), body)
	# 顶架平台 + 两个听筒挂钩
	p.panel(Rect2(-30, -40, 60, 9), face, 4)
	p.panel(Rect2(-28, -48, 9, 12), dark, 3)
	p.panel(Rect2(19, -48, 9, 12), dark, 3)
	# 正面转盘：大圆盘 + 十个指孔 + 中心号码牌
	var dc := Vector2(0, -15)
	p.draw_circle(dc, 16.5, dial)
	p.draw_arc(dc, 16.5, 0.0, TAU, 32, brass, 1.6)
	for k in range(10):
		var a := TAU * float(k) / 10.0 + 0.31
		p.draw_circle(dc + Vector2(cos(a), sin(a)) * 11.0, 2.1, brass)
	p.draw_circle(dc, 5.5, face)
	p.draw_arc(dc, 5.5, 0.0, TAU, 16, brass, 1.2)
	p.text_center(str(num), dc.x, dc.y + 2.5, 8, Color("#ffe092") if not done else Color("#6e5638"))
	# 左侧卷卷的电话线
	for k in range(3):
		p.draw_arc(Vector2(-56, -8.0 + float(k) * 5.5), 4.5, 0.0, TAU, 12, brass, 1.6)
	if done:
		_draw_handset_on(p, Vector2(64, -6), 22, dark) # 挂断：听筒搁在旁边地上
	else:
		_draw_handset_on(p, Vector2(0, -54), 26, body) # 架在挂钩上的听筒
		if ringing:
			var lit := 0.55 + 0.4 * sin(main.elapsed * 10.0)
			p.draw_circle(Vector2(-34, -22), 3.5, Color(0.9, 0.32, 0.25, lit)) # 呼叫红灯
	p.draw_set_transform_matrix(Transform2D())

func _draw_calls() -> void:
	var p = main
	var round_label := "第 " + str(calls_round) + " 波"
	var status := "看好响铃顺序……"
	if calls_state == "play":
		status = "按顺序点掉来电！" + ("（剩 " + str(int(ceil(calls_t))) + "s）" if calls_t < 3.0 else "")
	elif calls_state == "result":
		status = "全挂断了，清静。" if calls_win else "顺序错了 / 超时了 —— 催收员还在线上。"
	_panel_title("催债电话连打", round_label + " · " + status)
	var cx := PANEL_RECT.get_center().x
	for i in range(mini(calls_seq.size(), CALL_SLOTS.size())):
		var c: Vector2 = CALL_SLOTS[i]
		var num := i + 1
		var dimmed: bool = calls_state == "play" and calls_done[i]
		var ringing: bool = _call_ringing(i, dimmed)
		_draw_call_phone(p, c, num, ringing, dimmed)
		if ringing: # 响铃动画：两圈错相的扩散波，从机身上滚出去
			for k in range(2):
				var wave: float = fmod(main.elapsed * 30.0 + 17.0 * float(k), 34.0)
				p.draw_arc(c + Vector2(0, -14), 52.0 + wave, 0.0, TAU, 32,
					Color(1.0, 0.87, 0.57, 0.38 * (1.0 - wave / 34.0)), 2.0)
	# 桌角的老式电话机：一切骚扰的源头——通话时机身发抖、红灯闪
	_draw_phone(p, Vector2(640, 616))
	if calls_state == "play": # 限时阶段：整块面板边缘红光脉动
		p.draw_rect(PANEL_RECT.grow(-3), Color(0.88, 0.32, 0.24, 0.22 + 0.16 * sin(main.elapsed * 9.0)), false, 3.0)
	match calls_state:
		"result":
			var line := "+¥" + str(CALL_REWARD) + " · 房东的下一轮催收推迟了" if calls_win else "体力 -" + str(int(CALL_FAIL_STAMINA))
			p.text_center(line, cx, 560, 16, Color("#b59a7c"))
			p.button(CONFIRM_RECT, "收下" if calls_win else "认了")
		"play":
			p.text_center("错一次就前功尽弃", cx, 560, 14, Color("#554636"))

# ---------------------------------------------------------------- 视觉小零件（三个玩法共用的绘制件）

func _ease_out() -> float:
	return 1.0 - pow(1.0 - open_t, 3.0)

func _ellipse(p, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(22):
		var a := TAU * float(i) / 22.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	p.draw_polygon(pts, PackedColorArray([col]))

func _draw_chip(p, pos: Vector2, r: float, col: Color) -> void:
	# 赌场筹码：外圈白条纹 + 深色内芯
	p.draw_circle(pos, r, col)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var dir := Vector2(cos(a), sin(a))
		p.draw_line(pos + dir * (r * 0.62), pos + dir * r, Color("#f2e8d5"), 4.5)
	p.draw_circle(pos, r * 0.55, col.darkened(0.25))
	p.draw_arc(pos, r * 0.55, 0.0, TAU, 24, Color("#f2e8d5"), 1.5)

func _draw_chip_stack(p, base: Vector2, n: int, col: Color) -> void:
	p.draw_circle(base + Vector2(0, 4), 20.0, Color(0, 0, 0, 0.25)) # 底下一片影子
	for i in range(maxi(1, n)):
		_draw_chip(p, base + Vector2(0, -8.0 * i), 17.0, col)

func _draw_boss(p, c: Vector2, s: float) -> void:
	# 当铺老板：瓜皮帽 + 眯成缝的笑眼 + 八字胡，身子藏在柜台后面
	_ellipse(p, c + Vector2(0, s * 1.5), s * 0.95, s * 0.8, Color("#2e2620"))
	p.draw_circle(c + Vector2(0, -s * 0.62), s * 0.66, Color("#33261a")) # 帽
	p.draw_circle(c + Vector2(0, -s * 1.1), s * 0.11, Color("#a5432a")) # 帽顶红结
	p.draw_circle(c, s * 0.72, Color("#e3b489")) # 脸
	for dx in [-1.0, 1.0]:
		p.draw_arc(c + Vector2(dx * s * 0.3, -s * 0.08), s * 0.15, 0.35, PI - 0.35, 12, Color("#3a2c20"), 2.5) # 眯眼︶
	p.draw_line(c + Vector2(-s * 0.1, s * 0.26), c + Vector2(-s * 0.42, s * 0.42), Color("#4a382a"), 3.0) # 八字胡
	p.draw_line(c + Vector2(s * 0.1, s * 0.26), c + Vector2(s * 0.42, s * 0.42), Color("#4a382a"), 3.0)
	p.draw_line(c + Vector2(-s * 0.12, s * 0.52), c + Vector2(s * 0.12, s * 0.52), Color("#8a5a3a"), 2.0) # 报着的嘴

func _draw_pawn_pig(p, c: Vector2, s: float) -> void:
	# 柜台上待价而沽的小陶猪：拍板时会震一晃
	var amp := (pawn_bang / 0.35) if pawn_bang > 0.0 else 0.0
	var cc := c + Vector2(sin(main.elapsed * 42.0) * 5.0 * amp, 0)
	_ellipse(p, c + Vector2(0, s * 0.5), s * 1.35, s * 0.2, Color("#8a3a2e")) # 红绸垫
	for dx in [-1.0, 1.0]:
		p.draw_circle(cc + Vector2(dx * s * 0.55, -s * 0.7), s * 0.22, Color("#d98a8f")) # 耳朵
	_ellipse(p, cc, s, s * 0.72, Color("#efb0b6")) # 身体
	p.draw_circle(cc + Vector2(0, s * 0.2), s * 0.34, Color("#f6c6cb")) # 鼻君
	p.draw_circle(cc + Vector2(-s * 0.12, s * 0.18), s * 0.055, Color("#b2626a"))
	p.draw_circle(cc + Vector2(s * 0.12, s * 0.18), s * 0.055, Color("#b2626a"))
	p.draw_circle(cc + Vector2(-s * 0.42, -s * 0.2), s * 0.07, Color("#3a2620")) # 眼
	p.draw_circle(cc + Vector2(s * 0.42, -s * 0.2), s * 0.07, Color("#3a2620"))
	p.draw_rect(Rect2(cc.x - s * 0.2, cc.y - s * 0.76, s * 0.4, s * 0.08), Color("#5a4030")) # 投币口

func _draw_mallet(p, pivot: Vector2, prog: float) -> void:
	# 拍板的小木槽：prog 1→0，从扬起到落定
	var ang := lerpf(1.1, -1.7, prog)
	var tip := pivot + Vector2(cos(ang), sin(ang)) * 56.0
	p.draw_line(pivot, tip, Color("#6b4a2f"), 6.0)
	var dir := Vector2(cos(ang), sin(ang))
	p.draw_circle(tip + Vector2(-dir.y, dir.x) * 10.0, 15.0, Color("#543823"))
	p.draw_circle(tip + Vector2(-dir.y, dir.x) * 10.0, 7.0, Color("#7a5433"))

func _draw_pawn_sign(p) -> void:
	# 挂着的"当"字招牌：随风轻晃
	var top := Vector2(348, 106)
	var sway := sin(main.elapsed * 1.3) * 5.0
	var rect := Rect2(322 + sway, 130, 52, 52)
	p.draw_line(top, Vector2(rect.position.x + 10, rect.position.y), Color("#8a6a4a"), 2.0)
	p.draw_line(top, Vector2(rect.end.x - 10, rect.position.y), Color("#8a6a4a"), 2.0)
	p.panel(rect, Color("#a5432a"), 6)
	p.draw_rect(rect.grow(-3), Color("#e0b552"), false, 1.5)
	p.text_center("当", rect.get_center().x, rect.get_center().y + 2, 30, Color("#ffe9c8"))

func _draw_dealer_pig(p, c: Vector2, s: float) -> void:
	# 赌桌庄家：一头戴遮阳帽檐的黑猪，"押多少，朋友？"
	for dx in [-1.0, 1.0]:
		p.draw_circle(c + Vector2(dx * s * 0.62, -s * 0.78), s * 0.26, Color("#3a332c")) # 耳朵
	p.draw_circle(c, s, Color("#5a5148")) # 头
	p.draw_circle(c + Vector2(0, s * 0.5), s * 0.44, Color("#6e635a")) # 长哥
	p.draw_circle(c + Vector2(-s * 0.14, s * 0.5), s * 0.07, Color("#2e2620"))
	p.draw_circle(c + Vector2(s * 0.14, s * 0.5), s * 0.07, Color("#2e2620"))
	p.draw_circle(c + Vector2(-s * 0.42, -s * 0.12), s * 0.09, Color("#1a140c")) # 眼
	p.draw_circle(c + Vector2(s * 0.42, -s * 0.12), s * 0.09, Color("#1a140c"))
	p.draw_rect(Rect2(c.x - s * 0.95, c.y - s * 0.62, s * 1.9, s * 0.2), Color("#2e523b")) # 帽檐
	p.draw_rect(Rect2(c.x - s * 0.5, c.y - s * 0.98, s, s * 0.42), Color("#2e523b")) # 帽顶

func _draw_handset_on(p, c: Vector2, s: float, col: Color) -> void:
	# 架在挂钩上的听筒：两只圆头朝下扣进架座，弓身向上拱起（老式电话的驾法）
	p.draw_circle(c + Vector2(-s * 0.85, 0), s * 0.32, col)
	p.draw_circle(c + Vector2(s * 0.85, 0), s * 0.32, col)
	p.draw_arc(c, s * 0.85, PI + 0.45, TAU - 0.45, 20, col, s * 0.3)

func _draw_phone(p, c: Vector2) -> void:
	# 桌角的老式转盘电话机（棕木色，和催债关里四台同款）：通话时机身发抖、红灯闪
	var shaking: bool = calls_state == "memo" or calls_state == "play"
	var cc := c + (Vector2(sin(main.elapsed * 32.0) * 2.5, 0) if shaking else Vector2.ZERO)
	var body := Color("#5f4227")
	var face := Color("#6d4d2e")
	var dark := Color("#3a2817")
	var brass := Color("#b58c54")
	p.panel(Rect2(cc.x - 44, cc.y + 2, 88, 10), dark, 5) # 垫脚
	p.draw_colored_polygon(PackedVector2Array([Vector2(cc.x - 38, cc.y + 2), Vector2(cc.x + 38, cc.y + 2), Vector2(cc.x + 26, cc.y - 26), Vector2(cc.x - 26, cc.y - 26)]), body) # 金字塔机身
	p.panel(Rect2(cc.x - 24, cc.y - 33, 48, 8), face, 4) # 顶架
	var dc := cc + Vector2(0, -11)
	p.draw_circle(dc, 13, Color("#2b1d10"))
	p.draw_arc(dc, 13, 0.0, TAU, 24, brass, 1.4)
	for k in range(10):
		var a := TAU * float(k) / 10.0 + 0.31
		p.draw_circle(dc + Vector2(cos(a), sin(a)) * 8.6, 1.7, brass)
	_draw_handset_on(p, cc + Vector2(0, -40), 20, body)
	p.draw_arc(cc + Vector2(-52, 2), 5.5, 0.0, TAU, 14, brass, 1.8) # 卷卷的电话线
	if calls_state != "result" or not calls_win:
		var lit := 0.55 + 0.4 * sin(main.elapsed * 10.0)
		p.draw_circle(cc + Vector2(-24, -16), 3.2, Color(0.9, 0.32, 0.25, lit)) # 呼叫红灯
