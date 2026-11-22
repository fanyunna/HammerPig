extends SceneTree
var game
var checks := 0
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("FAIL: " + message)

func choose(id: String) -> void:
	game.phase = "card"
	game.card_type = "reward"
	game.card_offers.assign([{"id": id, "name": id}, {"id": "cash"}, {"id": "double"}])
	game.apply_card(0)

func break_one(value: int, secondary := false) -> int:
	game.phase = "playing"
	var pig: Dictionary = game.pigs[0]
	pig.type = {"id": "piggy", "value": value}
	pig.hp = 0
	pig.respawn = 0.0
	game.combo_count = 0
	var before: int = game.score
	game.settle_card_break(pig, secondary)
	return game.score - before

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.reset_game()
	game.settings["round_target"] = 100000
	var b = game.build
	var base_cooldown: float = b.cooldown(game)
	var base_cost: float = b.cost(game)
	choose("long_handle")
	check(game.phase == "playing", "selection resumes play")
	check(is_equal_approx(game.hammer_reach_multiplier, 1.2), "long handle adds range")
	check(is_equal_approx(b.cooldown(game), base_cooldown * 1.1), "long handle slows swing")
	b.acquire("long_handle", game)
	check(is_equal_approx(game.hammer_reach_multiplier, 1.2), "long handle cannot stack")
	choose("frugal")
	check(is_equal_approx(b.cost(game), base_cost - 0.5), "frugal reduces stamina cost")
	check(is_equal_approx(b.income_multiplier(), 0.9), "frugal reduces positive income")
	check(break_one(10) == 9, "income penalty reaches real settlement")
	check(break_one(-2) == -2, "negative pig loss remains unchanged")
	game.reset_game()
	choose("scrap")
	choose("artisan")
	check(break_one(10) == 10, "first direct break grants normal payout")
	check(break_one(10) == 10, "second direct break grants normal payout")
	check(break_one(10) == 12, "third direct break grants level one scrap")
	check(b.counts.artisan == 3, "direct positive breaks advance mastery")
	break_one(10, true)
	check(b.counts.artisan == 3 and b.scrap_breaks == 0, "secondary break cannot farm new cards")
	break_one(-2)
	check(b.counts.artisan == 3 and b.scrap_breaks == 0, "debt pig cannot farm new cards")
	break_one(10)
	check(b.level("artisan") == 2, "four direct breaks unlock rank two")
	check(is_equal_approx(b.cooldown(game), base_cooldown * 0.97), "mastery grants cooldown reduction")
	for rank in range(2,5):
		choose("scrap")
		check(b.level("scrap") == rank, "repeated selection increases scrap rank")
	b.acquire("scrap", game)
	check(b.level("scrap") == 4, "scrap caps at rank four")
	b.scrap_breaks = 2
	check(break_one(10) == 18, "max rank pays eight extra coins")
	for i in range(10):
		break_one(10)
	check(b.level("artisan") == 4 and b.counts.artisan == 12, "mastery caps progress and rank")
	var pool: Array[Dictionary] = []
	for card in b.prepare_pool(pool):
		check(not card.id in ["scrap", "artisan"], "capped and owned cards are excluded")
	game.hammer_cooldown_reduction = 999.0
	check(b.cooldown(game) >= 0.08, "cooldown has a safety floor")
	game.stamina_cost_reduction = 999.0
	check(b.cost(game) >= 0.5, "stamina has a safety floor")
	game.reset_game()
	check(b.levels.is_empty() and b.scrap_breaks == 0, "restart clears weekly state")
	check(is_equal_approx(game.hammer_reach_multiplier, 1.0), "restart clears range")
	check(is_equal_approx(b.cost(game), base_cost), "restart clears cost effects")
	check(is_equal_approx(b.income_multiplier(), 1.0), "restart clears income effects")
	game.free()
	await process_frame
	if not failed:
		print("ALL ", checks, " WEEK3 CHECKS PASSED")
	quit(1 if failed else 0)
