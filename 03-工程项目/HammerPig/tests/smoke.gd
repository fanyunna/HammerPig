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
    game.stamina = 100.0 # 模拟充足体力，避免影响旧流程
    game.strike(point)

func break_pig(index: int) -> void:
    var point: Vector2 = game.pigs[index].position
    click(point)
    click(point)

func exhaust_round() -> void:
    game.stamina = 5.0
    game._process(0.1)

func normalize_pigs() -> void:
    for pig in game.pigs:
        pig.kind = "normal"
        pig.hp = 2

func run() -> void:
    game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    game.settings["crit_chance"] = 0.0 # 先关闭暴击，保证断言确定性
    await process_frame
    check(game.pigs.size() == 8 and game.coins == 0, "initial scene and eight pigs")
    check(game.bg_texture != null and game.pig_textures.size() == 4 and game.hammer_texture != null, "western art assets loaded")
    var streams_ok := true
    for p in game.sfx.values():
        streams_ok = streams_ok and p.stream != null
    check(streams_ok, "all seven sound effects loaded")
    normalize_pigs()
    check(game.stamina == 100.0, "stamina starts at 100")
    var pos_before: Vector2 = game.pigs[1].position
    game._process(0.5)
    check(game.pigs[1].position != pos_before, "pigs move over time")
    game.cooldown = 0.0
    game.strike(Vector2(0, 0))
    check(game.stamina == 90.0 and game.hits == 0 and game.coins == 0, "swing costs 10 stamina even on miss")
    game.stamina = 5.0
    game.cooldown = 0.0
    game.strike(game.pigs[0].position)
    check(game.pigs[0].hp == 2 and game.stamina == 5.0, "insufficient stamina blocks swing")
    game._process(0.1)
    check(game.phase == "finished" and game.rounds_played == 1, "round ends when stamina is exhausted")
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = KEY_R
    game._unhandled_input(key)
    check(game.phase == "playing" and game.stamina == 100.0 and game.coins == 0 and game.rounds_played == 0, "R fully resets everything")
    normalize_pigs()
    # 范围攻击：两只猪站在一起会被同时敲中
    game.pigs[0].position = Vector2(600, 450)
    game.pigs[1].position = Vector2(640, 450)
    click(Vector2(600, 450))
    check(game.pigs[0].hp == 1 and game.pigs[1].hp == 1 and game.pigs[0].hop > 0.0, "hammer hits all pigs in range")
    game.strike(Vector2(600, 450))
    check(game.pigs[0].hp == 1 and game.pigs[1].hp == 1, "cooldown blocks rapid duplicate hit")
    click(Vector2(600, 450))
    check(game.coins == 10 and game.broken == 2, "two pigs in range break together")
    click(Vector2(600, 450))
    check(game.coins == 10, "dead pigs give no coins")
    game.settings["crit_chance"] = 1.0
    break_pig(2)
    check(game.coins == 20, "crit doubles coins to 10")
    game.settings["crit_chance"] = 0.0
    # 每 5 轮弹卡：前 4 轮正常结束
    for r in range(1, 5):
        exhaust_round()
        check(game.phase == "finished" and game.rounds_played == r, "round " + str(r) + " ends without card")
        game.new_round()
    exhaust_round()
    check(game.phase == "card" and game.rounds_played == 5, "card pops after every five rounds")
    click(game.pigs[3].position)
    check(game.coins == 20, "modal card blocks gameplay")
    game.apply_card()
    check(game.phase == "playing" and game.stamina == 100.0 and game.coins == 20, "closing card starts next round with savings kept")
    exhaust_round()
    check(game.phase == "finished" and game.rounds_played == 6, "sixth round ends normally")
    click(game.pigs[0].position)
    check(game.coins == 20, "finished round blocks scoring")
    game.new_round()
    check(game.coins == 20 and game.round_coins == 0 and game.broken == 0, "next round keeps coins and resets round stats")
    game._unhandled_input(key)
    check(game.coins == 0 and game.rounds_played == 0, "R clears savings and round counter")
    print("ALL ", checks, " CHECKS PASSED")
    for p in game.sfx.values():
        p.stop()
    await create_timer(0.25).timeout
    game.queue_free()
    game = null
    await process_frame
    await process_frame
    quit()