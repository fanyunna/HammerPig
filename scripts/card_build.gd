extends RefCounted
## Run-only card state. Damage waves are iterative and visit each pig at most once.
const DEFINITIONS = {
	"heavy": ["重锤改造", "进化", ["伤害 +1", "累计伤害 +2 / 范围 +10%", "每三次命中产生爆破", "爆破伤害 +1 / 击碎额外 ¥5"]],
	"lucky": ["幸运马蹄铁", "进化", ["暴击率 +5%", "累计暴击率 +10%", "暴击额外 ¥3", "连续三次暴击额外 ¥12"]],
	"chain": ["连锁破碎", "进化", ["击碎伤害附近一个目标", "击碎伤害附近两个目标", "允许传播 / 最多八个目标", "连锁击碎额外 ¥5"]],
	"overdrive": ["过载引擎", "代价", ["冷却 -20% / 每锤体力 +1"]],
	"devil": ["恶魔契约", "代价", ["收益 +40% / 体力上限 -20%"]],
	"tax": ["贪婪税", "代价", ["收益 +35% / 每30秒新增账单"]],
	"berserker": ["狂战士训练", "任务", ["命中15/30/50次自动成长", "攻速 +10%", "每10次命中狂暴4秒", "狂暴体力消耗 -30%"]],
	"hunter": ["猎猪执照", "任务", ["击碎10/25/50/100只成长", "收益 +10%", "收益 +20%", "收益 +30% / 百只奖励 ¥40"]],
	"broker": ["债务操盘手", "任务", ["还清1/2/3/5张成长", "每次还款额外恢复3体力", "每次还款额外恢复6体力", "每次还款额外恢复9体力"]]
}
const GOALS = {"berserker": [15, 30, 50], "hunter": [10, 25, 50, 100], "broker": [1, 2, 3, 5]}
var panel_open := false
var levels: Dictionary = {}
var counts: Dictionary = {}
var effective_hits := 0
var crit_streak := 0
var tax_timer := 0.0
var rage := 0.0
var lucky_lock := 0.0
var effects: Array[Dictionary] = []
var final_paid: Dictionary = {}


func reset() -> void:
	panel_open = false
	levels.clear()
	counts.clear()
	final_paid.clear()
	effective_hits = 0
	crit_streak = 0
	tax_timer = 0.0
	rage = 0.0
	lucky_lock = 0.0
	effects.clear()


func level(id: String) -> int:
	return int(levels.get(id, 0))


func prepare_pool(original: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in original:
		if String(card.id) != "heavy":
			result.append(card)
	for id in DEFINITIONS:
		var d: Array = DEFINITIONS[id]
		var owned := level(id)
		if (d[1] == "进化" and owned >= 4) or (d[1] != "进化" and owned > 0):
			continue
		var target := owned + 1
		var description := String(d[2][target - 1])
		if d[1] == "任务":
			description = String(d[2][0])
		if d[1] == "进化" and target < 4:
			description += "\n下级：" + String(d[2][target])
		result.append(
			{
				"id": id,
				"name": String(d[0]) + " Lv." + str(target),
				"desc": String(d[1]) + "\n" + description,
				"icon": "!" if d[1] == "代价" else "↑",
				"color": "#e8836b" if d[1] == "代价" else "#75c7b2"
			}
		)
	return result


func acquire(id: String, game) -> void:
	if not DEFINITIONS.has(id):
		return
	var d: Array = DEFINITIONS[id]
	var old := level(id)
	if (d[1] != "进化" and old > 0) or old >= 4:
		return
	levels[id] = old + 1
	if id == "heavy":
		if old < 2:
			game.hammer_damage_bonus += 1
		if old == 1:
			game.hammer_reach_multiplier += 0.1
		if old == 2:
			effective_hits = 0
	if id == "devil":
		game.settings["stamina_max"] = maxf(20.0, float(game.settings.stamina_max) * 0.8)
		game.stamina = minf(game.stamina, float(game.settings.stamina_max))
	if GOALS.has(id):
		counts[id] = 0


func cost(game) -> float:
	var value := maxf(
		1.0,
		(
			float(game.settings.get("stamina_cost", 4))
			- game.stamina_cost_reduction
			+ (1.0 if level("overdrive") > 0 else 0.0)
		)
	)
	if rage > 0 and level("berserker") >= 4:
		value *= 0.7
		if level("overdrive") > 0 and game.stamina_cost_reduction > 0:
			value *= 0.5
	return maxf(0.5, value)


func cooldown(game) -> float:
	var value: float = (
		float(game.settings.swing_cooldown) * game.swing_cooldown_mul()
		- game.hammer_cooldown_reduction
	)
	if level("overdrive") > 0:
		value *= 0.8
	if level("berserker") >= 2:
		value *= 0.9
	return maxf(0.08, value)


func damage_bonus() -> int:
	return 1 if rage > 0 else 0


func income_multiplier() -> float:
	return (
		(1.4 if level("devil") > 0 else 1.0)
		* (1.35 if level("tax") > 0 else 1.0)
		* (1.0 + maxf(0.0, level("hunter") - 1) * 0.1)
	)


func secondary_reward(game) -> int:
	var reward := 5 if level("chain") >= 4 or level("heavy") >= 4 else 0
	if level("heavy") > 0 and level("chain") > 0 and game.hammer_reach_multiplier > 1.1:
		reward += 3
	return reward


func roll_critical() -> bool:
	var chance := 0.1 if level("lucky") >= 2 else (0.05 if level("lucky") == 1 else 0.0)
	return randf() < chance


func critical_reward(critical: bool, game) -> void:
	crit_streak = crit_streak + 1 if critical else 0
	if critical and level("lucky") >= 3:
		game.score += 3
	if crit_streak >= 3 and level("lucky") >= 4 and lucky_lock <= 0:
		game.score += 12
		lucky_lock = 3.0
		crit_streak = 0
		notify(game, "幸运连锁 +¥12")


func progress(id: String, game) -> void:
	if level(id) == 0:
		return
	counts[id] = int(counts.get(id, 0)) + 1
	var goals: Array = GOALS[id]
	while level(id) < 4 and int(counts[id]) >= int(goals[level(id) - 1]):
		levels[id] = level(id) + 1
		notify(game, String(DEFINITIONS[id][0]) + " Lv." + str(level(id)))
	if id == "berserker" and level(id) >= 3 and int(counts[id]) % 10 == 0:
		rage = 4.0
		notify(game, "狂暴！")
	if id == "broker":
		game.stamina = minf(float(game.settings.stamina_max), game.stamina + (level(id) - 1) * 3.0)
		if level("tax") > 0 and game.earnings_multiplier > 1.0:
			game.score += 5
			notify(game, "资本家协同 +¥5")
	if int(counts[id]) >= int(goals.back()) and not final_paid.has(id):
		final_paid[id] = true
		if id == "hunter" or id == "broker":
			game.score += 40
			notify(game, "成长任务完成 +¥40")


func tick(delta: float, game) -> void:
	rage = maxf(0.0, rage - delta)
	lucky_lock = maxf(0.0, lucky_lock - delta)
	for e in effects:
		e.life -= delta
	effects = effects.filter(func(e): return e.life > 0.0)
	if level("tax") > 0:
		tax_timer += delta
		while tax_timer >= 30.0:
			tax_timer -= 30.0
			game.bills.append(
				{
					"name": "贪婪税",
					"amount": 20,
					"due": game.format_game_date(game.game_day + 3),
					"due_day": game.game_day + 3
				}
			)
			game.sort_bills()
			notify(game, "新增账单：贪婪税 ¥20")


func notify(game, message: String) -> void:
	game.popups.append({"position": Vector2(640, 180), "life": 1.5, "text": message})
	game.get_node("/root/Sound").play("card")


func after_hit(origin: Dictionary, _point: Vector2, game) -> void:
	effective_hits += 1
	var blast := level("heavy") >= 3 and effective_hits % 3 == 0
	if not blast and (origin.hp > 0 or level("chain") == 0):
		return
	var frontier: Array = [origin]
	var visited: Array = [origin]
	var budget := 8
	while not frontier.is_empty() and budget > 0:
		var source: Dictionary = frontier.pop_front()
		var candidates: Array = []
		for pig in game.pigs:
			if (
				pig.hp > 0
				and not visited.has(pig)
				and Vector2(pig.position).distance_to(source.position) <= 230.0
			):
				candidates.append(pig)
		candidates.sort_custom(
			func(a, b):
				return (
					Vector2(a.position).distance_squared_to(source.position)
					< Vector2(b.position).distance_squared_to(source.position)
				)
		)
		var limit := 8 if blast else (2 if level("chain") >= 2 else 1)
		for target in candidates.slice(0, mini(limit, budget)):
			visited.append(target)
			budget -= 1
			target.hp -= 2 if blast and level("heavy") >= 4 else 1
			target.flash = 0.14
			effects.append({"from": source.position, "to": target.position, "life": 0.3})
			if target.hp <= 0:
				game.settle_card_break(target, true)
				if level("chain") >= 3:
					frontier.append(target)
		blast = false


func draw_effects(game) -> void:
	for e in effects:
		game.draw_line(e.from, e.to, Color("#ffd166", minf(1.0, float(e.life) / 0.3)), 3.0)


func draw_status(game) -> void:
	game.text_at("C 查看构筑 / 成长", Vector2(1000, 225), 14, Color("#ffd166"))
	if not panel_open:
		return
	game.draw_rect(Rect2(0, 0, 1280, 800), Color(0.02, 0.02, 0.02, 0.90))
	game.text_at("本局构筑 · 已暂停 · C 返回", Vector2(180, 110), 26)
	var row := 0
	for id in levels:
		var d: Array = DEFINITIONS[id]
		var label := String(d[0]) + " Lv." + str(level(id))
		if GOALS.has(id):
			var goals: Array = GOALS[id]
			label += (
				"   "
				+ str(counts.get(id, 0))
				+ "/"
				+ str(goals[mini(level(id) - 1, goals.size() - 1)])
			)
		game.text_at(label, Vector2(180, 160 + row * 62), 19, Color("#ffd166"))
		game.text_at(String(d[2][level(id) - 1]), Vector2(180, 183 + row * 62), 15)
		row += 1
	if row == 0:
		game.text_at("尚未获得成长卡", Vector2(180, 170), 20)
