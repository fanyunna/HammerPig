extends SceneTree
## 商店/背包/锤子/技能系统的回归测试（headless，固定目录木质货架版）
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


func _prep_pig(index: int, pos: Vector2, hp: float) -> Dictionary:
	var pig: Dictionary = game.pigs[index]
	pig.position = pos
	pig.hp = hp
	pig.respawn = 0.0
	pig.velocity = Vector2.ZERO
	pig["wheel_gold"] = false
	return pig


func _isolate() -> void:
	# 把桌上所有猪都挪远，避免磁吸/连击波及其他猪
	for i in range(game.pigs.size()):
		_prep_pig(i, Vector2(1000 + i * 10, 1000), 10.0)


func _key(code) -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	game._unhandled_input(k)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.intro_open = false
	game.reset_game()
	var shop = game.shop
	check(shop != null, "shop module is mounted")

	# 1) 商店开合 / 固定目录 / 默认锤子区 / 标签切换
	check(not shop.is_open(), "shop closed at start")
	shop.try_open_shop()
	check(shop.is_open() and shop.shop_open, "open shop pauses game")
	check(shop.shop_tab == 0, "shop defaults to hammer tab")
	check(shop.hammer_stock.size() == 3 and shop.skill_stock.size() == 2 and shop.box_stock, "fixed catalog: 3 hammers / 2 skills / 1 box")
	check(shop.hammer_stock[0] == "dual" and shop.hammer_stock[1] == "gravity" and shop.hammer_stock[2] == "magnet", "hammer tab order: dual / gravity / magnet")
	check(shop.skill_stock[0] == "hourglass" and shop.skill_stock[1] == "abacus", "skill tab order: hourglass / abacus")
	shop._set_tab(1)
	check(shop.shop_tab == 1, "switch to skill tab")
	shop._set_tab(0)
	check(shop.shop_tab == 0, "switch back to hammer tab")
	shop.try_open_shop()
	check(not shop.is_open(), "toggle closes shop")

	# 2) 锤子购买/替换/不足（固定目录，购买后商品常驻）
	game.score = 500
	shop.try_open_shop()
	shop.buy_hammer(0)
	check(shop.current_hammer_id == "dual" and game.score == 280, "buy hammer equips and deducts 220")
	check(shop.hammer_stock.size() == 3 and shop.hammer_stock[0] == "dual", "hammer shelf stays after purchase (no refill / removal)")
	shop.buy_hammer(1)
	check(shop.current_hammer_id == "gravity" and game.score == 60, "second hammer replaces the first")
	game.score = 100
	shop.buy_hammer(2)
	check(game.score == 100 and shop.current_hammer_id == "gravity", "insufficient funds blocks hammer")
	shop.close_all()

	# 2.5) 常驻货架：同一槽位可连续购买
	game.score = 1000
	shop.try_open_shop()
	shop.buy_hammer(0)
	shop.buy_hammer(0) # 商品常驻，可再买
	check(game.score == 560, "consecutive hammer purchases each deduct 220")
	shop.close_all()

	# 3) 技能购买/容量/满包
	game.score = 500
	shop.try_open_shop()
	shop.buy_skill(0)
	check(shop.backpack.size() == 1 and game.score == 320, "buy skill stores in backpack")
	check(shop.skill_stock.size() == 2 and shop.skill_stock[0] == "hourglass", "skill shelf stays after purchase")
	shop.buy_skill(1)
	check(shop.backpack.size() == 2 and game.score == 140, "second skill also stored")
	game.score = 500
	shop.buy_skill(0)
	check(shop.backpack.size() == 3 and game.score == 320, "third skill fills backpack")
	shop.buy_skill(1)
	check(shop.backpack.size() == 3 and game.score == 320, "full backpack blocks purchase")
	shop.close_all()

	# 3.5) 技能区第三格路由：_buy_cell(2) -> 盲盒
	game.reset_game()
	shop = game.shop
	game.score = 300
	shop.try_open_shop()
	shop._set_tab(1)
	shop.box_result_override = 2 # coins +25
	shop._buy_cell(2)
	check(game.score == 125, "skill-tab third cell routes to mystery box")
	shop.close_all()

	# 4) 盲盒五种奖励（覆写随机）
	game.reset_game()
	shop = game.shop
	game.score = 300
	shop.try_open_shop()
	shop.box_result_override = 2 # coins
	shop.buy_box()
	check(game.score == 125, "box coins +25")
	check(shop.box_stock, "box stays available after purchase (fixed catalog)")

	game.score = 300
	shop.box_stock = true
	shop.box_result_override = 3 # damage_up
	shop.buy_box()
	check(shop.damage_bonus_pct == 0.15 and is_equal_approx(shop.hammer_damage_mul(), 1.15), "box hammer damage +15%")

	game.score = 300
	shop.box_stock = true
	shop.box_result_override = 4 # triple_kill
	shop.buy_box()
	check(shop.triple_kills == 3 and shop.kill_bonus_mul() == 3.0, "box triple-kill x3")

	game.score = 300
	shop.box_stock = true
	shop.box_result_override = 0 # hammer
	shop.buy_box()
	check(shop.current_hammer_id != "iron", "box hammer replaces current")

	shop.backpack.clear()
	game.score = 300
	shop.box_stock = true
	shop.box_result_override = 1 # skill
	shop.buy_box()
	check(shop.backpack.size() == 1, "box skill enters backpack")

	shop.backpack.append(shop._make_skill("hourglass"))
	shop.backpack.append(shop._make_skill("abacus"))
	game.score = 300
	shop.box_stock = true
	shop.box_result_override = 1 # skill，但背包已满
	shop.buy_box()
	check(shop.backpack.size() == 3 and game.score == 100, "full backpack wastes box skill but still deducts")
	shop.close_all()

	# 4.5) 悬停气泡文案（与需求逐字一致）+ 自动换行
	game.reset_game()
	shop = game.shop
	shop.try_open_shop()
	check(shop._cell_tip(0) == "连续两次砸击，单伤偏低，共用冷却。无时效，永久持有，购买后替换当前主武器。", "tip: dual hammer")
	check(shop._cell_tip(1) == "长按蓄力，蓄力越久伤害与范围越大，砸击后自身短暂硬直。无时效，永久持有，购买后替换当前主武器。", "tip: gravity hammer")
	check(shop._cell_tip(2) == "砸击时吸附附近小猪至落点中心，再结算伤害。无时效，永久持有，购买后替换当前主武器。", "tip: magnet hammer")
	shop._set_tab(1)
	check(shop._cell_tip(0) == "全场小猪移速降至40%，持续2.5秒。技能可重复释放，刷新持续时间。", "tip: hourglass")
	check(shop._cell_tip(1) == "4秒内击杀小猪得分×2，金币不翻倍。技能持续时间内可叠加击杀收益。", "tip: abacus")
	check(shop._cell_tip(2) == "消耗200金币抽取随机奖励，可能获得锤子、技能、金币、伤害加成或分数倍率。", "tip: mystery box")
	check(shop._wrap_text("一二三四五六七八九十一二三四五六", 14, 100).size() >= 2, "tooltip text wraps by width")
	# 3D 模型管线：7 个内置低模经单视口烘焙成各自独立的 ImageTexture
	var model_keys := ["hammer:iron", "hammer:dual", "hammer:gravity", "hammer:magnet", "skill:hourglass", "skill:abacus", "box:box"]
	for k in model_keys:
		check(shop.icons_3d.has_model(k), "3d model registered: " + k)
	# 烘焙为异步流程（每模型 2 帧），等待足够帧数后再验收
	for _i in range(24):
		await process_frame
	var tex_rids := {}
	var tex_hashes := {}
	var any_rendered_content := false
	for k in model_keys:
		var tex: Texture2D = shop.icons_3d.get_texture(k)
		check(tex != null, "3d icon baked to texture: " + k)
		if tex != null:
			var rid: RID = tex.get_rid()
			check(not tex_rids.has(rid), "texture RID unique: " + k)
			tex_rids[rid] = k
			var img: Image = tex.get_image()
			if img != null:
				var bytes: PackedByteArray = img.get_data()
				var signature := Marshalls.raw_to_base64(bytes)
				var has_content := false
				for b in bytes:
					if b != 0:
						has_content = true
						break
				any_rendered_content = any_rendered_content or has_content
				if has_content:
					check(not tex_hashes.has(signature), "rendered pixels differ from other icons: " + k)
					tex_hashes[signature] = k
	if not any_rendered_content:
		print("INFO: headless dummy renderer produced blank images, pixel-diff check skipped (RID uniqueness still enforced)")
	check(shop.icons_3d.get_texture("hammer:unknown") == null, "unknown model falls back to placeholder")
	# 内置低模必须有可测量的几何包围盒（相机自动取景依赖它）
	var factory := preload("res://scripts/shop_models_builtin.gd")
	var probe: Node3D = factory.make_node("abacus")
	check(probe != null and shop.icons_3d._combined_aabb(probe).size != Vector3.ZERO, "builtin model exposes non-empty geometry AABB")
	probe.free()
	shop.close_all()

	# 5) 技能释放/冷却/拖拽保留冷却
	game.reset_game()
	shop = game.shop
	var hour: Dictionary = shop._make_skill("hourglass")
	shop.quickbar[0] = hour
	shop.try_activate_skill(0)
	check(shop.slow_active > 0.0 and float(hour.cd) > 0.0, "hourglass activates with slow + cooldown")
	var cd_before: float = float(hour.cd)
	shop.tick(1.0)
	check(float(hour.cd) < cd_before, "cooldown ticks down during gameplay")
	var cd_now: float = float(hour.cd)
	shop.move_item("quickbar", 0, "backpack", 0)
	check(shop.quickbar[0] == null and shop.backpack.size() == 1, "drag quickbar -> backpack")
	check(is_equal_approx(float(shop.backpack[0].cd), cd_now), "cooldown preserved across drag")

	var ab: Dictionary = shop._make_skill("abacus")
	shop.quickbar[0] = ab
	shop.try_activate_skill(0)
	check(shop.score_mul() == 2.0, "abacus activates score x2")
	shop.slow_active = 1.0
	check(is_equal_approx(shop.speed_mul(), 0.4), "slow active reduces pig speed to 40%")
	shop.slow_active = 0.0
	check(shop.speed_mul() == 1.0, "no slow = full speed")

	# 6) 三款锤子行为
	game.reset_game()
	shop = game.shop
	game.phase = "playing"
	game.cooldown = 0.0
	game.stamina = 999.0
	game.hits = 0
	_isolate()

	# 连打：自动 2 击
	shop.current_hammer_id = "dual"
	var dual_pig := _prep_pig(0, Vector2(400, 400), 2.0)
	game.strike(Vector2(400, 400))
	check(game.hits == 2, "dual hammer lands two hits")
	check(is_equal_approx(float(dual_pig.hp), 0.7), "dual hammer total damage 1.3")

	# 磁吸：吸附 + 递减伤害
	game.cooldown = 0.0
	shop.current_hammer_id = "magnet"
	var a := _prep_pig(0, Vector2(400, 400), 10.0)
	var b := _prep_pig(1, Vector2(400, 500), 10.0)
	game.strike(Vector2(400, 400))
	check(a.position == Vector2(400, 400) and b.position == Vector2(400, 400), "magnet pulls pigs to center")
	check(float(a.hp) < float(b.hp) and float(a.hp) < 10.0, "magnet closer pig takes more damage")

	# 重力：满蓄力 3 伤害 + 落地硬直
	game.cooldown = 0.0
	shop.current_hammer_id = "gravity"
	game.charging = true
	game.charge_time = 1.0
	game.charge_t = 1.0
	game.hammer_position = Vector2(400, 400)
	_isolate() # 清场：只留 grav_pig 在落点，避免磁吸那步的 b 猪抢走最近目标
	var grav_pig := _prep_pig(0, Vector2(400, 400), 10.0)
	game._gravity_strike()
	check(is_equal_approx(float(grav_pig.hp), 7.0), "gravity full charge deals 3 damage")
	check(game.stun_t > 0.0, "gravity landing sets stun")

	# 7) 击杀计数递减
	shop.triple_kills = 3
	shop.consume_kill()
	check(shop.triple_kills == 2, "kill consumes one triple charge")

	# 8) T 快捷键接线
	game.reset_game()
	shop = game.shop
	game.phase = "playing"
	_key(KEY_T)
	check(shop.is_open() and shop.shop_open, "T hotkey opens shop")
	_key(KEY_T)
	check(not shop.is_open(), "T hotkey toggles shop closed")

	# 9) reset 清空一切
	game.reset_game()
	check(shop.current_hammer_id == "iron" and shop.backpack.is_empty(), "reset clears hammer and backpack")
	check(shop.quickbar.size() == 3 and shop.quickbar[0] == null and shop.quickbar[1] == null and shop.quickbar[2] == null, "reset clears quickbar")
	check(shop.damage_bonus_pct == 0.0 and shop.triple_kills == 0 and shop.slow_active == 0.0 and shop.abacus_active == 0.0, "reset clears buffs and timers")
	check(shop.shop_tab == 0 and shop.hammer_stock.size() == 3 and shop.skill_stock.size() == 2, "reset restores fixed catalog and default tab")

	game.queue_free()
	print("ALL ", checks, " SHOP CHECKS PASSED")
	quit(0)
