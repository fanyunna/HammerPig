extends SceneTree
const BillManagerScript = preload("res://scripts/bill_manager.gd")
var game
var checks := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    if not ok:
        push_error("FAIL: " + message)
        quit(1)
    assert(ok, message)
    checks += 1
    print("PASS: ", message)

func click(point: Vector2) -> void:
    game.cooldown = 0.0
    game.strike(point)

func break_pig(index: int) -> void:
    var point: Vector2 = game.pigs[index].position
    click(point)
    click(point)

func key_press(code) -> void:
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = code
    game._unhandled_input(key)


## 造三张卡，第一张是指定的那张：apply_card 只认"正好三张"的牌面
func offers_with(first_id: String, first_name: String) -> Array[Dictionary]:
    return [
        {"id": first_id, "name": first_name, "desc": "测试", "icon": "?", "color": "#ffffff"},
        {"id": "cash", "name": "现金奖励", "desc": "测试", "icon": "+", "color": "#ffffff"},
        {"id": "heavy", "name": "重锤改造", "desc": "测试", "icon": "?", "color": "#ffffff"},
    ]


## P1 辅助：数一数桌上还有几张叫这个名字的账单
func _count_named(nm: String) -> int:
    var n := 0
    for b in game.bills:
        if String(b.get("name", "")) == nm:
            n += 1
    return n


func _interest_count() -> int:
    return _count_named("信用卡利息")


func _interest_sum() -> int:
    var s := 0
    for b in game.bills:
        if String(b.get("name", "")) == "信用卡利息":
            s += int(b.amount)
    return s


## P1 辅助：按种类 id 找账单下标（-1 = 已经还掉了）
func _find_id(id: String) -> int:
    for i in range(game.bills.size()):
        if String(game.bills[i].get("id", "")) == id:
            return i
    return -1

func run() -> void:
    game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    # 第一段流程使用短阈值做快速回归；之后恢复 JSON 中的当前平衡值并单独覆盖。
    var configured_card_first := int(game.settings.get("card_first_at", 160))
    var configured_card_interval := int(game.settings.get("card_interval", 135))
    var configured_round_target := int(game.settings.get("round_target", 950))
    game.settings["card_first_at"] = 60
    game.settings["card_interval"] = 50
    game.settings["round_target"] = 10000
    game.settings["respawn_seconds"] = 0.8
    # 猪现在是随机种类，"两锤 +¥10"这类断言就不稳了：先清空种类表（pick_pig_type 会回退到
    # pig_hp / points_per_pig 的默认值），老断言照旧成立；新机制在文件末尾单独测。
    game.settings["pig_types"] = []
    # 冷却缓冲会把"被冷却挡住的那一锤"记下来补发：老断言不指望它，先关掉，文件末尾单独开测。
    game.settings["strike_buffer"] = 0.0
    # 账单到期考核会打断砸猪、把 phase 切成 challenge：老断言不指望它，先关掉，文件末尾单独开测。
    game.bill_data["challenge_max_per_run"] = 0
    game.settings["crit_base_chance"] = 0.0
    game.settings["crit_per_combo"] = 0.0
    game.settings["crit_max_chance"] = 0.0
    key_press(KEY_R)
    # pig mechanics
    check(game.pigs.size() == game.pig_count() and game.score == 0, "starts broke at 0 with a full table of pigs")
    click(Vector2(0, 0))
    check(game.hits == 0 and game.score == 0, "miss gives no points")
    click(game.pigs[0].position)
    check(game.pigs[0].hp == 1 and game.score == 0, "first hit cracks pig")
    game.strike(game.pigs[0].position)
    check(game.pigs[0].hp == 1, "cooldown blocks rapid duplicate hit")
    click(game.pigs[0].position)
    check(game.score == 10 and game.broken == 1 and game.pigs[0].hp == 0, "second hit breaks pig and scores")
    click(game.pigs[0].position)
    check(game.score == 10, "dead pig cannot score twice")
    game._process(float(game.settings.respawn_seconds) + 0.1)
    check(game.pigs[0].hp == 2, "broken pig respawns")

    # 手感三件套：命中回体力 + 打击顿帧 + 结算高光（§8.14）
    check(float(game.settings.get("stamina_regen_per_second", 0)) >= 1.0, "stamina regen no longer punishes with a freeze")
    check(float(game.settings.get("stamina_hit_refund", 0)) >= 1.0, "landing a hit refunds stamina")
    check(game.best_gain >= int(game.settings.points_per_pig) and game.combo_max >= 1, "session highlights recorded on pig break")
    var st_before = game.stamina
    game.cooldown = 0.0
    game.strike(game.pigs[0].position)
    check(game.stamina == st_before - float(game.settings.stamina_cost) + float(game.settings.stamina_hit_refund), "hit refunds 1 stamina against its 3 cost")
    check(game.hit_stop > 0.0, "a landed strike freezes the world for a few frames")
    game.day_events.dice_hand.assign([10, 11]) # 21 点直接摊牌：赢了要记进赌桌战绩
    game.day_events.dice_dealer.assign([9, 8])
    game.day_events.dice_poor = false
    game.day_events.dice_bet = 10
    var gamble_score_before = game.score
    game.day_events._dice_settle()
    check(game.gamble_wins >= 1 and game.score == gamble_score_before + 10, "dice win recorded in session highlights")
    game.day_events.dice_hand.assign([10, 5])
    game.day_events.dice_dealer.assign([9, 9])
    game.day_events.dice_poor = false
    game.day_events.dice_bet = 5
    game.day_events._dice_settle()
    check(game.gamble_losses >= 1, "dice loss recorded in session highlights")

    # first card -> reward（注意：卡片不再当场弹，见 §3.6 的半秒缓冲）
    game.gamble_used = true # 隔离：这段专门测卡片，别让桌边那枚硬币插进来
    for i in range(1, 6):
        break_pig(i)
    check(game.score == 65 and game.phase == "playing", "60+5 reached but the card waits out the burst（十四轮赌桌块净赚 5）")
    game._process(0.5)
    check(game.phase == "card", "the card pops once the burst has played out")
    game.card_type = "reward"
    game.card_offers.clear() # 走旧奖励兼容分支，避免随机升级影响金额断言
    game.apply_card()
    check(game.score == 65 + int(game.settings.reward_card_amount) and game.phase == "playing", "reward card pays out and resumes")
    game._process(0.9)

    # second card -> collect bill
    for i in range(3):
        break_pig(i)
    check(game.score == 130 and game.phase == "playing", "the second card threshold is crossed")
    game._process(0.5)
    check(game.phase == "card", "the second card pops after the same beat")
    game.card_type = "collect"
    game.apply_card()
    check(game.phase == "challenge" and game.bill_timer > 0.0, "collect bill enters challenge with a round timer")
    check(game.collect_cards.size() == 3, "the table is dealt three ways to get money")
    check(game.collect_round == 1 and game.collect_rounds >= 3, "the first round starts with rounds left")
    var challenge_start_score: int = game.score
    var bills_before_card: int = game.unpaid_bills
    # 选最左那张（稳）：钱进袋，代价轻
    var first_card: Dictionary = game.collect_cards[0]
    var first_gain: int = game.collect_gain(first_card)
    game.click_collect(game.collect_card_rects()[0].get_center())
    check(game.collected == first_gain, "picking a way collects its money")
    game._process(0.6)
    check(game.collect_round == 2 and game.collect_cards.size() == 3, "the next round is dealt after the pick")
    # 犹豫超时：这一轮白过，钱不涨
    var coins_before_timeout: int = game.collected
    var round_before_timeout: int = game.collect_round
    game.bill_timer = 0.0
    game._process(0.1)
    game._process(0.5)
    check(game.collected == coins_before_timeout, "a timeout wastes the round instead of paying out")
    check(game.collect_round > round_before_timeout or game.phase != "challenge", "a timeout still burns a round")
    # 凑够即过关（清账 + 奖励）
    game.collected = game.bill_amount
    game.collect_advance()
    check(game.phase == "playing" and game.score == challenge_start_score + int(game.settings.bill_reward), "clearing bill keeps money and rewards")
    check(game.unpaid_bills == bills_before_card - 1, "clearing a bill removes one from the unpaid stack")

    # 代价：借新账 / 耗力气，两条路都真的落在本局状态上
    game.card_type = "collect"
    game.phase = "card"
    game.apply_card()
    var pain_before: float = game.stamina
    game.collect_apply_cost({"cost": "stamina", "cost_value": 12.0})
    check(game.stamina < pain_before and game.stamina >= 6.0, "a stamina cost really drains the swinging arm")
    var iou_before: int = game.unpaid_bills
    var debt_text: String = game.collect_apply_cost({"cost": "bill", "cost_ratio": 0.4, "debt_name": "欠条"})
    check(game.unpaid_bills == iou_before + 1 and debt_text.contains("的账"), "borrowing money signs a new bill")
    game.phase = "playing"
    game.collect_cards.clear()
    game.challenge_bill_tag = ""
    var score_before_fail: int = game.score

    # fail collect bill -> deduct（轮次用尽还没凑齐）
    game.card_type = "collect"
    game.phase = "card"
    game.apply_card()
    game.collect_round = game.collect_rounds
    game.collected = 0
    game.bill_timer = 0.0
    game._process(0.1)
    game._process(0.6)
    check(game.score == score_before_fail - int(game.settings.bill_amount) and game.phase == "playing", "running out of rounds deducts the amount")

    # bankrupt
    game.score = int(game.settings.bill_amount)
    game.card_type = "collect"
    game.phase = "card"
    game.apply_card()
    game.bill_timer = 0.0
    game.collect_round = game.collect_rounds
    game._process(0.1)
    game._process(0.6)
    check(game.phase == "bankrupt" and game.score == 0, "balance at 0 goes bankrupt")
    key_press(KEY_R)
    check(game.score == 0 and game.phase == "playing" and game.next_card == int(game.settings.card_first_at), "R resets after bankruptcy")
    check(game.unpaid_bills == int(game.bill_data.get("start_count", 7)), "reset restores the unpaid bill stack")

    game.settings["card_first_at"] = configured_card_first
    game.settings["card_interval"] = configured_card_interval
    game.settings["round_target"] = configured_round_target
    game.settings["respawn_seconds"] = 1.05

    # lucky coin: appears once the balance reaches the threshold, and can be turned down
    key_press(KEY_R)
    game.next_card = 10000 # 隔离弹卡，专门检查抛硬币阈值
    check(game.gamble_state == "none" and not game.gamble_used, "no coin before the threshold")
    game.score = game.gamble_threshold() - 1
    game._process(0.016)
    check(game.gamble_state == "none", "coin stays away just below the threshold")
    game.score = game.gamble_threshold()
    game._process(0.016)
    check(game.gamble_state == "ready", "coin rolls in at the threshold")
    check(game.gamble_t == 0.0, "coin starts its roll-in animation from the edge")
    game._process(0.2)
    check(game.gamble_t > 0.0 and game.gamble_state == "ready", "coin keeps rolling until it settles")
    game.skip_gamble()
    check(game.gamble_used and game.gamble_state == "none", "turning the coin down removes it for the round")
    game.score = game.gamble_threshold() * 2
    game._process(0.016)
    check(game.gamble_state == "none", "a turned-down coin never comes back")

    # heads doubles the money, tails wipes it
    key_press(KEY_R)
    game.next_card = 10000
    game.score = int(game.gamble_threshold())
    game._process(0.016)
    game.gamble_heads = true
    game.resolve_gamble()
    check(game.score == int(game.gamble_threshold()) * 2 and game.gamble_state == "result", "heads doubles the balance")
    key_press(KEY_R)
    game.next_card = 10000
    game.score = int(game.gamble_threshold())
    game._process(0.016)
    game.gamble_heads = false
    game.resolve_gamble()
    check(game.score == 0, "tails clears the balance")
    check(game.phase == "playing", "tails does not end the round")
    check(game.gamble_used, "the coin is spent once flipped")

    # flipping pauses the round
    key_press(KEY_R)
    game.next_card = 10000
    game.score = game.gamble_threshold()
    game._process(0.016)
    game.start_gamble()
    game.cooldown = 0.5
    game._process(0.1)
    check(game.cooldown == 0.5 and game.gamble_state == "flip", "flipping the coin pauses the round")

    # double card
    key_press(KEY_R)
    game.card_type = "double"
    game.phase = "card"
    game.apply_card()
    check(game.phase == "playing" and game.double_timer > 0.0 and game.score == 0, "double card activates without instant cash")
    game.double_timer = 10.0
    break_pig(0)
    check(game.score == 2 * int(game.settings.points_per_pig), "double card doubles pig earnings")
    key_press(KEY_R)

    # dodge card -> 逃跑场面（夺门而出 + 双车道跑酷，十五轮）
    game.card_type = "dodge"
    game.phase = "card"
    game.apply_card()
    check(game.phase == "challenge" and game.dodge_lives == int(game.settings.dodge_lives), "dodge card enters challenge with lives")
    check(game.escape.is_open() and game.escape.state == "intro", "the escape opens with the door cinematic")
    for i in range(6):
        game.escape.update(0.5) # 3 秒：演出 2.2 秒走完，最后一帧进跑酷
    check(game.escape.state == "run", "the cinematic hands over to the run")
    game.escape.mouse_control = false # 测试不走鼠标：直接看键盘步进与目标高度
    game.escape.target_y = game.escape._y_max() # 人先站到最下端：只有那里才有往上的空间（无头模式下鼠标跟随会把目标锁在上限）
    var y_start: float = game.escape.target_y
    game.escape.handle_key(KEY_UP)
    check(game.escape.target_y == y_start - game.escape.KEY_STEP, "up arrow lifts the runner")
    game.escape.handle_key(KEY_DOWN)
    check(game.escape.target_y == y_start, "...and down brings him back")
    var lives_before_hit: int = game.dodge_lives
    game.escape.forced_obstacles.assign([{"row": 1, "kind": "bin"}])
    game.escape.spawn_t = 0.0 # 强迫本帧立即生成，免得长跑等待
    game.escape.update(0.2) # 障碍从右缘生成并左移
    game.escape.obstacles[0].x = game.escape._runner_x() # 直接挪到脚下，省去长跑等待
    game.escape.obstacles[0].y = game.escape.runner_y # 同一高度：必撞
    game.escape.update(1.0 / 60.0)
    check(game.dodge_lives == lives_before_hit - 1, "hitting an obstacle gets you caught once")
    game.escape.forced_obstacles.assign([{"row": 0, "kind": "bin"}])
    game.escape.target_y = game.escape._y_max() # 人贴到最近的一端
    game.escape.runner_y = game.escape._y_max()
    game.escape.spawn_t = 0.0
    game.escape.update(0.2)
    game.escape.obstacles[0].x = game.escape._runner_x()
    game.escape.obstacles[0].y = game.escape._y_min() # 障碍在最远的一端：够不着你
    game.escape.update(1.0 / 60.0)
    check(game.dodge_lives == lives_before_hit - 1, "vertical distance is what saves you now")
    game.bill_timer = 0.05
    game._process(0.1) # 主循环里 bill_timer 递减，escape 检测到就结算
    check(game.phase == "playing" and game.score == int(game.settings.bill_reward), "surviving the run clears bill and rewards")

    # win
    key_press(KEY_R)
    game.score = int(game.settings.round_target) - 10
    break_pig(0)
    check(game.phase == "finished" and game.score == int(game.settings.round_target), "reaching target escapes bankruptcy")
    click(game.pigs[7].position)
    check(game.score == int(game.settings.round_target), "finished round blocks scoring")
    key_press(KEY_R)
    check(game.score == 0 and game.phase == "playing" and game.next_card == int(game.settings.card_first_at), "R resets after win")
    check(game.particles.is_empty() and game.broken == 0 and game.pigs[0].hp == 2, "reset clears effects and restores pigs")

    # bill list (water / power / gas ...)
    var n0: int = game.bills.size()
    check(n0 == int(game.bill_data.get("start_count", 7)), "starts with the configured number of bills")
    check(int(game.bills[0].amount) <= int(game.bills[1].amount), "bills are sorted cheapest first")
    game.score = 0
    game.pay_bill(0)
    check(game.bills.size() == n0 and game.score == 0, "cannot pay a bill without money")
    game.score = int(game.bills[0].amount)
    game.stamina = 50.0
    game.pay_bill(0)
    check(game.score == 0 and game.bills.size() == n0 - 1 and game.paid_count == 1, "paying a bill spends the money and clears it")
    check(game.stamina > 50.0, "paying a bill refunds some stamina")

    # ledger (opened by clicking the stack) pauses the round and pages over the bills
    game.cooldown = 0.5
    game.bill_open = true
    game._process(0.1)
    check(game.cooldown == 0.5, "reading the ledger pauses the round")
    game.bill_open = false
    check(game.ledger_page_count() > 1, "bills spread over several pages")
    game.bill_page = 99
    game.clamp_bill_page()
    check(game.bill_page == game.ledger_page_count() - 1, "page never goes past the last one")

    # combo & shake
    key_press(KEY_R)
    check(game.combo_count == 0 and game.combo_timer == 0.0 and game.shake == 0.0, "fresh round has no combo or shake")
    click(game.pigs[0].position)
    check(game.combo_count == 1 and game.combo_timer > 0.0, "first hit starts combo at 1")
    game._process(0.4)
    click(game.pigs[0].position)
    check(game.combo_count == 2, "second hit within window extends combo")
    click(game.pigs[0].position)
    game._process(game.settings.combo_window + 0.1)
    check(game.combo_count == 0, "combo resets after window expires")
    game.shake = 0.0
    break_pig(1)
    check(game.shake > 0.0, "breaking pig triggers screen shake")
    game._process(game.settings.shake_duration + 0.1)
    check(game.shake == 0.0, "shake decays after duration")
    key_press(KEY_R)
    check(game.combo_count == 0 and game.combo_timer == 0.0 and game.shake == 0.0, "R clears combo and shake")

    # moving pigs (first round feature, merged in)
    var bounds: Rect2 = game.PIG_BOUNDS
    var before: Vector2 = game.pigs[0].position
    game._process(0.5)
    check(game.pigs[0].position != before, "pigs wander instead of standing still")
    for i in range(60):
        game._process(0.1)
    var inside := true
    for p in game.pigs:
        # grow(1.0)：猪被夹回围栏时坐标可能正好落在边界上，has_point 对边界是排他的
        if p.hp > 0 and not bounds.grow(1.0).has_point(p.position):
            inside = false
    check(inside, "wandering pigs stay inside the pen")

    # stamina (first round feature, merged in)
    key_press(KEY_R)
    check(game.stamina == float(game.settings.stamina_max), "fresh round starts with full stamina")
    var stamina_before: float = game.stamina
    click(game.pigs[0].position)
    check(game.stamina == stamina_before - float(game.settings.stamina_cost) + float(game.settings.stamina_hit_refund), "a hit costs the base swing stamina (minus its refund)")
    stamina_before = game.stamina
    click(Vector2(100, 300))
    var miss_cost := float(game.settings.stamina_cost) + float(game.settings.stamina_miss_extra)
    check(is_equal_approx(game.stamina, stamina_before - miss_cost), "a miss costs extra stamina")
    var score_before: int = game.score
    game.stamina = float(game.settings.stamina_cost) - 1.0
    click(game.pigs[0].position)
    check(game.phase == "finished" and game.end_reason == "exhausted" and game.score == score_before, "empty stamina ends the round without scoring")
    key_press(KEY_R)
    check(game.phase == "playing" and game.stamina == float(game.settings.stamina_max) and game.end_reason == "", "R refills stamina")

    # gamble coin (赌博心理：攒够阈值滚出硬币，抛正面翻倍 / 反面清零 / 不抛本局作废)
    check(game.gamble_state == "none" and not game.gamble_used, "fresh round has no coin on the table")
    game.score = int(game.gamble_threshold())
    game._process(0.1)
    check(game.gamble_state == "ready", "reaching the threshold rolls out the coin")
    game.start_gamble()
    check(game.gamble_state == "flip", "tossing the coin starts the flip")
    game.gamble_heads = true
    game.resolve_gamble()
    check(game.score == int(game.gamble_threshold()) * 2 and game.gamble_state == "result", "heads doubles the balance")
    check(game.phase == "finished" and game.end_reason == "coin", "doubling past the target wins via the coin")
    game.gamble_state = "none"
    key_press(KEY_R)
    game.score = int(game.gamble_threshold())
    game._process(0.1)
    game.start_gamble()
    game.gamble_heads = false
    game.resolve_gamble()
    check(game.score == 0 and game.gamble_state == "result", "tails wipes the balance to zero")
    game.gamble_state = "none"
    key_press(KEY_R)
    game.score = int(game.gamble_threshold())
    game._process(0.1)
    game.skip_gamble()
    check(game.gamble_used and game.gamble_state == "none", "declining the coin ends the gamble for the round")

    # --- pig types: different pigs pay different money ---
    var types: Array = [
        {"id": "piggy", "weight": 100, "hp": 2, "value": 14, "speed": 1.0, "scale": 1.0},
        {"id": "gold", "weight": 0, "hp": 3, "value": 34, "speed": 1.3, "scale": 1.16},
        {"id": "mini", "weight": 0, "hp": 1, "value": 9, "speed": 1.85, "scale": 0.7},
        {"id": "debt", "weight": 0, "hp": 1, "value": -9, "speed": 1.6, "scale": 0.95, "min_score": 15}
    ]
    game.settings["pig_types"] = types
    key_press(KEY_R)
    game.next_card = 10000 # 隔离：别让弹卡打断
    check(game.pig_max_hp(game.pigs[0].type) == 2 and game.pig_value(game.pigs[0].type) == 14,
        "with only the common pig weighted, it is the two-hit ¥14 one")

    # 金猪：三锤才碎，值 ¥34
    game.pigs[0].type = types[1]
    game.pigs[0].max_hp = 3
    game.pigs[0].hp = 3
    click(game.pigs[0].position)
    check(game.pigs[0].hp == 2 and game.score == 0, "gold pig survives the first hit")
    click(game.pigs[0].position)
    check(game.pigs[0].hp == 1 and game.score == 0, "gold pig survives the second hit")
    click(game.pigs[0].position)
    check(game.score == 34 and game.pigs[0].hp == 0, "gold pig pays ¥34 on the third hit")

    # 迷你猪：一锤就碎，¥9
    key_press(KEY_R)
    game.next_card = 10000
    game.pigs[1].type = types[2]
    game.pigs[1].max_hp = 1
    game.pigs[1].hp = 1
    click(game.pigs[1].position)
    check(game.score == 9, "mini pig breaks in one hit for ¥9")

    # 体型决定判定大小：迷你猪比标准猪更难打中
    key_press(KEY_R)
    game.next_card = 10000
    game.pigs[2].type = types[2] # scale 0.7
    game.pigs[2].max_hp = 1
    game.pigs[2].hp = 1
    click(game.pigs[2].position + Vector2(72, 0)) # 在标准猪的判定范围内，但在迷你猪之外
    check(game.pigs[2].hp == 1, "the small pig is harder to hit than a normal one")
    click(game.pigs[2].position)
    check(game.pigs[2].hp == 0, "the small pig still breaks when hit dead on")

    # 催债猪：碎了倒贴 ¥9
    key_press(KEY_R)
    game.next_card = 10000
    game.score = 40
    game.pigs[3].type = types[3]
    game.pigs[3].max_hp = 1
    game.pigs[3].hp = 1
    click(game.pigs[3].position)
    check(game.score == 31, "debt pig costs ¥9 instead of paying")

    # 倒贴不该一锤就把人打成破产
    key_press(KEY_R)
    game.next_card = 10000
    game.score = 5
    game.pigs[4].type = types[3]
    game.pigs[4].max_hp = 1
    game.pigs[4].hp = 1
    click(game.pigs[4].position)
    check(game.score == 1 and game.phase == "playing", "debt pig cannot bankrupt you outright")

    # 兜里没钱的时候，催债猪根本不出现
    var mixed: Array = [
        {"id": "piggy", "weight": 1, "hp": 2, "value": 10, "scale": 1.0},
        {"id": "debt", "weight": 99, "hp": 1, "value": -9, "scale": 0.95, "min_score": 15}
    ]
    game.settings["pig_types"] = mixed
    game.score = 0
    var leaked := false
    for i in range(50):
        if String(game.pick_pig_type().get("id", "")) == "debt":
            leaked = true
    check(not leaked, "the debt pig never shows up while you have no money")
    game.score = 40
    var showed := false
    for i in range(50):
        if String(game.pick_pig_type().get("id", "")) == "debt":
            showed = true
    check(showed, "the debt pig shows up once there is money to lose")

    # --- 光标：UI 界面必须把系统箭头还回来，否则那些界面上一个指针都没有 ---
    key_press(KEY_R)
    game.phase = "playing"
    game.card_type = "dodge"
    game._process(0.016)
    check(game.cursor_hidden, "the hammer stands in for the cursor while you are playing")
    game.phase = "challenge"
    game._process(0.016)
    check(not game.cursor_hidden, "...and the system cursor stays for the mouse-follow run")
    game.phase = "card"
    game._process(0.016)
    check(not game.cursor_hidden, "the system cursor comes back on the card screen")
    game.phase = "finished"
    game._process(0.016)
    check(not game.cursor_hidden, "...and on the result screen")
    game.phase = "playing"
    game.bill_open = true
    game._process(0.016)
    check(not game.cursor_hidden, "...and while the ledger is open")
    game.bill_open = false
    game._process(0.016)
    check(game.cursor_hidden, "...and the hammer takes over again once you are back at the table")
    game.day_events._open("pawn") # 小游戏弹窗：同样必须还回系统箭头（全靠鼠标点，藏了就没法玩）
    game._process(0.016)
    check(game.day_events.is_open() and not game.cursor_hidden, "...and while a day-event popup is open")
    game.day_events._close()
    game._process(0.016)
    check(game.cursor_hidden, "...and the hammer takes over again after the popup closes")

    # --- 大肚猪要四锤；价目表只列见过的种类 ---
    var real: Array = [
        {"id": "fat", "label": "大肚猪", "weight": 100, "hp": 4, "value": 36, "speed": 0.7, "scale": 1.3},
        {"id": "glass", "label": "玻璃猪", "weight": 0, "hp": 1, "value": 17, "speed": 1.15, "scale": 0.85, "glass": true}
    ]
    game.settings["pig_types"] = real
    key_press(KEY_R)
    game.next_card = 10000
    game.pigs[0].type = real[0]
    game.pigs[0].max_hp = 4
    game.pigs[0].hp = 4
    for i in range(3):
        click(game.pigs[0].position)
    check(game.score == 0 and game.pigs[0].hp == 1, "the big belly pig takes four hits")
    click(game.pigs[0].position)
    check(game.score == 36, "...and pays ¥36 on the fourth")

    game.seen_types.clear()
    check(not game.pig_legend().contains("大肚猪"), "the price list only shows pigs you have already met")
    game.seen_types["fat"] = true
    check(game.pig_legend().contains("大肚猪"), "...and adds them once you have met one")

    # --- 弹卡不许糊掉爆钱的反馈：当前首卡阈值 ¥160，且要等半秒 ---
    var real_types: Array = game.settings["pig_types"]
    game.settings["pig_types"] = [
        {"id": "fat", "label": "大肚猪", "weight": 100, "hp": 1, "value": 10, "speed": 0.0, "scale": 1.3}
    ]
    key_press(KEY_R)
    game.gamble_used = true # 隔离：这段测卡片节奏，别让硬币插进来
    check(game.next_card == 160 and game.card_delay == 0.0, "the first card waits until ¥160")
    for i in range(15):
        click(game.pigs[0].position)
        game._process(float(game.settings.respawn_seconds) + 0.1) # 等它重生，否则下一锤没东西可打
    check(game.phase == "playing" and game.card_delay == 0.0, "still playing below the card threshold")
    click(game.pigs[0].position) # 达到 ¥160
    check(game.next_card == 295, "crossing the threshold schedules the next one")
    check(game.phase == "playing", "the card does NOT pop on the same frame the pig bursts")
    check(game.card_delay > 0.0, "...it waits for the money-jingle to finish")
    game.cooldown = 0.18
    game._process(0.1)
    check(game.cooldown < 0.18, "the swing cooldown keeps ticking during the wait: you can keep hammering")
    game._process(0.2)
    check(game.phase == "playing", "a fifth of a second later it is still waiting")
    game._process(0.4)
    check(game.phase == "card", "the card arrives only after the burst has played out")
    check(game.card_delay == 0.0, "the delay does not linger after popping")

    # --- 碎猪撒出来的金币：钱越多的猪撒得越多，且不许堆成粒子洪水 ---
    game.particles.clear()
    game.spawn_particles(Vector2(400, 400), "mini", 9)
    var mini_coins := 0
    for p in game.particles:
        if bool(p.coin):
            mini_coins += 1
    game.particles.clear()
    game.spawn_particles(Vector2(400, 400), "gold", 34)
    var gold_coins := 0
    for p in game.particles:
        if bool(p.coin):
            gold_coins += 1
    check(gold_coins > mini_coins, "a richer pig spills more coins than a cheap one")
    check(mini_coins >= 5 and gold_coins <= 10, "the coin burst stays within its bounds")
    game.particles.clear()
    for i in range(12): # 狂热时一秒连碎好几只
        game.spawn_particles(Vector2(400, 400), "gold", 34)
    check(game.particles.size() <= 70, "the burst never stacks up into a particle flood")

    # 达标优先：同一帧既越过 next_card 又达到本局目标 → 先进入结算，不弹卡
    key_press(KEY_R)
    game.card_delay = 0.5 # 模拟：卡片正挂着
    game.settings["pig_types"] = [
        {"id": "test", "weight": 100, "hp": 1, "value": 10, "speed": 0.0, "scale": 1.0}
    ]
    key_press(KEY_R)
    game.score = int(game.settings.round_target) - 5
    click(game.pigs[0].position) # +10，越过目标
    check(game.phase == "finished", "hitting the target wins outright")
    game._process(0.6)
    check(game.phase == "finished", "no stray card pops over the win screen")
    game.settings["pig_types"] = real_types

    # --- 满桌小猪：数量 = 行 × 列，判定跟着绘制尺寸缩，且不会漂成一坨 ---
    var saved_types: Array = game.settings["pig_types"]
    var saved_size: float = float(game.settings.get("pig_draw_size", 138))
    game.settings["pig_types"] = [
        {"id": "piggy", "label": "白猪", "weight": 100, "hp": 2, "value": 10, "speed": 0.0, "scale": 1.0}
    ]
    key_press(KEY_R)
    game.next_card = 10000
    game.gamble_used = true
    check(game.pigs.size() == int(game.settings.pig_rows) * int(game.settings.pig_cols),
        "the table holds rows × cols pigs")

    var reach: float = 84.0 * (game.pig_size() / 138.0) # 判定是 84 × 尺寸比例
    click(game.pigs[0].position + Vector2(reach + 14.0, 0))
    check(game.pigs[0].hp == 2, "the hit box shrinks with the pig, not just its sprite")
    click(game.pigs[0].position)
    check(game.pigs[0].hp == 1, "...but a dead-on hit still lands")

    # 没有碰撞的随机游走迟早会聚成一坨：分离力要能把它们推开
    for i in range(140):
        game._process(0.016)
    var min_gap := 9999.0
    for i in range(game.pigs.size()):
        for j in range(i + 1, game.pigs.size()):
            if game.pigs[i].hp <= 0 or game.pigs[j].hp <= 0:
                continue
            min_gap = minf(min_gap, game.pigs[i].position.distance_to(game.pigs[j].position))
    check(min_gap > 35.0, "a table full of pigs spreads out instead of piling into one lump")
    game.settings["pig_types"] = saved_types
    game.settings["pig_draw_size"] = saved_size

    # --- P1 账单压力系统：效果由数据驱动，来源必须能按账单追踪 ---
    key_press(KEY_R)
    game.gamble_used = true
    game.next_card = 100000
    game.bills.clear()
    var fx_cards: Array = [
        {"name": "电费", "amount": 10, "id": "electricity", "effect_id": "blackout"},
        {"name": "信用卡还款", "amount": 20, "id": "credit_card", "effect_id": "interest"},
        {"name": "房租", "amount": 30, "id": "rent", "effect_id": "collection"},
        {"name": "水费", "amount": 40},
    ]
    for i in range(fx_cards.size()):
        var src: Dictionary = fx_cards[i]
        game.bills.append({"name": String(src.name), "amount": int(src.amount),
        "no": "100" + str(i), "due": "1 号",
        "id": String(src.get("id", "")), "effect_id": String(src.get("effect_id", ""))})
    game.bills_fx.reset()
    game.bills_fx.sync(game.bills)

    check(game.bills_fx.is_active("blackout"), "unpaid electricity keeps the lights off")
    check(game.bills_fx.is_active("interest"), "unpaid credit card keeps charging interest")
    check(game.bills_fx.is_active("collection"), "unpaid rent keeps the landlord coming")

    # 屋顶灯泡（十七轮）：欠费时闪烁、缴费后常亮
    game.blackout_fade = 1.0 # 直接拉满渐入，不等真实的 0.6 秒
    var flickers := {}
    for i in range(14):
        flickers[game.bulb_brightness_at(game.elapsed + 0.37 * i)] = true
    check(flickers.size() > 1, "the bulb flickers while the power bill is unpaid")
    check(float(game.bills_fx.number("blackout", "darkness_alpha", 1.0)) < 0.3,
        "blackout now darkens gently and lets the flickering bulb carry the mood")
    game.blackout_fade = 0.0
    check(game.bulb_brightness_at(game.elapsed) == 1.0, "a paid-up bulb burns steady")
    check(game.bulb_tex != null, "the painted bulb sprite loads (vector fallback only if missing)")

    # 余额不足：不扣钱、效果不解除
    game.score = 5
    game.pay_bill(0)
    check(game.bills.size() == 4 and game.bills_fx.is_active("blackout"),
        "paying with too little money changes nothing")

    # 支付电费：只解除停电，其它效果还在
    game.score = 500
    game.pay_bill(0)
    check(not game.bills_fx.is_active("blackout"), "paying the power bill brings the lights back")
    check(game.bills_fx.is_active("interest") and game.bills_fx.is_active("collection"),
        "...and only the power effect")
    check(game.bonus_timer > 0.0, "paying the power bill grants a short cooldown bonus")

    # 信用卡：一次失败只计一次息
    game.bill_amount = 30
    game.score = 500
    game.finish_challenge(false)
    check(_interest_count() == 1 and _interest_sum() == 10,
        "a failed challenge adds exactly one interest charge")
    game.finish_challenge(false)
    check(_interest_count() == 1 and _interest_sum() == 20,
        "interest piles onto the same bill, once per failure")

    # 还掉信用卡：它自己产生的利息一并作废，滞纳金不受影响
    var late_before := _count_named("滞纳金")
    var cc := _find_id("credit_card")
    game.score = 500
    game.pay_bill(cc)
    check(_interest_count() == 0, "paying the card voids its own interest")
    check(_count_named("滞纳金") == late_before, "...without touching late fees")

    # 房租催收：跨阈值触发，冷却与每局上限都生效
    var visits: Dictionary = {"n": 0}
    game.bills_fx.collection_triggered.connect(func(_t: String) -> void: visits.n += 1)
    game.bills_fx.update_collection(0.1, 100.0)
    check(visits.n == 1, "crossing the income threshold brings the landlord")
    game.bills_fx.update_collection(0.1, 150.0)
    check(visits.n == 1, "the landlord respects his cooldown")
    game.bills_fx.update_collection(60.0, 320.0)
    check(visits.n == 2, "...and comes back once the cooldown is over")
    game.bills_fx.update_collection(60.0, 620.0)
    check(visits.n == 3, "still coming while the rent stays unpaid")
    game.bills_fx.update_collection(60.0, 900.0)
    game.bills_fx.update_collection(60.0, 1200.0)
    check(visits.n == 3, "but never more than three times per run")

    # 还掉房租：不再有人上门
    var rent := _find_id("rent")
    game.score = 500
    game.pay_bill(rent)
    check(not game.bills_fx.is_active("collection"), "paying the rent stops the landlord")

    # 重开一局：利息累计与催收计数清零
    key_press(KEY_R)
    check(game.bills_fx.interest_total == 0 and game.bills_fx.collection_count == 0,
        "a new run clears accumulated interest and the collection counter")

    # --- 奖励构筑：猪群翻倍 ---
    key_press(KEY_R)
    var herd_base_count: int = game.pigs.size()
    game.phase = "card"
    game.card_type = "reward"
    var herd_offers: Array[Dictionary] = [
        {"id": "herd", "name": "猪群翻倍", "desc": "测试", "icon": "×2", "color": "#69b88e"},
        {"id": "cash", "name": "现金奖励", "desc": "测试", "icon": "＋", "color": "#efbc72"},
        {"id": "heavy", "name": "重锤改造", "desc": "测试", "icon": "⚒", "color": "#e8836b"},
    ]
    game.card_offers = herd_offers
    game.apply_card(0)
    check(game.pigs.size() == herd_base_count * 2, "herd card doubles the table population")
    check(is_equal_approx(game.pig_size_multiplier, 0.68), "herd card shrinks the full herd")
    check(game.pig_population_doubled and game.phase == "playing", "herd card marks the run and resumes play")
    key_press(KEY_R)
    check(game.pigs.size() == herd_base_count and is_equal_approx(game.pig_size_multiplier, 1.0),
        "a new run restores the original pig count and size")
    check(not game.pig_population_doubled, "a new run makes the herd card available again")

    # --- 蓄力重锤：轻点是快锤（power=1），按满松手是重锤（power=1.5） ---
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    game.pigs[0]["type"] = {"id": "piggy", "label": "白猪", "hp": 1, "value": 100, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    game.score = 100
    game.combo_count = 0
    game.combo_timer = 0.0
    game.cooldown = 0.0
    game.strike(game.pigs[0].position, 1.5)
    check(game.score == 250, "a full-charge hammer adds half again to the payout")

    game.pigs[0]["type"] = {"id": "fat", "label": "大肚猪", "hp": 4, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 4
    game.pigs[0]["max_hp"] = 4
    game.cooldown = 0.0
    game.strike(game.pigs[0].position, 1.5)
    check(int(game.pigs[0]["hp"]) == 2, "a full-charge hit deals two damage")
    game.cooldown = 0.0
    game.strike(game.pigs[0].position, 1.0)
    check(int(game.pigs[0]["hp"]) == 1, "a light tap still deals one")

    # 重锤砸空要付代价，轻锤砸空只付常规消耗
    game.stamina = 100.0
    game.cooldown = 0.0
    game.strike(Vector2(40, 40), 1.0)
    check(is_equal_approx(game.stamina, 95.0), "a light whiff costs the swing plus the miss penalty")
    game.cooldown = 0.0
    game.strike(Vector2(40, 40), 1.5)
    check(is_equal_approx(game.stamina, 88.0), "a heavy whiff costs extra stamina on top")

    # --- 按住/松手：按下只蓄力不落锤，松手那一刻才落 ---
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    game._unhandled_input(press)
    check(game.charging and game.charge_t == 0.0, "pressing the left button starts charging instead of striking")
    check(game.hits == 0, "no hammer lands while the button is held")
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    game._unhandled_input(release)
    check(not game.charging and game.charge_pig == -1, "releasing the button lands the hammer and clears the aim")

    # --- 松手瞄准修正：按住时猪走开了，松手只要还在锤头附近就砸它现在的位置 ---
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    game.pigs[0]["type"] = {"id": "piggy", "label": "白猪", "hp": 1, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    game.pigs[0]["velocity"] = Vector2.ZERO
    game.score = 0
    game.combo_count = 0
    game.combo_timer = 0.0
    game.charging = true
    game.charge_t = 0.5
    game.charge_pig = 0
    game.cooldown = 0.0
    game.strike_release(game.pigs[0].position, 1.5)
    check(game.score == 15, "a released charge strike lands on the pig it was aiming at")

    # --- 瞄准：打在谁身上，由「离准心最近」决定，不由猪在数组里的顺序决定 ---
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    var single := {"id": "gold", "label": "金猪", "hp": 99, "value": 10, "scale": 1.0}
    for i in range(game.pigs.size()):
        game.pigs[i]["hp"] = 99
        game.pigs[i]["max_hp"] = 99
        game.pigs[i]["type"] = Dictionary(single)
        game.pigs[i]["velocity"] = Vector2.ZERO
    game.pigs[0]["position"] = Vector2(520, 430) # 先出现在数组里的那只
    game.pigs[1]["position"] = Vector2(572, 430) # 后出现的、但离准心更近
    for i in range(2, game.pigs.size()):
        game.pigs[i]["hp"] = 0 # 其余清空，别插进判定
    game.cooldown = 0.0
    game.strike(Vector2(566, 430))
    check(int(game.pigs[0]["hp"]) == 99, "the far pig keeps its hp even though it comes first in the list")
    check(int(game.pigs[1]["hp"]) == 98, "the pig closest to the crosshair takes the hit")

    # --- 判定跟着「看得见的位置」走，且范围有边界 ---
    var ext: Vector2 = game.pig_hit_extents(game.pigs[1])
    var down: Vector2 = game.pig_visual_center(game.pigs[1]) + Vector2(0, ext.y * 0.9)
    check(game.hit_offset(down, game.pigs[1]) < 1.0,
        "the hit area is centred on the pig as drawn, not on some offset point")
    var too_far: Vector2 = game.pig_visual_center(game.pigs[1]) + Vector2(ext.x * 1.2, 0)
    check(game.hit_offset(too_far, game.pigs[1]) > 1.0,
        "and it still ends somewhere: 1.2 half-widths out is a miss")

    # --- 暴击：连击越高越容易，上限 30% ---
    game.settings["crit_base_chance"] = 0.06
    game.settings["crit_per_combo"] = 0.015
    game.settings["crit_max_chance"] = 0.30
    check(is_equal_approx(game.crit_chance(1), 0.06), "a cold opener gets the base crit chance")
    check(is_equal_approx(game.crit_chance(10), 0.06 + 9.0 * 0.015),
        "every combo layer on top adds crit chance")
    check(is_equal_approx(game.crit_chance(100), 0.30), "crit chance is capped at 30%")

    # 必定暴击的极端参数下：正收益翻倍，黑猪的亏损一分都不放大
    # ⚠️ 上限也要一起放开 —— 只把 base 设成 1.0 会被 crit_max_chance 夹回 30%
    game.settings["crit_base_chance"] = 1.0
    game.settings["crit_per_combo"] = 0.0
    game.settings["crit_max_chance"] = 1.0
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    game.pigs[0]["type"] = {"id": "piggy", "label": "白猪", "hp": 1, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    game.score = 100
    game.combo_count = 0
    game.combo_timer = 0.0
    game.cooldown = 0.0
    game.strike(game.pigs[0].position)
    check(game.score == 120, "a guaranteed crit doubles a normal pig's payout")

    game.pigs[0]["type"] = {"id": "debt", "label": "黑猪", "hp": 1, "value": -9, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    var debt_before: int = game.score
    game.cooldown = 0.0
    game.strike(game.pigs[0].position)
    check(game.score == debt_before - 9, "a crit never doubles the black pig's loss")
    game.settings["crit_base_chance"] = 0.0
    game.settings["crit_per_combo"] = 0.0
    game.settings["crit_max_chance"] = 0.0

    # --- 输入缓冲：冷却里按下的那一下不丢，冷却一好就落下去 ---
    game.settings["strike_buffer"] = 0.3
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    var hp_before: int = int(game.pigs[1]["hp"])
    game.cooldown = 0.10
    game.strike(game.pigs[1].position)
    check(game.pending_strike.size() > 0, "a click inside the swing cooldown is remembered, not thrown away")
    check(int(game.pigs[1]["hp"]) == hp_before, "and it does not hit twice in the same instant")
    game.pending_t = 0.2
    game.cooldown = 0.0
    game._process(0.016)
    check(int(game.pigs[1]["hp"]) == hp_before - 1, "the remembered click lands as soon as the cooldown ends")
    check(game.pending_strike.is_empty(), "the buffer is emptied after it fires")

    # 冷却还剩很久时，等到过期就作废（不能补一锤几秒前的旧账）
    game.pending_strike = {"point": game.pigs[1].position, "power": 1.0, "pig": 1}
    game.pending_t = 0.02
    game.cooldown = 5.0
    for i in range(6): # 顿帧会吞头两帧（hit_stop 0.06 > 单帧 0.05）：多跑几帧等它解冻
        game._process(0.05)
    check(game.pending_strike.is_empty(), "a buffered click that waits too long is dropped")
    game.settings["strike_buffer"] = 0.0

    # ================= A：账单到期考核 =================
    # 到期不再默默盖章，而是先给一次「凑钱 / 躲催债」的机会。
    key_press(KEY_R)
    game.bill_data["challenge_max_per_run"] = 3
    game.bill_data["challenge_warning_seconds"] = 0.0 # 老断言按"立即开考"写：预告关掉
    game.bill_data["challenge_rest_seconds"] = 0.0
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.challenge_count = 0
    game.pending_challenge = {}
    game.score = 800
    # 把最便宜的一张账单的到期日拉到今天，再把收入推过一天的门槛
    game.bills[0]["due_day"] = game.game_day
    var income_day := float(game.bill_data["income_per_game_day"])
    game.earned_total = income_day * 2.0
    game._process(0.016)
    check(game.phase == "challenge", "a bill falling due opens a payment challenge instead of silently stamping it")
    check(not game.challenge_bill_tag.is_empty(), "the challenge is bound to the bill that came due")
    check(game.challenge_count == 1, "the challenge counter goes up exactly once")
    check(not game.challenge_label.is_empty(), "the challenge panel knows which bill is being chased")

    # 赢了：付掉的是「被催的那一张」，不是最便宜的那一张
    var bills_before_win: int = game.bills.size()
    game.finish_challenge(true)
    check(game.phase == "playing", "clearing the challenge resumes play")
    check(game.bills.size() == bills_before_win - 1, "winning pays off exactly one bill")
    check(game.challenge_bill_tag.is_empty(), "the bound bill is released after settlement")

    # 输了：账单当场逾期，钱照扣
    game.bills.sort_custom(func(a, b): return int(a.get("due_day", 9999)) < int(b.get("due_day", 9999)))
    # 排序后的第一张可能是前面日历测试已盖过逾期章的旧账（advance_calendar 会跳过它），
    # 绑账单必须绑一张还活着的，否则这段断言随 roll_bills 的随机结果时好时坏
    var _alive := -1
    for bi in range(game.bills.size()):
        if not bool(game.bills[bi].get("overdue", false)):
            _alive = bi
            break
    game.bills[_alive]["due_day"] = game.game_day
    # 日历会一次性推进多天（earned_total 已攒了几天的量）：其余账单全部推到远期，
    # 保证这一步只有被绑定的那张到期 —— 否则逾期计数随随机账单时好时坏
    for bi in range(game.bills.size()):
        if bi != _alive:
            game.bills[bi]["due_day"] = game.game_day + 999
    game.pending_challenge = {}
    game.earned_total += income_day
    game._process(0.016)
    check(game.phase == "challenge", "the next due bill opens another challenge")
    var bound_tag_loss: String = game.challenge_bill_tag
    check(not bound_tag_loss.is_empty(), "the loss challenge is bound to a real bill")
    var score_before_loss: int = game.score
    game.finish_challenge(false)
    # 意图断言：被绑定的那张账单（或同标签的连坐单）当场盖了逾期章。
    # 不再比较逾期计数 —— 利息单/滞纳单可能与被绑账单同标签，计数会随随机账单漂移。
    var stamped := false
    for b in game.bills:
        if String(BillManagerScript.tag_of(b)) == bound_tag_loss and bool(b.get("overdue", false)):
            stamped = true
    check(stamped, "losing stamps the due bill as overdue right away")
    check(game.score == score_before_loss - int(game.settings.bill_amount), "losing still costs the penalty")

    # 一局有上限：超出上限就退回原来的「直接盖章」
    game.challenge_count = 3
    game.bills.sort_custom(func(a, b): return int(a.get("due_day", 9999)) < int(b.get("due_day", 9999)))
    game.bills[0]["due_day"] = game.game_day
    game.pending_challenge = {}
    game.earned_total += income_day
    game._process(0.016)
    check(game.phase == "playing" and game.pending_challenge.is_empty(),
        "no more challenges once the per-run cap is reached")
    game.bill_data["challenge_max_per_run"] = 0

    # ================= A2：考核预告与喘息冷却 =================
    # 挂起后不再立即开考：先亮预告横幅倒计时；考核结束有喘息；喘息/让出机会期间到期票推迟不盖章。
    key_press(KEY_R)
    game.bill_data["challenge_max_per_run"] = 3
    game.bill_data["challenge_warning_seconds"] = 3.0
    game.bill_data["challenge_rest_seconds"] = 6.0
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.challenge_count = 0
    game.pending_challenge = {}
    game.score = 800
    # 两张账单同一天到期：一张拿考核机会（先亮预告），另一张不当场盖逾期章
    game.bills[0]["due_day"] = game.game_day
    game.bills[1]["due_day"] = game.game_day
    game.earned_total = income_day * 2.0
    game._process(0.016)
    check(game.phase == "playing" and not game.pending_challenge.is_empty(),
        "a due bill schedules a warning instead of jumping straight into the challenge")
    check(game.challenge_warn_t > 0.0, "the challenge warning shows a visible countdown")
    check(not bool(game.bills[1].get("overdue", false)),
        "a second bill due in the same calendar jump is deferred, not stamped")
    game._process(4.0) # 预告走完
    check(game.phase == "challenge", "the challenge starts once the warning expires")
    game.finish_challenge(true) # 赢了免单：进入喘息期
    check(game.challenge_rest_t > 0.0, "a finished challenge grants a breathing cooldown")
    # 喘息期内另一张票仍挂着到期：不挂新考核、也不盖逾期章
    game.earned_total += income_day
    game._process(0.016)
    check(game.phase == "playing" and game.pending_challenge.is_empty(),
        "no new challenge is scheduled during the breathing cooldown")
    check(not bool(game.bills[1].get("overdue", false)),
        "bills falling due during the cooldown are deferred, not stamped")
    game.challenge_rest_t = 0.0 # 冷却结束：下次日历推进时它拿到机会
    game.earned_total += income_day
    game._process(0.016)
    check(not game.pending_challenge.is_empty(),
        "the deferred bill gets its own chance once the cooldown is over")
    game.bill_data["challenge_max_per_run"] = 0

    # ================= B：代价型构筑卡 =================
    # 孤注一掷：体力上限砍四成，收益 ×1.8
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    var cap_before: int = int(game.settings["stamina_max"])
    game.phase = "card"
    game.card_type = "reward"
    game.card_offers = offers_with("allin", "孤注一掷")
    game.apply_card(0)
    check(is_equal_approx(game.stamina_max_multiplier, 0.6), "all-in trades stamina capacity for payout")
    check(int(game.settings["stamina_max"]) == maxi(20, int(round(float(cap_before) * 0.6))),
        "all-in lowers the stamina ceiling itself, not just the bar")
    check(is_equal_approx(game.earnings_multiplier, 1.8), "all-in pays almost double per pig")
    # 重开必须把上限还回去，不能把代价带进下一局
    key_press(KEY_R)
    check(is_equal_approx(game.stamina_max_multiplier, 1.0) and int(game.settings["stamina_max"]) >= 20,
        "a new run undoes all-in")

    # 玻璃猎人：玻璃猪 ×3，其余 ×0.7
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    game.phase = "card"
    game.card_type = "reward"
    game.card_offers = offers_with("glasshunter", "玻璃猎人")
    game.apply_card(0)
    check(float(game.type_value_bonus.get("glass", 0.0)) == 3.0, "the glass hunter triples glass pigs")
    check(is_equal_approx(game.type_value_penalty, 0.7), "and docks every other breed by 30%")
    game.phase = "playing"
    game.score = 0
    game.combo_count = 0
    game.combo_timer = 0.0
    game.pigs[0]["type"] = {"id": "glass", "label": "玻璃猪", "hp": 1, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    game.cooldown = 0.0
    game.strike(game.pigs[0]["position"])
    check(game.score == 30, "a glass pig now pays triple")
    game.pigs[0]["type"] = {"id": "piggy", "label": "牛仔猪", "hp": 1, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 1
    game.pigs[0]["max_hp"] = 1
    game.score = 0
    game.cooldown = 0.0
    game.pending_strike = {}
    game.pending_t = 0.0
    game.strike(game.pigs[0]["position"])
    check(game.score == 7, "an ordinary pig now pays 70%")

    # 断臂求生：轻锤零伤害，重锤翻倍
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.pending_strike = {}
    game.pending_t = 0.0
    game.phase = "card"
    game.card_type = "reward"
    game.card_offers = offers_with("onehand", "断臂求生")
    game.apply_card(0)
    check(game.light_hammer_off and is_equal_approx(game.heavy_hammer_multiplier, 2.0),
        "one-hand mode kills light taps and doubles heavy blows")
    game.phase = "playing"
    game.pigs[0]["type"] = {"id": "fat", "label": "胖警长", "hp": 4, "value": 10, "scale": 1.0}
    game.pigs[0]["hp"] = 4
    game.pigs[0]["max_hp"] = 4
    game.combo_count = 0
    game.cooldown = 0.0
    game.strike(game.pigs[0]["position"], 1.0)
    check(int(game.pigs[0]["hp"]) == 4, "a light tap does nothing at all with one arm")
    game.cooldown = 0.0
    game.pending_strike = {}
    game.pending_t = 0.0
    game.strike(game.pigs[0]["position"], 1.5)
    check(int(game.pigs[0]["hp"]) == 0, "a heavy blow hits for double")

    # 透支信用：现在拿钱，立刻多一张账单
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    var bills_before_od: int = game.bills.size()
    var score_before_od: int = game.score
    game.phase = "card"
    game.card_type = "reward"
    game.card_offers = offers_with("overdraft", "透支信用")
    game.apply_card(0)
    check(game.score == score_before_od + int(game.settings.get("overdraft_cash", 200)),
        "overdraft hands the cash over up front")
    check(game.bills.size() == bills_before_od + 1, "and a new bill appears right away")

    # 守财奴：每还一张账单，往后每一锤更值钱
    key_press(KEY_R)
    game.next_card = 999999
    game.gamble_used = true
    game.settings["pig_types"] = []
    game.phase = "card"
    game.card_type = "reward"
    game.card_offers = offers_with("miser", "守财奴")
    game.apply_card(0)
    check(is_equal_approx(game.pay_greed_per_pay, 0.05), "the miser turns every payment into a raise")
    game.phase = "playing"
    game.score = 5000
    var em_before: float = game.earnings_multiplier
    game.pay_bill(0)
    check(is_equal_approx(game.earnings_multiplier, em_before + 0.05),
        "paying a bill raises every future payout")

    # 一次性改造不会抽到第二次
    game.stamina_max_multiplier = 0.6
    game.light_hammer_off = true
    game.type_value_bonus = {"glass": 3.0}
    var seen_ids := {}
    for i in range(60):
        for card in game.make_card_offers():
            seen_ids[String(card.id)] = true
    check(not seen_ids.has("allin") and not seen_ids.has("onehand") and not seen_ids.has("glasshunter"),
        "one-off remodel cards are never offered again")

    # ================= 幸运转盘：机会获取 / 暂停 / 六种结果 / 金猪 =================
    # 本地版多了概率暴击（合并版没有），测试段先关掉保证确定性
    game.settings["crit_base_chance"] = 0.0
    game.settings["crit_per_combo"] = 0.0
    key_press(KEY_R)
    game.next_card = 100000
    game.gamble_used = true
    game.challenge_count = 99 # 日历推进不再触发考核打断（满上限后只盖章）
    for b in game.bills:
        b["due_day"] = game.game_day + 999 # 账单全部推到远期：日历怎么走都不会逾期
    check(game.wheel != null and game.wheel.chances == 0, "a fresh run starts with no wheel chances")
    check(not game.wheel.open_wheel(), "the wheel refuses to open without chances")

    # 余额跨过 ¥500 → +1 次机会
    game.score = 499
    game._process(0.016)
    check(game.wheel.chances == 0, "no wheel chance just below ¥500")
    game.score = 500
    game._process(0.016)
    check(game.wheel.chances == 1, "reaching ¥500 grants a wheel chance")
    game.wheel.chances = 0

    # 连续砸中 12 只 → +1 次机会；漏砸（挥空）清零
    game.settings["pig_types"] = [
        {"id": "piggy", "weight": 100, "hp": 1, "value": 1, "speed": 0.0, "scale": 1.0}
    ]
    key_press(KEY_R)
    game.next_card = 100000
    game.gamble_used = true
    game.challenge_count = 99
    for b in game.bills:
        b["due_day"] = game.game_day + 999
    for i in range(12):
        click(game.pigs[i].position)
    check(game.wheel.chances == 1 and game.wheel.streak == 0,
        "12 consecutive hits grant a wheel chance and reset the streak")
    for i in range(12, 17):
        click(game.pigs[i].position)
    check(game.wheel.streak == 5, "landed hits count up the streak")
    click(Vector2(0, 0))
    check(game.wheel.streak == 0, "a missed swing resets the streak")
    game.wheel.chances = 0

    # 转盘弹窗期间整局暂停；结果 0 = +¥120
    game.wheel.chances = 1
    check(game.wheel.open_wheel(0), "the wheel opens on a forced sector")
    check(game.wheel.is_open(), "the wheel popup is open")
    game.cooldown = 0.5
    game._process(0.1)
    check(game.cooldown == 0.5, "the wheel popup pauses the round")
    var score_before_spin: int = game.score
    game.wheel.finish_spin()
    check(game.score == score_before_spin + 120, "sector 0 pays ¥120")
    game.wheel.confirm_result()
    check(not game.wheel.is_open(), "confirm closes the wheel popup")

    # 结果 3 = 直还 5 张账单（先垫 5 张小额账单，保证一定有得免）
    key_press(KEY_R)
    game.next_card = 100000
    game.gamble_used = true
    game.challenge_count = 99
    for i in range(5):
        game.bills.append({"name": "测试垫账 " + str(i), "amount": 10, "due_day": game.game_day + 999})
    game.sort_bills()
    var bills_before: int = game.bills.size()
    game.wheel.chances = 1
    game.wheel.open_wheel(3)
    game.wheel.finish_spin()
    game.wheel.confirm_result()
    check(game.bills.size() == bills_before - 5, "sector 3 pays off five bills for free")

    # 结果 1 = 20 秒得分翻倍（独立计时器，作用在敲猪收益上）
    game.wheel.chances = 1
    game.wheel.open_wheel(1)
    game.wheel.finish_spin()
    game.wheel.confirm_result()
    check(game.wheel.double_left > 19.0, "sector 1 arms the double buff for 20s")
    var s0: int = game.score
    break_pig(0)
    check(game.score == s0 + 2, "the wheel double buff doubles pig earnings")

    # 结果 2/4 = 变慢与变快叠加：独立计时器同时生效
    game.wheel.chances = 2
    game.wheel.open_wheel(2)
    game.wheel.finish_spin()
    game.wheel.confirm_result()
    game.wheel.open_wheel(4)
    game.wheel.finish_spin()
    game.wheel.confirm_result()
    check(game.wheel.slow_left > 0.0 and game.wheel.fast_left > 0.0,
        "slow and fast buffs stack with independent timers")
    check(game.wheel.pig_speed_multiplier() < 1.0, "the stacked multipliers apply to pig speed")
    game._process(21.0)
    check(game.wheel.slow_left == 0.0 and game.wheel.fast_left == 0.0
        and is_equal_approx(game.wheel.pig_speed_multiplier(), 1.0),
        "buffs expire on their own timers")

    # 结果 5 = 金猪降临：生成 5 只，砸中 +¥200，压扁后爆金币移除，到期自动消失
    key_press(KEY_R)
    game.next_card = 100000
    game.gamble_used = true
    game.challenge_count = 99
    var base_pigs: int = game.pigs.size()
    game.wheel.chances = 1
    game.wheel.open_wheel(5)
    game.wheel.finish_spin()
    game.wheel.confirm_result()
    check(game.pigs.size() == base_pigs + 5, "sector 5 spawns five extra pigs")
    var golds := 0
    for p in game.pigs:
        if bool(p.get("wheel_gold", false)):
            golds += 1
    check(golds == 5, "...and they are the golden ones")

    # 把普通猪挪出判定范围，单独砸一只金猪
    var gi := -1
    for i in range(game.pigs.size()):
        if bool(game.pigs[i].get("wheel_gold", false)):
            gi = i
            break
    for p in game.pigs:
        if not bool(p.get("wheel_gold", false)):
            p.position = Vector2(60, 760)
    game.pigs[gi].velocity = Vector2.ZERO
    var s1: int = game.score
    click(game.pigs[gi].position)
    check(game.score == s1 + 200, "smashing a wheel gold pig pays a flat ¥200")
    check(game.pigs[gi].hp == 0 and float(game.pigs[gi].gold_squash) > 0.0,
        "...and starts the squash animation before bursting")
    game._process(0.5)
    golds = 0
    for p in game.pigs:
        if bool(p.get("wheel_gold", false)):
            golds += 1
    check(golds == 4 and game.pigs.size() == base_pigs + 4,
        "the smashed gold pig bursts into coins and leaves the table")
    game._process(game.wheel.GOLD_PIG_LIFE + 1.0)
    golds = 0
    for p in game.pigs:
        if bool(p.get("wheel_gold", false)):
            golds += 1
    check(golds == 0 and game.pigs.size() == base_pigs,
        "unsmashed gold pigs vanish on their own and the table is back to normal")

    # ================= 卡片2.0：卡池 / 获得 / 修正 / 连锁结算 =================
    key_press(KEY_R)
    game.next_card = 100000
    game.gamble_used = true
    game.challenge_count = 99
    for b in game.bills:
        b["due_day"] = game.game_day + 999

    # prepare_pool：抽掉基础重锤，换上完整的一套卡片2.0
    var fake_pool: Array[Dictionary] = [
        {"id": "heavy", "name": "重锤改造", "desc": "", "icon": "", "color": ""}
    ]
    var prepared: Array[Dictionary] = game.build.prepare_pool(fake_pool)
    var prepared_ids := {}
    for card in prepared:
        prepared_ids[String(card.id)] = true
    check(prepared.size() == game.build.DEFINITIONS.size() and prepared_ids.has("heavy")
        and prepared_ids.has("lucky") and prepared_ids.has("berserker"),
        "prepare_pool swaps the plain heavy for the full card 2.0 roster")

    # 弹出的卡池里，重锤都是进化版（带 Lv.），不再是那张一次性基础卡
    var plain_heavy := false
    for card in game.make_card_offers():
        if String(card.id) == "heavy" and not String(card.name).contains("Lv."):
            plain_heavy = true
    check(not plain_heavy, "the plain heavy card is replaced by its evolved version")

    # 重锤改造 Lv.1：+1 伤害（走 acquire，不再走本地 match）
    game.build.acquire("heavy", game)
    check(int(game.hammer_damage_bonus) == 1, "the evolved heavy grants +1 damage at Lv.1")

    # 恶魔契约：收益 ×1.4，体力上限打八折
    var smax_before: float = float(game.settings.get("stamina_max", 100))
    game.build.acquire("devil", game)
    check(is_equal_approx(game.build.income_multiplier(), 1.4), "the devil contract raises income by 40%")
    check(float(game.settings.get("stamina_max", 100)) < smax_before,
        "...and cuts the stamina ceiling by 20%")

    # 酒馆赊账：立得 ¥45，挥锤冷却 ×1.15
    var s2: int = game.score
    game.build.acquire("loan", game)
    check(game.score == s2 + 45, "the tavern loan pays ¥45 up front")
    var base_cd: float = float(game.settings.swing_cooldown) * game.swing_cooldown_mul() \
        - game.hammer_cooldown_reduction
    check(is_equal_approx(game.build.cooldown(game), base_cd * 1.15),
        "...and slows the swing cooldown by 15%")

    # 狂战士训练：15 次命中升到 Lv.2，冷却再 ×0.9
    game.build.acquire("berserker", game)
    for i in range(15):
        game.build.progress("berserker", game)
    check(game.build.level("berserker") == 2, "berserker grows to Lv.2 after 15 landed hits")
    check(is_equal_approx(game.build.cooldown(game), base_cd * 1.15 * 0.9),
        "...and Lv.2 berserker speeds up the swing by 10%")

    # 稳手学徒：两组五连击升到 Lv.2，挥锤体力 -0.25
    var cost_before: float = game.build.cost(game)
    game.build.acquire("steadiness", game)
    game.build.progress("steadiness", game)
    game.build.progress("steadiness", game)
    check(game.build.level("steadiness") == 2, "steadiness reaches Lv.2 after two five-combos")
    check(is_equal_approx(game.build.cost(game), cost_before - 0.25),
        "...and each swing costs 0.25 less stamina")

    # 破罐保险：每三次空挥返还 2 体力
    game.build.acquire("insurance", game)
    game.stamina = 10.0
    for i in range(3):
        game.build.register_miss(game)
    check(is_equal_approx(game.stamina, 12.0), "the insurance refunds 2 stamina every third miss")

    # 收据收藏家：第一次还账升 Lv.2，返现 ¥2
    game.build.acquire("collector", game)
    var s3: int = game.score
    game.build.record_payment(game)
    check(game.score == s3 + 2, "the receipt collector rebates ¥2 per payment")

    # 幸运马蹄铁 Lv.3：暴击额外 +¥3
    game.build.acquire("lucky", game)
    game.build.acquire("lucky", game)
    game.build.acquire("lucky", game)
    var s4: int = game.score
    game.build.critical_reward(true, game)
    check(game.score == s4 + 3, "a lucky Lv.3 crit tips an extra ¥3")

    # 已持有的代价/任务卡退出卡池；进化卡未满级仍会出现
    var prepared2: Array[Dictionary] = game.build.prepare_pool(fake_pool)
    var prepared2_ids := {}
    for card in prepared2:
        prepared2_ids[String(card.id)] = true
    check(not prepared2_ids.has("devil") and not prepared2_ids.has("loan")
        and not prepared2_ids.has("steadiness") and prepared2_ids.has("lucky"),
        "owned cost/quest cards leave the pool while unfinished evolutions stay")

    # 连锁/爆破击杀结算：settle_card_break 入账并安排重生
    var chain_pig := {
        "position": Vector2(640, 400), "type": game.pigs[0].type,
        "hp": 0, "max_hp": 1, "respawn": 0.0, "flash": 0.0, "hop": 0.0,
        "seed": 1.0, "hop_phase": 0.0, "left": true, "velocity": Vector2.ZERO
    }
    var s5: int = game.score
    game.settle_card_break(chain_pig, true)
    check(float(chain_pig.respawn) > 0.0 and game.score == s5 + 1,
        "settle_card_break pays a chain-killed pig and schedules its respawn")

    # —— 房东上门 = 躲债：只在"房租欠着 + 收入跨门槛"时触发，不再有主动接单 ——
    game.reset_game()
    game.pending_challenge = {}
    game.challenge_rest_t = 0.0
    game.bill_data["challenge_max_per_run"] = 3 # 上一段把打断额度关成了 0：这里恢复
    game.bill_data["challenge_warning_seconds"] = 0.0 # 立即开考便于断言
    game.bill_data["challenge_rest_seconds"] = 0.0
    for b in game.bills: # 账单全部推到远期：别让日历到期考核抢这次触发
        b["due_day"] = game.game_day + 999
    # 随机抽的账单里本来就可能有房租：先清干净，让"房东绑哪张房租"变成唯一解（否则断言会跟抽卡走）
    for i in range(game.bills.size() - 1, -1, -1):
        if String(game.bills[i].get("effect_id", "")) == "collection":
            game.bills.remove_at(i)
    # 造一张没还的房租（催收效果挂在房租上）
    game.bills.append({"name": "房租", "amount": 560, "no": "T999", "id": "rent",
        "effect_id": "collection", "due": "第999天", "due_day": game.game_day + 999})
    game.bills_fx.sync(game.bills)
    var rent_tag := "rent#T999"
    check(game.bills_fx.is_active("collection"), "unpaid rent puts the collection effect on the table")
    var bills_before_visit: int = game.bills.size()
    # 收入跨过第一道门槛（¥100）→ 房东上门排班（预告横幅，然后逃跑场面）
    game.earned_total = game.bills_fx.collection_next
    game.last_observed_score = game.score
    game._process(0.016)
    check(not game.pending_challenge.is_empty() and String(game.pending_challenge.get("kind", "")) == "dodge",
        "crossing the rent threshold schedules a landlord dodge")
    check(bool(game.pending_challenge.get("collection", false)), "the scheduled dodge is a landlord visit")
    game._process(0.016) # 预告 0 秒：下一帧直接开跑
    check(game.phase == "challenge" and game.card_type == "dodge" and game.collection_mode,
        "the landlord visit starts the escape run")
    var rent_idx := -1
    for i in range(game.bills.size()):
        if String(BillManagerScript.tag_of(game.bills[i])) == rent_tag:
            rent_idx = i
    check(rent_idx >= 0, "the landlord visit is bound to the unpaid rent bill")
    check(String(game.challenge_bill_tag) == rent_tag, "the run is bound to that rent, not a random bill")
    var due_before: int = int(game.bills[rent_idx]["due_day"])
    game.finish_challenge(true)
    rent_idx = -1
    for i in range(game.bills.size()):
        if String(BillManagerScript.tag_of(game.bills[i])) == rent_tag:
            rent_idx = i
    check(game.phase == "playing", "dodging the landlord returns to play")
    check(game.bills.size() == bills_before_visit, "dodging the landlord clears no bills")
    check(rent_idx >= 0 and int(game.bills[rent_idx]["due_day"]) == maxi(due_before, game.game_day) + 2,
        "winning only defers the rent: delay, not a free pass")
    check(rent_idx >= 0 and not bool(game.bills[rent_idx].get("overdue", false)),
        "a successful dodge leaves the rent unstamped")

    # 输了：房租当场逾期、掉体力
    game.challenge_rest_t = 0.0
    game.bills_fx.collection_cd = 0.0
    game.earned_total = game.bills_fx.collection_next
    game.last_observed_score = game.score
    game._process(0.016)
    check(not game.pending_challenge.is_empty(), "the next threshold brings the landlord back")
    game._process(0.016)
    check(game.phase == "challenge", "the second visit also opens a dodge run")
    game.stamina = maxf(game.stamina, 120.0) # 防止体力见底时失败分支被夹在底线、断言随状态漂移
    var stamina_before_visit: float = game.stamina
    game.finish_challenge(false)
    check(game.phase == "playing", "a lost landlord visit returns to play")
    check(game.stamina < stamina_before_visit and game.stamina >= 6.0,
        "losing to the landlord drains stamina but leaves a sliver")
    rent_idx = -1
    for i in range(game.bills.size()):
        if String(BillManagerScript.tag_of(game.bills[i])) == rent_tag:
            rent_idx = i
    check(rent_idx >= 0 and bool(game.bills[rent_idx].get("overdue", false)),
        "getting caught stamps the rent overdue on the spot")
    game.bill_data["challenge_max_per_run"] = 0 # 后续测试不需要打断：额度关掉，免得房东来抢流程
    # —— 天数里程碑小游戏：调度 + 当铺砍价 + 赌桌比大小 + 催债电话连打 ——
    game.reset_game()
    check(game.day_events.served == 0 and game.day_events.pending.is_empty() and not game.day_events.is_open(),
        "reset clears the day-event schedule")
    check(game.day_events.last_day == int(game.game_day), "reset anchors the schedule to the current day")
    game.game_day = 4 # 一帧跨过第 2、4 天两个里程碑
    game.day_events._schedule_check()
    check(game.day_events.served == 1 and game.day_events.active == "pawn" and game.day_events.pending.size() == 1,
        "crossing two days queues both milestones and opens the oldest")
    # —— 当铺砍价：指针 mul = 1.45 + 0.75·sin(2π·t/period)，t=0 时恰好 1.45x ——
    var pawn_price := int(round(180 * 1.45)) # 261
    var score_before_pawn: int = game.score
    game.day_events.pawn_t = 0.0
    game.day_events.handle_click(Vector2(640, 400))
    check(game.day_events.pawn_state == "preview" and game.day_events.pawn_locked_mul == 1.45,
        "the first pawn swing locks the current multiplier for preview")
    game.day_events.handle_click(Vector2(game.day_events.PAWN_REROLL_RECT.get_center()))
    check(game.day_events.pawn_state == "swing" and game.day_events.pawn_final,
        "rerolling starts the faster final swing")
    game.day_events.pawn_t = 0.0
    game.day_events.handle_click(Vector2(640, 400))
    check(game.day_events.pawn_state == "result" and game.score == score_before_pawn + pawn_price,
        "the final swing sells at the locked price")
    game.day_events.handle_key(KEY_SPACE)
    check(not game.day_events.is_open(), "confirming the pawn result closes the popup")
    # —— 赌桌：发牌从 forced_deck 取，庄家 17 停牌 ——
    game.score = 800
    game.day_events._open("dice")
    check(game.day_events.dice_state == "bet" and not game.day_events.dice_poor, "the dice table opens in bet phase")
    game.day_events.forced_deck.assign([10, 13, 8, 6, 6]) # 玩家 20，庄家 14→20
    game.day_events.handle_click(Vector2(game.day_events.BET_RECTS[0].get_center()))
    check(game.day_events.dice_state == "player" and game.day_events.dice_bet == 50, "betting deals the hand")
    game.day_events.handle_click(Vector2(game.day_events.STAND_RECT.get_center()))
    game.day_events._process(0.6) # 快进庄家翻牌动画（0.55s），走完才补牌结算
    check(game.day_events.dice_state == "result" and game.day_events.dice_outcome == "push",
        "equal totals push the bet back")
    check(game.score == 800, "a push costs nothing")
    game.day_events.handle_key(KEY_SPACE)
    check(not game.day_events.is_open(), "leaving the table closes the popup")
    game.day_events._open("dice")
    game.day_events.forced_deck.assign([13, 12, 9, 7, 13]) # 玩家 20，要牌一张 J → 30 爆牌
    game.day_events.handle_click(Vector2(game.day_events.BET_RECTS[1].get_center()))
    game.day_events.handle_click(Vector2(game.day_events.HIT_RECT.get_center()))
    check(game.day_events.dice_outcome == "lose" and game.score == 800 - 120,
        "busting loses the wager")
    # —— 赊账局：余额不足 ¥50 免押注，赢了只拿固定赏金 ——
    game.score = 40
    game.day_events._open("dice")
    check(game.day_events.dice_poor, "a broke player gets the credit game")
    game.day_events.forced_deck.assign([10, 9, 8, 6, 13]) # 玩家 19，庄家 14 → 补一张 13 → 27 爆（第 5 张是给庄家补牌的，别让牌堆抽空进随机）
    game.day_events.handle_click(Vector2(game.day_events.CONFIRM_RECT.get_center()))
    game.day_events.handle_click(Vector2(game.day_events.STAND_RECT.get_center()))
    game.day_events._process(0.6) # 快进庄家翻牌动画
    check(game.day_events.dice_outcome == "win" and game.score == 40 + 80,
        "the credit game pays the fixed bounty on a dealer bust")
    # —— 催债电话：记忆→复现，全对 +¥120 并推迟催收，点错立即判负只扣体力 ——
    game.score = 500
    game.day_events._open("calls")
    check(game.day_events.active == "calls" and game.day_events.calls_state == "memo",
        "the calls event opens in memo phase")
    game.day_events.forced_sequence.assign([3, 1, 0, 2])
    game.day_events._open("calls")
    for i in range(12):
        game.day_events._process(0.5) # 快进记忆阶段
    check(game.day_events.calls_state == "play", "memo phase hands over to play phase")
    var score_before_calls: int = game.score
    var collection_before: float = float(game.bills_fx.collection_next)
    var call_slots: Array = game.day_events.CALL_SLOTS
    for idx in [3, 1, 0, 2]:
        game.day_events.handle_click(Vector2(call_slots[idx]))
    check(game.day_events.calls_state == "result" and game.day_events.calls_win,
        "clicking the bell order in sequence wins")
    check(game.score == score_before_calls + 120, "hanging up every call pays the reward")
    check(game.bills_fx.collection_next > collection_before, "winning pushes back the landlord's next visit")
    game.day_events.handle_key(KEY_SPACE)
    var stamina_before_calls: float = float(game.stamina)
    game.stamina = maxf(game.stamina, 120.0)
    game.day_events._open("calls")
    game.day_events.forced_sequence.assign([1, 0, 3, 2])
    for i in range(12):
        game.day_events._process(0.5)
    var stamina_before_calls_fail: float = float(game.stamina)
    game.day_events.handle_click(Vector2(call_slots[0])) # 顺序第一位是 1，点 0 就是错
    check(game.day_events.calls_state == "result" and not game.day_events.calls_win,
        "a wrong click fails immediately")
    check(game.score == score_before_calls + 120, "failing the calls costs no money")
    check(game.stamina < stamina_before_calls_fail, "failing the calls drains stamina")
    game.day_events.handle_click(Vector2(640, 673)) # CONFIRM_RECT 中心：结果态「认了」用鼠标也要能点掉（真机踩过：只有空格能关）
    check(not game.day_events.is_open(), "the calls result button is clickable with the mouse, not just space")
    # —— 三场弹窗都不会残留到新局 ——
    game.reset_game()
    check(not game.day_events.is_open() and game.day_events.served == 0,
        "a new run clears any leftover day-event state")
    # —— 传承商店：碎片买永久饰品，下一局 reset_game 生效 ——
    game.settings["crit_base_chance"] = 0.06 # 前面测试段把暴击清零了，这里恢复默认再验证戒指
    game.settings["crit_max_chance"] = 0.30
    game.meta_shards = 20
    game.meta_shop.clear()
    check(game.legacy_next_cost("watch") == 4, "the shop prices level 1 items correctly")
    check(game.legacy_buy("watch"), "buying a legacy item spends shards")
    check(game.meta_shards == 16 and game.legacy_level("watch") == 1, "...and records the level")
    game.meta_shards = 2
    check(not game.legacy_buy("grip"), "buying without enough shards is rejected")
    check(game.legacy_level("grip") == 0 and game.meta_shards == 2, "...leaving shards and levels untouched")
    game.meta_shop["watch"] = 3
    check(game.legacy_next_cost("watch") == -1, "maxed items report no price")
    check(not game.legacy_buy("watch"), "...and cannot be bought again")
    game.meta_shop.clear()
    game.meta_shop["watch"] = 2
    game.meta_shop["grip"] = 1
    game.meta_shop["ring"] = 1
    game.meta_shop["abacus"] = 1
    game.meta_shop["flask"] = 1
    game.meta_unlocked.clear() # 隔离里程碑解锁，只测商店饰品
    game.reset_game()
    check(game.score == 40, "the pocket watch adds starting cash per level")
    check(int(game.settings.stamina_max) == int(game.base_stamina_max) + 12, "the wrist guard raises stamina cap by 12 per level")
    check(abs(game.earnings_multiplier - 1.06) < 0.001, "the abacus grants permanent earnings")
    check(abs(game.stamina_regen_bonus - 0.6) < 0.001, "the flask grants permanent regen")
    var crit_base: float = float(game.settings.get("crit_base_chance", 0.06))
    check(abs(game.crit_chance(1) - (crit_base + 0.015)) < 0.001, "the ring grants permanent crit")
    game.meta_shop.clear()
    game.reset_game()

    # —— 序幕 + 商店同开：十三轮踩坑——商店盖不住序幕时输入走商店分支、画面停在序幕，玩家像"进不了游戏" ——
    game.intro_open = true
    game.shop_open = true
    key_press(KEY_B)
    check(not game.shop_open and game.intro_open, "B closes the intro shop without leaving the intro")
    key_press(KEY_SPACE)
    check(not game.intro_open, "the intro still responds to keys once the shop is closed")
    game.intro_open = false

    print("ALL ", checks, " CHECKS PASSED")
    game.queue_free() # 音效在 Sound 这个 autoload 里，不随场景释放，不用等它放完
    game = null
    await process_frame
    await process_frame
    quit()
