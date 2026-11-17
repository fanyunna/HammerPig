extends SceneTree
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

    # first card -> reward（注意：卡片不再当场弹，见 §3.6 的半秒缓冲）
    game.gamble_used = true # 隔离：这段专门测卡片，别让桌边那枚硬币插进来
    for i in range(1, 6):
        break_pig(i)
    check(game.score == 60 and game.phase == "playing", "60 reached but the card waits out the burst")
    game._process(0.5)
    check(game.phase == "card", "the card pops once the burst has played out")
    game.card_type = "reward"
    game.card_offers.clear() # 走旧奖励兼容分支，避免随机升级影响金额断言
    game.apply_card()
    check(game.score == 60 + int(game.settings.reward_card_amount) and game.phase == "playing", "reward card pays out and resumes")
    game._process(0.9)

    # second card -> collect bill
    for i in range(3):
        break_pig(i)
    check(game.score == 125 and game.phase == "playing", "the second card threshold is crossed")
    game._process(0.5)
    check(game.phase == "card", "the second card pops after the same beat")
    game.card_type = "collect"
    game.apply_card()
    check(game.phase == "challenge" and game.bill_timer > 0.0, "collect bill enters challenge with timer")
    var challenge_start_score: int = game.score
    game.coins.clear()
    game.coins.append({"position": Vector2(400, 400), "velocity": Vector2.ZERO, "value": int(game.settings.coin_value), "fake": false, "life": 5.0})
    game.click_coin(Vector2(400, 400))
    check(game.collected == int(game.settings.coin_value), "clicking a coin collects its value")
    game.coins.append({"position": Vector2(500, 400), "velocity": Vector2.ZERO, "value": -int(game.settings.coin_value), "fake": true, "life": 5.0})
    game.click_coin(Vector2(500, 400))
    check(game.collected == 0, "fake coin reduces collected")
    var bills_before_card: int = game.unpaid_bills
    game.collected = game.bill_amount
    game._process(0.0)
    check(game.phase == "playing" and game.score == challenge_start_score + int(game.settings.bill_reward), "clearing bill keeps money and rewards")
    check(game.unpaid_bills == bills_before_card - 1, "clearing a bill removes one from the unpaid stack")

    # fail collect bill -> deduct
    game.card_type = "collect"
    game.phase = "card"
    game.apply_card()
    game._process(game.bill_time + 0.1)
    check(game.score == challenge_start_score + int(game.settings.bill_reward) - int(game.settings.bill_amount) and game.phase == "playing", "failing bill deducts amount")

    # bankrupt
    game.score = int(game.settings.bill_amount)
    game.card_type = "collect"
    game.phase = "card"
    game.apply_card()
    game._process(game.bill_time + 0.1)
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

    # dodge card
    game.card_type = "dodge"
    game.phase = "card"
    game.apply_card()
    check(game.phase == "challenge" and game.dodge_lives == int(game.settings.dodge_lives), "dodge card enters challenge with lives")
    game.hammer_position = Vector2(400, 400)
    game.invincible_timer = 0.0
    game.dodgers.clear()
    game.dodgers.append({"position": Vector2(400, 400), "life": 5.0, "seed": 0.0})
    game.update_dodge(0.0)
    check(game.dodge_lives == int(game.settings.dodge_lives) - 1, "dodger touching player costs a life")
    game.bill_timer = 0.0
    game.update_dodge(0.0)
    check(game.phase == "playing" and game.score == int(game.settings.bill_reward), "surviving dodge clears bill and rewards")

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
    check(game.stamina == stamina_before - float(game.settings.stamina_cost), "a hit costs the base swing stamina")
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
    check(game.cursor_hidden, "...and while you are dodging (you have to see where you are)")
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
    game._process(0.05)
    check(game.pending_strike.is_empty(), "a buffered click that waits too long is dropped")
    game.settings["strike_buffer"] = 0.0

    # ================= A：账单到期考核 =================
    # 到期不再默默盖章，而是先给一次「凑钱 / 躲催债」的机会。
    key_press(KEY_R)
    game.bill_data["challenge_max_per_run"] = 3
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
    game.pending_challenge = {}
    game.earned_total += income_day
    game._process(0.016)
    check(game.phase == "challenge", "the next due bill opens another challenge")
    var overdue_before := 0
    for b in game.bills:
        if bool(b.get("overdue", false)):
            overdue_before += 1
    var score_before_loss: int = game.score
    game.finish_challenge(false)
    var overdue_after := 0
    for b in game.bills:
        if bool(b.get("overdue", false)):
            overdue_after += 1
    check(overdue_after == overdue_before + 1, "losing stamps the due bill as overdue right away")
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

    print("ALL ", checks, " CHECKS PASSED")
    game.queue_free() # 音效在 Sound 这个 autoload 里，不随场景释放，不用等它放完
    game = null
    await process_frame
    await process_frame
    quit()
