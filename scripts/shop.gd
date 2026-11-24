extends Node2D
## 商店 / 背包 / 快捷栏 / 技能 / 锤子 系统（低侵入扩展层）
## 作为 main 的最上层子节点挂载，负责全部数据与 UI；main 只调少量查询/钩子接口。
## 货币统一用 main.score（余额）。

const SHOP_PATH := "res://data/shop.json"
const Icons3DScript := preload("res://scripts/shop_icons_3d.gd")

# 面板几何
const SHOP_TITLE_POS := Vector2(640, 100)          # 标题中心
const SHOP_TABS := [Rect2(455, 148, 185, 48), Rect2(660, 148, 185, 48)]  # 锤子区 / 技能区
const SHOP_SHELF := Rect2(150, 210, 980, 350)      # 货架外框
const SHOP_CELLS := [Rect2(170, 230, 300, 310), Rect2(490, 230, 300, 310), Rect2(810, 230, 300, 310)]  # 3 格
const SHOP_DIVIDERS := [Rect2(466, 212, 24, 346), Rect2(786, 212, 24, 346)]  # 隔板
const SHOP_CLOSE := Rect2(540, 686, 200, 52)
const BACKPACK_PANEL := Rect2(240, 150, 800, 470)
const BACKPACK_CLOSE := Rect2(540, 596, 200, 46)

# 背包面板内槽位
const BP_SLOTS := [Rect2(340, 230, 120, 140), Rect2(480, 230, 120, 140), Rect2(620, 230, 120, 140)]
const QB_SLOTS := [Rect2(340, 410, 120, 140), Rect2(480, 410, 120, 140), Rect2(620, 410, 120, 140)]

# 快捷栏 HUD（平时常驻，右上角）
const QB_HUD := [Rect2(990, 128, 48, 48), Rect2(1044, 128, 48, 48), Rect2(1098, 128, 48, 48)]

var main = null
var data: Dictionary = {}

var shop_open := false
var backpack_open := false

var hammer_stock: Array = []   # 锤子区固定目录（hammer_pool，常驻不售罄）
var skill_stock: Array = []    # 技能区固定目录（skill_pool，常驻不售罄）
var box_stock := true
var shop_tab := 0  # 当前商店标签：0=锤子区, 1=技能区

var current_hammer_id := "iron"

var backpack: Array = []        # 技能实例 Dictionary（未装配）
var quickbar: Array = [null, null, null]  # 快捷栏 3 槽，技能实例或 null

# 本局 buff
var damage_bonus_pct := 0.0
var triple_kills := 0
var triple_mult := 3.0

# 技能全局效果计时（重复释放仅刷新，不叠加）
var slow_active := 0.0
var abacus_active := 0.0

# 拖拽
var dragging := false
var drag_kind := ""
var drag_idx := -1

# 提示
var notice := ""
var notice_timer := 0.0

# 测试用：盲盒结果覆写（>=0 时强制取 box_pool 该下标）
var box_result_override := -1

# 3D 模型图标渲染器（模型缺失时 get_texture 返回 null，自动回退占位图）
var icons_3d = null


func setup(host) -> void:
	main = host
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SHOP_PATH))
	data = raw if raw is Dictionary else {}
	if not data.has("hammers"):
		data["hammers"] = {
			"iron": {"name": "普通铁锤", "hits": 1, "damage": 1.0, "radius": 1.0, "desc": "基础铁锤", "accent": "#c9c9cf"},
			"dual": {"name": "连打锤", "hits": 2, "damage": 0.65, "radius": 1.0, "desc": "连砸 2 次", "accent": "#ff8c3a"},
			"gravity": {"name": "重力锤", "charge": true, "charge_time": 1.0, "damage_min": 1.0, "damage_max": 3.0, "radius": 1.0, "radius_max": 1.6, "stun": 0.45, "desc": "长按蓄力", "accent": "#8b5cf6"},
			"magnet": {"name": "磁吸锤", "damage": 1.0, "radius": 1.0, "pull_radius": 150.0, "falloff_min": 0.4, "desc": "吸附小猪", "accent": "#4f8ef7"},
		}
	if not data.has("hammer_pool"):
		data["hammer_pool"] = ["dual", "gravity", "magnet"]
	if not data.has("skill_pool"):
		data["skill_pool"] = ["hourglass", "abacus"]
	if not data.has("box_pool"):
		data["box_pool"] = [{"type": "coins", "weight": 1, "amount": 25}]
	# 挂载 3D 图标渲染器：shop.json 里 model 路径为空时零开销、不影响占位图
	icons_3d = Icons3DScript.new()
	add_child(icons_3d)
	icons_3d.setup(self, data)
	reset_run()


func reset_run() -> void:
	shop_open = false
	backpack_open = false
	hammer_stock = (data.get("hammer_pool", []) as Array).duplicate()
	skill_stock = (data.get("skill_pool", []) as Array).duplicate()
	box_stock = true
	shop_tab = 0
	current_hammer_id = "iron"
	backpack.clear()
	quickbar = [null, null, null]
	damage_bonus_pct = 0.0
	triple_kills = 0
	triple_mult = 3.0
	slow_active = 0.0
	abacus_active = 0.0
	dragging = false
	drag_kind = ""
	drag_idx = -1
	notice = ""
	notice_timer = 0.0
	box_result_override = -1
	queue_redraw()


func is_open() -> bool:
	return shop_open or backpack_open


# ---------- 商店 / 背包开关 ----------

func try_open_shop() -> void:
	if shop_open:
		shop_open = false
	else:
		shop_open = true
		backpack_open = false
		shop_tab = 0 # 打开商店默认进入锤子区
	queue_redraw()


func try_open_backpack() -> void:
	if backpack_open:
		backpack_open = false
	else:
		backpack_open = true
		shop_open = false
	queue_redraw()


func close_all() -> void:
	shop_open = false
	backpack_open = false
	queue_redraw()


func _set_tab(tab: int) -> void:
	shop_tab = clampi(tab, 0, 1)
	queue_redraw()


# ---------- 查询接口（main 调用） ----------

func current_hammer() -> Dictionary:
	var hammers: Dictionary = data.get("hammers", {})
	return hammers.get(current_hammer_id, hammers.get("iron", {}))


func hammer_base_damage() -> float:
	return float(current_hammer().get("damage", 1.0))


func hammer_damage_mul() -> float:
	return 1.0 + damage_bonus_pct


func pull_radius() -> float:
	return float(current_hammer().get("pull_radius", 150.0))


func falloff_min() -> float:
	return float(current_hammer().get("falloff_min", 0.4))


func is_gravity() -> bool:
	return current_hammer_id == "gravity"


func speed_mul() -> float:
	if slow_active > 0.0:
		return float(data.get("skills", {}).get("hourglass", {}).get("slow_mul", 0.4))
	return 1.0


func score_mul() -> float:
	if abacus_active > 0.0:
		return float(data.get("skills", {}).get("abacus", {}).get("score_mul", 2.0))
	return 1.0


func kill_bonus_mul() -> float:
	return triple_mult if triple_kills > 0 else 1.0


func consume_kill() -> void:
	if triple_kills > 0:
		triple_kills -= 1


func skill_name(id: String) -> String:
	return String(data.get("skills", {}).get(id, {}).get("name", id))


func hammer_name(id: String) -> String:
	return String(data.get("hammers", {}).get(id, {}).get("name", id))


# ---------- 技能 ----------

func _make_skill(id: String) -> Dictionary:
	var cd: float = float(data.get("skills", {}).get(id, {}).get("cooldown", 10.0))
	return {"id": id, "cd": 0.0, "cd_max": cd}


func try_activate_skill(slot: int) -> void:
	if slot < 0 or slot >= quickbar.size():
		return
	var item = quickbar[slot]
	if item == null or not (item is Dictionary):
		return
	if float(item.get("cd", 0.0)) > 0.0:
		return
	var id := String(item.get("id", ""))
	var def: Dictionary = data.get("skills", {}).get(id, {})
	var cd: float = float(def.get("cooldown", 10.0))
	var dur: float = float(def.get("duration", 2.5))
	item["cd"] = cd
	if id == "hourglass":
		slow_active = maxf(slow_active, dur)
		Sound.play("flip")
		_notice("凝时沙漏：全场小猪移速降至 40%")
	elif id == "abacus":
		abacus_active = maxf(abacus_active, dur)
		Sound.play("cash")
		_notice("鎏金算筹：击杀得分 ×2")
	queue_redraw()


func tick(delta: float) -> void:
	slow_active = maxf(0.0, slow_active - delta)
	abacus_active = maxf(0.0, abacus_active - delta)
	for item in backpack:
		if item is Dictionary:
			item["cd"] = maxf(0.0, float(item.get("cd", 0.0)) - delta)
	for item in quickbar:
		if item is Dictionary:
			item["cd"] = maxf(0.0, float(item.get("cd", 0.0)) - delta)
	notice_timer = maxf(0.0, notice_timer - delta)


# ---------- 购买 ----------

func buy_hammer(index: int) -> void:
	if not shop_open or index < 0 or index >= hammer_stock.size():
		return
	if hammer_stock[index] == "":
		return
	var price: int = int(data.get("hammer_price", 220))
	if main.score < price:
		_notice("金币不足")
		return
	main.score -= price
	current_hammer_id = String(hammer_stock[index])
	_notice("已装备「" + hammer_name(current_hammer_id) + "」")
	Sound.play("cash")
	queue_redraw()


func buy_skill(index: int) -> void:
	if not shop_open or index < 0 or index >= skill_stock.size():
		return
	if skill_stock[index] == "":
		return
	var price: int = int(data.get("skill_price", 180))
	var capacity: int = int(data.get("backpack_capacity", 3))
	if main.score < price:
		_notice("金币不足")
		return
	if backpack.size() >= capacity:
		_notice("背包已满，无法购买该技能道具")
		return
	var sid := String(skill_stock[index])
	main.score -= price
	backpack.append(_make_skill(sid))
	_notice("已购买「" + skill_name(sid) + "」")
	Sound.play("cash")
	queue_redraw()


func buy_box() -> void:
	if not shop_open or not box_stock:
		return
	var price: int = int(data.get("box_price", 200))
	if main.score < price:
		_notice("金币不足")
		return
	main.score -= price
	_roll_box() # 盲盒购买后立即补位（box_stock 保持 true，可继续购买）
	queue_redraw()


func _roll_box() -> void:
	var pool: Array = data.get("box_pool", [])
	if pool.is_empty():
		return
	var idx := box_result_override
	if idx < 0 or idx >= pool.size():
		idx = _weighted_pick(pool)
	var reward: Dictionary = pool[idx]
	match String(reward.get("type", "")):
		"hammer":
			var hp: Array = data.get("hammer_pool", [])
			if not hp.is_empty():
				current_hammer_id = String(hp[randi() % hp.size()])
				_notice("盲盒开出「" + hammer_name(current_hammer_id) + "」！已装备")
				Sound.play("crit")
		"skill":
			var capacity: int = int(data.get("backpack_capacity", 3))
			if backpack.size() >= capacity:
				_notice("盲盒开出技能，但背包已满，奖励作废")
			else:
				var sp: Array = data.get("skill_pool", [])
				if not sp.is_empty():
					var sid := String(sp[randi() % sp.size()])
					backpack.append(_make_skill(sid))
					_notice("盲盒开出「" + skill_name(sid) + "」！已入背包")
					Sound.play("cash")
		"coins":
			var amt: int = int(reward.get("amount", 25))
			main.score += amt
			_notice("盲盒开出 +" + str(amt) + " 金币")
			Sound.play("cash")
		"damage_up":
			damage_bonus_pct = float(reward.get("pct", 0.15))
			_notice("盲盒开出：本局锤子伤害 +15%")
			Sound.play("crit")
		"triple_kill":
			triple_kills = int(reward.get("kills", 3))
			triple_mult = float(reward.get("mult", 3.0))
			_notice("盲盒开出：接下来 3 次击杀分数 ×3")
			Sound.play("crit")


func _weighted_pick(pool: Array) -> int:
	var total := 0.0
	for r in pool:
		total += float(r.get("weight", 1.0))
	var roll := randf() * total
	for i in range(pool.size()):
		roll -= float(pool[i].get("weight", 1.0))
		if roll <= 0.0:
			return i
	return pool.size() - 1


# ---------- 拖拽 ----------

func move_item(from_kind: String, from_idx: int, to_kind: String, to_idx: int) -> void:
	if from_kind == to_kind:
		return
	var capacity: int = int(data.get("backpack_capacity", 3))
	if from_kind == "backpack":
		if from_idx < 0 or from_idx >= backpack.size():
			return
		var item = backpack[from_idx]
		var displaced = quickbar[to_idx]
		backpack.remove_at(from_idx)
		if displaced != null:
			backpack.insert(mini(from_idx, backpack.size()), displaced)
		quickbar[to_idx] = item
	else:
		var item = quickbar[from_idx]
		if item == null:
			return
		if backpack.size() >= capacity:
			_notice("背包已满")
			return
		backpack.insert(mini(to_idx, backpack.size()), item)
		quickbar[from_idx] = null
	queue_redraw()


# ---------- 输入分发（main 在 shop 打开时转发） ----------

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(get_global_mouse_position())
		else:
			_on_release(get_global_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T: try_open_shop()
			KEY_I: try_open_backpack()
			KEY_ESCAPE: close_all()
	queue_redraw()


func handle_click(point: Vector2) -> void:
	_on_press(point)
	_on_release(point)
	queue_redraw()


func _on_press(point: Vector2) -> void:
	dragging = false
	drag_kind = ""
	drag_idx = -1
	if backpack_open:
		var slot := _slot_at(point)
		if slot != null and _slot_item(slot) != null:
			dragging = true
			drag_kind = slot["kind"]
			drag_idx = slot["idx"]


func _on_release(point: Vector2) -> void:
	if shop_open:
		if SHOP_CLOSE.has_point(point):
			try_open_shop()
			return
		for i in range(SHOP_TABS.size()):
			if SHOP_TABS[i].has_point(point):
				_set_tab(i)
				return
		for i in range(SHOP_CELLS.size()):
			if SHOP_CELLS[i].has_point(point):
				_buy_cell(i)
				return
	elif backpack_open:
		if BACKPACK_CLOSE.has_point(point):
			try_open_backpack()
			return
		if dragging:
			var slot := _slot_at(point)
			if slot != null:
				move_item(drag_kind, drag_idx, String(slot["kind"]), int(slot["idx"]))
			dragging = false
			drag_kind = ""
			drag_idx = -1
			return


func _buy_cell(index: int) -> void:
	if shop_tab == 0:
		buy_hammer(index)
	elif index < 2:
		buy_skill(index)
	else:
		buy_box()


func _slot_at(point: Vector2) -> Dictionary:
	for i in range(BP_SLOTS.size()):
		if BP_SLOTS[i].has_point(point):
			return {"kind": "backpack", "idx": i}
	for i in range(QB_SLOTS.size()):
		if QB_SLOTS[i].has_point(point):
			return {"kind": "quickbar", "idx": i}
	return {}


func _slot_item(slot: Dictionary) -> Variant:
	var kind := String(slot.get("kind", ""))
	var idx := int(slot.get("idx", -1))
	if kind == "backpack":
		if idx >= 0 and idx < backpack.size():
			return backpack[idx]
		return null
	if idx >= 0 and idx < quickbar.size():
		return quickbar[idx]
	return null


func _notice(text: String) -> void:
	notice = text
	notice_timer = 1.8


# ---------- 绘制 ----------

func _process(_delta: float) -> void:
	if shop_open or backpack_open:
		queue_redraw()
	elif main != null and main.phase == "playing" and not main.intro_open:
		queue_redraw()


func _draw() -> void:
	if main == null:
		return
	if main.phase == "playing" and not main.intro_open and not shop_open and not backpack_open:
		_draw_quickbar_hud()
	if shop_open:
		_draw_shop()
	if backpack_open:
		_draw_backpack()
	if notice_timer > 0.0 and notice != "":
		_text_center(notice, 640, 736, 20, Color("#ffe092"))


# 绘制辅助
func _text(value: String, pos: Vector2, size: int, color := Color("#f4e0b8")) -> void:
	draw_string(main.font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_center(value: String, cx: float, y: float, size: int, color := Color("#f4e0b8")) -> void:
	var w: float = main.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(cx - w / 2.0, y), size, color)


func _panel(rect: Rect2, color: Color, radius := 12, border := 0, border_color := Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border > 0:
		style.set_border_width_all(border)
		style.border_color = border_color
	draw_style_box(style, rect)


func _button(rect: Rect2, label: String, active := true, color := Color("#d49f59")) -> void:
	var col: Color = color if active else Color("#454b4c")
	var hovered: bool = active and rect.has_point(get_local_mouse_position())
	if hovered:
		col = col.lightened(0.16)
	_panel(rect, col, 12, 2 if hovered else 0, Color("#fff2d0"))
	var fs := 21
	var center := rect.get_center()
	var baseline: float = center.y + (main.font.get_ascent(fs) - main.font.get_descent(fs)) * 0.5
	_text_center(label, center.x, baseline, fs, Color("#252c2b"))


func _draw_quickbar_hud() -> void:
	for i in range(QB_HUD.size()):
		var rect: Rect2 = QB_HUD[i]
		var item = quickbar[i]
		if item == null or not (item is Dictionary):
			_panel(rect, Color(0.05, 0.07, 0.07, 0.55), 8, 1, Color("#4a443c"))
			_text_center(str(i + 1), rect.get_center().x, rect.get_center().y + 6, 16, Color("#6d675c"))
			continue
		var cooling: bool = float(item.get("cd", 0.0)) > 0.0
		_panel(rect, Color(0.08, 0.06, 0.05, 0.9), 8, 2, Color("#8a6a3a") if not cooling else Color("#4a443c"))
		_draw_skill_icon(rect.get_center(), 20, String(item.get("id", "")))
		if cooling:
			draw_rect(rect.grow(-2), Color(0, 0, 0, 0.55))
			_text_center(str(int(ceilf(float(item.get("cd", 0.0))))), rect.get_center().x, rect.get_center().y + 6, 15, Color("#e7a6a4"))


func _draw_shop() -> void:
	# 深色外围背景
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.03, 0.02, 0.015, 0.78))
	# 顶部：标题（居中）+ 金币（右侧，禁用 ¥ 与「余额」字样）
	_text_center("道具商店", SHOP_TITLE_POS.x, SHOP_TITLE_POS.y, 42, Color("#efbc72"))
	_draw_coin(Vector2(1000, SHOP_TITLE_POS.y), 15)
	_text("金币：" + str(main.score), Vector2(1026, SHOP_TITLE_POS.y + 9), 23, Color("#ffe092"))
	# 切换标签
	for i in range(SHOP_TABS.size()):
		_draw_tab(SHOP_TABS[i], i)
	# 木质货架
	_draw_shelf()
	# 悬停气泡
	_draw_tooltip()
	# 关闭按钮
	_button(SHOP_CLOSE, "关闭商店", true, Color("#c98d4e"))


func _draw_backpack() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.03, 0.02, 0.015, 0.72))
	_panel(BACKPACK_PANEL, Color("#2b1c11"), 18)
	_text_center("背包 · 技能道具", 640, 186, 26, Color("#efbc72"))
	_text_center("背包（未装配，容量 " + str(int(data.get("backpack_capacity", 3))) + "）", 640, 216, 16, Color("#c9b08a"))
	for i in range(BP_SLOTS.size()):
		_draw_slot(BP_SLOTS[i], "backpack", i)
	_text_center("快捷栏（拖入后按 1 / 2 / 3 释放）", 640, 396, 16, Color("#c9b08a"))
	for i in range(QB_SLOTS.size()):
		_draw_slot(QB_SLOTS[i], "quickbar", i)
	_button(BACKPACK_CLOSE, "关闭背包")


func _draw_coin(c: Vector2, r: float) -> void:
	# 纯金币图标：圆环 + 高光，不使用任何货币符号
	draw_circle(c, r, Color("#7a4d17"))
	draw_circle(c, r * 0.84, Color("#f2c14e"))
	draw_arc(c, r * 0.55, 0, TAU, 28, Color("#b8862b"), 2.5)
	draw_circle(c + Vector2(-r * 0.28, -r * 0.28), r * 0.18, Color(1.0, 0.92, 0.6, 0.7))


func _draw_tab(rect: Rect2, index: int) -> void:
	# 选中标签高亮，未选中淡化
	var selected: bool = shop_tab == index
	var label := "锤子区" if index == 0 else "技能区"
	var fs := 22
	var baseline: float = rect.get_center().y + (main.font.get_ascent(fs) - main.font.get_descent(fs)) * 0.5
	if selected:
		_panel(rect, Color("#7a5230"), 12, 2, Color("#efbc72"))
		_text_center(label, rect.get_center().x, baseline, fs, Color("#ffe9bd"))
	else:
		_panel(rect, Color(0.16, 0.11, 0.07, 0.85), 12)
		_text_center(label, rect.get_center().x, baseline, fs, Color("#8a7a60"))


func _draw_shelf() -> void:
	# 复古分层棕木纹货架：背板 + 木纹横线 + 顶/底厚木板 + 隔板
	_panel(SHOP_SHELF, Color("#4a3018"), 16, 4, Color("#7a5230"))
	for i in range(7):
		var y: float = SHOP_SHELF.position.y + 34 + i * 47
		draw_line(Vector2(SHOP_SHELF.position.x + 16, y), Vector2(SHOP_SHELF.end.x - 16, y), Color(0.26, 0.16, 0.08, 0.45), 2.0)
	_panel(Rect2(SHOP_SHELF.position.x, SHOP_SHELF.position.y, SHOP_SHELF.size.x, 14), Color("#5d3d21"), 10)
	_panel(Rect2(SHOP_SHELF.position.x, SHOP_SHELF.end.y - 18, SHOP_SHELF.size.x, 18), Color("#3d2715"), 8)
	for d in SHOP_DIVIDERS:
		_panel(d, Color("#5d3d21"), 8, 1, Color("#7a5532"))
	for i in range(SHOP_CELLS.size()):
		if shop_tab == 0:
			_draw_shelf_hammer(SHOP_CELLS[i], i)
		elif i < 2:
			_draw_shelf_skill(SHOP_CELLS[i], i)
		else:
			_draw_shelf_box(SHOP_CELLS[i])


func _icon_shadow(ic: Vector2) -> void:
	# 图标下方投影，模拟道具摆在木架上
	_panel(Rect2(ic.x - 46, ic.y + 34, 92, 15), Color(0, 0, 0, 0.35), 8)


func _draw_shelf_hammer(cell: Rect2, index: int) -> void:
	var id := String(hammer_stock[index])
	var def: Dictionary = data.get("hammers", {}).get(id, {})
	var price: int = int(data.get("hammer_price", 220))
	var affordable: bool = main.score >= price
	var accent := Color(String(def.get("accent", "#ffffff")))
	var ic := Vector2(cell.get_center().x, 322)
	_icon_shadow(ic)
	_draw_hammer_icon(ic, 46, id, accent)
	_text_center(String(def.get("name", "")), cell.get_center().x, 420, 22, Color("#ffe9bd"))
	_buy_button(Rect2(cell.position.x + 55, cell.end.y - 62, 190, 46), price, affordable)


func _draw_shelf_skill(cell: Rect2, index: int) -> void:
	var id := String(skill_stock[index])
	var def: Dictionary = data.get("skills", {}).get(id, {})
	var price: int = int(data.get("skill_price", 180))
	var full: bool = backpack.size() >= int(data.get("backpack_capacity", 3))
	var affordable: bool = main.score >= price and not full
	var ic := Vector2(cell.get_center().x, 322)
	_icon_shadow(ic)
	_draw_skill_icon(ic, 46, id)
	_text_center(String(def.get("name", "")), cell.get_center().x, 420, 22, Color("#ffe9bd"))
	_buy_button(Rect2(cell.position.x + 55, cell.end.y - 62, 190, 46), price, affordable)


func _draw_shelf_box(cell: Rect2) -> void:
	var price: int = int(data.get("box_price", 200))
	var affordable: bool = main.score >= price
	var ic := Vector2(cell.get_center().x, 322)
	_icon_shadow(ic)
	_draw_box_icon(ic, 50)
	_text_center(String(data.get("box", {}).get("name", "神秘盲盒")), cell.get_center().x, 420, 22, Color("#ffe9bd"))
	_buy_button(Rect2(cell.position.x + 55, cell.end.y - 62, 190, 46), price, affordable)


func _buy_button(rect: Rect2, price: int, affordable: bool) -> void:
	# 金币充足：绿色渐变（底 + 顶部高光）可点击；不足：灰色置灰、文字淡化
	var fs := 19
	var baseline: float = rect.get_center().y + (main.font.get_ascent(fs) - main.font.get_descent(fs)) * 0.5
	var label := "购买 " + str(price) + " 金币"
	if affordable:
		var base := Color("#3e8e41")
		if rect.has_point(get_local_mouse_position()):
			base = base.lightened(0.14)
		_panel(rect, base, 10)
		_panel(Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, rect.size.y * 0.45), Color(1, 1, 1, 0.16), 8)
		_text_center(label, rect.get_center().x, baseline, fs, Color("#f2fff0"))
	else:
		_panel(rect, Color("#383b3a"), 10)
		_text_center(label, rect.get_center().x, baseline, fs, Color("#83878a"))


func _cell_tip(index: int) -> String:
	if shop_tab == 0:
		var hid := String(hammer_stock[index]) if index < hammer_stock.size() else ""
		return String(data.get("hammers", {}).get(hid, {}).get("tip", ""))
	if index < 2:
		var sid := String(skill_stock[index]) if index < skill_stock.size() else ""
		return String(data.get("skills", {}).get(sid, {}).get("tip", ""))
	return String(data.get("box", {}).get("tip", ""))


func _wrap_text(text: String, size: int, max_width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for ch in text:
		if ch == "\n":
			lines.append(current)
			current = ""
			continue
		if current != "" and main.font.get_string_size(current + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
			lines.append(current)
			current = ch
		else:
			current += ch
	if current != "":
		lines.append(current)
	return lines


func _draw_tooltip() -> void:
	# 悬浮格子 -> 深色半透明圆角气泡 + 向上箭头，移开自动消失（每帧重绘检测鼠标）
	var mouse := get_local_mouse_position()
	var hovered := -1
	for i in range(SHOP_CELLS.size()):
		if SHOP_CELLS[i].has_point(mouse):
			hovered = i
			break
	if hovered < 0:
		return
	var tip := _cell_tip(hovered)
	if tip == "":
		return
	var fs := 14
	var lines := _wrap_text(tip, fs, 300)
	var pad := 16
	var line_h: float = main.font.get_ascent(fs) + main.font.get_descent(fs) + 6
	var bw: float = 332.0
	var bh: float = lines.size() * line_h + pad * 2
	var cell: Rect2 = SHOP_CELLS[hovered]
	var cx: float = clampf(cell.get_center().x, bw * 0.5 + 10, 1280.0 - bw * 0.5 - 10)
	var rect := Rect2(cx - bw / 2.0, cell.end.y + 14, bw, bh)
	var bg := Color(0.07, 0.06, 0.05, 0.92)
	var ax: float = clampf(cell.get_center().x, rect.position.x + 16, rect.end.x - 16)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ax - 9, rect.position.y + 2),
		Vector2(ax + 9, rect.position.y + 2),
		Vector2(ax, rect.position.y - 10),
	]), bg)
	_panel(rect, bg, 12, 1, Color("#8a6a3a"))
	var ty: float = rect.position.y + pad + main.font.get_ascent(fs)
	for line in lines:
		_text(line, Vector2(rect.position.x + pad, ty), fs, Color("#f0e2c8"))
		ty += line_h


func _draw_slot(rect: Rect2, kind: String, index: int) -> void:
	var item: Variant = null
	if kind == "backpack":
		if index < backpack.size():
			item = backpack[index]
	else:
		item = quickbar[index]
	if item == null or not (item is Dictionary):
		_panel(rect, Color("#241c14"), 10, 1, Color("#4a443c"))
		_text_center(str(index + 1), rect.get_center().x, rect.get_center().y + 8, 18, Color("#6d675c"))
		return
	var cooling: bool = float(item.get("cd", 0.0)) > 0.0
	_panel(rect, Color("#3a2c1c"), 10, 2, Color("#4a443c") if cooling else Color("#8a6a3a"))
	_draw_skill_icon(rect.get_center() + Vector2(0, -14), 36, String(item.get("id", "")))
	if cooling:
		draw_rect(rect.grow(-2), Color(0, 0, 0, 0.5))
		_text_center(str(int(ceilf(float(item.get("cd", 0.0))))) + "s", rect.get_center().x, rect.end.y - 12, 13, Color("#e7a6a4"))
	_text_center(skill_name(String(item.get("id", ""))), rect.get_center().x, rect.position.y + 112, 15, Color("#fff1d0"))


# 图标（程序化自绘，风格统一）
# 优先绘制 3D 模型纹理；模型未配置/加载失败时返回 false，由下方占位图兜底
func _try_draw_model(kind: String, id: String, c: Vector2, r: float) -> bool:
	if icons_3d == null:
		return false
	var tex: Texture2D = icons_3d.get_texture(kind + ":" + id)
	if tex == null:
		return false
	var s: float = r * 2.3 # 纹理边长（透明背景，视觉大小由模型取景决定）
	draw_texture_rect(tex, Rect2(c.x - s / 2.0, c.y - s / 2.0, s, s), false)
	return true


func _draw_hammer_icon(c: Vector2, r: float, id: String, accent: Color) -> void:
	if _try_draw_model("hammer", id, c, r):
		return
	_panel(Rect2(c.x - 5, c.y - r * 0.1, 10, r * 0.75), Color("#6b4a2f"), 4)
	_panel(Rect2(c.x - r * 0.55, c.y - r * 0.7, r * 1.1, r * 0.5), accent.darkened(0.3), 6)
	_panel(Rect2(c.x - r * 0.55, c.y - r * 0.7, r * 1.1, r * 0.5).grow(-3), accent, 5)
	match id:
		"dual":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.35, -r * 0.4), c + Vector2(-r * 0.1, -r * 0.55), c + Vector2(-r * 0.1, -r * 0.25)]), Color("#fff2d0"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.35, -r * 0.4), c + Vector2(r * 0.1, -r * 0.55), c + Vector2(r * 0.1, -r * 0.25)]), Color("#fff2d0"))
		"gravity":
			draw_arc(c + Vector2(0, -r * 0.45), r * 0.26, 0, TAU, 24, Color("#d8b4fe"), 2.5)
			draw_arc(c + Vector2(0, -r * 0.45), r * 0.15, 0, TAU, 24, Color("#d8b4fe"), 2.5)
		"magnet":
			draw_circle(c + Vector2(-r * 0.16, -r * 0.45), r * 0.18, Color("#4f8ef7"))
			draw_circle(c + Vector2(r * 0.16, -r * 0.45), r * 0.18, Color("#e85d5d"))
			_text_center("N", c.x - r * 0.16, c.y - r * 0.4, 13, Color.WHITE)
			_text_center("S", c.x + r * 0.16, c.y - r * 0.4, 13, Color.WHITE)


func _draw_skill_icon(c: Vector2, r: float, id: String) -> void:
	if _try_draw_model("skill", id, c, r):
		return
	match id:
		"hourglass":
			var sand := Color("#a8d8e8")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.35), c + Vector2(r * 0.4, -r * 0.35), c]), sand)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.35), c + Vector2(r * 0.4, r * 0.35), c]), sand.darkened(0.25))
			draw_arc(c, r * 0.5, 0, TAU, 24, Color("#b08a4a"), 3)
		"abacus":
			_panel(Rect2(c.x - r * 0.45, c.y + r * 0.18, r * 0.9, r * 0.2), Color("#8a6a42"), 3)
			for i in range(3):
				var x := c.x + (i - 1) * r * 0.25
				draw_line(Vector2(x, c.y - r * 0.35), Vector2(x, c.y + r * 0.2), Color("#d4a017"), 4)
				draw_circle(Vector2(x, c.y - r * 0.35), 4, Color("#ffe9a0"))


func _draw_box_icon(c: Vector2, r: float) -> void:
	if _try_draw_model("box", "box", c, r):
		return
	_panel(Rect2(c.x - r * 0.55, c.y - r * 0.45, r * 1.1, r * 0.9), Color("#5a3a20"), 8)
	for i in range(3):
		draw_line(Vector2(c.x - r * 0.5, c.y - r * 0.25 + i * r * 0.2), Vector2(c.x + r * 0.5, c.y - r * 0.25 + i * r * 0.2), Color(0.3, 0.2, 0.12), 1)
	_text_center("?", c.x, c.y + r * 0.16, int(r * 0.9), Color("#ffd76a"))
