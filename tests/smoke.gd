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
    check(game.stamina == stamina_before - float(game.settings.stamina_cost), "each swing costs stamina")
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

    print("ALL ", checks, " CHECKS PASSED")
    game.queue_free() # 音效在 Sound 这个 autoload 里，不随场景释放，不用等它放完
    game = null
    await process_frame
    await process_frame
    quit()
