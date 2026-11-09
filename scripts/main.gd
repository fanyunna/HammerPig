extends Node2D
## 第二轮：余额=积分。开局破产(0)，敲猪赚钱；卡片分奖励/双倍/账单(限时凑钱/躲催债)，失败扣钱，余额≤0破产，攒够目标摆脱破产。

signal pig_broken(points: int)
signal card_opened

const SETTINGS_PATH := "res://data/balance.json"
const META_PATH := "user://hammerpig_meta.cfg"
const STORY_PATH := "res://data/story.json" # 背景设定与全部叙事文案（赌徒心理那几句也在里面）
const BILLS_PATH := "res://data/bills.json" # 账单目录（水费/电费/煤气…）与开局张数
const BILL_PANEL := Rect2(1078, 244, 194, 418) # 右侧那一沓账单纸的点击区域（猪活动区到 x=1010，半径 69，不会挡猪）
const BILL_STACK := Rect2(1088, 360, 168, 210) # 那一沓纸最上面那张的落位（层叠往上堆）
const LEDGER_RECT := Rect2(90, 76, 1100, 578) # 摊开的账本（浮层）
const DETAIL_RECT := Rect2(430, 110, 420, 570) # 单张账单放大的样子（浮层）
const DETAIL_PAY := Rect2(464, 560, 160, 54) # 大账单上的「还 ¥xx」
const DETAIL_CLOSE := Rect2(656, 560, 160, 54) # 大账单上的「放回」
const CARD_RECT := Rect2(510, 290, 260, 250)
const UPGRADE_CARD_RECTS := [Rect2(150, 270, 290, 300), Rect2(495, 270, 290, 300), Rect2(840, 270, 290, 300)]
const CONTINUE_RECT := Rect2(535, 563, 210, 52)
const INTRO_RECT := Rect2(540, 516, 200, 52) # 开场序幕的「敲开第一只」按钮
const RESET_RECT := Rect2(1090, 36, 140, 46)
const PIG_BOUNDS := Rect2(270, 320, 740, 310) # 小猪在赌桌上的活动范围；同时决定 3D 桌板大小。
# ↑ 纵向从 230 撑到 310：小猪要铺满整张桌子，挤在中间一条带子里看不出"满桌都是猪"
const PIG3D_SIZE := 138.0 # 3D 猪纹理的绘制边长（基准；实际尺寸见 pig_size()，由 pig_draw_size 配置）
const MAX_PARTICLES := 70 # 粒子上限：狂热时一秒连碎好几只，别让金币堆到掉帧
const PIG3D_OFFSET := Vector2(0, -10) # 纹理中心相对猪身体中心的偏移
const DESK_RECT := Rect2(110, 260, 1060, 396) # 桌面外框的屏幕矩形（3D 桌板按它反算尺寸）
const ART_DIR := "res://assets/art/" # AI 生成的西部风素材目录（运行时直接读 PNG，不依赖 import）
const PIG_TEXTURE_FILES := { # 猪种 id → 素材文件名（不含扩展名）；没列到/没生成的种类回退 3D 图元
	"piggy": "pig_normal",
	"stripe": "pig_stripe",
	"mini": "pig_mini",
	"gold": "pig_gold",
	"debt": "pig_debt",
	"glass": "pig_glass",
	"fat": "pig_fat",
}
var settings: Dictionary
var story: Dictionary = {} # 背景设定（data/story.json）；读不到就用 {} 走内置兜底文案
var bill_data: Dictionary = {} # 账单目录（data/bills.json）
var bills: Array[Dictionary] = [] # 桌上那叠真实账单：{"name": "水费", "amount": 38}，按金额升序
var paid_count := 0 # 本局已还掉的张数
var bill_open := false # 账本是否摊开（摊开时游戏暂停）
var bill_page := 0 # 账本翻到第几页
var bill_detail := -1 # 正在放大看第几张（-1 = 没在看）
var gamble_state := "none" # 那枚硬币：none（还没攒够/已用过） / ready（可以抛了） / flip（正在翻） / result（已落定）
var gamble_t := 0.0 # 抛硬币动画与结果定格的计时
var gamble_heads := true # 这一抛是正面还是反面
var gamble_used := false # 本局是否已经赌过（赌过就没了；不赌的话硬币一直在桌上等着）
var unpaid_bills := 7 # = bills.size()：应付掉一张 -1，逾期 +1（越欠越多）
var intro_open := false # 开场序幕是否正在显示（headless 下自动关掉，免得挡住自动化测试）
var pigs: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var cursor_hidden := false # 系统箭头有没有被锤子顶掉（见 sync_cursor）
var seen_types := {} # 已经见过哪些种类的猪（用来决定要不要弹一句说明）
var tip_queue: Array = [] # 排队待显示的说明，一条一条放，别一次糊三条
var tip_text := ""
var tip_timer := 0.0
var score := 0
var hits := 0
var broken := 0
var next_card := 50
var card_delay := 0.0 # 卡片的半秒缓冲：等爆钱的反馈播完再弹（见砸碎结算处）
var phase := "playing" # playing / card / challenge / finished / bankrupt
var cooldown := 0.0
var swing := 0.0
const BillManagerScript := preload("res://scripts/bill_manager.gd")
const Hammer3DScript := preload("res://scripts/hammer3d.gd")
const WheelScript := preload("res://scripts/lucky_wheel.gd")
var bills_fx # 账单效果：电费停电 / 信用卡利息 / 房租催收（BillManagerScript 实例）
var hammer3d # 独立透明视口中的立体锤光标
var wheel # 幸运转盘：独立子节点，低侵入，只读写 main 的公开状态
var earned_total := 0 # 本局累计赚到的钱（房租催收按它跨阈值触发）
var last_observed_score := 0
var vignette_tex: ImageTexture # 停电暗角贴图（开局生成一次）
var bonus_timer := 0.0 # 支付电费后的挥锤冷却减免还剩多久
var blackout_fade := 0.0 # 停电暗化的渐入进度（0→1，避免闪进闪出）
var collection_flash := 0.0 # 房东催收的红色警告脉冲
var hammer_position := Vector2(1030, 540)
var mouse_pos := PIG_BOUNDS.get_center() # 追踪的鼠标位置：窗口里由鼠标事件实时更新；headless 停在桌中央，等价旧行为
var card_type := "" # "reward" / "double" / "collect" / "dodge"
var card_offers: Array[Dictionary] = [] # 三选一卡片：本局升级与即时奖励
var hammer_damage_bonus := 0
var stamina_cost_reduction := 0.0
var earnings_multiplier := 1.0
var combo_bonus_per_hit := 0
var hammer_reach_multiplier := 1.0
var hammer_cooldown_reduction := 0.0
var stamina_regen_bonus := 0.0
var pig_size_multiplier := 1.0
var pig_population_doubled := false
var card_pop := 0.0 # 卡片弹出动画的计时（0 → 0.16 秒内放大到位）
var challenge_streak := 0
var bill_amount := 30
var bill_time := 10.0
var bill_timer := 0.0
var collected := 0
var coins: Array[Dictionary] = []
var coin_spawn_timer := 0.0
var double_timer := 0.0
var combo_count := 0
var combo_timer := 0.0
var combo_max := 0
var shake := 0.0
var shake_x := 0.0
var shake_y := 0.0
var dodgers: Array[Dictionary] = []
var dodger_spawn_timer := 0.0
var dodge_lives := 3
var invincible_timer := 0.0
var elapsed := 0.0
var game_day := 1 # 游戏内日期：按 bills.json 的 income_per_game_day 推进
var meta_shards := 0
var meta_runs := 0
var meta_unlocked: Array[String] = []
var meta_rewarded := false
var base_stamina_max := 100.0
var stamina := 100.0
var stamina_flash := 0.0
var end_reason := "" # "target" / "exhausted"
var font := SystemFont.new()

var pig_tex: Dictionary = {} # 猪贴图：id → Texture2D（缺的键 = 素材还没生成，静默回退原路径）
var hammer_tex: Texture2D = null # 握锤的手贴图；null = 用回 3D 锤
var bg_tex: Texture2D = null # 西部酒馆背景；null = 用回纯色底
var pig3d: Array[Pig3D] = [] # 每只猪一个 SubViewport（3D）
var desk3d: Desk3D = null # 3D 木桌背景（全屏 SubViewport）
var use_3d := false # 由 balance.json 的 pig_3d 控制，headless 下强制关闭
var use_desk_3d := false # 由 balance.json 的 desk_3d 控制（可单独关桌子、保留 3D 猪）

func _ready() -> void:
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans SC", "Noto Sans CJK SC"])
	settings = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	base_stamina_max = float(settings.get("stamina_max", 100))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH))
	story = parsed if parsed is Dictionary else {}
	var parsed_bills = JSON.parse_string(FileAccess.get_file_as_string(BILLS_PATH))
	bill_data = parsed_bills if parsed_bills is Dictionary else {}
	bills_fx = BillManagerScript.new()
	load_meta()
	bills_fx.setup(bill_data)
	bills_fx.collection_triggered.connect(_on_collection_triggered)
	vignette_tex = _make_vignette() # 停电暗角用；headless 下也只是生成一张空图，不会崩
	_load_art_textures() # 美术贴图：读不到的键不进字典，绘制处自动回退 3D 图元 / 2D 自绘
	# 开场序幕：headless 下关掉，否则自动化测试第一下点击会被序幕吃掉
	intro_open = bool(story.get("intro_enabled", true)) and not DisplayServer.get_name().contains("headless")
	sync_cursor() # 开场是序幕，这里应该是系统箭头：点「敲开第一只」要看得见自己在点什么
	# 3D 猪：headless（dummy 渲染驱动）下没有真实像素，自动回退 2D 自绘
	use_3d = bool(settings.get("pig_3d", true)) and not DisplayServer.get_name().contains("headless")
	use_desk_3d = use_3d and bool(settings.get("desk_3d", true))
	if use_3d:
		if use_desk_3d:
			desk3d = Desk3D.new()
			add_child(desk3d)
			desk3d.build(DESK_RECT, PIG_BOUNDS) # 桌板尺寸按猪活动区反算（不再画围栏）
		for i in range(pig_count()): # 一只猪一个 SubViewport，数量跟着网格走
			var vp := Pig3D.new()
			add_child(vp)
			pig3d.append(vp)
	if not DisplayServer.get_name().contains("headless"):
		hammer3d = Hammer3DScript.new()
		add_child(hammer3d)
	wheel = WheelScript.new()
	add_child(wheel) # 最后挂上：画在所有东西之上（抽奖按钮 / 弹窗 / 金币特效）
	wheel.setup(self)
	reset_game()


## 读一张美术 PNG 成纹理。走 Image.load_from_file 而不是 load()：仓库里没有 .import 文件也能用；
## 文件不存在 / 解码失败都返回 null（先 file_exists 探路，不往控制台报错），绘制处静默回退。
func _load_png_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## 美术贴图总入口：猪按种类各一张，外加锤子与酒馆背景
func _load_art_textures() -> void:
	for id in PIG_TEXTURE_FILES:
		var tex := _load_png_texture(ART_DIR + String(PIG_TEXTURE_FILES[id]) + ".png")
		if tex != null:
			pig_tex[id] = tex
	hammer_tex = _load_png_texture(ART_DIR + "hammer_hand.png")
	bg_tex = _load_png_texture(ART_DIR + "bg_western.png")


## 开局/重开：从目录里随机抽 start_count 张不重复的账单，按金额升序（小额在上，先还得起）
func roll_bills() -> void:
	bills.clear()
	paid_count = 0
	bill_open = false
	bill_page = 0
	bill_detail = -1
	var picks: Array = bill_data.get("catalog", []).duplicate()
	if picks.is_empty():
		return
	var n := int(bill_data.get("start_count", 24))
	for i in range(n):
		var t: Dictionary = picks[randi() % picks.size()]
		var name := String(t.get("name", "账单"))
		var amount := int(t.get("amount", 30))
		var seen := 0 # 同名账单按出现次数带上期数：电费 → 电费 第2期
		for b in bills:
			if String(b.name).begins_with(name):
				seen += 1
		var due_day := randi_range(int(bill_data.get("first_due_min_days", 4)), int(bill_data.get("first_due_max_days", 16)))
		bills.append({
			"name": name if seen == 0 else name + " 第" + str(seen + 1) + "期",
			"amount": maxi(1, roundi(float(amount) * randf_range(0.75, 1.3))), # 每期金额略有出入
			"no": str(1000 + randi() % 8999),
			"due": format_game_date(game_day + due_day),
			"due_day": game_day + due_day,
			"overdue": false,
			"id": String(t.get("id", "")), # 效果按种类 id 匹配：电费 第2期 也要连带停电
			"effect_id": String(t.get("effect_id", "")), # 空 = 普通账单（旧数据兼容）
		})
	sort_bills()
	bills_fx.reset()
	bills_fx.sync(bills)


## 排序 + 同步 unpaid_bills（列表长度就是未付张数，不再单独计数）
func sort_bills() -> void:
	bills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.amount) < int(b.amount))
	unpaid_bills = bills.size()


func bills_total() -> int:
	var total := 0
	for b in bills:
		total += int(b.amount)
	return total


func bill_pay_amount(index: int) -> int:
	if index < 0 or index >= bills.size():
		return 0
	var bill: Dictionary = bills[index]
	var amount := int(bill.get("amount", 0))
	var tag := BillManagerScript.tag_of(bill)
	for child in bills:
		if String(child.get("source", "")) == tag and String(child.get("fee_kind", "")) == "calendar_late":
			amount += int(child.get("amount", 0))
	return amount


func format_game_date(day_number: int) -> String:
	var normalized := maxi(1, day_number) - 1
	var month := 1 + int(normalized / 30) % 12
	var day := 1 + normalized % 30
	return str(month) + "月" + str(day) + "日"


func advance_calendar() -> void:
	# 每收入 ¥30 推进一天；时间跟着玩家的游戏进度走，不依赖现实等待。
	var income_per_day := maxf(1.0, float(bill_data.get("income_per_game_day", 30)))
	var target_day := 1 + int(earned_total / income_per_day)
	while game_day < target_day:
		game_day += 1
		for i in range(bills.size()):
			var bill: Dictionary = bills[i]
			if bool(bill.get("overdue", false)) or int(bill.get("due_day", 9999)) > game_day:
				continue
			bill.overdue = true
			var tag := BillManagerScript.tag_of(bill)
			bills.append({"name": "逾期滞纳金", "amount": int(bill_data.get("calendar_late_fee", 12)),
				"no": String(bill.get("no", "")), "due": format_game_date(game_day),
				"source": tag, "fee_kind": "calendar_late"})
			popups.append({"position": Vector2(780, 300), "life": 1.5, "text": String(bill.name) + " 已逾期 · 滞纳 ¥" + str(int(bill_data.get("calendar_late_fee", 12)))})
			Sound.play("stamp", 0.75)
	if bills.size() > 0:
		bills_fx.sync(bills)
		sort_bills()


func bill_status_text(bill: Dictionary) -> String:
	if bool(bill.get("overdue", false)):
		return "已逾期 · 原定 " + String(bill.get("due", "—"))
	if String(bill.get("fee_kind", "")) == "calendar_late":
		return "逾期附加费"
	return "截止 " + String(bill.get("due", "—"))


func active_bill_synergies() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	var raw: Variant = bill_data.get("synergies", [])
	if not (raw is Array):
		return active
	for rule in raw:
		if rule is Dictionary and bills_fx.is_synergy_active(String(rule.get("id", ""))):
			active.append(rule)
	return active


func active_synergy_names() -> String:
	var names: PackedStringArray = []
	for rule in active_bill_synergies():
		names.append(String(rule.get("name", "账单联动")))
	return "、".join(names) if not names.is_empty() else "暂无"


func active_synergy_rules_for_bill(bill: Dictionary) -> Array[Dictionary]:
	var related: Array[Dictionary] = []
	var effect_id := String(bill.get("effect_id", ""))
	if effect_id == "":
		return related
	for rule in active_bill_synergies():
		var required: Variant = rule.get("requires", [])
		if required is Array and required.has(effect_id):
			related.append(rule)
	return related


func wrap_text_lines(value: String, max_chars: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for i in range(value.length()):
		line += value.substr(i, 1)
		if line.length() >= max_chars:
			lines.append(line)
			line = ""
	if line != "":
		lines.append(line)
	return lines


func load_meta() -> void:
	# 自动化脚本会反复模拟胜负，不能读取或改写真实玩家的跨局进度。
	if DisplayServer.get_name().contains("headless"):
		return
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return
	meta_shards = int(cfg.get_value("meta", "shards", 0))
	meta_runs = int(cfg.get_value("meta", "runs", 0))
	var raw: Variant = cfg.get_value("meta", "unlocked", [])
	if raw is Array:
		meta_unlocked.assign(raw)


func save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "shards", meta_shards)
	cfg.set_value("meta", "runs", meta_runs)
	cfg.set_value("meta", "unlocked", meta_unlocked)
	cfg.save(META_PATH)


func award_meta_progress() -> void:
	if DisplayServer.get_name().contains("headless"):
		return
	if meta_rewarded:
		return
	meta_rewarded = true
	meta_runs += 1
	meta_shards += maxi(1, int(broken / 3))
	var unlocks := [{"id":"steady_start", "at":3}, {"id":"deep_pockets", "at":8}, {"id":"combo_school", "at":15}]
	for unlock in unlocks:
		if meta_shards >= int(unlock.at) and not meta_unlocked.has(String(unlock.id)):
			meta_unlocked.append(String(unlock.id))
	save_meta()


func meta_starting_cash() -> int:
	return 10 if meta_unlocked.has("steady_start") else 0


func meta_unlock_summary() -> String:
	var parts: Array[String] = []
	if meta_unlocked.has("steady_start"):
		parts.append("开局 ¥10")
	if meta_unlocked.has("deep_pockets"):
		parts.append("体力上限 +10")
	if meta_unlocked.has("combo_school"):
		parts.append("连击卡 +1")
	return " · ".join(parts) if not parts.is_empty() else "继续积累碎片解锁永久能力"


## 主动还掉第 index 张：钱够才扣；还完回一点体力（"手头松快些，能多挥几锤"）
func pay_bill(index: int) -> void:
	if phase != "playing" or index < 0 or index >= bills.size():
		return
	var b: Dictionary = bills[index]
	var synergies_before := active_bill_synergies()
	var due_amount := bill_pay_amount(index)
	if score < due_amount:
		popups.append({"position": Vector2(780, 300), "life": 0.9, "text": "还差 ¥" + str(due_amount - score)})
		return
	var extra: Array = bills_fx.extra_source_tags(b) # 这张卡带出来的利息单，跟着一起作废
	var source_tag := BillManagerScript.tag_of(b)
	for child in bills:
		if String(child.get("source", "")) == source_tag and not extra.has(source_tag):
			extra.append(source_tag) # 逾期滞纳金也归属本金账单
	score -= due_amount
	bills.remove_at(index)
	paid_count += 1
	for j in range(bills.size() - 1, -1, -1): # 倒着删，免得删完后面的下标全乱
		var left: Variant = bills[j]
		if left is Dictionary and extra.has(String(left.get("source", ""))):
			bills.remove_at(j)
	if String(b.get("effect_id", "")) == "interest":
		bills_fx.clear_interest_of(b)
	# 重建效果来源：这一张已经不在 bills 里了，它带的停电/计息就该跟着消失
	var cleared: int = bills_fx.sync(bills)
	var synergies_after := active_bill_synergies()
	sort_bills()
	clamp_bill_page() # 还掉一张可能让最后一页消失
	var bonus := float(bill_data.get("pay_stamina_bonus", 18))
	stamina = minf(float(settings.get("stamina_max", 100)), stamina + bonus)
	# 支付奖励只给电费：挥锤冷却短时减免。
	# ⚠️ 不能再用"恢复体力"当电费奖励 —— pay_bill() 本来就会返还 18 点体力，
	# 两个叠上去就是白给，正好踩中任务书 §3.1 警告的重复叠加失衡。
	var tail := ""
	if String(b.get("effect_id", "")) == "blackout":
		bonus_timer = bills_fx.number("blackout", "payment_bonus_duration", 8.0)
		tail = " · 已复电"
	if cleared > 0:
		tail += " · 免息 ¥" + str(cleared)
	for old_rule in synergies_before:
		var still_active := false
		for current_rule in synergies_after:
			if String(current_rule.get("id", "")) == String(old_rule.get("id", "")):
				still_active = true
				break
		if not still_active:
			tail += " · 解除「" + String(old_rule.get("name", "账单联动")) + "」"
	popups.append({"position": Vector2(780, 300), "life": 1.3, "text": "已还" + String(b.name) + " -¥" + str(due_amount) + tail})
	Sound.play("cash", 0.85) # 交出去的钱也是钱的一声，比赚到低一点


## 考核卡通关：自动付掉最便宜的一张（已按金额升序，第一张就是最小的）
func clear_cheapest_bill() -> void:
	if bills.is_empty():
		return
	var paid := bills[0]
	var tag := BillManagerScript.tag_of(paid)
	bills.remove_at(0)
	for i in range(bills.size() - 1, -1, -1):
		if String(bills[i].get("source", "")) == tag:
			bills.remove_at(i)
	paid_count += 1
	bills_fx.sync(bills) # 万一免费清掉的是张电费/信用卡，效果也得跟着走
	sort_bills()


## 信用卡利息：考核失败时，每张还没还的信用卡各追加一笔利息。
## ⚠️ 只在 finish_challenge(false) 里调 —— 那是全局唯一的考核失败结算点，
## 所以"一次失败只计一次息"是天然成立的，不用再加去重标记。
## 利息单带 source（=那张信用卡的 id#户号），等你还掉那张卡时由 sync() 一并作废。
func add_interest_bills() -> void:
	var by_tag: Dictionary = {} # tag -> 这次该加多少
	for i in range(bills.size()):
		var raw: Variant = bills[i]
		if not (raw is Dictionary):
			continue
		var bill: Dictionary = raw
		var surcharge := 0
		if bills_fx.is_synergy_active("credit_broadband"):
			surcharge = int(bills_fx.synergy_rule("credit_broadband").get("interest_surcharge", 5))
		var amount: int = bills_fx.accrue_interest(bill, surcharge)
		if amount > 0:
			var tag := BillManagerScript.tag_of(bill)
			by_tag[tag] = int(by_tag.get(tag, 0)) + amount
	if by_tag.is_empty():
		return
	for tag in by_tag:
		var grow: int = int(by_tag[tag])
		var found := false
		for j in range(bills.size()): # 并入已存在的那张利息单，别每次新开一张刷屏
			var ex: Variant = bills[j]
			if ex is Dictionary and String(ex.get("source", "")) == String(tag):
				ex.amount = int(ex.amount) + grow
				found = true
				break
		if not found:
			bills.append({"name": "信用卡利息", "amount": grow,
			"no": str(1000 + randi() % 8999), "due": "待还", "source": String(tag)})
	sort_bills()
	bills_fx.sync(bills)


## 逾期：不但没还掉，还多出一张滞纳单
func add_overdue_bill() -> void:
	bills.append({"name": "考核逾期滞纳金", "amount": int(settings.bill_amount), "due": format_game_date(game_day + 3), "due_day": game_day + 3})
	sort_bills()


## 一张纸质账单（够比例排版，所以桌上一沓、账本里一张、放大的一张都能复用）
func draw_bill_paper(r: Rect2, b: Dictionary, can_pay: bool, tilt: float, lift: float) -> void:
	draw_set_transform(r.get_center() + Vector2(0, -lift), tilt, Vector2.ONE) # 绕纸心歪一点，才不像表格行
	var half := r.size / 2.0
	var rect := Rect2(-half, r.size)
	var paper := Color("#f8f1de") if can_pay else Color("#ded6c2")
	panel(Rect2(-half + Vector2(3 + lift, 4 + lift), r.size), Color(0.04, 0.07, 0.07, 0.4), 3) # 纸落在桌上的影子
	panel(rect, paper, 3)
	panel(Rect2(-half, Vector2(5, r.size.y)), Color("#c05a4e") if can_pay else Color("#a8756c"), 1) # 左侧骑缝红条
	draw_colored_polygon(PackedVector2Array([half, half - Vector2(13, 0), half - Vector2(0, 13)]), paper.darkened(0.16)) # 右下折角
	draw_line(Vector2(-half.x + 12, -half.y + r.size.y * 0.58), Vector2(half.x - 12, -half.y + r.size.y * 0.58), paper.darkened(0.13), 1) # 纸上的横格线
	var title_size := 15 if r.size.x < 200.0 else 20
	text_at(String(b.name), Vector2(-half.x + 13, -half.y + r.size.y * 0.40), title_size, Color("#3d3630") if can_pay else Color("#6d675c"))
	var amt := "¥" + str(int(b.amount))
	var amt_size := 20 if r.size.x < 200.0 else 26
	var w: float = font.get_string_size(amt, HORIZONTAL_ALIGNMENT_LEFT, -1, amt_size).x
	text_at(amt, Vector2(half.x - 15 - w, -half.y + r.size.y * 0.44), amt_size, Color("#b8541f") if can_pay else Color("#8a8272"))
	var status := bill_status_text(b)
	text_at(status, Vector2(-half.x + 13, -half.y + r.size.y * 0.86), 11, Color("#b8541f") if not bool(b.get("overdue", false)) else Color("#9a5c4e"))
	draw_set_transform(Vector2.ZERO)


## 桌角那一沓账单：只画最上面几张与侧边层叠，堆得多深由 bills.size() 决定
func draw_bills() -> void:
	var n := bills.size()
	text_at("桌上的账单", BILL_PANEL.position + Vector2(10, 24), 16, Color("#efbc72"))
	if n == 0:
		text_at("都还清了", BILL_PANEL.position + Vector2(10, 60), 15, Color("#a4d007"))
		return
	text_at("¥" + str(bills_total()), BILL_PANEL.position + Vector2(110, 24), 17, Color("#e7a6a4"))
	var layers := clampi(ceili(float(n) / 2.0), 3, 12) # 张数越多纸沓越厚（最多画 12 层，每层露 6px）
	for i in range(layers):
		var k := layers - 1 - i # 从下往上画，上面的纸压住下面的
		var off := Vector2(sin(k * 2.1) * 4.0, -float(k) * 6.0)
		panel(Rect2(BILL_STACK.position + off, BILL_STACK.size), Color("#cfc7b2" if k % 2 == 0 else "#d8d0bb"), 3)
	# 最上面那张：印着抬头、汇总，让这一沓看起来真的在催钱
	var top := Rect2(BILL_STACK.position + Vector2(sin(float(layers - 1) * 2.1) * 4.0, -float(layers - 1) * 6.0), BILL_STACK.size)
	panel(Rect2(top.position, Vector2(top.size.x, 34)), Color("#c0594a"), 3)
	text_center("催 缴 通 知 单", top.position.x + top.size.x / 2.0, top.position.y + 23, 14, Color("#fdeee9"))
	text_at(String(bills[0].name) + " 等", top.position + Vector2(14, 62), 13, Color("#5d564c"))
	text_at(str(n) + " 张", top.position + Vector2(14, 104), 24, Color("#b8541f"))
	text_at("合计 ¥" + str(bills_total()), top.position + Vector2(14, 132), 14, Color("#7d7669"))
	draw_line(top.position + Vector2(14, 148), top.position + Vector2(top.size.x - 14, 148), Color("#c3bba9"), 1)
	text_at("点开查账 →", top.position + Vector2(14, 176), 13, Color("#b8541f"))


## 账本：把一沓纸摊成一屏，4 列 × 5 行，翻页靠 ←/→
const LEDGER_COLS := 4
const LEDGER_ROWS := 5
const LEDGER_PER_PAGE := 20


func ledger_page_count() -> int:
	return maxi(1, ceili(float(bills.size()) / float(LEDGER_PER_PAGE)))


func ledger_cell_rect(i: int) -> Rect2:
	var col := i % LEDGER_COLS
	var row := i / LEDGER_COLS
	return Rect2(LEDGER_RECT.position.x + 34 + col * 262, LEDGER_RECT.position.y + 92 + row * 92, 236, 74)


## 点在第几张纸上（-1 = 点在空白处）
func ledger_index_at(point: Vector2) -> int:
	for i in range(LEDGER_PER_PAGE):
		var idx := bill_page * LEDGER_PER_PAGE + i
		if idx >= bills.size():
			return -1
		if ledger_cell_rect(i).has_point(point):
			return idx
	return -1


func clamp_bill_page() -> void:
	bill_page = clampi(bill_page, 0, ledger_page_count() - 1)


func draw_ledger() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.055, 0.033, 0.02, 0.76))
	panel(Rect2(LEDGER_RECT.position + Vector2(6, 8), LEDGER_RECT.size), Color(0.02, 0.05, 0.05, 0.55), 20) # 桌子上的投影
	panel(LEDGER_RECT, Color("#2b1c11"), 18)
	panel(Rect2(LEDGER_RECT.position + Vector2(0, 0), Vector2(LEDGER_RECT.size.x, 62)), Color("#1f130c"), 18) # 账本封面条
	text_at("摊开的账单", LEDGER_RECT.position + Vector2(28, 40), 24, Color("#efbc72"))
	text_at(str(bills.size()) + " 张没付 · 合计 ¥" + str(bills_total()), LEDGER_RECT.position + Vector2(200, 40), 18, Color("#e7a6a4"))
	text_at("游戏日期 " + format_game_date(game_day), LEDGER_RECT.position + Vector2(LEDGER_RECT.size.x - 440, 40), 18, Color("#efbc72"))
	text_at("第 " + str(bill_page + 1) + " / " + str(ledger_page_count()) + " 页", LEDGER_RECT.position + Vector2(LEDGER_RECT.size.x - 190, 40), 18, Color("#c9b08a"))
	for i in range(LEDGER_PER_PAGE):
		var idx := bill_page * LEDGER_PER_PAGE + i
		if idx >= bills.size():
			break
		var b: Dictionary = bills[idx]
		var can_pay: bool = phase == "playing" and score >= bill_pay_amount(idx)
		draw_bill_paper(ledger_cell_rect(i), b, can_pay, sin(float(idx) * 2.3) * 0.035, 3.0 if can_pay else 0.0)
	var active_rules := active_bill_synergies()
	if active_rules.is_empty():
		text_center("当前没有账单联动 · 每累计收入 ¥" + str(int(bill_data.get("income_per_game_day", 100))) + " 前进一天", 640, LEDGER_RECT.end.y - 26, 15, Color("#7f8b87"))
	else:
		var combo_text := PackedStringArray()
		for rule in active_rules:
			combo_text.append(String(rule.get("name", "账单联动")))
		text_center("激活联动：" + "、".join(combo_text), 640, LEDGER_RECT.end.y - 26, 15, Color("#ffb86b"))
	text_center("点账单查看/还款 · 每 ¥" + str(int(bill_data.get("income_per_game_day", 100))) + " 收入前进一天 · ←/→ 翻页 · B 收起", 640, LEDGER_RECT.end.y - 8, 14, Color("#c9b08a"))


## 单张账单放大版：一张完整的催缴通知单（这才是「点开」看到的）
func draw_bill_detail() -> void:
	if bill_detail < 0 or bill_detail >= bills.size():
		return
	var b: Dictionary = bills[bill_detail]
	var principal := int(b.amount)
	var amount := bill_pay_amount(bill_detail)
	var can_pay: bool = phase == "playing" and score >= amount
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.055, 0.033, 0.02, 0.82))
	draw_set_transform(DETAIL_RECT.get_center(), -0.012, Vector2.ONE)
	var half := DETAIL_RECT.size / 2.0
	var rect := Rect2(-half, DETAIL_RECT.size)
	var paper := Color("#f6f0dd")
	panel(Rect2(-half + Vector2(8, 10), DETAIL_RECT.size), Color(0.03, 0.05, 0.05, 0.5), 8)
	panel(rect, paper, 6)
	panel(Rect2(-half, Vector2(DETAIL_RECT.size.x, 96)), Color("#c0594a"), 6) # 抬头红条
	text_center("催 缴 通 知 单", 0.0, -half.y + 40, 20, Color("#fdeee9"))
	text_center(String(b.name), 0.0, -half.y + 76, 28, Color("#fff3ea"))
	text_at("户号 " + String(b.no), Vector2(-half.x + 40, -half.y + 150), 17, Color("#6d675c"))
	text_at("当前 " + format_game_date(game_day) + "　·　" + bill_status_text(b), Vector2(-half.x + 40, -half.y + 178), 17, Color("#9a5c4e"))
	text_center("¥" + str(amount), 0.0, -half.y + 300, 84, Color("#3d3630"))
	text_center("应 缴 金 额", 0.0, -half.y + 336, 17, Color("#8a8272"))
	for i in range(3): # 明细：像真账单那样列几行
		var y := -half.y + 372 + i * 34
		draw_line(Vector2(-half.x + 40, y + 12), Vector2(half.x - 40, y + 12), paper.darkened(0.14), 1)
		var late_fee := 0
		var source_tag := BillManagerScript.tag_of(b)
		for child in bills:
			if String(child.get("source", "")) == source_tag and String(child.get("fee_kind", "")) == "calendar_late":
				late_fee += int(child.get("amount", 0))
		var row: Array = ["本期费用", "附加费用", "应付合计"]
		text_at(row[i], Vector2(-half.x + 44, y), 16, Color("#6d675c"))
		var v := str(principal) if i == 0 else (str(late_fee) if i == 1 else str(amount))
		var vw: float = font.get_string_size("¥" + v, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		text_at("¥" + v, Vector2(half.x - 44 - vw, y), 16, Color("#3d3630"))
	# 特殊账单才多印这一行：告诉玩家"不还不只是欠着，它正在改你玩的游戏"
	var related_rules := active_synergy_rules_for_bill(b)
	if not related_rules.is_empty():
		var synergy_titles := PackedStringArray()
		var synergy_hints := PackedStringArray()
		for rule in related_rules:
			synergy_titles.append(String(rule.get("name", "账单联动")))
			synergy_hints.append(String(rule.get("hint", "")))
		text_center("组合效果：" + "、".join(synergy_titles), 0.0, -half.y + 370, 15, Color("#ffb86b"))
		var hint_lines := wrap_text_lines("；".join(synergy_hints), 30)
		for i in range(mini(hint_lines.size(), 3)):
			text_center(hint_lines[i], 0.0, -half.y + 396 + i * 18, 12, Color("#b8541f"))
	elif BillManagerScript.is_special(b):
		var hint: String = bills_fx.hint_of(b)
		if hint != "":
			text_center(hint, 0.0, -half.y + 420, 15, Color("#b8541f"))
	# 红色印章：歪着盖在纸上
	draw_set_transform(DETAIL_RECT.get_center() + Vector2(128, -14), -0.18, Vector2.ONE)
	draw_rect(Rect2(-46, -32, 92, 64), Color("#c0392b"), false, 3)
	text_center(String(bill_data.get("unpaid_stamp", "未付")), 0.0, 12, 24, Color("#c0392b"))
	draw_set_transform(Vector2.ZERO)
	button(DETAIL_PAY, "还 ¥" + str(amount), can_pay, Color("#8fd05a"))
	button(DETAIL_CLOSE, "放回桌上", true, Color("#7d8a88"))
	if not can_pay:
		text_center("手上只有 ¥" + str(score) + "，还差 ¥" + str(amount - score), 640, DETAIL_RECT.end.y - 26, 17, Color("#e7a6a4"))


func random_pig_velocity(type := {}) -> Vector2:
	var angle := randf_range(0.0, TAU)
	var sp := float(settings.get("pig_speed", 90)) * float(type.get("speed", 1.0)) * wheel_speed_mul() # 每种猪自带速度倍率；转盘变慢/变快在这里生效
	return Vector2(cos(angle), sin(angle)) * sp * randf_range(0.7, 1.3)


## 鼠标是否在小猪活动区内：区内举锤瞄准可敲击；区外是自由鼠标（普通光标，自由点所有 UI）
func mouse_in_pig_bounds() -> bool:
	return PIG_BOUNDS.has_point(mouse_pos)


## 自绘的锤子只在「鼠标就是你的身体」时才顶替系统光标：敲猪和躲催债这两段。
## 序幕 / 卡片 / 账本 / 结算必须把系统箭头还回来 —— 那些界面不画锤子，
## 再把箭头藏了就等于一个指针都没有，玩家连「继续」都点不到。
## 配置 hammer_cursor: false 可以彻底用回系统箭头（有人就是更习惯真的指针）。
func sync_cursor() -> void:
	var hide: bool = bool(settings.get("hammer_cursor", true))
	hide = hide and (phase == "playing" or (phase == "challenge" and card_type == "dodge"))
	hide = hide and not intro_open and not bill_open and bill_detail < 0
	hide = hide and not (wheel != null and wheel.is_open()) # 转盘弹窗里得看得见箭头
	hide = hide and (phase != "playing" or mouse_in_pig_bounds()) # 敲猪时鼠标进小猪活动区才举锤；区外还给系统箭头自由点 UI
	if hide == cursor_hidden:
		return
	cursor_hidden = hide
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE)


## 抽一种猪：按 weight 加权。带 min_score 的种类（催债猪）在玩家兜里还没钱时不出现 —— 开局第一锤就倒贴太伤
func pick_pig_type() -> Dictionary:
	var types: Array = settings.get("pig_types", [])
	if types.is_empty():
		return {} # 配置没写就用老默认值：pig_hp / points_per_pig
	var pool: Array = []
	for t in types:
		var w := int(t.get("weight", 1))
		if w <= 0 or score < int(t.get("min_score", 0)):
			continue
		for i in range(w):
			pool.append(t)
	return Dictionary(pool[randi() % pool.size()]) if not pool.is_empty() else Dictionary(types[0])


func pig_max_hp(t: Dictionary) -> int:
	return int(t.get("hp", settings.get("pig_hp", 2)))

## 这一只值多少（催债猪是负数 —— 碎了要倒贴）
func pig_value(t: Dictionary) -> int:
	return int(t.get("value", settings.get("points_per_pig", 10)))

func pig_scale(t: Dictionary) -> float:
	return float(t.get("scale", 1.0))


## 挥锤冷却倍率：还掉电费之后的一小段时间里锤得更快（支付奖励）。
## 只减冷却，不再补体力 —— pay_bill() 本来就返还 18 点体力，再补就是白给。
func swing_cooldown_mul() -> float:
	if bonus_timer <= 0.0:
		return 1.0
	return bills_fx.number("blackout", "cooldown_multiplier", 0.9)


## 房东上门催收：不扣钱、不生新猪，只给一次明确的警告（任务书 §2.1C 要求首版做轻量事件）
func _on_collection_triggered(msg: String) -> void:
	collection_flash = 1.2
	# 房东敲门是一次强烈的短促冲击；复用桌面震动层，让猪和飞散粒子一起震。
	var dark_knock: bool = bills_fx.is_synergy_active("dark_knock")
	shake = maxf(shake, 0.68 if dark_knock else 0.48)
	if dark_knock:
		msg = "停电时房东砸门！"
	popups.append({"position": Vector2(640, 296), "life": 1.6, "text": msg})
	Sound.play("stamp", 0.72, 1.25)


## 催收警告：屏幕四周闪一圈红，1.2 秒衰减。不做全屏红闪 —— 那会盖住猪和按钮。
func draw_collection_flash() -> void:
	if collection_flash <= 0.0:
		return
	var k := clampf(collection_flash / 1.2, 0.0, 1.0)
	var c := Color(0.86, 0.26, 0.2, 0.5 * k)
	var w := 14.0
	draw_rect(Rect2(0.0, 0.0, 1280.0, w), c)
	draw_rect(Rect2(0.0, 800.0 - w, 1280.0, w), c)
	draw_rect(Rect2(0.0, w, w, 800.0 - w * 2.0), c)
	draw_rect(Rect2(1280.0 - w, w, w, 800.0 - w * 2.0), c)


## 桌面上一共几只猪：行 × 列（改配置就换密度，不用改代码）。位置按网格均分，不写死坐标。
func pig_count() -> int:
	return maxi(1, int(settings.get("pig_rows", 3)) * int(settings.get("pig_cols", 6)))


## 一只猪画多大（像素边长）。这是桌面密度的总开关：猪画小了才塞得下更多只。
## ⚠️ 命中判定和阴影/裂纹都按它等比缩放，别只改绘制 —— 判定不变会变成"看着小、其实很好打"。
func pig_size() -> float:
	return float(settings.get("pig_draw_size", PIG3D_SIZE)) * pig_size_multiplier


## 一群猪如果没有互相排斥，几十秒后必然漂成一坨（随机游走的聚集是迟早的事），
## 桌面上就只剩下一团猪。给一点分离力道，它们才会一直铺满整张桌子。
## O(n²)：18 只 = 324 次/帧，可以忽略。
func separate_pigs(delta: float) -> void:
	var min_dist: float = 76.0 * (pig_size() / PIG3D_SIZE) # 跟着猪的尺寸走：猪缩小了就该靠得更近
	for i in range(pigs.size()):
		var a: Dictionary = pigs[i]
		if a.hp <= 0: # 碎掉的猪不占位置
			continue
		var push := Vector2.ZERO
		for j in range(pigs.size()):
			if i == j:
				continue
			var b: Dictionary = pigs[j]
			if b.hp <= 0:
				continue
			var d: Vector2 = a.position - b.position
			var dist := d.length()
			if dist > 0.01 and dist < min_dist:
				push += d / dist * (min_dist - dist)
		if push == Vector2.ZERO:
			continue
		a.position += push * 2.6 * delta
		a.position.x = clampf(a.position.x, PIG_BOUNDS.position.x, PIG_BOUNDS.end.x)
		a.position.y = clampf(a.position.y, PIG_BOUNDS.position.y, PIG_BOUNDS.end.y)


## 底部那行猪价目表：从 pig_types 直接生成，改了配置就不用跟着改文案。
## 只列出**已经见过**的种类 —— 七种猪的名字全排开这行根本放不下，而且一次全告诉你就没得发现了。
func pig_legend() -> String:
	var types: Array = settings.get("pig_types", [])
	if types.is_empty():
		return "每只两锤 · 每只 +¥" + str(int(settings.get("points_per_pig", 10)))
	var parts := PackedStringArray()
	var known := 0
	for t in types:
		if not seen_types.has(String(t.get("id", ""))):
			continue
		known += 1
		var v := int(t.get("value", 0))
		parts.append(String(t.get("label", t.get("id", "?"))) + " " + ("+¥" + str(v) if v > 0 else "-¥" + str(-v)))
	if known < types.size():
		parts.append("还有 " + str(types.size() - known) + " 种没见过")
	return " · ".join(parts)


## 第一次见到某种猪时给一句说明。warn_only = 开局那批只预警"会让你亏钱"的那一种：
## 开局连着弹三条提示没人看，而倒贴这种事必须有预告，否则玩家会觉得被坑。
func note_pig_type(t: Dictionary, warn_only := false) -> void:
	var id := String(t.get("id", "piggy"))
	if seen_types.has(id):
		return
	seen_types[id] = true
	if warn_only and pig_value(t) >= 0:
		return
	var tip := String(story.get("pig_tip_" + id, ""))
	if tip != "" and not tip_queue.has(tip):
		tip_queue.append(tip)

func reset_game() -> void:
	while pig3d.size() > pig_count():
		var extra_viewport: Pig3D = pig3d.pop_back()
		if is_instance_valid(extra_viewport):
			extra_viewport.queue_free()
	score = 0
	hits = 0
	broken = 0
	earned_total = 0
	bonus_timer = 0.0
	blackout_fade = 0.0
	collection_flash = 0.0
	game_day = 1
	meta_rewarded = false
	roll_bills() # 里面会 bills_fx.reset() 并按新账单重建效果来源
	score = meta_starting_cash()
	last_observed_score = score
	settings["stamina_max"] = base_stamina_max + (10.0 if meta_unlocked.has("deep_pockets") else 0.0)
	# 第一张卡要来得晚一点（card_first_at）：开局这段必须是"砸 → 爆钱 → 砸"的连续反馈，
	# 把对外服务的教学/抉择留到玩家已经上手之后。之后每张按 card_interval 间隔。
	next_card = int(settings.get("card_first_at", settings.get("card_interval", 50)))
	card_delay = 0.0
	phase = "playing"
	card_type = ""
	card_offers.clear()
	hammer_damage_bonus = 0
	stamina_cost_reduction = 0.0
	earnings_multiplier = 1.0
	combo_bonus_per_hit = 0
	hammer_reach_multiplier = 1.0
	hammer_cooldown_reduction = 0.0
	stamina_regen_bonus = 0.0
	pig_size_multiplier = 1.0
	pig_population_doubled = false
	if meta_unlocked.has("combo_school"):
		combo_bonus_per_hit = 1
	challenge_streak = 0
	bill_amount = int(settings.bill_amount)
	bill_time = float(settings.bill_time)
	bill_timer = 0.0
	collected = 0
	coins.clear()
	coin_spawn_timer = 0.0
	double_timer = 0.0
	combo_count = 0
	combo_timer = 0.0
	combo_max = 0
	shake = 0.0
	shake_x = 0.0
	shake_y = 0.0
	dodgers.clear()
	dodger_spawn_timer = 0.0
	dodge_lives = int(settings.dodge_lives)
	invincible_timer = 0.0
	cooldown = 0.0
	swing = 0.0
	gamble_state = "none"
	gamble_t = 0.0
	gamble_heads = true
	gamble_used = false
	particles.clear()
	popups.clear()
	stamina = float(settings.get("stamina_max", 100))
	stamina_flash = 0.0
	end_reason = ""
	pigs.clear()
	seen_types.clear()
	tip_queue.clear()
	tip_text = ""
	tip_timer = 0.0
	var cols := int(settings.get("pig_cols", 6))
	var rows := int(settings.get("pig_rows", 3))
	for row in range(rows):
		for col in range(cols):
			var t := pick_pig_type()
			var hp := pig_max_hp(t)
			# 按网格均分活动区：加行加列不用再改坐标，猪多了也不会挤成一堆
			pigs.append({
				"position": Vector2(
					PIG_BOUNDS.position.x + (float(col) + 0.5) * PIG_BOUNDS.size.x / float(cols),
					PIG_BOUNDS.position.y + (float(row) + 0.5) * PIG_BOUNDS.size.y / float(rows)),
				"type": t, "hp": hp, "max_hp": hp, "respawn": 0.0,
				"flash": 0.0, "hop": 0.0, "seed": float(row * 4 + col),
				"hop_phase": randf() * TAU, # 弹跳相位随机起步，不然满桌猪齐刷刷同起同落
				"left": true, # 朝向：素材朝左画，往右走时镜像（见 draw_pig_sprite）
				"velocity": random_pig_velocity(t)
			})
			note_pig_type(t, true) # 开局这批只预警会亏钱的那种
	if use_3d:
		for i in range(mini(pigs.size(), pig3d.size())):
			pig3d[i].apply_type(Dictionary(pigs[i].type))
	if wheel != null:
		wheel.reset_run() # 新局：机会/连击/三个 buff 计时全部清零（多余的金猪视口上面已随 pig3d 裁掉）
	queue_redraw()

func _process(delta: float) -> void:
	sync_cursor() # 必须排在所有提前 return 之前：翻账本时整局是停的，但箭头得还回来
	if hammer3d == null and not DisplayServer.get_name().contains("headless"):
		# 编辑器热重载不会重跑 _ready()；运行中的窗口也要能补建新加入的 3D 锤子视口。
		hammer3d = Hammer3DScript.new()
		add_child(hammer3d)
	if wheel != null and wheel.is_open(): # 转盘弹窗：整局暂停（猪停刷、不能砸）；转盘自己的 _process 继续转
		queue_redraw()
		return
	if bill_open or bill_detail >= 0: # 翻账单的时候整局都停下来：猪不走、卡不计时
		queue_redraw()
		return
	elapsed += delta
	if score > last_observed_score: # 累计每笔新增收入；还账扣款不会倒扣进度
		earned_total += score - last_observed_score
	last_observed_score = score
	advance_calendar()
	if phase == "playing": # 结束了就不再催收
		bills_fx.update_collection(delta, float(earned_total))
	if update_gamble(delta): # 抛硬币翻面/落定时整局暂停：猪不走、卡不计时
		queue_redraw()
		return
	cooldown = maxf(0.0, cooldown - delta)
	swing = maxf(0.0, swing - delta)
	bonus_timer = maxf(0.0, bonus_timer - delta)
	collection_flash = maxf(0.0, collection_flash - delta)
	# 停电暗化渐入渐出（0.6 秒），不要闪
	var want_fade := 1.0 if bills_fx.is_active("blackout") else 0.0
	blackout_fade = move_toward(blackout_fade, want_fade, delta / 0.6)
	double_timer = maxf(0.0, double_timer - delta)
	if wheel != null:
		wheel.tick(delta) # 转盘层：余额跨线送机会、buff 独立倒计时、金猪压扁/到期
	combo_timer = maxf(0.0, combo_timer - delta)
	if combo_timer <= 0.0:
		combo_count = 0
	# 卡片的半秒缓冲排在计时器之后：让爆钱的钱票和音效先播完。
	# 冷却、双倍计时照常走 —— 这半秒是要能接着砸猪的，不是把玩家按在原地看卡片。
	if card_delay > 0.0:
		card_delay = maxf(0.0, card_delay - delta)
		if card_delay <= 0.0 and phase == "playing":
			open_card() # 缓冲期间玩家可能已经凑够 120 直接赢了 —— 那就别弹了，先放行结算
		queue_redraw()
		return
	shake = maxf(0.0, shake - delta)
	if shake > 0.0:
		var k: float = shake / float(settings.get("shake_duration", 0.12))
		var intensity: float = float(settings.get("shake_intensity", 4.0)) * k
		shake_x = randf_range(-1.0, 1.0) * intensity
		shake_y = randf_range(-1.0, 1.0) * intensity
	else:
		shake_x = 0.0
		shake_y = 0.0
	stamina_flash = maxf(0.0, stamina_flash - delta)
	if phase == "playing":
		var stamina_max := float(settings.get("stamina_max", 100))
		var stamina_regen := float(settings.get("stamina_regen_per_second", 0.0)) + stamina_regen_bonus
		if bills_fx.is_synergy_active("health_fatigue"):
			var fatigue_rule: Dictionary = bills_fx.synergy_rule("health_fatigue")
			stamina_regen -= float(fatigue_rule.get("stamina_regen_penalty", 0.12))
		stamina_regen = maxf(0.0, stamina_regen)
		stamina = minf(stamina_max, stamina + stamina_regen * delta)
		if mouse_in_pig_bounds(): # 区外取消跟随：锤子停在最后一次瞄准处，光标也还给了系统
			hammer_position = mouse_pos
		for i in range(pigs.size()):
			var pig: Dictionary = pigs[i]
			pig.flash = maxf(0.0, pig.flash - delta)
			pig.hop = maxf(0.0, pig.hop - delta)
			if pig.hp > 0:
				pig.position += pig.velocity * delta * wheel_speed_mul()
				# 走路弹跳：相位随位移推进（每 26px 一步、蹦一下），速度越快蹦得越快
				pig.hop_phase = fmod(float(pig.get("hop_phase", 0.0)) + pig.velocity.length() * delta / 26.0 * PI, TAU)
				if absf(pig.velocity.x) > 4.0: # 近乎竖直走时别乱翻朝向
					pig.left = pig.velocity.x < 0.0
				if pig.position.x < PIG_BOUNDS.position.x or pig.position.x > PIG_BOUNDS.end.x:
					pig.velocity.x = -pig.velocity.x
					pig.position.x = clampf(pig.position.x, PIG_BOUNDS.position.x, PIG_BOUNDS.end.x)
				if pig.position.y < PIG_BOUNDS.position.y or pig.position.y > PIG_BOUNDS.end.y:
					pig.velocity.y = -pig.velocity.y
					pig.position.y = clampf(pig.position.y, PIG_BOUNDS.position.y, PIG_BOUNDS.end.y)
			else:
				pig.respawn -= delta * wheel_speed_mul() # 转盘变慢/变快同样作用于刷新速度
				if pig.respawn <= 0.0:
					pig.type = pick_pig_type() # 重生时换一种：桌上永远有新的诱惑
					pig.max_hp = pig_max_hp(pig.type)
					pig.hp = pig.max_hp
					pig.velocity = random_pig_velocity(pig.type)
					note_pig_type(pig.type)
					if use_3d and i < pig3d.size():
						pig3d[i].apply_type(Dictionary(pig.type))
		separate_pigs(delta)
		if stamina < float(settings.get("stamina_cost", 4)):
			end_round_exhausted()
	elif phase == "challenge":
		bill_timer -= delta
		hammer_position = get_global_mouse_position()
		if card_type == "collect":
			update_collect(delta)
		else:
			update_dodge(delta)
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		p.position += p.velocity * delta
		p.velocity.y += 480.0 * delta # 金币轻，掉得比陶片"慢"一点才飘得起来
		p.spin += float(p.get("spin_speed", 0.0)) * delta # 金币在空中翻跟头
		if p.life <= 0.0:
			particles.remove_at(i)
	for i in range(popups.size() - 1, -1, -1):
		popups[i].life -= delta
		popups[i].position.y -= 48.0 * delta
		if popups[i].life <= 0.0:
			popups.remove_at(i)
	if tip_timer > 0.0: # 一句一句放：新的猪来了才说，说完再排下一句
		tip_timer -= delta
		if tip_timer <= 0.0:
			tip_text = ""
	elif not tip_queue.is_empty():
		tip_text = String(tip_queue.pop_front())
		tip_timer = 2.8
	if use_3d:
		for i in range(pigs.size()):
			pig3d[i].update_visual(pigs[i], elapsed)
	if phase == "card":
		card_pop += delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse_pos = event.position # 鼠标一动就更新分界判定：区内举锤瞄准，区外自由光标
	if intro_open: # 序幕期间吞掉一切输入：点按钮或按任意键都只是「开始」
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				intro_open = false
		elif event is InputEventKey and event.pressed and not event.echo:
			intro_open = false
		return
	if wheel != null and wheel.is_open(): # 转盘弹窗期间：只认「确认」（点击或空格/回车），其余一律吞掉
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			wheel.handle_click(get_global_mouse_position())
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				wheel.confirm_result()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B: # 账本：开 / 收起
			if bill_detail >= 0:
				bill_detail = -1
			else:
				bill_open = not bill_open
			clamp_bill_page()
			queue_redraw()
			return
		if event.keycode == KEY_ESCAPE: # 逐层退出：大账单 → 账本 → 桌面
			if bill_detail >= 0:
				bill_detail = -1
			elif bill_open:
				bill_open = false
			queue_redraw()
			return
		if bill_open and bill_detail < 0:
			if event.keycode == KEY_LEFT:
				bill_page -= 1
			elif event.keycode == KEY_RIGHT:
				bill_page += 1
			clamp_bill_page()
			queue_redraw()
			return
		if event.keycode == KEY_M: # 静音
			Sound.toggle()
		if event.keycode == KEY_R:
			reset_game()
		elif phase == "card" and card_offers.size() == 3 and event.keycode in [KEY_1, KEY_2, KEY_3]:
			apply_card(int(event.keycode - KEY_1))
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if phase == "card":
				apply_card()
			elif phase == "finished" or phase == "bankrupt":
				reset_game()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		if gamble_state == "flip" or gamble_state == "result": # 硬币在空中 / 结果还没看完：点了也没用
			queue_redraw()
			return
		if bill_detail >= 0: # 正在看一张放大的账单
			if DETAIL_PAY.has_point(point):
				pay_bill(bill_detail)
				bill_detail = -1
			elif not DETAIL_RECT.has_point(point):
				bill_detail = -1
			queue_redraw()
			return
		if bill_open: # 账本摊开着：点纸放大，点外面收起
			if wheel != null and wheel.handle_click(point): # 压在账本右上角的抽奖按钮：点它不翻账本
				queue_redraw()
				return
			if LEDGER_RECT.has_point(point):
				var idx := ledger_index_at(point)
				if idx >= 0:
					bill_detail = idx
			else:
				bill_open = false
			queue_redraw()
			return
		if BILL_PANEL.has_point(point) and not bills.is_empty(): # 桌角那一沓纸：点开账本
			bill_open = true
			bill_page = 0
			Sound.play("card")
			queue_redraw()
			return
		if phase == "playing" and gamble_state == "ready" and gamble_t >= GAMBLE_ROLL_TIME:
			# 桌边那枚硬币：滚到位之后才接点击（滚进来的途中点了不算）
			if COIN_SKIP.has_point(point):
				skip_gamble()
				queue_redraw()
				return
			if COIN_THROW.has_point(point) or COIN_SLOT.has_point(point):
				start_gamble() # 点硬币本身也算抛
				queue_redraw()
				return
		if RESET_RECT.has_point(point):
			Sound.play("click")
			reset_game()
		elif phase == "card":
			if card_type == "reward" and card_offers.size() == 3:
				for i in range(UPGRADE_CARD_RECTS.size()):
					if UPGRADE_CARD_RECTS[i].has_point(point):
						Sound.play("click")
						apply_card(i)
						break
			elif CONTINUE_RECT.has_point(point) or CARD_RECT.has_point(point):
				Sound.play("click")
				apply_card()
		elif phase == "challenge":
			if card_type == "collect":
				click_coin(point)
		elif phase == "finished" or phase == "bankrupt":
			if CONTINUE_RECT.has_point(point):
				Sound.play("click")
				reset_game()
		else: # playing：UI 都在小猪活动区之外，由上面各分支各自处理
			if wheel != null and wheel.handle_click(point): # 抽奖按钮：点到了就不挥锤
				queue_redraw()
			elif PIG_BOUNDS.has_point(point): # 区内：挥锤照旧
				strike(point)
			# 区外点到空白：自由鼠标，不挥锤、也不清连击

func end_round_exhausted() -> void:
	# 体力见底：本轮结束（不是破产，余额保留，R 重开）
	end_reason = "exhausted"
	phase = "finished"
	award_meta_progress()
	Sound.play("fail")

func strike(point: Vector2) -> void:
	if phase != "playing" or cooldown > 0.0:
		return
	if stamina < float(settings.get("stamina_cost", 4)):
		stamina_flash = 0.4
		popups.append({"position": point + Vector2(-30, -40), "life": 0.7, "text": "体力不足"})
		end_round_exhausted()
		return
	hammer_position = point
	swing = 0.16
	cooldown = maxf(0.08, float(settings.swing_cooldown) * swing_cooldown_mul() - hammer_cooldown_reduction)
	stamina = maxf(0.0, stamina - maxf(1.0, float(settings.get("stamina_cost", 4)) - stamina_cost_reduction))
	var landed := false # 有没有打到东西：空挥要有和命中完全不同的声音
	for pig in pigs:
		# 判定跟着体型走：迷你猪最小最难打中，金猪最大最好打 —— 但它要三锤。
		# 再乘整体尺寸：猪画小了判定也要跟着小，否则"看着小、其实很好打"，还会跟邻居的判定打架
		var offset: Vector2 = (point - pig.position) / (Vector2(84.0, 64.0) * (pig_size() / PIG3D_SIZE) * pig_scale(pig.type) * hammer_reach_multiplier)
		if pig.hp > 0 and offset.length_squared() <= 1.0:
			hits += 1
			pig.flash = 0.14
			pig.hop = 0.24 # 受击跳动
			if combo_timer > 0.0:
				combo_count += 1
			else:
				combo_count = 1
			combo_timer = float(settings.get("combo_window", 1.5))
			var hit_damage := 1 + hammer_damage_bonus
			if hammer_damage_bonus > 0 and combo_count >= 3:
				hit_damage += 1 # 重锤 + 连击：連击热度达到 3 后再加一伤害
			pig.hp -= hit_damage
			if bool(pig.get("wheel_gold", false)): # 转盘金猪走专属结算：一锤 +¥200，压扁回弹后爆金币
				landed = true
				_resolve_wheel_gold_hit(pig)
				break
			if stamina_cost_reduction > 0.0 and combo_bonus_per_hit > 0 and hits % 4 == 0:
				stamina = minf(float(settings.get("stamina_max", 100)), stamina + 8.0) # 轻柄 + 连击卡：每四击回复体力
			if combo_count > combo_max:
				combo_max = combo_count
			if combo_count == int(settings.get("combo_threshold_fever", 5)):
				Sound.play("crit") # 连击刚到狂热线：一声上行琶音，手心发烫
			var base_pitch := 1.1 if pig.hp <= 0 else 0.85
			Sound.play("crack", minf(1.5, base_pitch + float(settings.get("combo_pitch_step", 0.05)) * (combo_count - 1)))
			landed = true
			if pig.hp <= 0:
				pig.respawn = float(settings.respawn_seconds)
				shake = float(settings.get("shake_duration", 0.12))
				var kind: String = String(pig.type.get("id", "piggy"))
				var gain := pig_value(pig.type)
				if gain > 0:
					gain = roundi(float(gain) * earnings_multiplier)
					if combo_count > 1:
						gain += (combo_count - 1) * combo_bonus_per_hit
						if earnings_multiplier > 1.0:
							gain += (combo_count - 1) * 2 # 贪婪 + 连击：连击层数继续放大收益
				if combo_count >= int(settings.get("combo_threshold_fever", 5)):
					for i in range(3): # 狂热：再撒两把，手气正旺的时候满桌是钱
						spawn_particles(pig.position, kind, gain)
				if gain < 0:
					# 催债猪：碎了要倒贴。双倍卡只放大收益、不放大损失（"收益翻倍"，不是"损失翻倍"），
					# 而且不该因为一锤失误就直接破产 —— 最多白干一场。
					score = maxi(1, score + gain)
				else:
					if double_timer > 0.0:
						gain *= 2
					gain = roundi(float(gain) * wheel_score_mul()) # 转盘得分翻倍：独立计时器，可与卡片双倍叠乘
					score += gain
				broken += 1
				spawn_particles(pig.position, kind, gain)
				var pcolor := Color("#ffe092")
				if gain < 0:
					pcolor = Color("#e06c5c")
					Sound.play("stamp", 1.0, 0.95)
					Sound.play("tails", 1.0, 0.45) # 下坠音：这不是好事
				else:
					if kind == "gold":
						pcolor = Color("#ffd76a")
						Sound.play("pop", 0.82) # 大，闷
						Sound.play("coin_land", 1.0, 0.55) # 金属余韵：一听就知道是大钱
					elif kind == "mini":
						Sound.play("pop", 1.35) # 小，脆
						Sound.play("cash", 1.2, 0.4)
					else:
						Sound.play("pop")
						Sound.play("cash", 1.0, 0.5) # 碎裂的闷响之后再给一声"叮"：钱到账了
				popups.append({"position": pig.position + Vector2(0, -55), "life": 0.9,
					"text": ("+¥" + str(gain) if gain > 0 else "-¥" + str(-gain)), "color": pcolor})
				pig_broken.emit(gain)
				if score >= int(settings.round_target):
					end_reason = "target"
					phase = "finished"
					award_meta_progress()
					Sound.play("win")
				elif score >= next_card:
					next_card += int(settings.card_interval)
					# 别在这一帧就弹：一分钱势的钱票还飘着、粒子刚炸开、音效还没响完。
					# 留半秒让反馈播完 —— 这段时间玩家还能继续砸，等于又多攒了几块。
					card_delay = float(settings.get("card_pop_delay", 0.45))
			break
	if wheel != null: # 转盘机会的连击计数：砸中 +1，漏砸（挥空）清零
		if landed:
			wheel.on_landed_hit()
		else:
			wheel.on_missed_swing()
	if not landed: # 挥空的"风声"要比命中轻，否则每次空挥都像打到了东西
		Sound.play("miss", 1.0, 0.7)

## 转盘金猪的结算：固定 +¥200（不吃卡片/连击加成），压扁回弹之后由转盘层引爆金币特效
func _resolve_wheel_gold_hit(pig: Dictionary) -> void:
	pig.hp = 0
	pig.respawn = 9999.0 # 不让普通重生逻辑捡走；转盘层在压扁动画结束后移除
	pig.gold_squash = 0.34
	var gain := 200
	score += gain
	shake = maxf(shake, float(settings.get("shake_duration", 0.12)))
	popups.append({"position": pig.position + Vector2(0, -55), "life": 0.9,
		"text": "+¥" + str(gain), "color": Color("#ffd76a")})
	Sound.play("pop", 0.85)
	pig_broken.emit(gain)
	if score >= int(settings.round_target):
		end_reason = "target"
		phase = "finished"
		award_meta_progress()
		Sound.play("win")

## 转盘 buff 的当前倍率。速度同时作用于小猪移动与重生倒计时；得分与卡片双倍相互独立
func wheel_speed_mul() -> float:
	return 1.0 if wheel == null else wheel.pig_speed_multiplier()

func wheel_score_mul() -> float:
	return 1.0 if wheel == null else wheel.score_multiplier()

## 转盘「直还账单」：免费清掉最便宜的 count 张（连带它们带出的利息/滞纳金单）
func pay_bills_free(count: int) -> int:
	var paid := 0
	for i in range(count):
		if bills.is_empty():
			break
		clear_cheapest_bill()
		paid += 1
	if paid > 0:
		popups.append({"position": Vector2(640, 300), "life": 1.6,
			"text": "转盘偿还了 " + str(paid) + " 张账单", "color": Color("#8fd0a8")})
		Sound.play("cash", 0.85)
	return paid

## 转盘「金猪降临」：临时加 count 只金色小猪（一锤 +¥200，到期没被砸中自动消失）
func spawn_wheel_gold_pigs(count: int) -> void:
	var t: Dictionary = wheel.gold_pig_type()
	for i in range(count):
		pigs.append({
			"position": _pick_gold_spawn_pos(),
			"type": t.duplicate(), "hp": 1, "max_hp": 1, "respawn": 9999.0,
			"flash": 0.0, "hop": 0.0, "seed": randf() * TAU,
			"hop_phase": randf() * TAU, "left": randf() < 0.5,
			"velocity": random_pig_velocity(t),
			"wheel_gold": true, "gold_squash": 0.0, "gold_life": wheel.GOLD_PIG_LIFE,
		})
		if use_3d:
			var vp := Pig3D.new()
			add_child(vp)
			pig3d.append(vp)
			vp.apply_type(t)
	popups.append({"position": Vector2(640, 300), "life": 1.6,
		"text": "金猪降临！每只 +¥200", "color": Color("#ffd76a")})
	Sound.play("crit")

## 给金猪挑个落脚处：多采几个候选点，留一个离现有猪群最远的，避免叠在一起
func _pick_gold_spawn_pos() -> Vector2:
	var area := PIG_BOUNDS.grow(-30.0)
	var best := Vector2(area.position.x + area.size.x * randf(),
		area.position.y + area.size.y * randf())
	var best_dist := -1.0
	for i in range(14):
		var cand := Vector2(area.position.x + area.size.x * randf(),
			area.position.y + area.size.y * randf())
		var nearest := 9999.0
		for p in pigs:
			if int(p.hp) > 0:
				nearest = minf(nearest, cand.distance_to(p.position))
		if nearest > best_dist:
			best_dist = nearest
			best = cand
	return best

## 移除一只猪（转盘金猪专用）：pigs 与 pig3d 按下标一一对应，必须同步删
func despawn_pig(index: int) -> void:
	if index < 0 or index >= pigs.size():
		return
	pigs.remove_at(index)
	if index < pig3d.size():
		var vp: Pig3D = pig3d[index]
		pig3d.remove_at(index)
		if is_instance_valid(vp):
			vp.queue_free()

func open_card() -> void:
	card_type = roll_card()
	card_offers.clear()
	card_offers = make_card_offers()
	card_pop = 0.0
	phase = "card"
	Sound.play("card")
	card_opened.emit()

func is_challenge(t: String) -> bool:
	return t == "collect" or t == "dodge"

func roll_card() -> String:
	# 弹出的牌统一是构筑选择；小游戏留在独立入口，不再打断敲猪节奏。
	return "reward"

func make_card_offers() -> Array[Dictionary]:
	var pool: Array[Dictionary] = [
		{"id":"heavy", "name":"重锤改造", "desc":"每次敲击额外 +1 伤害", "icon":"⚒", "color":"#e8836b"},
		{"id":"light", "name":"轻型锤柄", "desc":"每次挥锤少消耗 0.5 点体力", "icon":"↯", "color":"#66c0f4"},
		{"id":"reach", "name":"宽面锤头", "desc":"命中范围扩大 12%", "icon":"⌖", "color":"#75c7b2"},
		{"id":"swift", "name":"顺手轴承", "desc":"挥锤间隔缩短 0.025 秒", "icon":"➤", "color":"#9ec9ff"},
		{"id":"greed", "name":"贪婪本能", "desc":"敲碎小猪收益 +20%", "icon":"¥", "color":"#a4d007"},
		{"id":"combo", "name":"连击奖励", "desc":"连击时每击额外 +1 金钱", "icon":"×", "color":"#c084fc"},
		{"id":"stamina", "name":"体力扩容", "desc":"体力上限 +30，并恢复 45 点", "icon":"♥", "color":"#f472b6"},
		{"id":"coffee", "name":"慢燃咖啡", "desc":"自然恢复速度 +0.15 / 秒", "icon":"☕", "color":"#d99b70"},
		{"id":"double", "name":"双倍收益", "desc":"接下来 15 秒敲猪收益翻倍", "icon":"×2", "color":"#ffd166"},
		{"id":"cash", "name":"现金奖励", "desc":"立即获得 ¥" + str(int(settings.get("reward_card_amount", 35))), "icon":"＋", "color":"#efbc72"}
	]
	if not pig_population_doubled:
		pool.append({"id":"herd", "name":"猪群翻倍", "desc":"桌上存钱罐数量翻倍，整体缩小", "icon":"×2", "color":"#69b88e"})
	for card in pool:
		if String(card.id) == "heavy" and combo_bonus_per_hit > 0:
			card.desc = "已有连击联动：连击达到 3 层后再 +1 伤害"
		elif String(card.id) == "combo" and earnings_multiplier > 1.0:
			card.desc = "已有贪婪联动：连击每层额外 +2 金钱"
		elif String(card.id) == "greed" and combo_bonus_per_hit > 0:
			card.desc = "已有连击联动：连击层数也计入收益"
		elif String(card.id) == "stamina" and stamina_cost_reduction > 0.0:
			card.desc = "轻型锤柄联动：上限额外 +10，恢复 45 点"
	var offers: Array[Dictionary] = []
	while offers.size() < 3 and not pool.is_empty():
		var idx := randi() % pool.size()
		offers.append(pool.pop_at(idx))
	return offers


func double_pig_population() -> void:
	if pig_population_doubled or pigs.is_empty():
		return
	var original_count := pigs.size()
	var doubled_count := original_count * 2
	# 加一整桌新猪，再把全体缩小并重排成密集网格，避免 48 只挤在原来的 24 个点上。
	for i in range(original_count):
		var t := pick_pig_type()
		var hp := pig_max_hp(t)
		pigs.append({
			"position": Vector2.ZERO,
			"type": t, "hp": hp, "max_hp": hp, "respawn": 0.0,
			"flash": 0.0, "hop": 0.0, "seed": float(doubled_count + i),
			"hop_phase": randf() * TAU,
			"left": true,
			"velocity": random_pig_velocity(t)
		})
		note_pig_type(t)
		if use_3d:
			var vp := Pig3D.new()
			add_child(vp)
			pig3d.append(vp)
			vp.apply_type(t)
	pig_size_multiplier = 0.68
	var cols := ceili(sqrt(float(doubled_count) * PIG_BOUNDS.size.x / PIG_BOUNDS.size.y))
	var rows := ceili(float(doubled_count) / float(cols))
	for i in range(doubled_count):
		var row := int(i / cols)
		var col := i % cols
		var row_start := row * cols
		var row_items := mini(cols, doubled_count - row_start)
		var centered_col := float(col) + float(cols - row_items) * 0.5
		var pig: Dictionary = pigs[i]
		pig.position = Vector2(
			PIG_BOUNDS.position.x + (centered_col + 0.5) * PIG_BOUNDS.size.x / float(cols),
			PIG_BOUNDS.position.y + (float(row) + 0.5) * PIG_BOUNDS.size.y / float(rows))
	pig_population_doubled = true
	popups.append({"position": Vector2(640, 300), "life": 1.8, "text": "猪群翻倍！" + str(original_count) + " → " + str(doubled_count) + " 只"})
	Sound.play("coin_land", 1.0, 0.9)
	queue_redraw()


func apply_card(choice := -1) -> void:
	if phase != "card":
		return
	if card_type == "reward" and card_offers.size() == 3:
		if choice < 0 or choice >= card_offers.size():
			choice = 0
		var offer: Dictionary = card_offers[choice]
		match String(offer.id):
			"heavy":
				hammer_damage_bonus += 1
			"light":
				stamina_cost_reduction += 0.5
			"reach":
				hammer_reach_multiplier += 0.12
			"swift":
				hammer_cooldown_reduction += 0.025
			"greed":
				earnings_multiplier *= 1.2
			"combo":
				combo_bonus_per_hit += 1
			"stamina":
				settings["stamina_max"] = int(settings.get("stamina_max", 100)) + (40 if stamina_cost_reduction > 0.0 else 30)
				stamina = minf(float(settings.get("stamina_max", 100)), stamina + 45.0)
			"coffee":
				stamina_regen_bonus += 0.15
			"double":
				double_timer = maxf(double_timer, float(settings.get("double_duration", 15.0)))
			"herd":
				double_pig_population()
			"cash":
				score += int(settings.get("reward_card_amount", 20))
				Sound.play("cash")
		popups.append({"position": Vector2(640, 420), "life": 1.5, "text": String(offer.name) + " 已生效"})
		card_offers.clear()
		phase = "playing"
		return
	if card_type == "reward":
		var amount := int(settings.reward_card_amount)
		score += amount
		Sound.play("cash")
		popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "+¥" + str(amount)})
		phase = "playing"
	elif card_type == "double":
		double_timer = float(settings.double_duration)
		popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "双倍 ×2 激活"})
		phase = "playing"
	else:
		start_challenge()

func start_challenge() -> void:
	phase = "challenge"
	bill_timer = bill_time
	sync_cursor() # 凑钱小游戏需要系统箭头点硬币；躲催债仍使用锤子光标
	if card_type == "collect":
		collected = 0
		coins.clear()
		coin_spawn_timer = 0.0
	else:
		dodgers.clear()
		dodger_spawn_timer = 0.0
		dodge_lives = int(settings.dodge_lives)
		invincible_timer = 0.0

func finish_challenge(success: bool) -> void:
	coins.clear()
	dodgers.clear()
	if success:
		var reward := int(settings.bill_reward)
		score += reward
		clear_cheapest_bill() # 通关 = 付掉列表里最便宜的一张
		popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "付清 +¥" + str(reward)})
		phase = "playing"
		Sound.play("cash", 1.05)
	else:
		score -= bill_amount
		add_interest_bills() # 信用卡：每张没还的卡追加一笔利息（只此一处，不会重复计）
		add_overdue_bill() # 逾期：账单不但没消掉，还多出一张滞纳单
		Sound.play("stamp") # 盖章：一记实心闷击，比任何一行提示都直接
		if score <= 0:
			score = 0
			phase = "bankrupt"
			award_meta_progress()
			Sound.play("lose")
		else:
			popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "逾期 -¥" + str(bill_amount)})
			phase = "playing"
	collected = 0
	bill_timer = 0.0

func spawn_coin() -> void:
	var fake := randf() < float(settings.coin_fake_chance)
	var value := -int(settings.coin_value) if fake else int(settings.coin_value)
	coins.append({
		"position": Vector2(randf_range(160, 1120), randf_range(300, 620)),
		"velocity": Vector2(randf_range(-140, 140), randf_range(-90, 90)),
		"value": value, "fake": fake, "life": randf_range(2.2, 3.6)
	})

func update_collect(delta: float) -> void:
	coin_spawn_timer -= delta
	if coin_spawn_timer <= 0.0:
		spawn_coin()
		coin_spawn_timer = float(settings.coin_spawn_interval)
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		c.position += c.velocity * delta
		c.life -= delta
		if c.life <= 0.0:
			coins.remove_at(i)
	if collected >= bill_amount:
		finish_challenge(true)
	elif bill_timer <= 0.0:
		finish_challenge(false)

func update_dodge(delta: float) -> void:
	invincible_timer = maxf(0.0, invincible_timer - delta)
	dodger_spawn_timer -= delta
	if dodger_spawn_timer <= 0.0:
		spawn_dodger()
		dodger_spawn_timer = float(settings.dodger_spawn_interval)
	for i in range(dodgers.size() - 1, -1, -1):
		var d: Dictionary = dodgers[i]
		var dp: Vector2 = d.position
		var dir: Vector2 = hammer_position - dp
		if dir.length() > 4.0:
			d.position += dir.normalized() * float(settings.dodger_speed) * delta
		d.life -= delta
		if d.life <= 0.0:
			dodgers.remove_at(i)
			continue
		if invincible_timer <= 0.0:
			var cur: Vector2 = d.position
			if hammer_position.distance_squared_to(cur) <= 26.0 * 26.0:
				dodge_lives -= 1
				invincible_timer = float(settings.dodge_invincible)
				spawn_particles(cur)
				dodgers.remove_at(i)
	if dodge_lives <= 0:
		finish_challenge(false)
	elif bill_timer <= 0.0:
		finish_challenge(true)

func spawn_dodger() -> void:
	var side := randi() % 4
	var pos: Vector2
	match side:
		0: pos = Vector2(randf_range(80, 1200), 150)
		1: pos = Vector2(randf_range(80, 1200), 650)
		2: pos = Vector2(80, randf_range(150, 650))
		_: pos = Vector2(1200, randf_range(150, 650))
	dodgers.append({"position": pos, "life": randf_range(6.0, 9.0), "seed": randf() * TAU})

func click_coin(point: Vector2) -> void:
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		var cp: Vector2 = c.position
		if point.distance_squared_to(cp) <= 26.0 * 26.0:
			collected += int(c.value)
			var v := int(c.value)
			Sound.play("cash", 1.0 + float(clampi(collected, 0, 10)) * 0.03, 0.55) # 越捡越急，音高一点点往上爬
			popups.append({"position": cp + Vector2(0, -20), "life": 0.8,
				"text": ("+¥" + str(v) if v > 0 else "假币 -¥" + str(-v))})
			coins.remove_at(i)
			break

## 存钱罐碎了：里面攒的钱撒出来，罐子的陶片四溅。
## 金币数量跟着面额走（金猪一把钱，青猪叮当两声），陶片数量固定 —— 一眼就知道这一锤值不值。
func spawn_particles(center: Vector2, kind := "", value := 0) -> void:
	var coins: int = int(settings.get("burst_coin_base", 5)) + int(clampi(value, 0, 40) / int(settings.get("burst_coin_per", 6)))
	coins = mini(coins, int(settings.get("burst_coin_max", 10)))
	for i in range(coins + int(settings.get("burst_shards", 8))):
		if particles.size() >= MAX_PARTICLES: # 狂热时一秒连碎好几只，别让金币堆到掉帧
			break # 逐个判断：一批就是十几个，整批判断能从 65 一口气冲过 70
		var is_coin := i < coins
		# 金币飞得比陶片更远更飘（轻、会弹），陶片是闷着往下掉的
		var speed := randf_range(280.0, 520.0) if is_coin else randf_range(110.0, 250.0)
		# 横向必须真的分开：只用 cos(均匀角度) 的话大部分金币是直上直下的，
		# 落在屏幕上就是一柱"喷泉"，砸碎存钱罐要的是钱往两边撒。
		var vx := (1.0 if randf() < 0.5 else -1.0) * randf_range(0.35, 1.0) * speed
		var vy := -randf_range(0.45, 1.0) * speed
		particles.append({"position": center, "velocity": Vector2(vx, vy),
			"life": randf_range(0.6, 1.0), "coin": is_coin, "tint": kind,
			"spin": randf_range(0.0, TAU), "spin_speed": randf_range(4.0, 9.0)})

func text_at(value: String, pos: Vector2, size: int, color := Color("#f4e0b8")) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func text_center(value: String, center_x: float, y: float, size: int, color := Color("#f4e0b8")) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text_at(value, Vector2(center_x - width / 2, y), size, color)

func panel(rect: Rect2, color: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border > 0:
		style.set_border_width_all(border)
		style.border_color = border_color
	draw_style_box(style, rect)

func button(rect: Rect2, label: String, active := true, color := Color("#d49f59")) -> void:
	var col: Color = color if active else Color("#454b4c")
	var hovered: bool = active and rect.has_point(get_local_mouse_position())
	if hovered:
		col = col.lightened(0.16) # 悬停：填色亮一档 + 一圈亮边
	panel(rect, col, 12, 2 if hovered else 0, Color("#fff2d0"))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	text_at(label, Vector2(rect.get_center().x - width / 2, rect.position.y + 32), 21, Color("#252c2b"))

## 取 story.json 里的文案并把 {broken} / {score} / {bill} / {gap} 换成当前数值
func story_line(key: String, fallback: String) -> String:
	var s := String(story.get(key, fallback))
	var gap := maxi(0, int(settings.get("round_target", 120)) - score)
	var bname := String(bills[0].name) if not bills.is_empty() else "账单"
	return s.replace("{broken}", str(broken)).replace("{score}", str(score)).replace("{bill}", str(bill_amount)).replace("{gap}", str(gap)).replace("{unpaid}", str(unpaid_bills)).replace("{bill_name}", bname)


## 赌徒心理的实时诱导语：按「最该煽动哪一个」排优先级，同一时刻只显示一句
func gamble_hint() -> String:
	var cost := float(settings.get("stamina_cost", 4))
	if stamina < cost * 3.0:
		return story_line("gamble_tired", "手快抬不起来了……再挥一次？")
	if combo_count >= int(settings.get("combo_threshold_fever", 5)):
		return story_line("gamble_fever", "手感正热，趁现在多敲几只")
	if int(settings.get("round_target", 120)) - score <= int(settings.get("points_per_pig", 10)) * 3:
		return story_line("gamble_near", "就差 ¥{gap} 了 —— 再敲一只就够了")
	if not bills.is_empty() and score >= int(bills[0].amount):
		return story_line("gamble_canpay", "够还「{bill_name}」了 —— 还掉，还是再敲一只？")
	if score < bill_amount:
		return story_line("gamble_behind", "下一张账单 ¥{bill}，你手上只有 ¥{score}")
	if broken >= 5:
		return story_line("gamble_debt", "已经敲碎 {broken} 只了，你还在敲")
	return ""


func draw_gamble_hint() -> void:
	var line := gamble_hint()
	if line.is_empty():
		return
	text_center(line, 640, 692, 18, Color("#e7c98a")) # 底部信息栏第一行，暗底由 _draw 统一铺


const COIN_SLOT := Rect2(80, 392, 120, 120) # 桌边那枚等着被抛的硬币（落在桌内，避开猪活动区与底部说明栏）
const COIN_THROW := Rect2(72, 556, 136, 42) # 「抛一次」
const COIN_SKIP := Rect2(72, 604, 136, 38) # 「不要」
const GAMBLE_ROLL_TIME := 0.75 # 硬币从画面外滚到位的时间
const GAMBLE_FLIP_TIME := 1.3 # 抛硬币的动画时长
const GAMBLE_RESULT_TIME := 2.2 # 结果定格的时长


func gamble_threshold() -> int:
	return int(settings.get("gamble_threshold", 60))


## 那枚硬币：攒够阈值才从画面外滚进来等着；抛起来和看结果的时候整局暂停。返回 true = 本帧被硬币占住
func update_gamble(delta: float) -> bool:
	if gamble_state == "none":
		if not gamble_used and phase == "playing" and score >= gamble_threshold():
			gamble_state = "ready"
			gamble_t = 0.0 # 滚进来的动画从这里开始计时
			Sound.play("coin_roll")
			popups.append({"position": Vector2(112, 530), "life": 2.6, "text": "一枚硬币滚过来"})
		return false
	if gamble_state == "ready":
		if gamble_t < GAMBLE_ROLL_TIME and gamble_t + delta >= GAMBLE_ROLL_TIME:
			Sound.play("coin_land") # 滚到位的一声响
		gamble_t += delta
		return false
	gamble_t += delta
	if gamble_state == "flip" and gamble_t >= GAMBLE_FLIP_TIME:
		resolve_gamble()
	elif gamble_state == "result" and gamble_t >= GAMBLE_RESULT_TIME:
		gamble_state = "none"
	return true


## 抛：正反面在出手那一刻就定了，但玩家要等它落下来才知道
func start_gamble() -> void:
	gamble_heads = randf() < 0.5
	gamble_state = "flip"
	gamble_t = 0.0
	Sound.play("flip")


## 硬币落定：正面存款翻倍，反面一分不剩
func resolve_gamble() -> void:
	gamble_used = true
	gamble_state = "result"
	gamble_t = 0.0
	if gamble_heads:
		var before := score
		score *= 2
		Sound.play("heads")
		popups.append({"position": Vector2(452, 300), "life": 2.4, "text": "正面！¥" + str(before) + " → ¥" + str(score)})
		if score >= int(settings.round_target):
			end_reason = "coin"
			phase = "finished"
			award_meta_progress()
	else:
		score = 0
		shake = 0.6
		Sound.play("tails")
		popups.append({"position": Vector2(452, 300), "life": 2.4, "text": "反面…一分不剩"})


## 不赌：把硬币推到一边，本局它就不会再出现了
func skip_gamble() -> void:
	gamble_used = true
	gamble_state = "none"
	Sound.play("click") # 把硬币推到一边：一声轻响就够了，别把它弄得像赢了一样
	popups.append({"position": Vector2(92, 552), "life": 2.2, "text": "你把它推到一边"})


## 桌边那枚硬币：攒够阈值才从画面外滚进来，滚到位后一直轻轻鼓动 —— 没攒够时画面上根本不该有它
func draw_gamble_coin() -> void:
	if gamble_state != "ready" or gamble_used or phase != "playing":
		return
	var c := COIN_SLOT.get_center()
	var p := clampf(gamble_t / GAMBLE_ROLL_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - p, 3.0) # ease-out：滚进来后减速停住
	var pos := Vector2(lerpf(-80.0, c.x, e), c.y)
	draw_set_transform(Vector2(pos.x + 4.0, c.y + 58.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 52.0 * e, Color(0.05, 0.07, 0.07, 0.45)) # 影子跟着硬币一起到位
	draw_set_transform(Vector2.ZERO)
	if p < 1.0: # 滚的过程中在自转：绕竖轴翻，停下前转得越来越慢
		draw_coin_face(pos, 50.0, maxf(absf(cos(gamble_t * 15.0)), 0.25), true)
		return
	var pulse: float = 1.0 + sin(elapsed * 3.2) * 0.05 # 诱惑不该是静止的
	draw_coin_face(pos, 50.0 * pulse, 1.0, true)
	text_center("正面翻倍 / 反面清零", c.x, c.y + 76, 14, Color("#e7c98a"))
	button(COIN_THROW, "抛一次", true, Color("#d4a24c"))
	button(COIN_SKIP, "不要", true, Color("#7d8a88"))


## 一枚硬币：sx 是横向压缩（模拟绕竖轴翻转，接近 0 时看到的是侧面）
## 飞在空中的金币：只画三笔（边 + 面 + 一道内圈高光），不做齿边也不印字。
## 齿边和"¥"留给桌上/抛起的那几枚 —— 它们在镜头前停着，弹出去的金币是看不清细节的。
## 每枚省 13 次绘制，狂热时满桌金币才不会掉帧。sx 是横向压缩，模拟绕竖轴翻滚。
func draw_coin_simple(c: Vector2, r: float, sx: float, alpha := 1.0) -> void:
	if sx < 0.32: # 侧面：只剩一条厚度
		var e0 := Color("#8a6a1f")
		e0.a = alpha
		panel(Rect2(c - Vector2(r * 0.2, r), Vector2(r * 0.42, r * 2.0)), e0, 4)
		return
	draw_set_transform(c, 0.0, Vector2(sx, 1.0))
	var edge := Color("#8a6a1f")
	var face := Color("#f7cf5c") # 比桌上那枚亮一档：它在往深绿的桌面上飞，暗了就融进去了
	var shine := Color("#ffe89a")
	edge.a = alpha
	face.a = alpha
	shine.a = alpha
	draw_circle(Vector2.ZERO, r, edge)
	draw_circle(Vector2.ZERO, r * 0.85, face)
	draw_arc(Vector2.ZERO, r * 0.6, -0.9, 0.5, 8, shine, r * 0.16)
	draw_set_transform(Vector2.ZERO)


func draw_coin_face(c: Vector2, r: float, sx: float, heads: bool) -> void:
	if sx < 0.3: # 侧面：只剩一条厚度
		panel(Rect2(c - Vector2(r * 0.2, r), Vector2(r * 0.4, r * 2.0)), Color("#8a6a1f"), 5)
		return
	draw_set_transform(c, 0.0, Vector2(sx, 1.0))
	var edge := Color("#8a6a1f")
	var face := Color("#f2c14e") if heads else Color("#a8842f")
	var inner := Color("#ffe08a") if heads else Color("#8a6c2c")
	draw_circle(Vector2.ZERO, r, edge)
	draw_circle(Vector2.ZERO, r * 0.87, face)
	draw_circle(Vector2.ZERO, r * 0.66, inner)
	for i in range(12): # 齿边
		var a := float(i) / 12.0 * TAU
		draw_circle(Vector2(cos(a) * r * 0.94, sin(a) * r * 0.94), r * 0.07, edge)
	text_center("¥" if heads else "0", 0.0, r * 0.36, int(r * 0.95), Color("#7a5410") if heads else Color("#4a3a18"))
	draw_set_transform(Vector2.ZERO)


## 抛的那一下：硬币在屏幕中间翻转、落定，这段时间整局是停住的
func draw_gamble_flip() -> void:
	if gamble_state != "flip" and gamble_state != "result":
		return
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.055, 0.033, 0.02, 0.72))
	var p: float = 1.0 if gamble_state == "result" else clampf(gamble_t / GAMBLE_FLIP_TIME, 0.0, 1.0)
	var c := Vector2(640, 320)
	var h: float = -sin(p * PI) * 130.0 # 抛起来再落下
	var sx: float = 1.0
	var face_heads := gamble_heads
	if p < 0.76: # 空中翻转：正反面交替
		var spin := p * 34.0
		sx = maxf(absf(cos(spin)), 0.22)
		face_heads = cos(spin) >= 0.0
	else: # 定格：翻成这一抛的结果
		sx = lerpf(0.34, 1.0, clampf((p - 0.76) / 0.24, 0.0, 1.0))
		face_heads = gamble_heads
	draw_set_transform(Vector2(c.x, c.y + 168.0), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, maxf(18.0, 62.0 + h * 0.12), Color(0.02, 0.04, 0.04, 0.5)) # 抛得越高影子越小
	draw_set_transform(Vector2.ZERO)
	draw_coin_face(c + Vector2(0.0, h), 66.0, sx, face_heads)
	if gamble_state == "result":
		text_center("正面" if gamble_heads else "反面", 640, 232, 46, Color("#ffe092") if gamble_heads else Color("#e7a6a4"))
		text_center(story_line("coin_heads", "翻倍了。原来可以这样。") if gamble_heads else story_line("coin_tails", "没了，全没了。"), 640, 486, 22, Color("#c9bfae"))
	else:
		text_center("…", 640, 232, 46, Color("#e7c98a"))


## 一叠没付的账单纸（HUD 里的小图标）
func draw_bill_stack(base: Vector2, count: int) -> void:
	var n := mini(count, 6)
	for i in range(n):
		var off := Vector2(sin(i * 2.1) * 5.0, -float(i) * 6.0) # 偏移要够大，否则叠纸看起来只有一张
		var last: bool = i == n - 1
		panel(Rect2(base + off, Vector2(46, 30)), Color("#f3ead2") if last else Color("#e6dcc4"), 3)
	# 这里原来在纸右边写着「待还 ¥xxx」，正好压住中部那行提示：HUD 这一条只有 98px 高，
	# 横向再塞一个数字就撞车。待还总额在账本封面和桌上那沓纸上有（「合计 ¥」），不缺这一处。


## 电费没缴 = 停电：桌面明显压暗，四周再收一圈暗角。
## ⚠️ 调用位置是硬要求：必须紧跟 draw_desk()、画在 HUD 和小猪之前。
## 盖在猪身上会遮挡要打的目标，盖在 UI 上会挡住按钮 —— 两个都不能碰。
## 只压桌面本身，猪和 UI 仍清晰可见。
func draw_blackout() -> void:
	if blackout_fade <= 0.01:
		return
	var alpha: float = bills_fx.number("blackout", "darkness_alpha", 0.38) * blackout_fade
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.02, 0.011, 0.005, alpha))

## 暗角贴图：中心透明、越靠边越黑，开局生成一次。
## 用贴图而不是叠十几层矩形，一帧就两次 draw，加再多猪也不心疼。
func _make_vignette() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ink := Color(0.015, 0.02, 0.035)
	for y in range(n):
		for x in range(n):
			var dx := float(x) / float(n - 1) * 2.0 - 1.0
			var dy := float(y) / float(n - 1) * 2.0 - 1.0
			var d := mini(sqrt(dx * dx + dy * dy) / 1.414, 1.0)
			img.set_pixel(x, y, Color(ink.r, ink.g, ink.b, pow(d, 2.4)))
	return ImageTexture.create_from_image(img)


## 赌桌（3D 绒面桌贴图，或回退成 2D 三层面板）。单独抽出来是为了开场序幕能"只铺桌子不画 HUD"。
func draw_desk() -> void:
	if use_desk_3d and desk3d != null:
		draw_texture(desk3d.get_texture(), Vector2.ZERO) # 3D 赌场赌桌
		return
	# 2D 回退桌：胡桃木外框、深色木台面、黄铜镶边。
	panel(Rect2(98, 272, 1084, 402), Color("#1c120a"), 42)
	panel(Rect2(106, 260, 1068, 398), Color("#38251a"), 40)
	panel(Rect2(120, 274, 1040, 370), Color("#b18a45"), 36)
	panel(Rect2(128, 282, 1024, 354), Color("#402917"), 31)
	panel(Rect2(145, 299, 990, 320), Color("#573a20"), 25)
	# 台面上的柔和走向和暗角，保留足够平整的猪活动区。
	for y in range(315, 610, 38):
		draw_line(Vector2(152, y), Vector2(1128, y + 3), Color(0.78, 0.60, 0.40, 0.05), 1)
	draw_rect(Rect2(142, 296, 996, 326), Color("#d1ad59", 0.72), false, 2)
	draw_rect(Rect2(151, 305, 978, 308), Color("#d1ad59", 0.30), false, 1)
	# 椭圆下注圈和庄家区线，线条压在绒面之下，不干扰目标判定。
	draw_set_transform(Vector2(640, 455), 0.0, Vector2(1.65, 0.55))
	draw_arc(Vector2.ZERO, 170, 0.0, TAU, 96, Color("#d4ac51", 0.66), 2.2)
	draw_arc(Vector2.ZERO, 132, 0.0, TAU, 96, Color("#d4ac51", 0.40), 1.5)
	draw_arc(Vector2.ZERO, 34, 0.0, TAU, 64, Color("#e3c36e", 0.76), 2.0)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(220, 350), Vector2(1060, 350), Color("#d4ac51", 0.28), 1.5)
	# 牌角与筹码叠在桌沿区域，中央仍留给小猪和锤子。
	draw_table_chip_stack(Vector2(190, 575), Color("#a63832"), 4)
	draw_table_chip_stack(Vector2(224, 590), Color("#233e70"), 3)
	draw_set_transform(Vector2(1045, 582), -0.13, Vector2.ONE)
	draw_rect(Rect2(-30, -48, 58, 82), Color("#8d3029"), true)
	draw_rect(Rect2(-25, -52, 58, 82), Color("#eee3c8"), true)
	draw_rect(Rect2(-15, -42, 38, 62), Color("#b43f35"), false, 2)
	draw_set_transform(Vector2.ZERO)


func draw_table_chip_stack(center: Vector2, face: Color, count: int) -> void:
	for i in range(count):
		var c := center + Vector2(0, -float(i) * 6.0)
		draw_circle(c + Vector2(1, 3), 17, Color(0.02, 0.03, 0.02, 0.35))
		draw_circle(c, 16, face.darkened(0.35))
		draw_circle(c, 13, face)
		draw_arc(c, 10, 0.0, TAU, 24, Color("#f3e8d0"), 2)
		for pip in range(6):
			var angle := TAU * float(pip) / 6.0
			draw_line(c + Vector2(cos(angle), sin(angle)) * 11.0, c + Vector2(cos(angle), sin(angle)) * 14.0, Color("#f3e8d0"), 2)


## 站在桌后的那群黑影：看不清脸，就那么默默看着（他们不说话，但一直在）
func draw_watchers() -> void:
	var n := int(settings.get("watchers", 6))
	for i in range(n):
		var j1: float = fmod(absf(sin(float(i) * 12.9898)) * 43758.5453, 1.0) # 每人固定的体型/明暗差异
		var j2: float = fmod(absf(sin(float(i) * 78.233)) * 12345.6789, 1.0)
		var x: float = lerpf(90.0, 1175.0, float(i) / maxf(1.0, float(n - 1))) + (j1 - 0.5) * 46.0
		var bob: float = sin(elapsed * 0.7 + float(i) * 1.3) * 4.0 # 轻微起伏，别站成雕像
		var sway: float = sin(elapsed * 0.45 + float(i) * 2.1) * 3.0
		var shoulder_y: float = 152.0 + j2 * 48.0 + bob # 身高差拉大：高的只露头，矮的露出半肩
		var head_r: float = 22.0 + j1 * 14.0
		var body_w: float = 28.0 + j2 * 20.0
		var col := Color(0.04, 0.06, 0.06, 0.5 + j2 * 0.32)
		draw_colored_polygon(PackedVector2Array([ # 肩与小半个身子（下半部分会被 HUD 面板压住）
			Vector2(x - body_w - sway, 360.0),
			Vector2(x - body_w * 0.62, shoulder_y + sway * 0.3),
			Vector2(x + body_w * 0.62, shoulder_y - sway * 0.3),
			Vector2(x + body_w + sway, 360.0),
		]), col)
		panel(Rect2(x - 9, shoulder_y - head_r - 16, 18, 20), col, 6) # 脖子
		draw_set_transform(Vector2(x, shoulder_y - head_r - 18), sway * 0.01, Vector2(1.0, 1.16))
		draw_circle(Vector2.ZERO, head_r, col)
		draw_set_transform(Vector2.ZERO)
		if j1 > 0.35: # 只有一部分人有眼神 —— 更瘆人
			var eye := Color("#e2cd96", 0.26 + j2 * 0.2)
			draw_circle(Vector2(x - head_r * 0.36, shoulder_y - head_r - 22), 2.0, eye)
			draw_circle(Vector2(x + head_r * 0.36, shoulder_y - head_r - 22), 2.0, eye)


## 开场序幕：交代「欠了一屁股债 + 只能敲存钱罐 + 停不下来」
func draw_intro() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.075, 0.045, 0.026, 0.82)) # 半透，让桌子在序幕里压暗可见
	text_center(String(story.get("intro_title", "最后期限")), 640, 196, 42, Color("#efbc72"))
	var lines: Array = story.get("intro_lines", [])
	for i in range(lines.size()):
		var last: bool = i == lines.size() - 1
		text_center(String(lines[i]), 640, 292 + i * 50, 22, Color("#ffe092") if last else Color("#d8e2dc"))
	button(INTRO_RECT, String(story.get("intro_button", "敲开第一只")))
	text_center(String(story.get("intro_hint", "点按钮或按任意键开始")), 640, 600, 17, Color("#c9b08a"))


func _draw() -> void:
	if bg_tex != null: # 西部酒馆全景：拉伸铺满，再压一层暗保持 HUD 可读
		draw_texture_rect(bg_tex, Rect2(0, 0, 1280, 800), false)
		draw_rect(Rect2(0, 0, 1280, 800), Color(0.0, 0.0, 0.0, 0.35))
	else:
		draw_rect(Rect2(0, 0, 1280, 800), Color("#241610")) # 背景图没读到时用回纯色底
		draw_circle(Vector2(1050, 180), 380, Color("#312012"))
	draw_watchers() # 桌后那排黑影：画在桌子之前，才像"站在你身后看着"
	draw_desk() # 桌面先铺，后面的 HUD / 猪 / 卡片都在它上面
	if intro_open:
		draw_intro() # 序幕期间只留一张昏暗的桌子，不画 HUD
		draw_blackout()
		return
	text_at(String(story.get("title", "敲猪还债")), Vector2(54, 71), 36)
	text_at("计科2403  ·  " + String(story.get("subtitle", "账单今天到期")), Vector2(55, 103), 16, Color("#c9b08a"))
	var stamina_max := float(settings.get("stamina_max", 100))
	var stamina_cost := float(settings.get("stamina_cost", 4))
	var low: bool = stamina < stamina_cost * 3.0
	var bar_color := Color("#e06c5c") if low or stamina_flash > 0.0 else Color("#8fd0a8")
	if stamina_flash > 0.0:
		bar_color = Color("#e06c5c").lerp(Color.WHITE, 0.5 * sin(stamina_flash * 40) + 0.5)
	text_at("体力 " + str(int(stamina)) + " / " + str(int(stamina_max)), Vector2(330, 103), 20, bar_color)
	text_at("游戏日期 " + format_game_date(game_day), Vector2(745, 103), 17, Color("#efbc72"))
	panel(Rect2(500, 90, 220, 13), Color("#241a10"), 5)
	panel(Rect2(500, 90, 220 * clampf(stamina / stamina_max, 0.0, 1.0), 13), bar_color, 5)
	if Sound.muted: # 静音得有个可见的出口，否则玩家会以为游戏坏了
		text_at("已静音 · M 恢复", Vector2(975, 103), 16, Color("#b59a7c"))
	if double_timer > 0.0:
		text_at("双倍中 ×2 剩 " + ("%.0f" % double_timer) + "s", Vector2(975, 103), 20, Color("#a4d007"))
	button(RESET_RECT, "重新开始")
	panel(Rect2(52, 137, 1176, 98), Color("#37251a"))
	text_at("余额 ¥", Vector2(80, 174), 17, Color("#c9b08a"))
	text_at(str(score).pad_zeros(3), Vector2(80, 214), 32, Color("#efbc72"))
	text_at("敲碎 " + str(broken) + " 只", Vector2(255, 205), 24)
	text_at("跨局碎片 " + str(meta_shards), Vector2(255, 227), 14, Color("#efbc72"))
	# 猪的价目表移到底部整行：中部这块只有 220px 宽，四种猪的名字加金额会被账单纸压住
	text_at("攒够 ¥" + str(int(settings.get("card_first_at", 120))) + " 后选择一项升级", Vector2(480, 196), 18, Color("#c9b08a"))
	# 右上角原来写着「目标 ¥120 摆脱破产」+ 一条进度条，去掉了：把目标写在脸上，玩家就是在为数字打工，
	# 而不是"再敲一只就够"。round_target 仍然生效（攒够即结算），只是不让玩家盯着倒计时。
	# 靠右摆：原来在 x=700，纸叠有 46px 宽、还往上叠 6 层，正好盖住中部那句提示的"中途"两个字。
	# 右侧 996..1078 是空的，放这儿既压不到字，也离右边的账单面板近、语义连贯。
	if combo_count >= 2:
		var fever: int = int(settings.get("combo_threshold_fever", 5))
		var k: float = combo_timer / float(settings.get("combo_window", 1.5))
		var size: int = 28 + minf(combo_count - 2, 6) * 4
		var color: Color = Color("#a4d007") if combo_count >= fever else Color("#efbc72")
		color.a = 0.55 + k * 0.45
		var txt: String = "连击 ×" + str(combo_count)
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		text_at(txt, Vector2(640 - w / 2.0, 268), size, color) # 下移一点，别被顶部信息面板压住
		if combo_count >= fever:
			text_at("狂热！", Vector2(597, 264), 18, Color("#ffe092"))
	for i in range(pigs.size()):
		draw_pig_shaken(pigs[i], i)
	for p in particles:
		var pp: Vector2 = p.position
		if shake > 0.0:
			pp += Vector2(shake_x, shake_y)
		var alpha: float = minf(1.0, p.life * 2.0) # 最后半秒淡出，不然是一堆碎片凭空消失
		if p.coin:
			# 下限 0.36：翻到完全侧面时只剩一根竖条，看着不像钱，像根针
			draw_coin_simple(pp, 13.0, maxf(absf(cos(float(p.get("spin", 0.0)))), 0.36), alpha)
			continue
		var color := Color("#e7a6a4") # 陶片：碎的是罐子，颜色跟着罐子走
		match String(p.get("tint", "")):
			"gold": color = Color("#c99a4a") # 陶片压暗一档：金猪的碎片别和它撒出的金币抢眼
			"mini": color = Color("#a8e0ef")
			"debt": color = Color("#e0503f")
			"stripe": color = Color("#cfe3e8")
			"glass": color = Color("#cfe8ee")
			"fat": color = Color("#c9743f")
		color.a = alpha
		draw_set_transform(pp, float(p.get("spin", 0.0)) * 0.6, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(-5, -3), Vector2(4, -4), Vector2(5, 3), Vector2(-4, 4)]), color)
		draw_set_transform(Vector2.ZERO)
	for p in popups:
		text_at(p.text, p.position, 28, p.get("color", Color("#ffe092")))
	panel(Rect2(0, 664, 1280, 136), Color(0.06, 0.09, 0.09, 0.66), 0) # 3D 桌面是暖色，底部说明要压一条暗底才看得清
	if phase == "playing":
		draw_gamble_hint() # 赌徒心理的实时诱导，放在底部信息栏第一行
	var active_names := active_synergy_names()
	if active_names != "暂无":
		text_center("账单联动：" + active_names, 640, 714, 15, Color("#ffb86b"))
	text_center("移动鼠标瞄准 · 左键挥锤 · 小猪会跑动，挥锤耗体力 · R 重开", 640, 736, 22)
	text_center(pig_legend() + "　｜　点桌边账单查看期限与联动", 640, 770, 15, Color("#c9b08a"))
	if cursor_hidden:
		draw_hammer() # 锤子是光标：只在它真的顶掉了系统箭头时才画（躲催债那关也要看得见自己）
	if phase == "playing":
		draw_gamble_coin() # 硬币画在锤子之后：鼠标移过去时锤子不能把硬币盖住
	elif phase == "challenge":
		if card_type == "collect":
			draw_collect()
		else:
			draw_dodge()
	else:
		draw_rect(Rect2(0, 0, 1280, 800), Color(0.04, 0.07, 0.07, 0.78))
		if phase == "card":
			draw_card()
		elif phase == "finished":
			draw_finished()
		else:
			draw_bankrupt()
	draw_pig_tip() # 新猪的说明书：画在猪之上、卡片之下（打开卡片时别挡着）
	draw_bills() # 桌角那一沓账单纸，画在最上层：鼠标移到它上面时锤子不能把纸盖住
	if bill_open:
		draw_ledger()
	if bill_detail >= 0:
		draw_bill_detail()
	draw_collection_flash() # 催收警告：只在屏幕边缘画一圈，不挡任何操作
	draw_gamble_flip() # 抛硬币的翻面/落定动画，永远盖在最上层
	draw_blackout() # 电费未缴时覆盖全屏

func draw_pig(pig: Dictionary, index: int) -> void:
	if bool(pig.get("wheel_gold", false)):
		_draw_gold_aura(pig) # 金猪的自发光光晕画在身后，和普通猪一眼区分
	var t: Dictionary = pig.get("type", {})
	var tex: Texture2D = pig_tex.get(String(t.get("id", "piggy")))
	if tex != null: # 有贴图走贴图：AI 素材替掉图元 3D 模型
		draw_pig_sprite(pig, tex)
		return
	if use_3d and index < pig3d.size():
		var s := pig_size() / 190.0 # 阴影 / 裂纹 / 抖动幅度都按绘制尺寸等比缩放
		var pos: Vector2 = pig.position + PIG3D_OFFSET
		if pig.flash > 0.0:
			pos.x += sin(pig.flash * 90) * 8 * s
		if pig.hop > 0.0:
			pos.y -= sin(pig.hop / 0.24 * PI) * 26 * s # 受击向上跳起
		draw_set_transform(pig.position + Vector2(0, 43 * s), 0, Vector2(1, 0.25))
		draw_circle(Vector2.ZERO, 62 * s, Color(0.12, 0.1, 0.08, 0.27)) # 桌面投影
		draw_set_transform(Vector2.ZERO)
		if bool(pig.get("wheel_gold", false)): # 金猪：压扁回弹形变 + 暖黄描边，走专属分支
			var sq := _gold_squash_scale(pig)
			draw_set_transform(pos, 0.0, sq)
			draw_texture_rect(pig3d[index].get_texture(),
				Rect2(Vector2(-pig_size() / 2.0, -pig_size() / 2.0), Vector2(pig_size(), pig_size())), false)
			draw_arc(Vector2.ZERO, pig_size() * 0.5, 0.0, TAU, 44,
				Color(1.0, 0.8, 0.3, 0.5 + 0.25 * sin(elapsed * 5.0 + float(pig.seed))), 2.5)
			draw_set_transform(Vector2.ZERO)
			return
		var rect := Rect2(pos - Vector2(pig_size() / 2.0, pig_size() / 2.0), Vector2(pig_size(), pig_size()))
		draw_texture_rect(pig3d[index].get_texture(), rect, false)
		var dmg: int = int(pig.get("max_hp", 2)) - int(pig.hp) # 挨了几锤就画几道裂：金猪能裂两道
		if dmg >= 1:
			draw_set_transform(pos)
			draw_polyline(PackedVector2Array([Vector2(-26, -22) * s, Vector2(-13, -9) * s, Vector2(-23, 5) * s, Vector2(-7, 23) * s]), Color("#985f69"), 3, true)
			if dmg >= 2:
				draw_polyline(PackedVector2Array([Vector2(20, -30) * s, Vector2(8, -14) * s, Vector2(22, -2) * s, Vector2(11, 22) * s]), Color("#985f69"), 3, true)
			draw_set_transform(Vector2.ZERO)
		return
	draw_pig_flat(pig)


## 金猪的自发光光晕：两层暖光随时间明暗呼吸，外圈四个闪光点绕行
func _draw_gold_aura(pig: Dictionary) -> void:
	var s := pig_size() / PIG3D_SIZE
	var pulse := 0.5 + 0.5 * sin(elapsed * 5.0 + float(pig.seed))
	var c: Vector2 = pig.position
	draw_circle(c, 64.0 * s * (1.06 + 0.08 * pulse), Color(1.0, 0.82, 0.3, 0.10 + 0.08 * pulse))
	draw_circle(c, 52.0 * s * (1.03 + 0.06 * pulse), Color(1.0, 0.88, 0.45, 0.10 + 0.10 * pulse))
	for i in range(4):
		var a := elapsed * 1.9 + float(i) * TAU / 4.0 + float(pig.seed)
		draw_circle(c + Vector2(cos(a), sin(a)) * 56.0 * s, 2.6 * s,
			Color(1.0, 0.95, 0.62, 0.35 + 0.45 * pulse))


## 金猪被砸中瞬间的压扁回弹：前半程压扁（横宽竖窄），后半程弹回原状
func _gold_squash_scale(pig: Dictionary) -> Vector2:
	var t: float = float(pig.get("gold_squash", 0.0))
	if t <= 0.0:
		return Vector2.ONE
	var p := clampf(1.0 - t / 0.34, 0.0, 1.0)
	var k := sin(p * PI) # 0 → 1 → 0
	return Vector2(1.0 + 0.38 * k, 1.0 - 0.42 * k)


## 贴图猪（AI 西部素材）：移动时按 hop_phase 正弦弹跳 —— 视觉上移 = -abs(sin) × 跳高，
## 落地瞬间（sin 过零点附近）短暂挤压（0.9 / 1.08），空中轻微拉伸（1.05）；
## 被敲中的大跳（hop > 0）、受击抖动、死亡淡出都沿用原参数。
func draw_pig_sprite(pig: Dictionary, tex: Texture2D) -> void:
	var t: Dictionary = pig.get("type", {})
	var side := pig_size() * pig_scale(t) # 贴图最长边的绘制长度：跟整体尺寸与猪种体型走
	var k := side / PIG3D_SIZE # 阴影 / 裂纹 / 抖动幅度按绘制尺寸等比缩放（沿用原 3D 路径）
	var pos: Vector2 = pig.position + PIG3D_OFFSET
	if pig.flash > 0.0:
		pos.x += sin(pig.flash * 90) * 8 * k
	var squash := Vector2.ONE
	if pig.hp > 0:
		var spd: float = pig.velocity.length()
		var bounce := absf(sin(float(pig.get("hop_phase", 0.0))))
		var hop_h := lerpf(14.0, 20.0, clampf(spd / 160.0, 0.0, 1.0)) # 快猪跳高一点
		pos.y -= bounce * hop_h * k
		if bounce < 0.25: # 落地瞬间：短暂挤压
			squash = Vector2(1.08, 0.9)
		else: # 空中：轻微拉伸
			squash = Vector2(1.0, 1.0 + 0.05 * bounce)
	if pig.hop > 0.0:
		pos.y -= sin(pig.hop / 0.24 * PI) * 26 * k # 受击向上跳起（大跳，沿用原参数）
	draw_set_transform(pig.position + Vector2(0, 43 * k), 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, 62 * k, Color(0.12, 0.1, 0.08, 0.27)) # 桌面投影：画在脚下，不跟着跳
	draw_set_transform(Vector2.ZERO)
	var ts := tex.get_size()
	var fit := side / maxf(ts.x, ts.y) # 最长边对齐 side，等比缩放，不拉坏素材比例
	var flip := 1.0 if bool(pig.get("left", true)) else -1.0 # 素材朝左画；往右走时镜像
	pos.y += (1.0 - squash.y) * side * 0.5 # 以脚为轴挤压：中心下移，脚底保持贴地
	draw_set_transform(pos, 0.0, Vector2(flip * squash.x * fit, squash.y * fit))
	draw_texture(tex, -ts / 2.0)
	draw_set_transform(Vector2.ZERO)
	var dmg: int = int(pig.get("max_hp", 2)) - int(pig.hp) # 挨了几锤就画几道裂：金猪能裂两道
	if dmg >= 1:
		draw_set_transform(pos, 0.0, Vector2(flip * k, k))
		draw_polyline(PackedVector2Array([Vector2(-26, -22), Vector2(-13, -9), Vector2(-23, 5), Vector2(-7, 23)]), Color("#985f69"), 3, true)
		if dmg >= 2:
			draw_polyline(PackedVector2Array([Vector2(20, -30), Vector2(8, -14), Vector2(22, -2), Vector2(11, 22)]), Color("#985f69"), 3, true)
		draw_set_transform(Vector2.ZERO)


## 2D 回退版（headless / pig_3d: false）：形状照旧，但颜色与大小跟着种类走
func draw_pig_flat(pig: Dictionary) -> void:
	var t: Dictionary = pig.get("type", {})
	var sc := pig_scale(t) * (pig_size() / PIG3D_SIZE) # 2D 回退也跟着整体尺寸缩
	var body := Color(String(t.get("color", "#f0b6b5")))
	if bool(t.get("glass", false)):
		body.a = float(t.get("alpha", 0.42)) # 玻璃罐：罐壁半透明，看得见里面
	var dark := Color(String(t.get("accent", "#d9959a")))
	var eye := Color(String(t.get("eye", "#433b3a")))
	var pos: Vector2 = pig.position
	if pig.flash > 0.0:
		pos.x += sin(pig.flash * 90) * 8
	if pig.hop > 0.0:
		pos.y -= sin(pig.hop / 0.24 * PI) * 26 # 受击向上跳起
	var scale_y := 1.0 - 0.08 * sin(elapsed * 2 + pig.seed)
	draw_set_transform(pos, 0, Vector2(sc, sc * scale_y))
	draw_set_transform(pos + Vector2(0, 43 * sc), 0, Vector2(sc, sc * 0.25))
	draw_circle(Vector2.ZERO, 75, Color(0.12, 0.1, 0.08, 0.27))
	draw_set_transform(pos, 0, Vector2(sc, sc * scale_y))
	draw_line(Vector2(-64, -5), Vector2(-88, -16), dark.lightened(0.25), 8)
	draw_arc(Vector2(-88, -24), 9, 0.0, PI * 1.6, 16, dark.lightened(0.25), 5)
	draw_rect(Rect2(-44, 34, 18, 22), dark.darkened(0.15))
	draw_rect(Rect2(28, 34, 18, 22), dark.darkened(0.15))
	draw_set_transform(pos, 0, Vector2(1.25 * sc, sc * scale_y))
	draw_circle(Vector2.ZERO, 56, dark)
	if bool(t.get("glass", false)): # 玻璃罐：先把里面那堆钱画上，再盖一层半透明的罐壁
		for i in range(5):
			draw_circle(Vector2(-28 + i * 14, 12 - (i % 2) * 9), 8, Color("#d9a441"))
	draw_circle(Vector2(0, -5), 52, body if pig.flash <= 0.0 else Color("#ffe5d3"))
	draw_set_transform(pos, 0, Vector2(sc, sc * scale_y))
	if bool(t.get("striped", false)): # 搪瓷条纹：2D 回退版画几条竖道就够认了
		var stp := Color(String(t.get("stripe", "#4f7d8c")))
		for i in range(3):
			draw_line(Vector2(-34 + i * 24, -40), Vector2(-34 + i * 24, 34), stp, 11)
	draw_colored_polygon(PackedVector2Array([Vector2(23, -39), Vector2(39, -69), Vector2(53, -32)]), dark.lightened(0.2))
	draw_colored_polygon(PackedVector2Array([Vector2(-13, -45), Vector2(0, -71), Vector2(17, -44)]), dark.lightened(0.2))
	draw_line(Vector2(-21, -32), Vector2(8, -34), Color("#81595f"), 5)
	draw_circle(Vector2(31, -13), 5, eye)
	draw_circle(Vector2(33, -15), 1.5, Color.WHITE)
	draw_set_transform(pos + Vector2(53, 10) * sc, 0, Vector2(1.15 * sc, 0.8 * sc * scale_y))
	draw_circle(Vector2.ZERO, 23, dark)
	draw_circle(Vector2(-8, 1), 3.5, Color("#8e5b69"))
	draw_circle(Vector2(8, 1), 3.5, Color("#8e5b69"))
	draw_set_transform(pos, 0, Vector2(sc, sc * scale_y))
	var dmg: int = int(pig.get("max_hp", 2)) - int(pig.hp)
	if dmg >= 1:
		draw_polyline(PackedVector2Array([Vector2(-26,-22), Vector2(-13,-9), Vector2(-23,5), Vector2(-7,23)]), Color("#985f69"), 3, true)
		if dmg >= 2:
			draw_polyline(PackedVector2Array([Vector2(20,-30), Vector2(8,-14), Vector2(22,-2), Vector2(11,22)]), Color("#985f69"), 3, true)
	draw_set_transform(Vector2.ZERO)

## 第一次遇到某种猪时那句说明：横在桌面顶上，不挡猪也不挡底部说明
func draw_pig_tip() -> void:
	if tip_text == "":
		return
	var w: float = font.get_string_size(tip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 44
	var a: float = minf(1.0, tip_timer / 0.4) # 最后 0.4 秒淡出
	var bg := Color(0.06, 0.09, 0.09, 0.82)
	bg.a *= a
	panel(Rect2(640 - w / 2.0, 246, w, 42), bg, 10)
	var col := Color("#e7c98a")
	col.a = a
	text_center(tip_text, 640, 275, 18, col)


func draw_pig_shaken(pig: Dictionary, index: int) -> void:
	# 金猪被砸中后的压扁回弹阶段（hp 已归零）仍要画猪本体，不能画成等待重生的圈
	var alive: bool = pig.hp > 0 or float(pig.get("gold_squash", 0.0)) > 0.0
	var sh: Vector2 = Vector2(shake_x, shake_y) if shake > 0.0 else Vector2.ZERO
	if sh.is_zero_approx():
		if alive:
			draw_pig(pig, index)
		else:
			draw_set_transform(pig.position)
			draw_arc(Vector2.ZERO, 36, 0, TAU, 32, Color("#765d45"), 2)
			draw_set_transform(Vector2.ZERO)
		return
	if alive:
		var saved: Vector2 = pig.position
		pig.position = saved + sh
		draw_pig(pig, index)
		pig.position = saved
	else:
		draw_set_transform(pig.position + sh)
		draw_arc(Vector2.ZERO, 36, 0, TAU, 32, Color("#765d45"), 2)
		draw_set_transform(Vector2.ZERO)

const ARM_ANCHOR := Vector2(1540, 1010) # 黑影持锤者的手从画面右下伸进来（屏幕外）
## 手上路暂时关掉：程序化堆出来的手不像手，先让锤子自己浮着；等有更好的画法（比如剪影贴图）再打开
const SHOW_HAND := false


## 锤子（SHOW_HAND 为 true 时，会有一只从画外伸进来的黑影手攥着它）
## 鼠标停在一个按钮上时要把锤子"举起来"：系统光标已经藏了，锤子是唯一的指针，
## 它要是正好压住按钮，玩家就看不见自己在点什么。
func ui_hover_at(p: Vector2) -> bool:
	if RESET_RECT.has_point(p):
		return true
	if phase == "playing" and gamble_state == "ready" and gamble_t >= GAMBLE_ROLL_TIME:
		if COIN_THROW.has_point(p) or COIN_SKIP.has_point(p):
			return true
	if (phase == "card" or phase == "finished" or phase == "bankrupt") and CONTINUE_RECT.has_point(p):
		return true
	return bill_open or bill_detail >= 0 # 翻账本时手本来就该放下


func draw_hammer() -> void:
	var over := ui_hover_at(get_local_mouse_position())
	var angle := -sin(swing / 0.16 * PI) * 0.95 # 静止斜角由 3D 模型本身负责，挥锤只叠加动画角度
	var k: float = 0.68 if over else 1.0 # 悬停按钮：缩小并往右下让开，别挡住按钮本身
	var pivot := hammer_position + Vector2(13, -5)
	if over:
		pivot += Vector2(58, 46)
	if SHOW_HAND:
		# 握点取柄的下段（不是末端）：柄尾要露在拳头外面，"握着"才看得懂
		draw_shadow_arm(pivot + Vector2(19, 74).rotated(angle))
	if hammer_tex != null: # 贴图锤：皮手套握木柄锤，跟随鼠标，挥锤下压+旋转沿用 swing 动画
		var hs := hammer_tex.get_size()
		var hfit := 250.0 / maxf(hs.x, hs.y) # 最长边约 250：比原 3D 锤略大，握锤的手也进了画面
		draw_set_transform(pivot, angle, Vector2(k * hfit, k * hfit))
		draw_texture(hammer_tex, -hs / 2.0)
		draw_set_transform(Vector2.ZERO)
		return
	if hammer3d != null:
		draw_set_transform(pivot, angle, Vector2(k, k))
		draw_texture_rect(hammer3d.get_texture(), Rect2(-104, -104, 208, 208), false)
		draw_set_transform(Vector2.ZERO)
		if SHOW_HAND:
			draw_shadow_fist(pivot + Vector2(19, 74).rotated(angle), angle)
		return
	draw_set_transform(pivot, angle, Vector2(k, k))
	panel(Rect2(11, -2, 17, 100), Color("#5e412f"), 6)
	panel(Rect2(8, -5, 15, 98), Color("#c59859"), 5)
	panel(Rect2(-42, -30, 108, 47), Color("#172323"), 9)
	panel(Rect2(-47, -37, 108, 47), Color("#9aafb0"), 9)
	draw_line(Vector2(-35,-27), Vector2(44,-27), Color("#d7e1d8"), 4)
	draw_set_transform(Vector2.ZERO)
	if SHOW_HAND:
		draw_shadow_fist(pivot + Vector2(19, 74).rotated(angle), angle) # 拳头画在锤子之上，才像真的攥着柄


## 一段肢体：从 a 到 b 的锥形胶囊（起点粗 → 终点细），两端补圆当关节
func draw_limb(a: Vector2, b: Vector2, wa: float, wb: float, col: Color) -> void:
	var n := Vector2(-(b - a).y, (b - a).x).normalized()
	draw_colored_polygon(PackedVector2Array([
		a + n * wa * 0.5, b + n * wb * 0.5, b - n * wb * 0.5, a - n * wa * 0.5,
	]), col)
	draw_circle(a, wa * 0.5, col)
	draw_circle(b, wb * 0.5, col)


## 一根弯着的手指：指根粗 → 指节鼓出（bend 越大拱得越厉害）→ 指尖细，再压一道关节纹
func draw_finger_bent(base: Vector2, tip: Vector2, w: float, bend: float, col: Color, seam: Color) -> void:
	var mid := base.lerp(tip, 0.46) + Vector2(0.0, bend) # 指节：往下拱，手指才是弯的
	draw_line(base, mid, col, w)
	draw_line(mid, tip, col, w * 0.84) # 指尖略细
	draw_circle(mid, w * 0.54, col)
	draw_circle(tip, w * 0.42, col)
	var perp := Vector2(-(tip - base).y, (tip - base).x).normalized() * w * 0.36
	draw_line(mid + perp, mid - perp, seam, 2) # 指关节那道横纹


## 从画外伸进来的手臂：上臂粗、前臂收细，再加一道边缘光（纯黑会糊成一坨）
func draw_shadow_arm(grip: Vector2) -> void:
	var elbow := (ARM_ANCHOR + grip) * 0.5 + Vector2(-60, 46)
	var arm := Color(0.04, 0.06, 0.06, 0.86)
	var rim := Color("#f2e2c0", 0.2)
	var wrist := grip + Vector2(24, 16) # 手腕偏右侧接进来，别把柄尾盖掉
	draw_limb(ARM_ANCHOR, elbow, 84, 60, arm) # 上臂
	draw_limb(elbow, wrist, 60, 44, arm) # 前臂：往手腕收细
	var perp := Vector2(-(wrist - elbow).y, (wrist - elbow).x).normalized()
	draw_line(wrist + perp * 23, wrist - perp * 23, Color(0.1, 0.13, 0.13, 0.45), 3) # 袖口褶皱
	draw_line(elbow + perp * 28, wrist + perp * 21, rim, 3) # 前臂上缘的边缘光
	draw_line(ARM_ANCHOR + perp * 40, elbow + perp * 28, rim, 3)


## 攥住锤柄的手：手腕 → 掌根 → 掌背（先垫一层暗）→ 四根弯指绕在柄上 → 拇指斜压 → 边缘光
func draw_shadow_fist(grip: Vector2, angle: float) -> void:
	var skin := Color("#2b221d") # 手背：暗暖棕。比手臂亮一档 —— 手在桌灯下，人还在暗处
	var finger_col := Color("#1f1915") # 手指背光，比手背更暗
	var shade := Color("#120d0b", 0.8) # 掌心 / 掌指关节的暗部
	var seam := Color("#55463a", 0.55) # 指缝与关节纹
	var rim := Color("#f0d8ab", 0.45) # 边缘光：一圈亮边，手才不会糊成一坨
	var hand_scale := Vector2(1.42, 1.34) # 第一人称视角的手本来就该占画面
	draw_set_transform(grip, angle, hand_scale)
	draw_limb(Vector2(8, 80), Vector2(4, 44), 40, 54, Color("#151110")) # 手腕：先是一段黑影
	draw_limb(Vector2(6, 52), Vector2(3, 34), 46, 48, skin) # 靠近手背处过渡到肤色
	draw_set_transform(grip, angle, hand_scale * Vector2(1.12, 1.0))
	draw_circle(Vector2(2, 20), 34, shade) # 掌心暗部
	draw_set_transform(grip, angle, hand_scale * Vector2(1.06, 0.97))
	draw_circle(Vector2(1, 18), 30, skin) # 掌背
	draw_set_transform(grip, angle, hand_scale)
	draw_line(Vector2(-20.0, -38.0), Vector2(-17.0, 20.0), shade, 4) # 掌指关节那道折痕
	var lens := [50.0, 48.0, 43.0, 36.0] # 食指最长，小指最短
	var ys := [-32.0, -17.0, -2.0, 13.0] # 间距≈指宽：四指并排握住，不该挤成一片
	for i in range(4): # 四指横过锤柄，每根都往下拱一点（握的真实感全在这个弯曲上）
		var w := 14.0 - float(i) * 0.5
		var base := Vector2(-22.0, ys[i] - 2.0)
		var tip := Vector2(-22.0 + lens[i], ys[i] + 14.0) # 指尖往掌心勾下去，才像"扣住"而不是"贴着"
		draw_finger_bent(base, tip, w, 4.5, finger_col, seam)
		# 指缝是暗的（光进不去）：亮指背 + 暗指沟，手指才分得开
		draw_line(base + Vector2(6.0, w * 0.62), tip + Vector2(-4.0, w * 0.62), Color(0.03, 0.02, 0.02, 0.78), 4.0)
		var mx: float = -22.0 + float(lens[i]) * 0.46
		draw_line(Vector2(mx - 9.0, ys[i] - 6.0), Vector2(mx + 9.0, ys[i] - 7.0), rim, 2.5) # 指节凸起处一小段高光
		draw_line(Vector2(-18.0, ys[i] - 9.0), Vector2(-5.0, ys[i] - 8.5), Color(rim, 0.22), 2.0) # 指根一小段
	draw_finger_bent(Vector2(-16.0, 30.0), Vector2(6.0, -20.0), 17.0, -5.0, finger_col, seam) # 拇指：从掌根绕到柄前，压住食指
	draw_line(Vector2(-2.0, -16.0), Vector2(-12.0, 18.0), Color(seam, 0.6), 2) # 虎口那道缝
	draw_line(Vector2(-13.0, 22.0), Vector2(4.0, -24.0), rim, 2.5) # 拇指上缘
	for i in range(2): # 手背上两道极淡的肌腱：从腕部往指根发散
		draw_line(Vector2(3.0 + float(i) * 4.0, 38.0), Vector2(-16.0 + float(i) * 9.0, -18.0), Color(rim, 0.1), 2.0)
	draw_set_transform(Vector2.ZERO)

## 卡片外壳：投影 + 描边 + 顶部卡头条（标题在卡内，不再浮在卡片上方）
func card_shell(title: String, accent: Color) -> void:
	panel(Rect2(CARD_RECT.position + Vector2(1, 7), CARD_RECT.size + Vector2(12, 12)), Color(0.02, 0.05, 0.05, 0.5), 24) # 投影
	panel(CARD_RECT, accent.darkened(0.6), 22) # 外框（描边感）
	var inner := CARD_RECT.grow(-4)
	panel(inner, Color("#15212c"), 19) # 卡面
	panel(Rect2(inner.position.x, inner.position.y, inner.size.x, 48), accent.darkened(0.32), 19) # 卡头
	draw_line(Vector2(inner.position.x, inner.position.y + 48), Vector2(inner.end.x, inner.position.y + 48), accent.lightened(0.15), 3)
	text_center(title, CARD_RECT.get_center().x, inner.position.y + 36, 25, accent.lightened(0.3))


## 卡片中间的圆形徽章，放主数字（金额 / ×2），比纯文字更醒目
func card_badge(accent: Color, value: String, size: int) -> void:
	var c := Vector2(CARD_RECT.get_center().x, CARD_RECT.position.y + 110)
	draw_circle(c, 48, accent.darkened(0.5))
	draw_circle(c, 42, accent.darkened(0.18))
	draw_arc(c, 42, 0.0, TAU, 32, accent.lightened(0.25), 3)
	text_center(value, c.x, c.y + size * 0.36, size, Color("#fff6e2"))


func draw_card() -> void:
	if card_type == "reward" and card_offers.size() == 3:
		draw_upgrade_choices()
		return
	var t := clampf(card_pop / 0.16, 0.0, 1.0)
	var s := 0.9 + 0.1 * (1.0 - pow(1.0 - t, 3.0)) # 弹出：0.9 → 1.0，ease-out
	draw_set_transform(CARD_RECT.get_center() * (1.0 - s), 0.0, Vector2(s, s))
	var title := "账单到期"
	var accent := Color("#efbc72")
	var label := "开始应付"
	var hint := "也可按空格开始"
	if card_type == "reward":
		title = "奖励卡"
		accent = Color("#8fd05a")
		label = "收下奖励"
		hint = "也可按空格收下"
	elif card_type == "double":
		title = "双倍卡"
		accent = Color("#ffd166")
		label = "收下"
		hint = "也可按空格收下"
	elif card_type == "dodge":
		accent = Color("#e8836b") # 催债比账单更"危险"，用偏红的橙
	card_shell(title, accent)
	if card_type == "reward":
		card_badge(accent, "+¥" + str(int(settings.reward_card_amount)), 32)
		text_center("直接到账", 640, 490, 20, Color("#c7d5e0"))
	elif card_type == "double":
		card_badge(accent, "×2", 52)
		text_center("接下来 " + str(int(settings.double_duration)) + " 秒", 640, 480, 19, Color("#c7d5e0"))
		text_center("敲猪收益翻倍", 640, 504, 19, Color("#c7d5e0"))
	elif card_type == "collect":
		card_badge(accent, "¥" + str(bill_amount), 32)
		text_center("限时 " + str(int(bill_time)) + " 秒凑齐", 640, 464, 18, Color("#c7d5e0"))
		text_center("限时凑钱小游戏", 640, 486, 18, Color("#c9b08a"))
		text_center("凑不够就扣 ¥" + str(bill_amount), 640, 508, 16, Color("#e7a6a4"))
	else: # dodge
		card_badge(accent, "¥" + str(bill_amount), 32)
		text_center("限时 " + str(int(bill_time)) + " 秒", 640, 464, 18, Color("#c7d5e0"))
		text_center("躲开催债小游戏", 640, 486, 18, Color("#c9b08a"))
		text_center("被抓住就失败", 640, 508, 16, Color("#e7a6a4"))
	button(CONTINUE_RECT, label, true, accent)
	text_center(hint, 640, 652, 17, Color("#b1c0b8"))
	draw_set_transform(Vector2.ZERO)


func draw_upgrade_choices() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.015, 0.025, 0.035, 0.82))
	text_center("选择一张卡，决定这一局的打法", 640, 195, 30, Color("#ffe092"))
	text_center("点击卡片选择 · 按 1 / 2 / 3 快速选择", 640, 226, 17, Color("#b8c7c1"))
	for i in range(card_offers.size()):
		var card: Dictionary = card_offers[i]
		var rect: Rect2 = UPGRADE_CARD_RECTS[i]
		var accent := Color(String(card.color))
		panel(Rect2(rect.position + Vector2(3, 8), rect.size), Color(0.01, 0.02, 0.025, 0.7), 20)
		panel(rect, accent.darkened(0.55), 18)
		panel(rect.grow(-5), Color("#182522"), 15)
		panel(Rect2(rect.position.x + 5, rect.position.y + 5, rect.size.x - 10, 48), accent.darkened(0.3), 13)
		text_center(String(card.name), rect.get_center().x, rect.position.y + 38, 23, Color("#fff1d0"))
		draw_circle(Vector2(rect.get_center().x, rect.position.y + 140), 48, accent.darkened(0.35))
		draw_circle(Vector2(rect.get_center().x, rect.position.y + 140), 40, accent)
		text_center(String(card.icon), rect.get_center().x, rect.position.y + 155, 42, Color("#fff8e8"))
		text_center(String(card.desc), rect.get_center().x, rect.position.y + 222, 17, Color("#e2e9e4"))
		text_center("选择 " + str(i + 1), rect.get_center().x, rect.end.y - 22, 16, accent.lightened(0.3))

func draw_collect() -> void:
	panel(Rect2(40, 120, 1200, 560), Color("#1b2838"), 22)
	text_at("账单到期 · 限时凑钱", Vector2(80, 170), 30, Color("#efbc72"))
	text_at("应付 ¥" + str(bill_amount) + "      已凑 ¥" + str(collected), Vector2(80, 222), 24)
	text_at("剩余 " + ("%.1f" % maxf(0.0, bill_timer)) + " 秒", Vector2(80, 262), 22, Color("#c9b08a"))
	panel(Rect2(80, 296, 800, 16), Color("#171a21"), 6)
	panel(Rect2(80, 296, 800 * clampf(bill_timer / bill_time, 0.0, 1.0), 16), Color("#efbc72"), 6)
	text_at("点击金色硬币凑钱 · 别点黑色假币", Vector2(80, 340), 20, Color("#c7d5e0"))
	for c in coins:
		draw_coin(c)

func draw_coin(c: Dictionary) -> void:
	var pos: Vector2 = c.position
	if c.fake:
		draw_circle(pos, 24, Color("#3a3f44"))
		draw_circle(pos, 20, Color("#262a2e"))
		draw_arc(pos, 17, 0.0, TAU, 24, Color("#8a8f94"), 3)
		text_at("假", pos + Vector2(-9, 7), 18, Color("#e7a6a4"))
	else:
		draw_circle(pos, 24, Color("#a8742a"))
		draw_circle(pos, 20, Color("#efbc72"))
		draw_arc(pos, 17, 0.0, TAU, 24, Color("#7a4f18"), 3)
		text_at("¥", pos + Vector2(-8, 8), 20, Color("#5e3c12"))

func draw_dodge() -> void:
	panel(Rect2(40, 120, 1200, 560), Color("#1b2838"), 22)
	text_at("账单到期 · 躲开催债", Vector2(80, 170), 30, Color("#efbc72"))
	text_at("应付 ¥" + str(bill_amount) + "      坚持到时间结束", Vector2(80, 222), 24)
	text_at("剩余 " + ("%.1f" % maxf(0.0, bill_timer)) + " 秒", Vector2(80, 262), 22, Color("#c9b08a"))
	panel(Rect2(80, 296, 800, 16), Color("#171a21"), 6)
	panel(Rect2(80, 296, 800 * clampf(bill_timer / bill_time, 0.0, 1.0), 16), Color("#efbc72"), 6)
	text_at("生命 ", Vector2(80, 340), 20, Color("#c7d5e0"))
	for i in range(dodge_lives):
		draw_heart(Vector2(140 + i * 30, 340))
	text_at("移动鼠标躲开红色催债", Vector2(80, 380), 20, Color("#c7d5e0"))
	for d in dodgers:
		draw_dodger(d)
	draw_player()

func draw_dodger(d: Dictionary) -> void:
	var pos: Vector2 = d.position
	draw_circle(pos, 20, Color("#5e2a2a"))
	draw_circle(pos, 16, Color("#b23b3b"))
	draw_line(pos + Vector2(-10, -7), pos + Vector2(-3, -3), Color("#2a0e0e"), 3)
	draw_line(pos + Vector2(10, -7), pos + Vector2(3, -3), Color("#2a0e0e"), 3)
	text_at("催", pos + Vector2(-9, 7), 18, Color.WHITE)

func draw_player() -> void:
	var pos := hammer_position
	var col := Color("#a4d007") if invincible_timer > 0.0 else Color("#66c0f4")
	draw_circle(pos, 15, Color("#0a1518"))
	draw_circle(pos, 12, col)

func draw_heart(pos: Vector2) -> void:
	draw_circle(pos + Vector2(-4, -2), 5, Color("#e7a6a4"))
	draw_circle(pos + Vector2(4, -2), 5, Color("#e7a6a4"))
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(8, 0), pos + Vector2(0, 10)]), Color("#e7a6a4"))

func draw_finished() -> void:
	panel(Rect2(385, 270, 510, 375), Color("#2a475e"), 25)
	if end_reason == "exhausted":
		text_center("体力耗尽！", 640, 345, 36, Color("#efbc72"))
		text_center(story_line("exhausted_line", "手停下来了。账单还在桌上。"), 640, 400, 22)
	elif end_reason == "coin": # 靠抛硬币翻上去的：赢了，但是赢在运气上
		text_center("正面。", 640, 345, 36, Color("#ffe092"))
		text_center(story_line("win_coin_line", "一把就到手了 —— 你不会觉得这是运气，你会觉得自己有手感。"), 640, 400, 22)
	else:
		text_center(story_line("win_title", "暂时安全"), 640, 345, 36, Color("#a4d007"))
		text_center(story_line("win_line", "目标达成，你甩开了催债电话 —— 但桌上那叠账单，一张都没少。"), 640, 400, 22)
	text_center("余额 ¥" + str(score) + "    敲碎 " + str(broken) + " 只", 640, 452, 26, Color("#efbc72"))
	text_center("已还 " + str(paid_count) + " 张 · 还剩 " + str(bills.size()) + " 张（¥" + str(bills_total()) + "）", 640, 498, 20, Color("#c9b08a"))
	text_center("永久成长：" + meta_unlock_summary() + "　·　碎片 " + str(meta_shards), 640, 536, 15, Color("#efbc72"))
	button(CONTINUE_RECT, "再来一轮")

func draw_bankrupt() -> void:
	panel(Rect2(385, 270, 510, 375), Color("#3a2424"), 25)
	text_center(story_line("lose_title", "破产了"), 640, 345, 36, Color("#e7a6a4"))
	text_center(story_line("lose_line", "敲碎 {broken} 只存钱罐，账单反而又多了几张。"), 640, 400, 22)
	text_center("余额 ¥" + str(score) + "    敲碎 " + str(broken) + " 只", 640, 452, 26, Color("#efbc72"))
	text_center("已还 " + str(paid_count) + " 张 · 还剩 " + str(bills.size()) + " 张（¥" + str(bills_total()) + "）", 640, 498, 20, Color("#c9b08a"))
	text_center("永久成长：" + meta_unlock_summary() + "　·　碎片 " + str(meta_shards), 640, 536, 15, Color("#efbc72"))
	button(CONTINUE_RECT, "再来一轮")
