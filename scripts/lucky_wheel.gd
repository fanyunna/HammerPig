extends Node2D

## 幸运转盘（低侵入扩展层）：作为 main 的最后一个子节点挂在整局之上，自己画按钮、弹窗、转盘与特效。
## 与 main 的接口只有几处：
##   - main._process 里调 tick(delta)：喂余额、推进独立 buff 计时、管理金猪的压扁/到期消失
##   - main.strike 里喂 on_landed_hit() / on_missed_swing()：连续命中计数
##   - main 暴露 pay_bills_free() / spawn_wheel_gold_pigs() / despawn_pig() 供结果结算
## 弹窗打开时 main._process 直接返回（猪停刷、不能砸猪），本节点自己的 _process 继续跑旋转动画。

const BALANCE_TRIGGER := 500 # 余额跨过这条线 → +1 次机会
const STREAK_TRIGGER := 12 # 连续砸中 12 只 → +1 次机会（挥空清零）
const SECTOR_COUNT := 6
const SPIN_TIME := 3.4 # 旋转总时长：先快速加速，再平滑减速
const SPIN_ACCEL := 0.35 # 加速段时长
const SPIN_TURNS := 5 # 至少转满的圈数
const SLOW_MUL := 0.55 # 「小猪变慢」的速度倍率
const FAST_MUL := 1.7 # 「小猪变快」的速度倍率
const DOUBLE_DURATION := 20.0
const SLOW_DURATION := 20.0
const FAST_DURATION := 10.0
const GOLD_PIG_COUNT := 5
const GOLD_PIG_LIFE := 9.0 # 金猪没被砸中时的存活时间
const GOLD_PIG_VALUE := 200
const GOLD_SQUASH_TIME := 0.34 # 压扁回弹动画时长
const BTN_CENTER := Vector2(1180, 186)
const BTN_RADIUS := 32.0
const PANEL_RECT := Rect2(290, 84, 700, 632)
const WHEEL_CENTER := Vector2(640, 368)
const WHEEL_RADIUS := 200.0
const CONFIRM_RECT := Rect2(545, 648, 190, 50)
const FX_NODE_CAP := 90 # 特效节点保险丝，防止粒子/金币无限堆积

# 六个扇形：下标即结果编号，颜色区分度高，文字直接标在扇形里
const SECTORS := [
	{"label": "+¥120", "color": "#c9a227", "desc": "余额立刻增加 ¥120"},
	{"label": "得分×2", "color": "#d65a5a", "desc": "20 秒内敲猪得分翻倍"},
	{"label": "小猪变慢", "color": "#4f8fd0", "desc": "20 秒内小猪刷新与移动变慢"},
	{"label": "还5张账单", "color": "#5aa860", "desc": "直接偿还最便宜的 5 张账单"},
	{"label": "小猪变快", "color": "#9a6ad0", "desc": "10 秒内小猪刷新与移动加快"},
	{"label": "金猪降临", "color": "#e07840", "desc": "生成 5 只金猪，每砸中一只 +¥200"},
]

var main # 主游戏节点（main.gd），setup() 注入
var chances := 0 # 当前可抽奖次数
var streak := 0 # 连续砸中计数（挥空清零）
var prev_score := 0 # 上一次见到的余额，用来判断「跨过 ¥500」
# 三种 buff 各自独立倒计时，互不覆盖，可同时生效（叠乘）
var double_left := 0.0
var slow_left := 0.0
var fast_left := 0.0
var popup_open := false
var state := "closed" # closed / spinning / result
var result_index := 0
var wheel_rot := 0.0
var spin_t := 0.0
var spin_target := 0.0 # 本次旋转的总角度（保证停下时扇形正好对齐指针）
var btn_pulse := 0.0 # 获得新机会时按钮的跳动反馈

var _last_sector := -1
var _fx_nodes := 0
var _coin_tex: Texture2D
var _spark_tex: Texture2D


func setup(host) -> void:
	main = host
	prev_score = int(host.score)


func is_open() -> bool:
	return popup_open


## 打开转盘弹窗并消耗一次机会。force_result >= 0 时固定抽中该扇形（测试用）
func open_wheel(force_result := -1) -> bool:
	print("点击抽奖按钮，剩余抽奖次数：", chances)
	if popup_open or chances <= 0 or main == null:
		return false
	chances -= 1
	result_index = force_result if force_result >= 0 else randi() % SECTOR_COUNT
	popup_open = true
	state = "spinning"
	spin_t = 0.0
	wheel_rot = 0.0
	_last_sector = -1
	# 停下时让抽中扇形的中心正好对到上方指针：指针在 -90°，扇形中心在 (k+0.5)*60°
	var center_angle := (float(result_index) + 0.5) * TAU / float(SECTOR_COUNT)
	spin_target = fposmod(-PI / 2.0 - center_angle, TAU) + TAU * float(SPIN_TURNS)
	Sound.play("flip")
	queue_redraw()
	return true


func confirm_result() -> void:
	if not popup_open or state != "result":
		return
	popup_open = false
	state = "closed"
	Sound.play("click")
	queue_redraw()


## 点击分发：弹窗打开时吞掉所有点击；平时只认领抽奖按钮上的点击。返回 true = 已消费
func handle_click(point: Vector2) -> bool:
	if popup_open:
		if state == "result" and CONFIRM_RECT.has_point(point):
			confirm_result()
		return true
	if main == null or not _hud_visible():
		return false
	if point.distance_to(BTN_CENTER) <= BTN_RADIUS + 8.0:
		if chances > 0:
			open_wheel()
		else: # 次数为 0：按钮置灰、不执行任何抽奖逻辑，只给一声闷响 + 打印
			print("点击抽奖按钮，剩余抽奖次数：0（按钮已置灰，不执行抽奖）")
			Sound.play("click", 0.75, 0.35)
		return true
	return false


## 由 main._process 在游戏真正推进时调用：余额跨线送机会、buff 倒计时、金猪生命周期
func tick(delta: float) -> void:
	if main == null:
		return
	if prev_score < BALANCE_TRIGGER and int(main.score) >= BALANCE_TRIGGER:
		_grant("余额达到 ¥" + str(BALANCE_TRIGGER) + "！")
	prev_score = int(main.score)
	double_left = maxf(0.0, double_left - delta)
	slow_left = maxf(0.0, slow_left - delta)
	fast_left = maxf(0.0, fast_left - delta)
	# 金猪：压扁回弹播完 → 爆金币并移除；一直没人砸 → 到期自己消失
	var remove: Array[int] = []
	for i in range(main.pigs.size()):
		var pig: Dictionary = main.pigs[i]
		if not bool(pig.get("wheel_gold", false)):
			continue
		var sq: float = float(pig.get("gold_squash", 0.0))
		if sq > 0.0:
			pig.gold_squash = sq - delta
			if float(pig.gold_squash) <= 0.0:
				gold_coin_burst(pig.position)
				remove.append(i)
			continue
		var life: float = float(pig.get("gold_life", GOLD_PIG_LIFE)) - delta
		pig.gold_life = life
		if life <= 0.0:
			_vanish_puff(pig.position)
			remove.append(i)
	for i in range(remove.size() - 1, -1, -1):
		main.despawn_pig(remove[i])


## 连续砸中 +1；攒满 12 只换一次转盘机会并清零
func on_landed_hit() -> void:
	streak += 1
	if streak >= STREAK_TRIGGER:
		streak = 0
		_grant("连续砸中 " + str(STREAK_TRIGGER) + " 只小猪！")
	queue_redraw()


## 一旦漏砸（挥空），连续计数清零
func on_missed_swing() -> void:
	if streak > 0:
		streak = 0
		queue_redraw()


func reset_run() -> void:
	chances = 0
	streak = 0
	double_left = 0.0
	slow_left = 0.0
	fast_left = 0.0
	popup_open = false
	state = "closed"
	wheel_rot = 0.0
	spin_t = 0.0
	if main != null:
		prev_score = int(main.score)
	queue_redraw()


## 小猪刷新/移动速度倍率：变慢与变快可叠加（叠乘）
func pig_speed_multiplier() -> float:
	var m := 1.0
	if slow_left > 0.0:
		m *= SLOW_MUL
	if fast_left > 0.0:
		m *= FAST_MUL
	return m


## 得分倍率：与卡片的 double_timer 相互独立，可叠乘
func score_multiplier() -> float:
	return 2.0 if double_left > 0.0 else 1.0


## 转盘金猪的种类描述：体型与普通猪一致（scale 1.0），金色 + 自发光
func gold_pig_type() -> Dictionary:
	return {"id": "wheel_gold", "label": "转盘金猪", "hp": 1, "value": GOLD_PIG_VALUE,
		"speed": 1.0, "scale": 1.0, "glow": true,
		"color": "#ffd76a", "accent": "#e8b23a", "eye": "#5a3a10",
		"blush": "#ffe9a8", "rough": 0.3}


func _grant(reason: String) -> void:
	chances += 1
	btn_pulse = 0.8
	if main != null:
		main.popups.append({"position": Vector2(640, 300), "life": 1.6,
			"text": reason + " 转盘机会 +1", "color": Color("#ffd166")})
	Sound.play("flip", 1.15, 0.8)
	queue_redraw()


func _process(delta: float) -> void:
	if main == null:
		return
	btn_pulse = maxf(0.0, btn_pulse - delta)
	if popup_open and state == "spinning":
		spin_t += delta
		wheel_rot = _spin_angle(minf(spin_t, SPIN_TIME))
		var sec := _sector_under_pointer()
		if sec != _last_sector: # 每划过一个扇形轻响一声，越转越慢时音调渐低
			_last_sector = sec
			var k := clampf(1.0 - spin_t / SPIN_TIME, 0.25, 1.0)
			Sound.play("click", 0.8 + 0.5 * k, 0.3)
		if spin_t >= SPIN_TIME:
			finish_spin()
		queue_redraw()
	elif popup_open or double_left > 0.0 or slow_left > 0.0 or fast_left > 0.0 or _hud_visible():
		queue_redraw()


## 旋转曲线：前 SPIN_ACCEL 秒线性加速到峰值角速度，之后线性减速到 0，总角度正好 spin_target
func _spin_angle(t: float) -> float:
	var vmax := 2.0 * spin_target / SPIN_TIME
	if t <= SPIN_ACCEL:
		return vmax * t * t / (2.0 * SPIN_ACCEL)
	var dt := t - SPIN_ACCEL
	var tail := SPIN_TIME - SPIN_ACCEL
	return vmax * SPIN_ACCEL / 2.0 + vmax * dt - vmax * dt * dt / (2.0 * tail)


func _sector_under_pointer() -> int:
	var local := fposmod(-PI / 2.0 - wheel_rot, TAU)
	return int(local / (TAU / float(SECTOR_COUNT))) % SECTOR_COUNT


## 转到头：对齐、结算、出结果文字（测试也可直接调用跳过动画）
func finish_spin() -> void:
	if not popup_open or state != "spinning":
		return
	state = "result"
	wheel_rot = spin_target
	_apply_result()
	Sound.play("cash", 1.0, 0.9)
	queue_redraw()


func _apply_result() -> void:
	match result_index:
		0:
			main.score += 120
			main.popups.append({"position": Vector2(640, 300), "life": 1.5,
				"text": "转盘 +¥120", "color": Color("#ffd166")})
		1:
			double_left = maxf(double_left, DOUBLE_DURATION)
		2:
			slow_left = maxf(slow_left, SLOW_DURATION)
		3:
			main.pay_bills_free(5)
		4:
			fast_left = maxf(fast_left, FAST_DURATION)
		5:
			main.spawn_wheel_gold_pigs(GOLD_PIG_COUNT)


func _hud_visible() -> bool:
	# 账本摊开时抽奖按钮照常显示并可点（它画在最上层，点击由 main 的账本分支优先派发过来）；
	# 单张账单放大（bill_detail >= 0）仍是模态，按钮照旧隐藏
	if main == null or main.phase != "playing" or main.intro_open or main.bill_detail >= 0:
		return false
	return main.gamble_state != "flip" and main.gamble_state != "result"


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if main == null:
		return
	if popup_open:
		_draw_popup()
		return
	_draw_buff_chips()
	if _hud_visible():
		_draw_button()


func _draw_button() -> void:
	var enabled := chances > 0
	var pulse := 1.0 + 0.14 * (btn_pulse / 0.8) if btn_pulse > 0.0 else 1.0
	var r := BTN_RADIUS * pulse
	var c := BTN_CENTER
	draw_circle(c, r + 7.0, Color(0.09, 0.06, 0.04, 0.85))
	draw_arc(c, r + 7.0, 0.0, TAU, 40, Color("#8a6a3a") if enabled else Color("#5a5148"), 2.5)
	# 迷你转盘：有机会时慢慢自转，置灰时停住
	var rot := fmod(float(main.elapsed) * 0.6, TAU) if enabled else 0.0
	for i in range(SECTOR_COUNT):
		var col := Color(String(SECTORS[i].color))
		if not enabled:
			col = col.lerp(Color("#4a4642"), 0.75)
		_draw_sector(c, r, rot + float(i) * TAU / float(SECTOR_COUNT), TAU / float(SECTOR_COUNT), col)
	draw_circle(c, r * 0.22, Color("#3a2c1c"))
	# 顶部小指针
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-7, -r - 6), c + Vector2(7, -r - 6), c + Vector2(0, -r + 6)]),
		Color("#f4e0b8"))
	# 连砸进度环：从正上方顺时针绕一圈，攒满 12 只就换一次机会
	if streak > 0:
		draw_arc(c, r + 11.0, -PI / 2.0, -PI / 2.0 + TAU * float(streak) / float(STREAK_TRIGGER),
			40, Color("#ffd166"), 3.0)
	var label := "抽奖"
	var w: float = main.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(main.font, Vector2(c.x - w / 2.0, c.y + r + 24.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		Color("#f4e0b8") if enabled else Color("#7d746a"))
	# 次数徽标
	var badge := "×" + str(chances)
	var bw: float = main.font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_circle(c + Vector2(r * 0.8, -r * 0.8), 13.0,
		Color("#c9a227") if enabled else Color("#57504a"))
	draw_string(main.font, c + Vector2(r * 0.8 - bw / 2.0, -r * 0.8 + 5.0), badge,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#fff2d0"))


func _draw_sector(c: Vector2, r: float, a0: float, span: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var steps := 16
	for i in range(steps + 1):
		var a := a0 + span * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)


func _draw_popup() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.02, 0.02, 0.03, 0.55)) # 全屏压暗
	var p := PANEL_RECT
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.05, 0.04, 0.88) # 半透明深色面板
	box.set_corner_radius_all(22)
	box.set_border_width_all(3)
	box.border_color = Color("#8a6a3a")
	draw_style_box(box, p)
	_text_center("幸运转盘", 640.0, 128.0, 30, Color("#f4e0b8"))
	draw_string(main.font, Vector2(p.position.x + 26.0, p.position.y + 40.0),
		"机会 ×" + str(chances), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#c9b08a"))
	# 转盘本体：六个等分扇形，跟着 wheel_rot 一起转
	draw_circle(WHEEL_CENTER, WHEEL_RADIUS + 14.0, Color(0.0, 0.0, 0.0, 0.4))
	for i in range(SECTOR_COUNT):
		var s: Dictionary = SECTORS[i]
		var col := Color(String(s.color))
		if state == "result" and i == result_index:
			col = col.lightened(0.22) # 高亮抽中的扇形
		_draw_sector(WHEEL_CENTER, WHEEL_RADIUS,
			wheel_rot + float(i) * TAU / float(SECTOR_COUNT), TAU / float(SECTOR_COUNT), col)
	for i in range(SECTOR_COUNT):
		var a := wheel_rot + float(i) * TAU / float(SECTOR_COUNT)
		draw_line(WHEEL_CENTER, WHEEL_CENTER + Vector2(cos(a), sin(a)) * WHEEL_RADIUS,
			Color(0.12, 0.08, 0.05, 0.8), 2.0)
	draw_arc(WHEEL_CENTER, WHEEL_RADIUS, 0.0, TAU, 72, Color("#3a2c1c"), 8.0)
	draw_arc(WHEEL_CENTER, WHEEL_RADIUS + 4.0, 0.0, TAU, 72, Color("#8a6a3a"), 2.5)
	# 扇形里的奖励文字：沿半径方向立着写，跟转盘一起转
	for i in range(SECTOR_COUNT):
		var mid := wheel_rot + (float(i) + 0.5) * TAU / float(SECTOR_COUNT)
		var label := String(SECTORS[i].label)
		var w: float = main.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lp := WHEEL_CENTER + Vector2(cos(mid), sin(mid)) * WHEEL_RADIUS * 0.62
		draw_set_transform(lp, mid + PI / 2.0, Vector2.ONE)
		draw_string(main.font, Vector2(-w / 2.0, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color("#fff8e8"))
		draw_set_transform(Vector2.ZERO)
	# 中心转轴
	draw_circle(WHEEL_CENTER, 30.0, Color("#2c2115"))
	draw_circle(WHEEL_CENTER, 24.0, Color("#c9a227"))
	draw_circle(WHEEL_CENTER, 10.0, Color("#5a4318"))
	draw_arc(WHEEL_CENTER, 24.0, 0.0, TAU, 40, Color("#ffe9a0"), 2.0)
	# 固定不动的三角指针：指向哪个扇形就是哪个结果
	draw_colored_polygon(PackedVector2Array([Vector2(620, 140), Vector2(660, 140), Vector2(640, 178)]),
		Color("#f4e0b8"))
	draw_colored_polygon(PackedVector2Array([Vector2(626, 143), Vector2(654, 143), Vector2(640, 170)]),
		Color("#c23b2e"))
	# 结果区
	if state == "spinning":
		_text_center("转动中……", 640.0, 612.0, 22, Color("#c9b08a"))
	else:
		var s: Dictionary = SECTORS[result_index]
		_text_center("★ " + String(s.label) + " ★", 640.0, 608.0, 27, Color("#ffd166"))
		_text_center(String(s.desc), 640.0, 636.0, 16, Color("#c9b08a"))
		var hover: bool = CONFIRM_RECT.has_point(get_global_mouse_position())
		var bcol := Color("#d49f59") if hover else Color("#b98a4c")
		draw_style_box(_button_box(bcol), CONFIRM_RECT)
		_text_center("确认", CONFIRM_RECT.get_center().x, CONFIRM_RECT.position.y + 34.0, 22,
			Color("#241610"))
	_text_center("余额达到 ¥500 或连续砸中 12 只小猪，均可再获得一次机会", 640.0, 706.0, 13,
		Color("#8f7a5e"))


func _draw_buff_chips() -> void:
	var chips: Array[Dictionary] = []
	if double_left > 0.0:
		chips.append({"text": "得分×2 " + str(int(ceilf(double_left))) + "s", "color": Color("#ffd166")})
	if slow_left > 0.0:
		chips.append({"text": "小猪变慢 " + str(int(ceilf(slow_left))) + "s", "color": Color("#6fb3e8")})
	if fast_left > 0.0:
		chips.append({"text": "小猪变快 " + str(int(ceilf(fast_left))) + "s", "color": Color("#c58ae0")})
	if chips.is_empty():
		return
	var total := 0.0
	var widths: Array[float] = []
	for ch in chips:
		var w: float = main.font.get_string_size(String(ch.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 30.0
		widths.append(w)
		total += w + 8.0
	var x := 640.0 - total / 2.0 + 4.0
	for i in range(chips.size()):
		var ch: Dictionary = chips[i]
		var col: Color = ch.color
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.06, 0.05, 0.8)
		box.set_corner_radius_all(11)
		box.set_border_width_all(2)
		box.border_color = col
		draw_style_box(box, Rect2(x, 40.0, widths[i], 26.0))
		draw_string(main.font, Vector2(x + 15.0, 58.0), String(ch.text),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		x += widths[i] + 8.0


func _button_box(col: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.set_corner_radius_all(12)
	return box


func _text_center(value: String, center_x: float, y: float, size: int, color: Color) -> void:
	var w: float = main.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(main.font, Vector2(center_x - w / 2.0, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1,
		size, color)


# ---------------------------------------------------------------- 金币爆散特效

## 金猪被砸碎时：GPUParticles2D 火花/闪光 + Tween 驱动的弹跳金币 + 金币音效
func gold_coin_burst(pos: Vector2) -> void:
	Sound.play("pop", 0.8, 0.7)
	Sound.play("cash", randf_range(1.0, 1.5), 0.9)
	Sound.play("coin_land", randf_range(0.85, 1.2), 0.9)
	_spawn_burst_particles(pos, 46, Color("#ffd76a"), 240.0, 540.0, Vector3(0, 720, 0), 0.9)
	# 闪光粒子：更轻、更快、白光
	_spawn_burst_particles(pos, 22, Color("#fff6d8"), 320.0, 620.0, Vector3(0, 260, 0), 0.5)
	_flash(pos)
	for i in range(10):
		_bounce_coin(pos)


func _spawn_burst_particles(pos: Vector2, amount: int, color: Color, v_min: float, v_max: float,
		gravity: Vector3, life: float) -> void:
	if _fx_nodes > FX_NODE_CAP:
		return
	var gp := GPUParticles2D.new()
	gp.position = pos
	gp.amount = amount
	gp.lifetime = life
	gp.one_shot = true
	gp.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 62.0
	mat.initial_velocity_min = v_min
	mat.initial_velocity_max = v_max
	mat.gravity = gravity
	mat.scale_min = 0.45
	mat.scale_max = 1.15
	mat.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var gtex := GradientTexture1D.new()
	gtex.gradient = ramp
	mat.color_ramp = gtex
	gp.process_material = mat
	gp.texture = _spark_texture()
	add_child(gp)
	_fx_nodes += 1
	gp.emitting = true
	# 一次性粒子放完就清掉；不用 finished 信号，定时兜底在低版本引擎上更稳
	get_tree().create_timer(life + 1.0).timeout.connect(_free_fx.bind(gp))


## 闪光：一圈白光迅速放大淡出
func _flash(pos: Vector2) -> void:
	if _fx_nodes > FX_NODE_CAP:
		return
	var sp := Sprite2D.new()
	sp.texture = _spark_texture()
	sp.position = pos
	sp.modulate = Color(1.0, 0.95, 0.7, 0.9)
	sp.scale = Vector2.ONE * 2.0
	add_child(sp)
	_fx_nodes += 1
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector2.ONE * 9.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(_free_fx.bind(sp))


## 一枚弹跳金币：向上飞溅 → 落下 → 压扁回弹 → 再弹两次（逐次衰减）→ 淡出
func _bounce_coin(pos: Vector2) -> void:
	if _fx_nodes > FX_NODE_CAP:
		return
	var coin := Sprite2D.new()
	coin.texture = _coin_texture()
	coin.position = pos
	add_child(coin)
	_fx_nodes += 1
	var floor_y := pos.y + randf_range(24.0, 52.0)
	var drift := randf_range(60.0, 200.0)
	if randf() < 0.5:
		drift = -drift
	var h := randf_range(90.0, 160.0)
	var dur := randf_range(0.30, 0.38)
	var x := pos.x
	var tw := coin.create_tween()
	for i in range(3):
		var peak := Vector2(x + drift * dur * 0.5, floor_y - h)
		x += drift * dur
		var land := Vector2(x, floor_y)
		tw.tween_property(coin, "position", peak, dur * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(coin, "position", land, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(coin, "scale", Vector2(1.28, 0.66), 0.05) # 落地压扁
		tw.tween_property(coin, "scale", Vector2.ONE, 0.07) # 回弹
		h *= 0.45
		dur *= 0.82
	tw.tween_property(coin, "modulate:a", 0.0, 0.25)
	tw.tween_callback(_free_fx.bind(coin))
	# 空中打转：整枚金币慢慢翻滚
	var spin := coin.create_tween()
	spin.tween_property(coin, "rotation", randf_range(-6.0, 6.0), 1.3)
	get_tree().create_timer(3.2).timeout.connect(_free_fx.bind(coin))


## 金猪到期没被砸中：一小蓬暗金色碎光，悄悄退场
func _vanish_puff(pos: Vector2) -> void:
	Sound.play("miss", 1.0, 0.35)
	_spawn_burst_particles(pos, 12, Color("#d8c07a"), 60.0, 160.0, Vector3(0, 300, 0), 0.55)


func _free_fx(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_fx_nodes -= 1
	node.queue_free()


func _spark_texture() -> Texture2D:
	if _spark_tex != null:
		return _spark_tex
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(c) / float(size / 2)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


func _coin_texture() -> Texture2D:
	if _coin_tex != null:
		return _coin_tex
	var size := 36
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d > 16.0:
				continue
			var col := Color("#f7c94b")
			if d > 13.5:
				col = Color("#b9821f")
			elif d < 6.0:
				col = Color("#ffe9a0")
			img.set_pixel(x, y, col)
	_coin_tex = ImageTexture.create_from_image(img)
	return _coin_tex
