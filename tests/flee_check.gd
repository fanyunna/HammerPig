extends SceneTree
## 快速行为验证：移动性格（随机换向 + 躲锤）——headless 跑
## 用法：console.exe --headless --path . --script tests/flee_check.gd

var game

func _initialize() -> void:
	run.call_deferred()

func key_press(code) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = code
	game._unhandled_input(key)

func fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	# 进入 playing 阶段：R 键开局（与 smoke.gd 同款）
	key_press(KEY_R)
	await process_frame
	await process_frame
	if game.phase != "playing":
		fail("phase=%s 不是 playing" % game.phase)
		return
	# ---- 1) 随机换向：把锤子放到离所有猪很远的地方，几秒后方向应该变过 ----
	game.hammer_position = Vector2(-9999, -9999)
	var pig: Dictionary = game.pigs[0]
	pig.type = {"id": "piggy", "speed": 1.0, "flee": 0.9}
	pig.velocity = Vector2(90, 0)
	pig.wander_t = 0.01
	var dirs := {}
	for f in range(600): # ~10 秒，覆盖多个换向周期
		game._process(1.0 / 60.0)
		dirs[Vector2(roundf(pig.velocity.normalized().x * 2), roundf(pig.velocity.normalized().y * 2))] = true
	if dirs.size() < 3:
		fail("猪 4 秒内方向几乎没变过（换向逻辑没生效），方向数=%d" % dirs.size())
		return
	print("PASS: 猪会随机换向（4 秒内出现 %d 种方向）" % dirs.size())
	# ---- 2) 躲锤：锤子压在猪身侧，速度方向应该背离锤子 ----
	var pig2: Dictionary = game.pigs[1]
	pig2.type = {"id": "piggy", "speed": 1.0, "flee": 0.9}
	pig2.hp = pig2.max_hp
	pig2.position = Vector2(640, 480)
	pig2.velocity = Vector2(0, 0)
	var hammer_at: Vector2 = pig2.position + Vector2(-30, 0) # 锤子压在猪左侧
	game.update_pig_motion(pig2, 1.0 / 60.0, hammer_at)
	var v: Vector2 = pig2.velocity
	var away: Vector2 = pig2.position - hammer_at
	if v.length() < 10.0:
		fail("锤子压住猪时猪没跑（速度=%.1f）" % v.length())
		return
	if v.normalized().dot(away.normalized()) < 0.9:
		fail("逃跑方向不对：v=%s away=%s" % [v, away])
		return
	print("PASS: 锤子压住猪时猪向外逃（速度 %.0f px/s，方向背离锤子）" % v.length())
	# ---- 3) 胖警长懒得动：flee=0.15 的猪在锤子旁边也几乎不加速 ----
	var pig3: Dictionary = game.pigs[2]
	pig3.type = {"id": "fat", "speed": 0.7, "flee": 0.15}
	pig3.hp = pig3.max_hp
	pig3.position = Vector2(640, 480)
	pig3.velocity = Vector2(0, 0)
	game.update_pig_motion(pig3, 1.0 / 60.0, hammer_at)
	var lazy_speed: float = pig3.velocity.length() / maxf(float(pig3.type.get("speed", 1.0)), 0.15)
	if pig3.velocity.length() > float(game.settings.get("pig_speed", 90)) * 1.2:
		fail("胖警长被吓得狂奔（速度=%.1f），flee 逻辑误伤懒猪" % pig3.velocity.length())
		return
	print("PASS: 胖警长（flee=0.15）在锤子旁边也只慢吞吞挪（速度 %.0f px/s）" % pig3.velocity.length())
	print("ALL FLEE CHECKS PASSED")
	quit(0)
