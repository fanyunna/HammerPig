extends SceneTree
var game
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1
	print("PASS: ", message)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.intro_open = false
	game.reset_game()
	var b = game.build
	var initial_max: float = game.settings.stamina_max
	var normal_cost: float = b.cost(game)
	var normal_cooldown: float = b.cooldown(game)
	b.acquire("overdrive", game)
	check(is_equal_approx(b.cost(game), normal_cost + 1.0), "overdrive applies stamina cost")
	check(b.cooldown(game) <= normal_cooldown, "overdrive reduces cooldown within floor")
	b.acquire("overdrive", game)
	check(b.level("overdrive") == 1, "risk cards cannot be stacked accidentally")
	b.acquire("devil", game)
	check(
		is_equal_approx(float(game.settings.stamina_max), maxf(20, initial_max * 0.8)),
		"contract reduces maximum"
	)
	check(game.stamina <= game.settings.stamina_max, "contract clamps current stamina")
	check(is_equal_approx(b.income_multiplier(), 1.4), "contract raises income")
	b.acquire("tax", game)
	var debt_count: int = game.bills.size()
	b.tick(29.9, game)
	check(game.bills.size() == debt_count, "tax does not fire early")
	b.tick(0.2, game)
	check(game.bills.size() == debt_count + 1, "tax uses existing bill list")
	b.tick(60, game)
	check(game.bills.size() == debt_count + 3, "tax accounts for elapsed periods")
	game.reset_game()
	check(b.levels.is_empty() and b.counts.is_empty(), "restart clears ownership and progress")
	check(
		is_equal_approx(float(game.settings.stamina_max), initial_max),
		"restart removes maximum penalty"
	)
	check(is_equal_approx(b.cost(game), normal_cost), "restart removes extra cost")
	for id in ["heavy", "lucky", "chain"]:
		for expected in range(1, 5):
			b.acquire(id, game)
			check(b.level(id) == expected, id + " evolves to " + str(expected))
		b.acquire(id, game)
		check(b.level(id) == 4, id + " cannot exceed cap")
	check(game.hammer_damage_bonus == 2, "heavy damage applies once per first two ranks")
	check(is_equal_approx(game.hammer_reach_multiplier, 1.1), "heavy range applies once")
	for iteration in range(50):
		var offers: Array = game.make_card_offers()
		check(offers.size() == 3, "three offers remain available")
		var ids: Array = []
		for offer in offers:
			check(not ids.has(offer.id), "offers do not duplicate")
			check(not offer.id in ["heavy", "lucky", "chain"], "max rank cards leave pool")
			ids.append(offer.id)
	game.reset_game()
	b.acquire("berserker", game)
	var before: int = b.counts.berserker
	game.cooldown = 0
	game.strike(Vector2(-1000, -1000))
	check(b.counts.berserker == before, "empty swing grants no progress")
	for n in range(15):
		b.progress("berserker", game)
	check(b.level("berserker") == 2, "fifteen hits advances training")
	for n in range(35):
		b.progress("berserker", game)
	check(b.level("berserker") == 4 and b.rage > 0, "fifty cumulative hits unlock final rage")
	b.acquire("hunter", game)
	var current: int = game.broken
	var target: Dictionary = game.pigs[0]
	target.hp = 0
	target.respawn = 0.0
	game.settle_card_break(target, false)
	check(
		game.broken == current + 1 and b.counts.hunter == 1, "real break records one hunter event"
	)
	game.settle_card_break(target, false)
	check(game.broken == current + 1 and b.counts.hunter == 1, "duplicate settlement is ignored")
	b.acquire("broker", game)
	game.phase = "playing"
	game.bills.clear()
	game.bills.append({"name": "test", "amount": 10, "due_day": 100, "due": "test"})
	game.score = 0
	game.pay_bill(0)
	check(b.counts.broker == 0, "failed payment grants no progress")
	game.score = 100
	game.pay_bill(0)
	check(b.counts.broker == 1 and b.level("broker") == 2, "successful payment advances broker")
	game.reset_game()
	b.acquire("chain", game)
	b.acquire("chain", game)
	b.acquire("chain", game)
	var origin: Dictionary = game.pigs[0]
	origin.hp = 0
	origin.position = Vector2(400, 400)
	for index in range(1, game.pigs.size()):
		game.pigs[index].hp = 1
		game.pigs[index].respawn = 0.0
		game.pigs[index].position = Vector2(400 + index * 20, 400)
	current = game.broken
	b.after_hit(origin, origin.position, game)
	check(
		game.broken - current == mini(8, game.pigs.size() - 1),
		"chain visits bounded unique targets"
	)
	check(b.effects.size() <= 8, "chain visual events are bounded")
	game.reset_game()
	check(
		b.effects.is_empty() and b.rage == 0 and b.tax_timer == 0,
		"restart clears effects and timers"
	)
	b.acquire("lucky", game)
	b.acquire("lucky", game)
	b.acquire("lucky", game)
	b.acquire("lucky", game)
	game.score = 0
	for n in range(3):
		b.critical_reward(true, game)
	check(game.score == 21, "critical sequence pays base bonuses and one chain")
	for n in range(3):
		b.critical_reward(true, game)
	check(game.score == 30, "lucky chain respects cooldown")

	game.reset_game()
	game.settings["pig_types"] = []
	game.reset_game()
	game.phase = "card"
	game.card_type = "reward"
	game.card_offers.clear()
	for id in ["heavy", "cash", "double"]:
		game.card_offers.append({"id": id, "name": id})
	game.apply_card(0)
	check(
		game.phase == "playing" and b.level("heavy") == 1,
		"real card selection resumes and acquires rank"
	)
	b.acquire("berserker", game)
	game.cooldown = 0.0
	game.strike(game.pigs[0].position)
	check(b.counts.berserker == 1, "real hit contributes exactly one mastery event")
	b.acquire("hunter", game)
	b.acquire("broker", game)
	for iteration in range(30):
		for offer in game.make_card_offers():
			check(not offer.id in ["berserker", "hunter", "broker"], "owned quest is excluded")
	game.reset_game()
	for rank in range(3):
		b.acquire("heavy", game)
	var first: Dictionary = game.pigs[0]
	var near: Dictionary = game.pigs[1]
	first.position = Vector2(400, 400)
	first.hp = 0
	near.position = Vector2(450, 400)
	near.hp = 10
	near.respawn = 0.0
	for index in range(2, game.pigs.size()):
		game.pigs[index].position = Vector2(1000, 1000)
	b.effective_hits = 2
	b.after_hit(first, first.position, game)
	check(near.hp == 9, "third effective hit explodes for one damage")
	check(b.effects.size() == 1, "blast draws a bounded visual link")
	b.acquire("heavy", game)
	b.effective_hits = 5
	b.after_hit(first, first.position, game)
	check(near.hp == 7, "fourth heavy rank increases explosion damage")
	b.acquire("chain", game)
	game.hammer_reach_multiplier = 1.22
	check(b.secondary_reward(game) == 8, "explosion synergy grants bounded extra reward")
	game.hammer_reach_multiplier = 1.1
	check(b.secondary_reward(game) == 5, "missing width removes synergy")
	b.acquire("overdrive", game)
	b.acquire("berserker", game)
	b.levels.berserker = 4
	b.rage = 4.0
	var rage_cost: float = b.cost(game)
	game.stamina_cost_reduction = 0.5
	check(b.cost(game) < rage_cost * 0.6, "light handle unlocks rage cost synergy")
	game.reset_game()
	check(is_equal_approx(b.income_multiplier(), 1.0), "restart removes all income multipliers")

	game.queue_free()
	print("ALL ", checks, " CARD CHECKS PASSED")
	quit(0)
