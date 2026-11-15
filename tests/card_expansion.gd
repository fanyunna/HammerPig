extends SceneTree

var game
var checks := 0
var failed := false


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAIL: " + message)


func swing_at(point: Vector2) -> void:
	game.cooldown = 0.0
	game.strike(point)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.reset_game()
	game.settings["round_target"] = 100000
	var build = game.build
	var score_before: int = game.score
	var base_cooldown: float = build.cooldown(game)
	game.phase = "card"
	game.card_type = "reward"
	game.card_offers.assign([{"id": "loan", "name": "酒馆赊账"}, {"id": "light"}, {"id": "reach"}])
	game.apply_card(0)
	check(game.score == score_before + 45, "loan pays on selection")
	check(is_equal_approx(build.cooldown(game), base_cooldown * 1.15), "loan increases cooldown")
	build.acquire("loan", game)
	check(game.score == score_before + 45, "loan cannot pay twice")

	game.reset_game()
	build.acquire("insurance", game)
	build.acquire("focus", game)
	for i in range(3):
		swing_at(Vector2(-1000, -1000))
	check(is_equal_approx(build.income_multiplier(), 0.9), "insurance reduces pig income")
	var miss_cost: float = build.cost(game) + float(game.settings.get("stamina_miss_extra", 0.0))
	var expected_stamina := float(game.settings.stamina_max) - 3.0 * miss_cost + 2.0
	check(is_equal_approx(game.stamina, expected_stamina), "third miss refunds stamina after base and miss costs")
	var pig: Dictionary = game.pigs[0]
	pig.hp = 8
	swing_at(pig.position)
	check(pig.hp == 6 and not build.focus_armed, "next real hit consumes one focus charge")
	swing_at(pig.position)
	check(pig.hp == 5, "subsequent hit has ordinary damage")
	for i in range(4):
		build.acquire("focus", game)
	check(build.level("focus") == 4, "focus stops at four levels")
	build.register_miss(game)
	check(build.consume_focus(game) == 3, "max focus grants three extra damage")

	game.reset_game()
	build.acquire("spurs", game)
	game.combo_count = 3
	game.combo_timer = 0.0
	check(is_equal_approx(build.cooldown(game), base_cooldown), "expired combo grants no spurs effect")
	game.combo_timer = 1.0
	check(is_equal_approx(build.cooldown(game), base_cooldown * 0.9), "active three-hit combo activates spurs")

	build.acquire("collector", game)
	game.bills.clear()
	for i in range(6):
		game.bills.append({"id": "test_" + str(i), "name": "test bill", "amount": 10})
	game.score = 0
	game.pay_bill(0)
	check(build.counts.collector == 0, "blocked payment does not count")
	game.score = 100
	game.pay_bill(0)
	check(build.level("collector") == 2 and game.score == 92, "payment upgrades collector and rebates two")
	for i in range(5):
		game.pay_bill(0)
	check(build.level("collector") == 4 and build.counts.collector == 5, "collector progress stops at five")

	build.acquire("steadiness", game)
	var base_cost: float = build.cost(game)
	for i in range(6):
		game.combo_count = 0
		game.combo_timer = 0
		pig = game.pigs[0]
		pig.hp = 99
		game.stamina = 100.0
		for j in range(6):
			swing_at(pig.position)
	check(build.counts.steadiness == 6 and build.level("steadiness") == 4, "each combo streak counts once")
	check(is_equal_approx(build.cost(game), base_cost - 0.75), "mastery reduces swing cost")
	for i in range(4):
		build.acquire("focus", game)
	var empty: Array[Dictionary] = []
	for card in build.prepare_pool(empty):
		check(not card.id in ["focus", "collector", "steadiness"], "owned task and max-rank cards excluded")
	game.reset_game()
	check(build.levels.is_empty() and not build.focus_armed and build.insurance_misses == 0, "restart clears weekly card state")
	game.free()
	if not failed:
		print("ALL ", checks, " EXPANSION CHECKS PASSED")
	quit(1 if failed else 0)
