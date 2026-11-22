extends Node
## 逃跑场面（第十五轮）：躲催债从"圆圈躲弹幕"升级成"夺门而出 · 沿街狂奔"。
## 参考《神庙逃亡》的跑与躲：
##   开场演出（敲门 → 门被砸开 → 主人公冲出 → 催债人追出）→ 街道奔跑 → 结算。
## 操作：鼠标自由上下跑（鼠标在街道里一动，目标高度就跟过去），键盘 ↑↓ / W S 是步进微调，
## 点舞台也会跑到点的那个高度。障碍分远/中/近三段随机来，靠上下穿插躲。
## 撑过倒计时 = 逃脱成功（复用 finish_challenge）；被抓满 3 次 = 失败。
## 接线和 day_events 一样低侵入：update / draw(host) / handle_click / handle_key。
## 测试可注入 forced_obstacles（{row|y|lane, kind}，按顺序消费）实现零随机复现。

const INTRO_TIME := 2.2 # 开场演出时长（秒）：敲门 0.5 → 砸门 1.0 → 夺门而出 2.2
const RUNNER_X_OFFSET := 250.0 # 主人公站在舞台左侧多远
const OBSTACLE_W := 34.0 # 障碍碰撞半宽（与跑步速度一起决定反应窗口）
const KNOCK_TIME := 0.5
const BURST_TIME := 1.0
const VERT_TOL := 38.0 # 上下方向的碰撞容差：离障碍这么近才算撞上
const KEY_STEP := 46.0 # 键盘 ↑↓ 一次挪多远（鼠标接管时键盘退居微调）

var main # main.gd 主脚本：只读它的计时器，结算回调 main.finish_challenge
var stage_rect := Rect2(56, 300, 1168, 372) # 舞台像素区：由 main._ready 把 CHALLENGE_STAGE 注进来（跨脚本读常量不稳）
var active := false # 躲债关是否进行中（state != idle）
var state := "" # intro / run / result
var intro_t := 0.0
var runner_y := 0.0 # 主人公脚底 y：鼠标自由上下跑，向 target_y 平滑插值
var target_y := 0.0 # 目标 y（鼠标高度 / 键盘步进 / 点击落点）
var mouse_control := true # 鼠标是否接管 y（测试关掉它，走纯键盘/直接赋值）
var mouse_anchor := Vector2(-1.0e9, -1.0e9) # 上一帧鼠标位置：只有真的动了才抢控制权
var run_dist := 0.0 # 已跑距离：驱动视差滚动与步伐
var spawn_t := 0.0
var obstacles: Array[Dictionary] = []
var forced_obstacles: Array = [] # 测试注入：[{y|row|lane, kind}]，按顺序消费；空则随机
var invincible_t := 0.0
var hit_flash := 0.0 # 被抓的红边闪烁
var run_t := 0.0 # 步伐相位
var door_open := 0.0 # 门开合角度（开场演出用）
var knock_shake := 0.0 # 砸门的震颤

func setup(host) -> void:
	main = host

func is_open() -> bool:
	return active

func reset_run() -> void:
	active = false
	state = ""
	obstacles.clear()
	forced_obstacles.clear()

## 躲债关开场：main.start_challenge 已把 dodge_lives / bill_timer 复位
func start() -> void:
	active = true
	state = "intro"
	intro_t = 0.0
	target_y = _y_max() - 12.0 # 从近处起步：先看清街道再往前冲
	runner_y = target_y
	mouse_control = true
	mouse_anchor = Vector2(-1.0e9, -1.0e9)
	run_dist = 0.0
	spawn_t = 0.6
	obstacles.clear()
	invincible_t = 0.0
	hit_flash = 0.0
	run_t = 0.0
	door_open = 0.0
	knock_shake = 0.0
	Sound.play("stamp", 0.8, 0.5) # 敲门声

## 可跑区域：脚底 y 的上下限。上限贴着街道远边，下限贴进画面底部
func _y_min() -> float:
	return stage_rect.position.y + stage_rect.size.y * 0.60

func _y_max() -> float:
	return stage_rect.position.y + stage_rect.size.y * 0.95

## 障碍的三个高度段（远 / 中 / 近）：自由移动下靠上下穿插躲，而不是选一条固定的道
func _row_y(r: int) -> float:
	var lo := _y_min()
	var span := _y_max() - lo
	return lo + span * (0.0 if r <= 0 else (0.5 if r == 1 else 1.0))

func _interval() -> float:
	return float(main.settings.get("escape_obstacle_interval", 1.1))

func _speed() -> float:
	return float(main.settings.get("escape_obstacle_speed", 260.0))

## ---------- 每帧更新：由 main._process 的 challenge 分支调用（bill_timer 由 main 递减） ----------
func update(delta: float) -> void:
	match state:
		"intro":
			intro_t += delta
			knock_shake = maxf(0.0, knock_shake - delta * 3.0)
			if intro_t < BURST_TIME and door_open == 0.0 and intro_t >= KNOCK_TIME:
				door_open = 0.01 # 门开始被砸开
				knock_shake = 1.0
				Sound.play("pop", 1.2, 0.9) # 门被砸开
				Sound.play("stamp", 1.0, 0.7)
			if door_open > 0.0:
				door_open = minf(1.0, door_open + delta * 2.4)
			if intro_t >= INTRO_TIME:
				state = "run"
				Sound.play("click", 1.1)
		"run":
			run_t += delta
			run_dist += _speed() * delta * 0.35 # 视差滚动的世界速度
			_follow_mouse() # 鼠标在街道里动一下：目标 y 就跟过去（自由上下跑）
			target_y = clampf(target_y, _y_min(), _y_max())
			runner_y = lerpf(runner_y, target_y, minf(1.0, delta * 16.0)) # 平滑跟手：不做瞬移
			invincible_t = maxf(0.0, invincible_t - delta)
			hit_flash = maxf(0.0, hit_flash - delta)
			spawn_t -= delta
			if spawn_t <= 0.0:
				_spawn_obstacle()
				spawn_t = _interval()
			for i in range(obstacles.size() - 1, -1, -1):
				var o: Dictionary = obstacles[i]
				o.x -= _speed() * delta
				var runner_x := _runner_x()
				if absf(float(o.x) - runner_x) <= OBSTACLE_W and absf(float(o.get("y", runner_y)) - runner_y) <= VERT_TOL:
					if invincible_t <= 0.0: # 撞上：被抓一次，催债人逼近
						main.dodge_lives -= 1
						invincible_t = float(main.settings.get("escape_invincible", 0.9))
						hit_flash = 0.4
						Sound.play("stamp", 0.9)
						obstacles.remove_at(i)
						if main.dodge_lives <= 0:
							_finish(false)
						continue
				if float(o.x) < stage_rect.position.x - 60.0:
					obstacles.remove_at(i)
			if state == "run" and main.bill_timer <= 0.0:
				_finish(true) # 撑过倒计时：逃脱成功
		"result":
			pass

func _finish(success: bool) -> void:
	active = false
	state = "result"
	if success:
		Sound.play("win")
	main.finish_challenge(success)

func _runner_x() -> float:
	return stage_rect.position.x + RUNNER_X_OFFSET

func _spawn_obstacle() -> void:
	var kinds := ["bin", "barrier", "bin"]
	var kind := String(kinds[randi() % kinds.size()])
	var y := _row_y(randi() % 3) # 上/中/下随机：逼你上下穿插
	if not forced_obstacles.is_empty():
		var f: Dictionary = forced_obstacles.pop_front()
		kind = String(f.get("kind", kind))
		if f.has("y"):
			y = float(f.y)
		elif f.has("row"):
			y = _row_y(int(f.row))
		elif f.has("lane"): # 兼容旧写法：lane 0 当远段，lane 1 当近段
			y = _row_y(0 if int(f.lane) == 0 else 2)
	obstacles.append({"y": y, "kind": kind, "x": stage_rect.end.x + 40.0})

## ---------- 输入：main._unhandled_input 的 challenge 分支转发 ----------
func handle_click(point: Vector2) -> void:
	if state == "intro":
		intro_t = INTRO_TIME # 点一下跳过演出
		return
	if state != "run":
		return
	target_y = clampf(point.y, _y_min(), _y_max()) # 点到哪就跑到哪一级高度

func handle_key(keycode: int) -> void:
	if state == "intro" and (keycode == KEY_SPACE or keycode == KEY_ENTER):
		intro_t = INTRO_TIME
		return
	if state != "run":
		return
	if keycode == KEY_UP or keycode == KEY_W:
		target_y = clampf(target_y - KEY_STEP, _y_min(), _y_max())
	elif keycode == KEY_DOWN or keycode == KEY_S:
		target_y = clampf(target_y + KEY_STEP, _y_min(), _y_max())

## 鼠标自由上下跑：鼠标"真的动了"才抢控制权（否则按键挪一格会被下一帧的鼠标位置盖回去）
## 鼠标停在界面按钮/账本上时不接管：人不会因为点了个按钮就往上飞
func _follow_mouse() -> void:
	if not mouse_control or main == null:
		return
	var m: Vector2 = main.hammer_position
	if m.distance_squared_to(mouse_anchor) <= 16.0: # 没动：别抢键盘的目标
		return
	mouse_anchor = m
	if m.y < stage_rect.position.y or m.y > stage_rect.end.y:
		return
	if m.x < stage_rect.position.x or m.x > stage_rect.end.x:
		return
	target_y = m.y

## ---------- 绘制：由 main._draw 在躲债关调用，全部画在主画布上 ----------
func draw(p) -> void:
	var stage: Rect2 = stage_rect
	_draw_hud(p, stage) # 考核标题的深色大面板先画（它盖住整个舞台），场景全部画在它上面
	_draw_backdrop(p, stage)
	_draw_house(p, stage)
	for o in obstacles:
		_draw_obstacle(p, stage, o)
	_draw_collectors(p, stage)
	if state != "intro":
		_draw_runner(p, stage)
	if state == "intro":
		_draw_intro_captions(p, stage)
	if hit_flash > 0.0:
		p.draw_rect(stage, Color(0.75, 0.15, 0.1, 0.22 * hit_flash / 0.4), false, 10.0)

func _draw_backdrop(p, stage: Rect2) -> void:
	p.panel(stage, Color("#2a1c10"), 16) # 黄昏的天
	# 远景剪影：随距离滚动，两层视差
	var spacing := 220.0
	var off := fmod(run_dist * 0.5, spacing)
	var x := stage.position.x - off
	while x < stage.end.x:
		var h := 60.0 + 22.0 * sin(x * 0.013)
		p.panel(Rect2(x, stage.end.y - 130.0 - h, 70.0, h + 130.0), Color("#3d2a16"), 6)
		x += spacing
	# 街面：给足 152px 厚度，人才有上下穿插的余地
	p.panel(Rect2(stage.position.x, stage.end.y - 152.0, stage.size.x, 152.0), Color("#57402a"), 0)
	p.panel(Rect2(stage.position.x, stage.end.y - 152.0, stage.size.x, 6.0), Color("#6b5238"), 0)
	# 路中虚线
	var dash := 34.0
	var doff := fmod(run_dist, dash * 2.0)
	var lx := stage.position.x - doff
	while lx < stage.end.x:
		p.panel(Rect2(lx, stage.end.y - 60.0, 20.0, 4.0), Color("#8a6a4a"), 2)
		lx += dash * 2.0

func _draw_house(p, stage: Rect2) -> void:
	# 家：开场时在门口，随奔跑向左退出画面
	var hx := stage.position.x + 40.0 - run_dist * 0.6
	if hx < -220.0:
		return
	var shake := knock_shake * 4.0
	var bx := hx + shake
	var by := stage.end.y - 152.0
	p.panel(Rect2(bx, by - 150.0, 150.0, 150.0), Color("#6b4a26"), 6)
	p.draw_polygon(PackedVector2Array([
		Vector2(bx - 12, by - 150.0), Vector2(bx + 75, by - 205.0), Vector2(bx + 162, by - 150.0)]),
		PackedColorArray([Color("#412402"), Color("#412402"), Color("#412402")]))
	# 门：开场演出里被砸开（door_open 0→1 控制门板旋转的假 3D）
	var dw := 52.0
	var dh := 92.0
	var dx := bx + 88.0
	p.panel(Rect2(dx, by - dh, dw, dh), Color("#241610"), 4)
	if door_open <= 0.0:
		p.panel(Rect2(dx + 3, by - dh + 3, dw - 6, dh - 6), Color("#8a5a2a"), 3)
	else:
		var wobble := sin(door_open * PI) * 14.0 # 砸开的晃动
		p.panel(Rect2(dx + 3 + door_open * 26.0 + wobble, by - dh + 3, (dw - 6) * (1.0 - door_open * 0.55), dh - 6),
			Color("#8a5a2a"), 3)
		p.draw_rect(Rect2(dx, by - dh, dw, dh), Color(0, 0, 0, 0.55 * door_open)) # 门内黑洞

func _draw_runner(p, stage: Rect2) -> void:
	var x := _runner_x()
	var y := runner_y
	var swing := sin(run_t * 16.0) # 步伐
	var bob := absf(sin(run_t * 16.0)) * 4.0
	var lean := 0.14 # 前倾
	if invincible_t > 0.0 and fmod(invincible_t, 0.2) > 0.1:
		return # 被抓后的无敌闪烁
	# 脚下的影子：自由上下跑时，它是唯一能告诉你"我站在哪一层"的参照
	p.draw_circle(Vector2(x, y + 3.0), 17.0, Color(0, 0, 0, 0.22))
	# 腿
	p.draw_line(Vector2(x, y - 34.0), Vector2(x + swing * 14.0, y), Color("#26215C"), 7.0)
	p.draw_line(Vector2(x, y - 34.0), Vector2(x - swing * 14.0, y), Color("#26215C"), 7.0)
	# 身体（前倾）
	p.draw_line(Vector2(x, y - 34.0), Vector2(x + lean * 40.0, y - 64.0 - bob), Color("#534AB7"), 12.0)
	# 手臂前后摆
	p.draw_line(Vector2(x + lean * 40.0, y - 58.0 - bob), Vector2(x + lean * 40.0 - swing * 16.0, y - 40.0 - bob), Color("#F5C4B3"), 6.0)
	p.draw_line(Vector2(x + lean * 40.0, y - 58.0 - bob), Vector2(x + lean * 40.0 + swing * 16.0, y - 40.0 - bob), Color("#F5C4B3"), 6.0)
	# 头 + 红头巾（和开场剧情对上：主角就是躲债的那位）
	var hy := y - 78.0 - bob
	p.draw_circle(Vector2(x + lean * 52.0, hy), 12.0, Color("#F5C4B3"))
	p.draw_rect(Rect2(x + lean * 52.0 - 11.0, hy - 10.0, 22.0, 6.0), Color("#A32D2D"))
	p.draw_line(Vector2(x + lean * 52.0 - 11.0, hy - 4.0), Vector2(x + lean * 52.0 - 20.0, hy + 4.0 + swing * 3.0), Color("#A32D2D"), 4.0)

func _draw_collectors(p, stage: Rect2) -> void:
	# 催债人始终吊在身后：被抓几次就逼近多少（纯演出 + 压力可视化）
	var max_lives: int = int(main.settings.get("dodge_lives", 3))
	var gap := 90.0 + 110.0 * (float(maxi(0, main.dodge_lives)) / float(max_lives))
	for i in range(2):
		var bob := absf(sin(run_t * 15.0 + i * 1.7)) * 5.0
		var cx := _runner_x() - gap - i * 34.0 + sin(run_t * 9.0 + i) * 6.0
		var y := runner_y + 4.0 - bob
		var swing := sin(run_t * 15.0 + i * 1.7)
		p.draw_line(Vector2(cx, y - 30.0), Vector2(cx + swing * 12.0, y), Color("#501313"), 7.0)
		p.draw_line(Vector2(cx, y - 30.0), Vector2(cx - swing * 12.0, y), Color("#501313"), 7.0)
		p.draw_line(Vector2(cx, y - 30.0), Vector2(cx, y - 56.0), Color("#791F1F"), 11.0)
		p.draw_line(Vector2(cx, y - 50.0), Vector2(cx + 18.0, y - 38.0), Color("#D3A077"), 6.0) # 伸出的手
		p.draw_circle(Vector2(cx, y - 68.0), 11.0, Color("#D3A077"))
		p.draw_rect(Rect2(cx - 10.0, y - 76.0, 20.0, 5.0), Color("#22212a")) # 黑帽

func _draw_obstacle(p, stage: Rect2, o: Dictionary) -> void:
	var x := float(o.x)
	var y := float(o.get("y", stage.end.y - 40.0))
	if y > stage.get_center().y: # 越靠近观众，影子越实：远近有个交代
		p.draw_circle(Vector2(x, y + 4.0), 20.0, Color(0, 0, 0, 0.25))
	if String(o.kind) == "bin":
		p.panel(Rect2(x - 16.0, y - 40.0, 32.0, 40.0), Color("#888780"), 3)
		p.panel(Rect2(x - 19.0, y - 45.0, 38.0, 8.0), Color("#5F5E5A"), 3)
		p.panel(Rect2(x - 16.0, y - 28.0, 32.0, 4.0), Color("#5F5E5A"), 0)
	else: # barrier：斜纹路障
		p.panel(Rect2(x - 20.0, y - 26.0, 40.0, 26.0), Color("#BA7517"), 3)
		p.draw_line(Vector2(x - 18.0, y - 4.0), Vector2(x + 2.0, y - 24.0), Color("#FAEEDA"), 5.0)
		p.draw_line(Vector2(x - 2.0, y - 4.0), Vector2(x + 18.0, y - 24.0), Color("#FAEEDA"), 5.0)

func _draw_hud(p, stage: Rect2) -> void:
	var left := int(ceilf(main.bill_timer))
	var hint := "移动鼠标上下跑（键盘 ↑↓ 也行）· 撞障碍被抓一次"
	if state == "intro":
		hint = "敲门声……（点一下跳过）"
	p.draw_challenge_header("夺门而逃", "撑到时间结束（还剩 " + str(left) + " 秒）",
		hint, maxi(0, main.dodge_lives))

func _draw_intro_captions(p, stage: Rect2) -> void:
	var c := stage.get_center()
	if intro_t < KNOCK_TIME:
		p.text_center("咚咚咚 ——「开门！欠的钱今天必须还！」", c.x, c.y - 20.0, 24, Color("#ffe092"))
	elif intro_t < INTRO_TIME:
		p.text_center("门被砸开了 —— 跑！", c.x, c.y - 20.0, 26, Color("#e8836b"))
