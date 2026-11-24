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
const LEGACY_SHOP_RECT := Rect2(400, 563, 120, 52) # 结算面板上的「传承商店」按钮（在再来一轮左边）
const INTRO_SHOP_RECT := Rect2(116, 586, 234, 44) # 序幕上的入口（在「任意键开始」下方）
const STORY_SKIP_RECT := Rect2(1088, 44, 108, 40) # 剧情对话页右上「跳过剧情」
const LEGACY_PANEL := Rect2(240, 80, 800, 584) # 传承商店全屏面板
const LEGACY_CLOSE_RECT := Rect2(585, 600, 110, 40) # 商店关闭按钮（鼠标玩家的出口；键盘 B/Esc 也行）
const INTRO_RECT := Rect2(112, 476, 234, 52) # 开场序幕的「敲开第一只」按钮
const RESET_RECT := Rect2(1090, 36, 140, 46)
const COLLECT_BOARD_RECT := Rect2(446, 152, 130, 70) # 催收预警牌：挂在体力牌和日历牌之间。只报信不可点 —— 躲债只由条件触发
const PIG_BOUNDS := Rect2(270, 320, 740, 310) # 小猪在赌桌上的活动范围；同时决定 3D 桌板大小。
# ↑ 纵向从 230 撑到 310：小猪要铺满整张桌子，挤在中间一条带子里看不出"满桌都是猪"
const PIG3D_SIZE := 138.0 # 3D 猪纹理的绘制边长（基准；实际尺寸见 pig_size()，由 pig_draw_size 配置）
const MAX_PARTICLES := 70 # 粒子上限：狂热时一秒连碎好几只，别让金币堆到掉帧
const PIG3D_OFFSET := Vector2(0, -10) # 纹理中心相对猪身体中心的偏移
const DESK_RECT := Rect2(110, 260, 1060, 396) # 桌面外框的屏幕矩形（3D 桌板按它反算尺寸）
## 账单考核浮层：上半屏是 HUD（标题 / 金额 / 计时），下半屏是一整块 3D 舞台。
## 舞台矩形同时是：3D 视口的像素尺寸、2D 回退的绘制区、金币与催债人的活动边界。
const CHALLENGE_PANEL := Rect2(40, 118, 1200, 574)
const CHALLENGE_STAGE := Rect2(56, 300, 1168, 372)
## 摆钱凑整：三张路子横排在舞台里，卡面尺寸固定 —— 玩家第二次遇到就认得版式。
const COLLECT_CARD_SIZE := Vector2(300, 268)
const COLLECT_CARD_Y := 318.0
const COLLECT_CARD_GAP := 44.0
## 按住左键蓄力：轻点是快锤（完全等于原来的手感），按满变成重锤 ——
## 收益 ×1.5、伤害 +1，但蓄力这半秒猪会跑，砸空还要额外付一次代价。
const CHARGE_MAX := 0.55
const CHARGE_POWER := 0.5 # 满蓄力最终倍率 = 1 + 0.5 = 1.5
const CHARGE_DAMAGE_AT := 0.75 # 蓄力超过七成才加伤害，避免"轻轻按住"就白拿一血
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
const QUICK_BILL_VISIBLE := 3
var quick_bill_offset := 0
var quick_paid_timer := 0.0
var quick_paid_text := ""
var paid_count := 0 # 本局已还掉的张数
const HELP_BUTTON := Rect2(54, 744, 116, 32)
var help_open := false
var bill_open := false # 账本是否摊开（摊开时游戏暂停）
var bill_page := 0 # 账本翻到第几页
var bill_detail := -1 # 正在放大看第几张（-1 = 没在看）
var gamble_state := "none" # 那枚硬币：none（还没攒够/已用过） / ready（可以抛了） / flip（正在翻） / result（已落定）
var gamble_t := 0.0 # 抛硬币动画与结果定格的计时
var gamble_heads := true # 这一抛是正面还是反面
var gamble_used := false # 本局是否已经赌过（赌过就没了；不赌的话硬币一直在桌上等着）
var unpaid_bills := 7 # = bills.size()：应付掉一张 -1，逾期 +1（越欠越多）
var intro_open := false # 开场序幕是否正在显示（headless 下自动关掉，免得挡住自动化测试）
var story_page := 0 # 剧情对话页码：< 页数在放对话，>= 页数就是标题页
var story_t := 0.0 # 剧情打字机计时（翻页归零）
var tutorial_step := 0 # 新手引导：0 未启动 1 瞄准 2 蓄力砸 3 收尾横幅 4 完成/跳过
var tutorial_t := 0.0 # 收尾横幅计时
var tutorial_gain := 0 # 第一只猪的收入：收尾横幅展示用
var tutorial_done := false # 存档位：教学只带第一次，之后直接开打
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
var impact_timer := 0.0
var impact_position := Vector2.ZERO
var impact_broken := false
var charging := false # 左键按住中
var charge_t := 0.0 # 已经蓄了多久
var charge_time := 1.0 # 重力锤：蓄满所需时间（锤子数据注入）
var stun_t := 0.0 # 重力锤落地硬直：这段时间不能挥锤
var charge_pig := -1 # 按下那一刻瞄准的猪（松手时它没跑远就还砸它）
var pending_strike: Dictionary = {} # 冷却期间按下的那一锤：冷却一结束立刻补上，不静默丢点击
var pending_t := 0.0
var pending_challenge: Dictionary = {} # 日历刚撞到期、等这一帧收尾就弹的账单考核
var challenge_warn_t := 0.0 # 考核预告倒计时：挂起后先亮横幅，归零才开考 —— 别在小游戏一结束就突袭
var challenge_rest_t := 0.0 # 喘息冷却：考核刚结束的几秒里不再挂新考核，也不把到期票盖成逾期
var challenge_count := 0 # 本局已触发的账单考核次数（上限见 bills.json 的 challenge_max_per_run）
var challenge_bill_tag := "" # 本次考核绑定的账单编号；空 = 不绑账单（老式通用考核）
var challenge_label := "" # 考核面板上那句"谁到期了、多少钱"
var collection_mode := false # 本次考核是房东上门躲债：赢了是房租延期（拖延），输了当场逾期
var swing := 0.0
const BillManagerScript := preload("res://scripts/bill_manager.gd")
const Hammer3DScript := preload("res://scripts/hammer3d.gd")
const WheelScript := preload("res://scripts/lucky_wheel.gd")
const CardBuildScript := preload("res://scripts/card_build.gd")
const DayEventsScript := preload("res://scripts/day_events.gd")
const EscapeScript := preload("res://scripts/escape.gd")
const ItemShopScript := preload("res://scripts/shop.gd") # 徐欣雨的道具商店：锤子/技能/背包/快捷栏
var bills_fx # 账单效果：电费停电 / 信用卡利息 / 房租催收（BillManagerScript 实例）
var hammer3d # 独立透明视口中的立体锤光标
var earned_total := 0 # 本局累计赚到的钱（房租催收按它跨阈值触发）
var last_observed_score := 0
var vignette_tex: ImageTexture # 停电暗角贴图（开局生成一次）
var glow_tex: ImageTexture # 灯泡辉光贴图：中心亮、边缘透明的径向渐变（开局生成一次）
var bulb_tex: Texture2D # 精绘灯泡精灵（tools/gen_bulb.py 离线生成）：玻璃渐变/灯丝辉光/黄铜灯座都烤在图里
var paper_atlas: Dictionary # 旧报纸账单贴图：key "宽x高" → 变体数组（tools/gen_newsprint.py 离线生成，撕边缺角烘在 alpha 里）
var bonus_timer := 0.0 # 支付电费后的挥锤冷却减免还剩多久
var blackout_fade := 0.0 # 停电暗化的渐入进度（0→1，避免闪进闪出）
var collection_flash := 0.0 # 房东催收的红色警告脉冲
var hammer_position := Vector2(1030, 540)
## 命中点相对锤头中心的偏移：锤头画在鼠标处，真正的判定点在锤头左下的击打面上。
## 准心画在判定点 —— 指哪打哪；锤头悬在命中点的右上，视觉上正要砸下去。
const AIM_OFFSET := Vector2(-42, 38)
var card_type := "" # "reward" / "double" / "collect" / "dodge"
var card_offers: Array[Dictionary] = [] # 三选一卡片：本局升级与即时奖励
var hammer_damage_bonus := 0
var stamina_cost_reduction := 0.0
var earnings_multiplier := 1.0
var combo_bonus_per_hit := 0
var hammer_reach_multiplier := 1.0
var hammer_cooldown_reduction := 0.0
var stamina_regen_bonus := 0.0
# --- 代价型构筑卡：改变打法，而不是只把数字调大 ---
var stamina_max_multiplier := 1.0 # 孤注一掷：体力上限倍率（0.6）
var type_value_bonus: Dictionary = {} # 玻璃猎人：猪种 id → 收益倍率（{"glass": 3.0}）
var type_value_penalty := 1.0 # 玻璃猎人：没被点名的猪种收益倍率（0.7）
var light_hammer_off := false # 断臂求生：轻锤不再出伤害
var heavy_hammer_multiplier := 1.0 # 断臂求生：重锤伤害倍率（2.0）
var pay_greed_per_pay := 0.0 # 守财奴：每还掉一张账单，永久收益 +这么多
var pig_size_multiplier := 1.0
var pig_population_doubled := false
var card_pop := 0.0 # 卡片弹出动画的计时（0 → 0.16 秒内放大到位）
var challenge_streak := 0
var bill_amount := 30
var bill_time := 10.0
var bill_timer := 0.0
var collected := 0
var coins: Array[Dictionary] = [] # 3D 舞台的硬币槽：凑钱关已改成"摆钱凑整"，这里恒为空
# —— 摆钱凑整（凑钱关）：桌上摊 3 张「来钱路子」，选一张，钱进袋、代价也进账 ——
var collect_cards: Array[Dictionary] = [] # 当前这一轮的三张路子（稳 / 中 / 猛）
var collect_round := 1 # 第几轮
var collect_rounds := 4 # 本关一共能给几次选择
var collect_pick_t := 0.0 # 选中后的结算停顿：这半秒里不接受点击，卡面要抬起来
var collect_picked := -1 # 刚选中的那张（高亮 + 其余变暗）
var collect_debt := 0 # 本关为了凑钱多签下的账（结算小结用）
var collect_pain := 0.0 # 本关为凑钱耗掉的力气（结算小结用）
var double_timer := 0.0
var wheel # 幸运转盘：独立子节点，低侵入，只读写 main 的公开状态
var build # 卡片2.0：构筑/成长卡系统（合并版移植），低侵入
var day_events # 天数里程碑小游戏（当铺/赌桌/电话）：独立子节点，低侵入
var escape # 逃跑场面（夺门而出+双车道跑酷）：替换旧的圆圈躲弹幕，独立子节点
var combo_count := 0
var combo_timer := 0.0
var combo_max := 0
var best_gain := 0 # 本局最大单笔收入（结算高光用）
var gamble_wins := 0 # 赌桌战绩：赢的局数（结算高光用）
var gamble_losses := 0 # 赌桌战绩：输的局数
var hit_stop := 0.0 # 打击顿帧剩余时间：命中瞬间全场定格几帧
var shake := 0.0
var shake_x := 0.0
var shake_y := 0.0
var dodgers: Array[Dictionary] = []
var dodger_spawn_timer := 0.0
var dodger_uid := 0
var dodge_lives := 3
var invincible_timer := 0.0
var elapsed := 0.0
var game_day := 1 # 游戏内日期：按 bills.json 的 income_per_game_day 推进
var meta_shards := 0
var meta_runs := 0
var meta_unlocked: Array[String] = []
var meta_rewarded := false
## 传承商店：碎片是可花货币（原版 Bills Must Be Paid 的传承点思路）。
## 里程碑解锁（steady_start 等）保留自动发放，商店是在其之上“玩家自己选成长方向”的一层。
const LEGACY_ITEMS := [
	{"id": "watch", "name": "旧怀表", "desc": "开局资金 +¥20/级", "max": 3, "costs": [4, 8, 12]},
	{"id": "grip", "name": "皮护腕", "desc": "体力上限 +12/级", "max": 3, "costs": [4, 8, 12]},
	{"id": "ring", "name": "幸运戒指", "desc": "暴击率 +1.5%/级", "max": 3, "costs": [5, 9, 14]},
	{"id": "abacus", "name": "商人算盘", "desc": "收益加成 +6%/级", "max": 3, "costs": [5, 9, 14]},
	{"id": "flask", "name": "咖啡壶", "desc": "体力回复 +0.6/秒/级", "max": 3, "costs": [4, 8, 12]},
]
var meta_shop: Dictionary = {} # 饰品 id → 已买等级
var shop_open := false # 传承商店面板开着时：整局暂停、输入只认商店
var shop # 局内道具商店（锤子/技能/背包/快捷栏）：独立子节点，挂在最上层自绘
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
var challenge3d: Challenge3D = null # 考核小游戏的 3D 舞台（金币雨 / 催债追捕）
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
	build = CardBuildScript.new() # 卡片2.0：RefCounted，不进场景树，只吃 main 的公开状态
	day_events = DayEventsScript.new()
	add_child(day_events)
	day_events.setup(self)
	escape = EscapeScript.new()
	add_child(escape) # 和 day_events 一样进场景树：生命周期跟着 main，不靠裸引用
	escape.setup(self)
	escape.stage_rect = CHALLENGE_STAGE # 舞台区域由这里注入：跨脚本读常量不做依赖
	shop = ItemShopScript.new()
	add_child(shop) # 最后挂上：商店/背包/快捷栏 HUD 要画在其他界面之上
	shop.setup(self)
	load_meta()
	bills_fx.setup(bill_data)
	bills_fx.collection_triggered.connect(_on_collection_triggered)
	vignette_tex = _make_vignette() # 停电暗角用；headless 下也只是生成一张空图，不会崩
	glow_tex = _make_glow_texture() # 灯泡光晕/光锥共用：比叠圆片平滑得多，没有硬边色带
	_load_art_textures() # 美术贴图：读不到的键不进字典，绘制处自动回退 3D 图元 / 2D 自绘
	# 开场序幕：headless 下关掉，否则自动化测试第一下点击会被序幕吃掉
	intro_open = bool(story.get("intro_enabled", true)) and not DisplayServer.get_name().contains("headless")
	var intro_pages: Array = story.get("pages", [])
	story_page = 0 if (intro_open and not intro_pages.is_empty()) else intro_pages.size() # 有剧情先放对话，没剧情直接标题页
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
		if bool(settings.get("challenge_3d", true)):
			challenge3d = Challenge3D.new()
			add_child(challenge3d)
			challenge3d.build(CHALLENGE_STAGE) # 舞台像素 = 屏幕像素，映射不用再算缩放
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
	bulb_tex = _load_png_texture(ART_DIR + "bulb_lit.png")
	# 旧报纸账单贴图：四种显示尺寸 × 各几张变体，按账单号挑一张
	for key in ["236x74", "182x100", "420x570", "46x30"]:
		var variants: Array[Texture2D] = []
		for i in range(4):
			var tex := _load_png_texture(ART_DIR + "billpaper_%s_%d.png" % [key, i])
			if tex == null:
				break
			variants.append(tex)
		if not variants.is_empty():
			paper_atlas[key] = variants


## 开局/重开：从目录里随机抽 start_count 张不重复的账单，按金额升序（小额在上，先还得起）
func roll_bills() -> void:
	bills.clear()
	quick_bill_offset = 0
	help_open = false
	quick_paid_timer = 0.0
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
	quick_bill_offset = mini(quick_bill_offset, quick_bill_max_offset())


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


## 把一张账单正式标成逾期，并给它挂一张滞纳金。
## 日历推进和考核失败两个入口共用这一处 —— 两段各写一遍迟早会漏掉其中一条。
func mark_bill_overdue(bill: Dictionary) -> void:
	bill.overdue = true
	var tag := BillManagerScript.tag_of(bill)
	bills.append({"name": "逾期滞纳金", "amount": int(bill_data.get("calendar_late_fee", 12)),
		"no": String(bill.get("no", "")), "due": format_game_date(game_day),
		"source": tag, "fee_kind": "calendar_late"})
	popups.append({"position": Vector2(780, 300), "life": 1.5, "text": String(bill.name) + " 已逾期 · 滞纳 ¥" + str(int(bill_data.get("calendar_late_fee", 12)))})
	Sound.play("stamp", 0.75)


func advance_calendar() -> void:
	# 每收入 ¥135 推进一天；时间跟着玩家的游戏进度走，不依赖现实等待。
	var income_per_day := maxf(1.0, float(bill_data.get("income_per_game_day", 30)))
	var target_day := 1 + int(earned_total / income_per_day)
	var challenge_cap := int(bill_data.get("challenge_max_per_run", 3))
	var gave_chance := false # 这一次推进里已经给过一张票考核机会了（大额收入常一次跨好几天）
	while game_day < target_day:
		game_day += 1
		for i in range(bills.size()):
			var bill: Dictionary = bills[i]
			if bool(bill.get("overdue", false)) or int(bill.get("due_day", 9999)) > game_day:
				continue
			# 到期不再是"默默盖个章"：先给一次催缴考核，这是整局里唯一会打断砸猪节奏的事。
			# 一局最多 challenge_cap 次 —— 再多就成了频繁打断，反而更烦。
			var bill_tag := String(BillManagerScript.tag_of(bill))
			var can_offer := phase == "playing" and challenge_rest_t <= 0.0 \
				and pending_challenge.is_empty() and challenge_count < challenge_cap \
				and not bill_tag.is_empty()
			if can_offer:
				pending_challenge = {"tag": bill_tag,
					"kind": "dodge" if int(bill.amount) >= 300 else "collect"}
				challenge_count += 1
				challenge_warn_t = float(bill_data.get("challenge_warning_seconds", 3.0))
				gave_chance = true
				continue # 先别判逾期：玩家还有一次机会
			# 轮不上它的情况：喘息冷却没过、这次推进机会已经给出去、或根本不在游玩态。
			# 前两种不当场盖逾期章 —— 等下次日历推进再给机会；只有"非游玩态撞到期"才直接盖。
			if gave_chance or (phase == "playing" and challenge_rest_t > 0.0):
				continue
			mark_bill_overdue(bill)
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
	var shop: Variant = cfg.get_value("meta", "shop", {})
	if shop is Dictionary:
		meta_shop = shop
	tutorial_done = bool(cfg.get_value("meta", "tutorial_done", false))


func save_meta() -> void:
	# load 有守卫，save 也要：headless 测试跑 legacy_buy 时不能把假进度写进真实存档
	if DisplayServer.get_name().contains("headless"):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "shards", meta_shards)
	cfg.set_value("meta", "runs", meta_runs)
	cfg.set_value("meta", "unlocked", meta_unlocked)
	cfg.set_value("meta", "shop", meta_shop)
	cfg.set_value("meta", "tutorial_done", tutorial_done)
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


## —— 传承商店：碎片买永久饰品，下一局开局生效 ——
func legacy_level(id: String) -> int:
	return int(meta_shop.get(id, 0))


func legacy_next_cost(id: String) -> int:
	for item in LEGACY_ITEMS:
		if String(item.id) == id:
			var lv := legacy_level(id)
			return -1 if lv >= int(item.max) else int(item.costs[lv])
	return -1


func legacy_buy(id: String) -> bool:
	var cost := legacy_next_cost(id)
	if cost < 0 or meta_shards < cost:
		return false # 满级或碎片不够：钱和等级都不动
	meta_shards -= cost
	meta_shop[id] = legacy_level(id) + 1
	save_meta()
	Sound.play("cash")
	return true


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
	build.record_payment(self) # 卡片2.0：债务操盘手/收据收藏家的还款成长与返现
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
	if pay_greed_per_pay > 0.0:
		# 守财奴：每还掉一张账单，往后每一锤都更值钱 —— 把"还债"从纯支出变成投资。
		earnings_multiplier += pay_greed_per_pay
		popups.append({"position": Vector2(780, 336), "life": 1.3,
			"text": "守财奴 · 收益 +" + str(int(round(pay_greed_per_pay * 100))) + "%"})
	quick_paid_text = "已付 · " + String(b.name) + tail
	quick_paid_timer = 1.6
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
	build.record_payment(self) # 考核免单也算还款：与合并版行为一致
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


## 旧纸的"手气"：纯函数，同一张账单每帧长得一样，重开一局才会换一张纸。
func _paper_hash(seed_value: int, k: int) -> float:
	return fposmod(sin(float(seed_value) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)


## 一条边上的抖动点：纸是刀切的、还被翻旧了，边线绝不能是数学上的直线。
func _paper_edge(a: Vector2, b: Vector2, normal: Vector2, seed_value: int, k0: int) -> PackedVector2Array:
	var steps := maxi(2, int(a.distance_to(b) / 26.0))
	var pts := PackedVector2Array()
	for s in range(steps):
		var t := float(s) / float(steps)
		var wobble := (_paper_hash(seed_value, k0 + s) - 0.5) * 2.2
		pts.append(a.lerp(b, t) + normal * wobble)
	return pts


## 手裁纸的轮廓：四角切个小斜角、每边微微抖 —— 完美圆角矩形正是"假纸"的第一眼破绽。
func _paper_outline(rect: Rect2, seed_value: int) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var c := 3.0 # 角上的小斜角
	var outline := PackedVector2Array()
	outline.append_array(_paper_edge(Vector2(p.x + c, p.y), Vector2(e.x - c, p.y), Vector2(0, 1), seed_value, 0))
	outline.append(Vector2(e.x, p.y + c))
	outline.append_array(_paper_edge(Vector2(e.x, p.y + c), Vector2(e.x, e.y - c), Vector2(-1, 0), seed_value, 40))
	outline.append(Vector2(e.x - c, e.y))
	outline.append_array(_paper_edge(Vector2(e.x - c, e.y), Vector2(p.x + c, e.y), Vector2(0, -1), seed_value, 80))
	outline.append(Vector2(p.x, e.y - c))
	outline.append_array(_paper_edge(Vector2(p.x, e.y - c), Vector2(p.x, p.y + c), Vector2(1, 0), seed_value, 120))
	outline.append(Vector2(p.x + c, p.y))
	return outline


## 一张旧报纸：撕边、缺角、毛茬、油渍、折痕、边缘氧化全部烘在贴图里
## （tools/gen_newsprint.py 按四种显示尺寸各生成几张变体），代码只负责
## 按账单号挑一张 + 把字排在安全区。贴图缺失时回退到手裁轮廓的纯色纸。
## tint 现在是调制色：正常 Color.WHITE，账单还不起时压灰。
func paper_sheet(rect: Rect2, tint: Color, seed_value: int, _aged := 1.0, _stains := true,
		shadow := Vector2(3, 4)) -> void:
	var key := "%dx%d" % [roundi(rect.size.x), roundi(rect.size.y)]
	var variants: Variant = paper_atlas.get(key)
	if variants == null or (variants as Array).is_empty():
		_paper_sheet_fallback(rect, tint, seed_value)
		return
	var list: Array = variants
	var tex: Texture2D = list[int(_paper_hash(seed_value, 7) * float(list.size())) % list.size()]
	if shadow != Vector2.ZERO: # 影子 = 同一张纸染黑：撕边形状完全一致
		draw_texture_rect(tex, Rect2(rect.position + shadow, rect.size), false, Color(0.02, 0.04, 0.04, 0.34))
	draw_texture_rect(tex, rect, false, tint)


## 贴图缺失时的兜底：手裁轮廓 + 暗角发黄，至少不像一张 UI 卡片
func _paper_sheet_fallback(rect: Rect2, tint: Color, seed_value: int) -> void:
	var outline := _paper_outline(rect, seed_value)
	draw_colored_polygon(outline, tint)
	if vignette_tex != null:
		draw_texture_rect(vignette_tex, rect, false, Color(0.40, 0.25, 0.09, 0.44))


## 一张纸质账单（够比例排版，所以桌上一沓、账本里一张、放大的一张都能复用）
func draw_bill_paper(r: Rect2, b: Dictionary, can_pay: bool, tilt: float, lift: float) -> void:
	draw_set_transform(r.get_center() + Vector2(0, -lift), tilt, Vector2.ONE) # 绕纸心歪一点，才不像表格行
	var half := r.size / 2.0
	var rect := Rect2(-half, r.size)
	# 旧法由账单号 + 金额决定：翻账本时每张纸都不一样，但画面不动它就不会闪
	var seed_value := absi(String(b.get("no", "0")).hash()) + int(b.get("amount", 0))
	# 还不起的那几张更灰更旧（贴图已含纸色，这里只调明暗）
	paper_sheet(rect, Color.WHITE if can_pay else Color(0.76, 0.74, 0.70), seed_value,
		1.0, true, Vector2(3 + lift, 4 + lift))
	# 左侧骑缝红条：颜料被纸吃进去，边缘不齐
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half.x, -half.y + 7), Vector2(-half.x + 5, -half.y + 6),
		Vector2(-half.x + 5, half.y - 6), Vector2(-half.x, half.y - 7),
	]), Color(0.66, 0.24, 0.17, 0.82) if can_pay else Color(0.50, 0.31, 0.26, 0.66))
	# （右下的缺角是贴图自己撕掉的，代码里不再画折角）
	# 预印的横格线：真账单是带表格的，线比纸深一点点就够
	var line_col := Color(0.58, 0.50, 0.36, 0.5) if can_pay else Color(0.55, 0.50, 0.42, 0.4)
	draw_line(Vector2(-half.x + 12, -half.y + r.size.y * 0.58), Vector2(half.x - 12, -half.y + r.size.y * 0.58), line_col, 1.0)
	draw_line(Vector2(-half.x + 12, -half.y + r.size.y * 0.75), Vector2(half.x - 12, -half.y + r.size.y * 0.75),
		Color(line_col, line_col.a * 0.6), 1.0)
	var title_size := 15 if r.size.x < 200.0 else 20
	text_at(String(b.name), Vector2(-half.x + 13, -half.y + r.size.y * 0.40), title_size, Color("#3a3126") if can_pay else Color("#6a6459"))
	var amt := "¥" + str(int(b.amount))
	var amt_size := 20 if r.size.x < 200.0 else 26
	var w: float = font.get_string_size(amt, HORIZONTAL_ALIGNMENT_LEFT, -1, amt_size).x
	text_at(amt, Vector2(half.x - 15 - w, -half.y + r.size.y * 0.44), amt_size,
		Color(0.65, 0.25, 0.11, 0.94) if can_pay else Color("#8a8272"))
	var status := bill_status_text(b)
	text_at(status, Vector2(-half.x + 13, -half.y + r.size.y * 0.86), 11,
		Color(0.62, 0.28, 0.18, 0.9) if not bool(b.get("overdue", false)) else Color("#9a5c4e"))
	draw_set_transform(Vector2.ZERO)


## 桌角那一沓账单：只画最上面几张与侧边层叠，堆得多深由 bills.size() 决定
func quick_bill_max_offset() -> int:
	return maxi(0, bills.size() - QUICK_BILL_VISIBLE)

func quick_bill_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(bills.size()):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var a_due := int(bills[a].get("due_day", 9999))
		var b_due := int(bills[b].get("due_day", 9999))
		return a < b if a_due == b_due else a_due < b_due)
	var start := mini(quick_bill_offset, quick_bill_max_offset())
	return indices.slice(start, start + QUICK_BILL_VISIBLE)

func quick_bill_rect(slot: int) -> Rect2:
	return Rect2(1084, 280 + slot * 108, 182, 100)

func quick_pay_rect(slot: int) -> Rect2:
	return Rect2(1092, 344 + slot * 108, 166, 28)

func quick_bill_hover() -> bool:
	return phase == "playing" and not intro_open and BILL_PANEL.has_point(get_global_mouse_position()) and not DisplayServer.get_name().contains("headless")

func draw_bills() -> void:
	var indices := quick_bill_indices()
	text_at("待还账单", Vector2(1086, 267), 16, Color("#efbc72"))
	if not indices.is_empty():
		var first := mini(quick_bill_offset, quick_bill_max_offset()) + 1
		var range_text := "%d–%d / %d" % [first, first + indices.size() - 1, bills.size()]
		text_center(range_text, 1225, 267, 13, Color("#c9b08a"))
	for slot in range(indices.size()):
		var index := indices[slot]
		var bill: Dictionary = bills[index]
		var rect := quick_bill_rect(slot)
		var amount := bill_pay_amount(index)
		# 桌上这一沓也用真纸：手心那几张更旧一点（被翻得最勤）
		var paper_seed := absi(String(bill.get("no", "0")).hash()) + amount
		paper_sheet(rect, Color.WHITE, paper_seed, 1.0, false, Vector2(2, 3))
		var name := String(bill.name)
		if name.length() > 10:
			name = name.substr(0, 9) + "…"
		text_at(name + " ¥" + str(amount), rect.position + Vector2(8, 20), 14, Color("#543b28"))
		var days := int(bill.get("due_day", game_day)) - game_day
		var due := "已到期" if days <= 0 else "还剩 " + str(days) + " 天"
		var effect := String(bill.get("effect_id", ""))
		var consequence := {"blackout": "停电", "interest": "计息", "collection": "催收"}
		text_at(due + (" · " + String(consequence[effect]) if consequence.has(effect) else ""), rect.position + Vector2(8, 41), 13, Color("#a34632") if days <= 2 else Color("#746044"))
		var can_pay := score >= amount
		var pay := quick_pay_rect(slot)
		panel(pay, Color("#73964d") if can_pay else Color("#b7ae98"), 4)
		text_center("还款 ¥" + str(amount) if can_pay else "还差 ¥" + str(amount - score), pay.get_center().x, pay.position.y + 20, 14, Color.WHITE if can_pay else Color("#635b4b"))
	if quick_paid_timer > 0.0:
		panel(Rect2(1084, 581, 182, 26), Color("#425c37"), 4)
		var notice := quick_paid_text
		if notice.length() > 14:
			notice = notice.substr(0, 13) + "…"
		text_center(notice, 1175, 600, 12, Color("#e2f2ba"))
	if indices.is_empty():
		text_at("账单都还清了！", Vector2(1090, 315), 16, Color("#a4d007"))
	button(Rect2(1084, 612, 182, 32), "全部账单 [B]")
	if quick_bill_hover():
		var hint := "已暂停 · 滚轮浏览" if quick_bill_max_offset() > 0 else "已暂停 · 移回桌面继续"
		text_at(hint, Vector2(1084, 658), 12, Color("#efbc72"))


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
	text_at(format_game_date(game_day), LEDGER_RECT.position + Vector2(LEDGER_RECT.size.x - 440, 40), 18, Color("#efbc72"))
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
	var paper := Color("#efe4c8") # 只用来算明细横线的颜色；纸本体已是撕边贴图
	var detail_seed := absi(String(b.get("no", "0")).hash()) + int(b.amount)
	paper_sheet(rect, Color.WHITE if can_pay else Color(0.78, 0.76, 0.72), detail_seed,
		1.0, true, Vector2(8, 10)) # 摊开看的那张最旧：缺角、水渍、十字折痕都在图里
	# 抬头红条：印刷红压得浅一点，下沿压一道暗线，像油墨渗进纸里
	var header := Rect2(-half.x + 1, -half.y + 1, DETAIL_RECT.size.x - 2, 94)
	draw_rect(header, Color(0.72, 0.28, 0.21, 0.88))
	draw_line(Vector2(-half.x + 1, -half.y + 95), Vector2(half.x - 1, -half.y + 95), Color(0.42, 0.15, 0.10, 0.55), 2.0)
	draw_line(Vector2(-half.x + 1, -half.y + 99), Vector2(half.x - 1, -half.y + 99), Color(0.42, 0.15, 0.10, 0.22), 1.0)
	# 左边两个装订孔：这是从催收档案里抽出来的一张
	for i in range(2):
		var hole_y := -half.y + 150.0 + float(i) * 100.0
		draw_circle(Vector2(-half.x + 18, hole_y), 6.5, Color(0.10, 0.075, 0.05, 0.92))
		draw_arc(Vector2(-half.x + 18, hole_y), 6.5, 0.0, TAU, 16, Color(0.55, 0.45, 0.30, 0.5), 1.2)
	text_center("催 缴 通 知 单", 0.0, -half.y + 40, 20, Color(0.99, 0.93, 0.88, 0.95))
	text_center(String(b.name), 0.0, -half.y + 76, 28, Color(1.0, 0.96, 0.90, 0.96))
	text_at("户号 " + String(b.no), Vector2(-half.x + 40, -half.y + 150), 17, Color("#6d675c"))
	text_at("当前 " + format_game_date(game_day) + "　·　" + bill_status_text(b), Vector2(-half.x + 40, -half.y + 178), 17, Color("#9a5c4e"))
	text_center("¥" + str(amount), 0.0, -half.y + 300, 84, Color(0.22, 0.18, 0.13, 0.93))
	text_center("应 缴 金 额", 0.0, -half.y + 336, 17, Color(0.42, 0.36, 0.26, 0.9))
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


## 自绘的锤子只在「鼠标就是你的身体」时才顶替系统光标：敲猪和躲催债这两段。
## 序幕 / 卡片 / 账本 / 结算必须把系统箭头还回来 —— 那些界面不画锤子，
## 再把箭头藏了就等于一个指针都没有，玩家连「继续」都点不到。
## 配置 hammer_cursor: false 可以彻底用回系统箭头（有人就是更习惯真的指针）。
func sync_cursor() -> void:
	var hide: bool = bool(settings.get("hammer_cursor", true))
	hide = hide and phase == "playing" # 躲债关改成鼠标跟手：系统箭头得留着（人跟着箭头跑，锤子别挡路）
	hide = hide and not intro_open and not bill_open and bill_detail < 0 and not quick_bill_hover() and not help_open and not (build != null and build.panel_open)
	hide = hide and not (wheel != null and wheel.is_open()) # 转盘弹窗里得看得见箭头
	hide = hide and not (day_events != null and day_events.is_open()) # 小游戏弹窗同理：全靠点击，藏箭头就没法玩了
	hide = hide and not (shop != null and shop.is_open()) # 道具商店/背包也一样：拖拽全靠箭头
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


## 房东上门催收：房租欠着时，收入每跨一道门槛房东就来堵一次门。
## 不再是"屏幕边缘闪一下"的提醒 —— 这里直接排一场躲债（预告横幅 → 逃跑场面）。
## 排班条件与日历经期考核同一条队：不叠加、不在喘息冷却里背靠背开跑。
func _on_collection_triggered(msg: String) -> void:
	collection_flash = 1.2
	# 房东敲门是一次强烈的短促冲击；复用桌面震动层，让猪和飞散粒子一起震。
	var dark_knock: bool = bills_fx.is_synergy_active("dark_knock")
	shake = maxf(shake, 0.68 if dark_knock else 0.48)
	if dark_knock:
		msg = "停电时房东砸门！"
	popups.append({"position": Vector2(640, 296), "life": 1.6, "text": msg})
	Sound.play("stamp", 0.72, 1.25)
	# 打断预算与日历考核共享：一局最多 challenge_max_per_run 次，房东也得排队用额度。
	var cap := int(bill_data.get("challenge_max_per_run", 3))
	if phase != "playing" or not pending_challenge.is_empty() or challenge_rest_t > 0.0 \
			or challenge_count >= cap:
		return # 已有考核排着队、刚考完在喘、或本局打断额度用完了：这次就当隔着门喊了两句
	var rent_tag := _collection_bill_tag()
	if rent_tag.is_empty():
		return
	challenge_count += 1
	pending_challenge = {"tag": rent_tag, "kind": "dodge", "collection": true}
	challenge_warn_t = float(bill_data.get("challenge_warning_seconds", 3.0))


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
	score = meta_starting_cash() + legacy_level("watch") * 20 # 旧怀表：开局资金
	last_observed_score = score
	# 代价型卡的加成必须在算体力上限之前清掉：否则"孤注一掷"会把上限一路压低到下一局。
	stamina_max_multiplier = 1.0
	type_value_bonus.clear()
	type_value_penalty = 1.0
	light_hammer_off = false
	heavy_hammer_multiplier = 1.0
	pay_greed_per_pay = 0.0
	settings["stamina_max"] = maxi(20, int(round((base_stamina_max + (10.0 if meta_unlocked.has("deep_pockets") else 0.0) + 12 * legacy_level("grip")) * stamina_max_multiplier)))
	# 第一张卡要来得晚一点（card_first_at）：开局这段必须是"砸 → 爆钱 → 砸"的连续反馈，
	# 把对外服务的教学/抉择留到玩家已经上手之后。之后每张按 card_interval 间隔。
	next_card = int(settings.get("card_first_at", settings.get("card_interval", 50)))
	card_delay = 0.0
	phase = "playing"
	card_type = ""
	card_offers.clear()
	charging = false
	charge_t = 0.0
	charge_pig = -1
	pending_strike = {}
	pending_t = 0.0
	pending_challenge = {}
	challenge_warn_t = 0.0
	challenge_rest_t = 0.0
	challenge_count = 0
	challenge_bill_tag = ""
	challenge_label = ""
	hammer_damage_bonus = 0
	stamina_cost_reduction = 0.0
	earnings_multiplier = 1.0 + 0.06 * legacy_level("abacus") # 商人算盘：永久收益加成，与对局内卡牌乘区叠乘
	combo_bonus_per_hit = 0
	hammer_reach_multiplier = 1.0
	hammer_cooldown_reduction = 0.0
	stamina_regen_bonus = 0.6 * legacy_level("flask") # 咖啡壶：永久回复，与对局内加成叠加
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
	collect_cards.clear()
	collect_round = 1
	collect_pick_t = 0.0
	collect_picked = -1
	collect_debt = 0
	collect_pain = 0.0
	double_timer = 0.0
	combo_count = 0
	combo_timer = 0.0
	combo_max = 0
	best_gain = 0
	gamble_wins = 0
	gamble_losses = 0
	hit_stop = 0.0
	shake = 0.0
	impact_timer = 0.0
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
	collection_mode = false
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
	build.reset() # 新局：本局构筑卡全部清空
	if shop != null:
		shop.reset_run() # 新局：已买锤子/技能/快捷栏全部清回初始（商店是局内资源）
	day_events.reset_run() # 新局：里程碑日程重排，排队事件清空
	escape.reset_run() # 逃跑场面复位（防结算瞬间残留在 intro/run 态）
	queue_redraw()

func _process(delta: float) -> void:
	quick_paid_timer = maxf(0.0, quick_paid_timer - delta)
	sync_cursor() # 必须排在所有提前 return 之前：翻账本时整局是停的，但箭头得还回来
	if hammer3d == null and not DisplayServer.get_name().contains("headless"):
		# 编辑器热重载不会重跑 _ready()；运行中的窗口也要能补建新加入的 3D 锤子视口。
		hammer3d = Hammer3DScript.new()
		add_child(hammer3d)
	if wheel != null and wheel.is_open(): # 转盘弹窗：整局暂停（猪停刷、不能砸）；转盘自己的 _process 继续转
		queue_redraw()
		return
	if bill_open or bill_detail >= 0 or quick_bill_hover() or help_open or build.panel_open or day_events.is_open() or shop_open or (shop != null and shop.is_open()): # 翻账单/看构筑/小游戏弹窗/传承商店/道具商店：整局都停下来
		queue_redraw()
		return
	if shop != null:
		shop.tick(delta) # 技能冷却/buff 计时只在游戏运行时走，面板打开时上面已 return
	elapsed += delta
	story_t += delta # 剧情打字机：翻页时归零，出全文后停走也无所谓（截断在绘制层做）
	if tutorial_step == 1: # 瞄准步骤：光标进圈就教下一步（蓄力）
		var tgt: Dictionary = _tutorial_target()
		if tgt.is_empty():
			tutorial_step = 0 # 桌上没猪了：直接放手让玩家自己玩
		elif get_global_mouse_position().distance_to(tgt.position) <= pig_size() * 0.5 + 24.0:
			tutorial_step = 2
	elif tutorial_step == 3: # 第一只猪已碎：横幅停留几秒收掉，记进存档
		tutorial_t += delta
		if tutorial_t > 3.2:
			tutorial_step = 4
			tutorial_done = true
			save_meta()
	stun_t = maxf(0.0, stun_t - delta) # 重力锤落地硬直：时间到了才能再挥
	if hit_stop > 0.0: # 打击顿帧：命中瞬间全场定格几帧 —— 冷却/猪/计时全停，只留给眼睛
		hit_stop = maxf(0.0, hit_stop - delta)
		if hit_stop > 0.0: # 还没解冻：这一帧定格。大步长（卡顿后的补帧/测试跳帧）一次耗完就照常走
			queue_redraw()
			return
	if score > last_observed_score: # 累计每笔新增收入；还账扣款不会倒扣进度
		earned_total += score - last_observed_score
	last_observed_score = score
	challenge_rest_t = maxf(0.0, challenge_rest_t - delta) # 考核后的喘息冷却只在游玩态走表
	advance_calendar()
	if not pending_challenge.is_empty() and phase == "playing":
		if challenge_warn_t > 0.0: # 预告期：横幅倒计时亮着，玩家照常砸猪，归零才进考核
			challenge_warn_t = maxf(0.0, challenge_warn_t - delta)
		if challenge_warn_t <= 0.0: # 同帧清零同帧开考：大步长（补帧/测试跳帧）也不拖一拍
			start_bill_challenge()
			queue_redraw()
			return
	if phase == "playing": # 结束了就不再催收
		bills_fx.update_collection(delta, float(earned_total))
	if update_gamble(delta): # 抛硬币翻面/落定时整局暂停：猪不走、卡不计时
		queue_redraw()
		return
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown <= 0.0 and not pending_strike.is_empty():
		fire_pending_strike()
	elif pending_t > 0.0:
		pending_t -= delta
		if pending_t <= 0.0:
			pending_strike = {} # 等太久了：玩家早就另起一锤了，这一锤作废
	if charging:
		# 蓄力封顶之后继续按住不再变强，但也不会掉 —— 玩家可以安心瞄准。
		charge_t = minf(CHARGE_MAX * 1.4, charge_t + delta)
	swing = maxf(0.0, swing - delta)
	impact_timer = maxf(0.0, impact_timer - delta)
	bonus_timer = maxf(0.0, bonus_timer - delta)
	collection_flash = maxf(0.0, collection_flash - delta)
	# 停电暗化渐入渐出（0.6 秒），不要闪
	var want_fade := 1.0 if bills_fx.is_active("blackout") else 0.0
	blackout_fade = move_toward(blackout_fade, want_fade, delta / 0.6)
	double_timer = maxf(0.0, double_timer - delta)
	if wheel != null:
		wheel.tick(delta) # 转盘层：余额跨线送机会、buff 独立倒计时、金猪压扁/到期
	if phase == "playing":
		build.tick(delta, self) # 卡片2.0：狂暴/幸运锁/贪婪税计时、闪电特效寿命
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
		hammer_position = get_global_mouse_position()
		for i in range(pigs.size()):
			var pig: Dictionary = pigs[i]
			pig.flash = maxf(0.0, pig.flash - delta)
			pig.hop = maxf(0.0, pig.hop - delta)
			if pig.hp > 0:
				pig.position += pig.velocity * delta * wheel_speed_mul() * (shop.speed_mul() if shop != null else 1.0)
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
		if stamina < swing_stamina_cost():
			end_round_exhausted()
	elif phase == "challenge":
		hammer_position = get_global_mouse_position()
		if card_type == "collect":
			update_collect(delta) # 摆钱凑整：bill_timer 是"本轮倒计时"，由它自己推进
		else:
			bill_timer -= delta
			escape.update(delta) # 逃跑场面：开场演出 + 双车道跑酷（十五轮）
	# 3D 舞台：只在凑钱考核期间活着。逃跑场面是横版 2D 自绘，不走 3D 舞台。
	if challenge3d != null:
		if phase == "challenge" and card_type == "collect":
			challenge3d.set_active(true)
			# mode 传空：柜台只当背景板，金色跟随圈收起来 —— 这关要读的是卡片，不是瞄硬币
			challenge3d.sync(coins, dodgers, hammer_position, "", invincible_timer)
		else:
			challenge3d.set_active(false)
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
	if shop != null and shop.is_open(): # 道具商店/背包打开：输入全转发给 shop（购买/拖拽、T/I/Esc 关闭）
		shop.handle_input(event)
		return
	if shop_open: # 传承商店：输入只认商店。B / Esc 关闭，点击交给购买/关闭按钮
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_B or event.keycode == KEY_ESCAPE):
			shop_open = false
			sync_cursor()
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			legacy_shop_click(get_global_mouse_position())
		return
	if intro_open: # 序幕期间吞掉一切输入：剧情页点击翻页，标题页才开始（商店按钮除外）
		var intro_pages: Array = story.get("pages", [])
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var mp := get_global_mouse_position()
				if story_page < intro_pages.size(): # 剧情对话：跳过 / 快进 / 翻页
					if STORY_SKIP_RECT.has_point(mp):
						story_page = intro_pages.size()
					elif int(story_t * 24.0) < _story_page_len(intro_pages[story_page]):
						story_t = 999.0 # 打字机没放完：第一下先出全文
					else:
						story_page += 1
						story_t = 0.0
					Sound.play("click")
				elif INTRO_SHOP_RECT.has_point(mp):
					shop_open = true
					Sound.play("click")
				else:
					intro_open = false
					_start_tutorial()
				queue_redraw()
		elif event is InputEventKey and event.pressed and not event.echo:
			if story_page < intro_pages.size():
				if int(story_t * 24.0) < _story_page_len(intro_pages[story_page]):
					story_t = 999.0
				else:
					story_page += 1
					story_t = 0.0
			else:
				intro_open = false
				_start_tutorial()
			queue_redraw()
		return
	if wheel != null and wheel.is_open(): # 转盘弹窗期间：只认「确认」（点击或空格/回车），其余一律吞掉
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			wheel.handle_click(get_global_mouse_position())
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				wheel.confirm_result()
		return
	if build.panel_open: # 构筑面板期间：C / Esc 关闭，其余输入一律吞掉（整局已暂停）
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_C or event.keycode == KEY_ESCAPE):
			build.panel_open = false
			sync_cursor()
			queue_redraw()
		return
	if day_events != null and day_events.is_open(): # 天数小游戏弹窗：吞掉一切输入，只认点击与确认键
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			day_events.handle_click(get_global_mouse_position())
		elif event is InputEventKey and event.pressed and not event.echo:
			day_events.handle_key(event.keycode)
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_H or (help_open and event.keycode == KEY_ESCAPE)):
		help_open = not help_open
		sync_cursor()
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if HELP_BUTTON.has_point(get_global_mouse_position()) or help_open:
			help_open = not help_open
			sync_cursor()
			queue_redraw()
			return
	if help_open:
		return
	if event is InputEventMouseButton and event.pressed:
		var wheel_up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
		var wheel_down: bool = event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if (wheel_up or wheel_down) and phase == "playing" and not bill_open and bill_detail < 0:
			if gamble_state != "flip" and gamble_state != "result":
				var mouse_point: Vector2 = get_canvas_transform().affine_inverse() * event.position
				if BILL_PANEL.has_point(mouse_point):
					var direction := 1 if wheel_down else -1
					quick_bill_offset = clampi(quick_bill_offset + direction, 0, quick_bill_max_offset())
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
	if event is InputEventKey and event.pressed and not event.echo:
		if tutorial_step in [1, 2, 3] and event.keycode == KEY_ESCAPE: # 教学随时可跳：不把老玩家按在教程里
			tutorial_step = 4
			tutorial_done = true
			save_meta()
			queue_redraw()
			return
		if phase == "playing" and shop != null and not bill_open and bill_detail < 0 and not help_open and not build.panel_open:
			# 道具商店的三个入口：商店/背包/快捷栏技能。只在真正的游玩阶段生效，不抢其他界面的键
			if event.keycode == KEY_T:
				shop.try_open_shop()
				sync_cursor()
				queue_redraw()
				return
			if event.keycode == KEY_I:
				shop.try_open_backpack()
				sync_cursor()
				queue_redraw()
				return
			if event.keycode in [KEY_1, KEY_2, KEY_3]:
				shop.try_activate_skill(int(event.keycode - KEY_1))
				queue_redraw()
				return
		if phase == "challenge" and card_type == "dodge" and escape != null:
			# 逃跑场面：↑↓/W/S 换道，空格跳过开场演出。先于 B/账本等全局键处理
			if event.keycode in [KEY_UP, KEY_W, KEY_DOWN, KEY_S, KEY_SPACE, KEY_ENTER]:
				escape.handle_key(event.keycode)
				queue_redraw()
				return
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
		if event.keycode == KEY_C and phase == "playing" and not bill_open: # 构筑面板：查看本局成长
			build.panel_open = not build.panel_open
			sync_cursor()
			queue_redraw()
			return
		if event.keycode == KEY_R:
			reset_game()
		elif phase == "card" and card_offers.size() == 3 and event.keycode in [KEY_1, KEY_2, KEY_3]:
			apply_card(int(event.keycode - KEY_1))
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if phase == "card":
				apply_card()
			elif phase == "finished" or phase == "bankrupt":
				reset_game()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		# 松开鼠标：这一锤落下去。轻点 = 快锤（和以前一模一样），按住 = 重锤。
		if charging:
			charging = false
			var ratio := clampf(charge_t / CHARGE_MAX, 0.0, 1.0)
			charge_t = 0.0
			if phase == "playing" and not bill_open and bill_detail < 0 \
					and not help_open and not build.panel_open and gamble_state != "flip" and gamble_state != "result":
				strike_release(get_global_mouse_position() + AIM_OFFSET, 1.0 + pow(ratio, 1.6) * CHARGE_POWER)
		return
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
		if bill_open: # 账本摊开着：点纸放大，点外面收起（转盘这时已收起，不再派发点击）
			if LEDGER_RECT.has_point(point):
				var idx := ledger_index_at(point)
				if idx >= 0:
					bill_detail = idx
			else:
				bill_open = false
			queue_redraw()
			return
		if phase == "playing" and BILL_PANEL.has_point(point):
			var indices := quick_bill_indices()
			for slot in range(indices.size()):
				if quick_pay_rect(slot).has_point(point):
					if score >= bill_pay_amount(indices[slot]):
						pay_bill(indices[slot])
					queue_redraw()
					return
			if Rect2(1084, 612, 182, 32).has_point(point):
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
				click_collect(point) # 摆钱凑整：点哪张路子就选哪张
			else:
				escape.handle_click(point) # 逃跑场面：点上下半屏换道 / 跳过演出
		elif phase == "finished" or phase == "bankrupt":
			if LEGACY_SHOP_RECT.has_point(point): # 结算后正好清点家底：顺手逛逛传承商店
				Sound.play("click")
				shop_open = true
				queue_redraw()
			elif CONTINUE_RECT.has_point(point):
				Sound.play("click")
				reset_game()
		else: # playing：桌边那枚硬币的按钮在前面已经处理过，这里就只剩挥锤了
			if wheel != null and wheel.handle_click(point): # 抽奖按钮：点到了就不挥锤
				queue_redraw()
				return
			# 不立刻砸：先记下“按住了”，松手那一刻才落锤。按住越久砸得越重。
			# 同时锁下这一刻瞄准的猪：按住的几百毫秒里它会走开，但"我要砸它"的意图没变。
			charging = true
			charge_t = 0.0
			charge_pig = pig_index(strike_target(point + AIM_OFFSET)) # 按下那一刻瞄的是准心处的猪

func end_round_exhausted() -> void:
	# 体力见底：本轮结束（不是破产，余额保留，R 重开）
	end_reason = "exhausted"
	phase = "finished"
	award_meta_progress()
	Sound.play("round_end") # 梅泽伟录的一轮收尾音，比原来的失败音更贴"本轮结束"的语义


## 转盘 buff 的当前倍率。速度同时作用于小猪移动与重生倒计时；得分与卡片双倍相互独立
func wheel_speed_mul() -> float:
	return 1.0 if wheel == null else wheel.pig_speed_multiplier()

func wheel_score_mul() -> float:
	return 1.0 if wheel == null else wheel.score_multiplier()

## 转盘「直还账单」：免费清掉最便宜的 count 张
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

## 转盘金猪的结算：固定 +¥200（不吃卡片/连击/暴击加成），压扁回弹之后由转盘层引爆金币特效
func _resolve_wheel_gold_hit(pig: Dictionary) -> void:
	pig.hp = 0
	pig.respawn = 9999.0 # 不让普通重生逻辑捡走；转盘层在压扁动画结束后移除
	pig.gold_squash = 0.34
	var gain := 200
	score += gain
	if gain > best_gain:
		best_gain = gain # 转盘金猪往往就是本局之最
	shake = maxf(shake, float(settings.get("shake_duration", 0.12)))
	popups.append({"position": pig.position + Vector2(0, -55), "life": 0.9,
		"text": "+¥" + str(gain), "color": Color("#ffd76a")})
	Sound.play("pop", 0.85)

## 金猪的自发光光晕：两圈呼吸金晕 + 四颗环绕小星，画在猪身后
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

# Match the visible sprite position, including its walking bounce and hit hop.
## 这只猪"看起来"在哪：判定中心跟视觉走（贴图偏移 / 走路弹跳 / 受击跳动 / 被砸闪白）。
## 差这几 px，玩家瞄准的是猪肚子，砸到的却是猪头顶上方那块桌子。
func pig_visual_center(pig: Dictionary) -> Vector2:
	var center: Vector2 = pig.position
	var k := pig_scale(pig.type) * pig_size() / PIG3D_SIZE
	if pig_tex.has(String(pig.type.get("id", "piggy"))):
		center += PIG3D_OFFSET
		var bounce := absf(sin(float(pig.get("hop_phase", 0.0))))
		var speed: float = pig.velocity.length()
		center.y -= bounce * lerpf(14.0, 20.0, clampf(speed / 160.0, 0.0, 1.0)) * k
		if pig.flash > 0.0:
			center.x += sin(pig.flash * 90) * 8 * k
	elif use_3d:
		center += PIG3D_OFFSET
	if pig.hop > 0.0:
		center.y -= sin(pig.hop / 0.24 * PI) * 26 * k
	return center

## 一只猪的判定椭圆半轴（像素，横向 / 纵向）。
## 判定、松手瞄准修正、输入缓冲三处都走这一个公式 —— 各写一遍迟早会对不上。
func pig_hit_extents(pig: Dictionary) -> Vector2:
	var k := pig_scale(pig.type) * pig_size() / PIG3D_SIZE * hammer_reach_multiplier
	return Vector2(84.0, 64.0) * k + Vector2(10, 10)

## 落点相对这只猪的"归一化距离"：<=1 就是在它身上，越小说明瞄得越正。
func hit_offset(point: Vector2, pig: Dictionary) -> float:
	var d: Vector2 = point - pig_visual_center(pig)
	return (d / pig_hit_extents(pig)).length()

## 这只猪在 pigs 里的下标（按引用找，不按内容比 —— 猪的数据会长得一样）
func pig_index(pig: Dictionary) -> int:
	if pig.is_empty():
		return -1
	for i in range(pigs.size()):
		if is_same(pigs[i], pig):
			return i
	return -1

func strike_target(point: Vector2) -> Dictionary:
	var target: Dictionary = {}
	var best := INF
	for pig in pigs:
		if pig.hp <= 0:
			continue
		var distance := hit_offset(point, pig)
		if distance <= 1.0 and distance < best:
			best = distance
			target = pig
	return target

func swing_stamina_cost() -> float:
	return build.cost(self) # 卡片2.0：稳手学徒减耗 / 过载引擎加耗 / 狂战士暴走七折


func strike(point: Vector2, power := 1.0) -> void:
	if phase != "playing" or build.panel_open or stun_t > 0.0:
		return
	if cooldown > 0.0:
		# 冷却里按下的这一锤不进垃圾桶：记下来，冷却一结束立刻补上。
		# 静默丢一次点击，玩家感觉不到"冷却"，只会觉得"我明明砸上去了却没反应"——
		# 这是"锤子不准"里最容易被忽略、也最伤手感的那一半。
		# strike_buffer 设 0 可整体关掉（自动化测试的确定性就靠它）。
		var buffer := float(settings.get("strike_buffer", 0.3))
		if buffer > 0.0 and pending_t <= 0.0:
			pending_strike = {"point": point, "power": power, "pig": pig_index(strike_target(point))}
			pending_t = buffer
		return
	var cost := swing_stamina_cost()
	if stamina < cost:
		stamina_flash = 0.4
		popups.append({"position": point + Vector2(-30, -40), "life": 0.7, "text": "体力不足"})
		end_round_exhausted()
		return
	hammer_position = point - AIM_OFFSET # 锤头悬在命中点的右上（AIM_OFFSET 的反方向）
	swing = 0.16
	cooldown = build.cooldown(self) # 卡片2.0：过载引擎/狂战士/赊账/马刺的冷却修正都算在里面
	stamina -= cost
	if shop != null and shop.current_hammer_id == "gravity": # 重力锤：蓄力越久伤害与范围越大，落地硬直
		_gravity_strike(point)
		if wheel != null:
			wheel.on_landed_hit()
		return
	var landed := false # 有没有打到东西：空挥要有和命中完全不同的声音
	var target := strike_target(point)
	var hammer_id: String = shop.current_hammer_id if shop != null else "iron"
	var hammer_dmg: float = shop.hammer_base_damage() if shop != null else 1.0
	if hammer_id == "magnet":
		# 磁吸锤：先把范围内的猪吸到落点，伤害按吸附前的距离递减
		var pull_r: float = shop.pull_radius()
		var fall: float = shop.falloff_min()
		for pig in pigs:
			if pig.hp <= 0 or float(pig.respawn) > 0.0:
				continue
			var d: float = pig.position.distance_to(point)
			if d <= pull_r:
				pig["magnet_scale"] = lerpf(1.0, fall, d / pull_r)
				pig.position = point
	for pig in pigs:
		var hit_this: bool = pig == target and not target.is_empty()
		if hammer_id == "magnet" and pig.hp > 0 and float(pig.respawn) <= 0.0 and pig.has("magnet_scale"):
			hit_this = true # 磁吸锤：范围里吸附过的猪全部结算
		if hit_this:
			hits += 1
			pig.flash = 0.14
			pig.hop = 0.24 # 受击跳动
			if combo_timer > 0.0:
				combo_count += 1
			else:
				combo_count = 1
			combo_timer = float(settings.get("combo_window", 1.5))
			var hit_damage := 1 + hammer_damage_bonus
			if power >= 1.30:
				hit_damage += 1 # 蓄满的重锤多打一血：这是它值得慢半秒的理由
			if hammer_damage_bonus > 0 and combo_count >= 3:
				hit_damage += 1 # 重锤 + 连击：連击热度达到 3 后再加一伤害
			if light_hammer_off:
				# 断臂求生：轻锤完全出不了伤害，想砸碎任何东西都必须蓄满。
				# 连击照样计数（你确实打中了），只是这一下不疼。
				hit_damage = int(round(float(hit_damage) * heavy_hammer_multiplier)) if power >= 1.30 else 0
			if hit_damage > 0: # 断臂求生的零伤锤不吃卡片增伤
				build.progress("berserker", self) # 狂战士训练：每命中一次记一次成长
				hit_damage += build.damage_bonus() + build.consume_focus(self) # 暴走 +1 / 校准锤蓄伤
				stamina = minf(float(settings.get("stamina_max", 100)), stamina + float(settings.get("stamina_hit_refund", 1.0))) # 打准了喘口气：命中回一点体力
			if combo_count == 5:
				build.progress("steadiness", self) # 稳手学徒：五连击计成长
			var lucky_crit: bool = build.roll_critical() # 幸运马蹄铁的独立暴击：伤害翻倍（与本地连击暴击相互独立）
			if lucky_crit and hit_damage > 0:
				hit_damage *= 2
				Sound.play("crit")
			build.critical_reward(lucky_crit, self)
			pig.hp -= float(hit_damage) * hammer_dmg * float(pig.get("magnet_scale", 1.0))
			if hammer_id == "dual" and pig.hp > 0.0: # 连打锤：紧接第二下，共用同一次冷却
				hits += 1
				pig.hp -= float(hit_damage) * hammer_dmg
				Sound.play("crack", 1.1, 0.6)
			if hit_damage <= 0:
				# 断臂求生：打中了却没掉血，必须给一句反馈，否则玩家会以为判定坏了
				popups.append({"position": point + Vector2(-30, -58), "life": 0.55,
					"text": "轻锤无效", "color": Color("#9a8f80"), "size": 18})
			impact_position = point
			impact_timer = 0.18
			impact_broken = pig.hp <= 0
			shake = maxf(shake, 0.065)
			hit_stop = maxf(hit_stop, float(settings.get("hit_stop_hit", 0.06))) # 顿帧：不管碎没碎，手感都在
			Sound.play("pop", 0.65 if impact_broken else 0.9, 0.65 if impact_broken else 0.35)
			if bool(pig.get("wheel_gold", false)) and pig.hp <= 0: # 转盘金猪走专属结算：一锤 +¥200，压扁回弹后爆金币
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
				var crit := false # 这一锤有没有暴击：只放大正收益，绝不放大黑猪的亏损
				if gain > 0:
					# 玻璃猎人：点名的猪种翻倍、其余打折 —— 这一局你要盯着某一类猪砸。
					var type_mul := float(type_value_bonus.get(kind, type_value_penalty))
					gain = roundi(float(gain) * earnings_multiplier * power * type_mul * build.income_multiplier())
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
					crit = roll_crit(combo_count)
					if crit:
						gain *= 2 # 暴击和三连以上叠加时能滚出很高的数字，这正是"手气来了"的时刻
					gain = roundi(float(gain) * wheel_score_mul()) # 转盘得分×2：与卡片双倍相互独立，可叠乘
					gain += build.direct_break_bonus(self) # 碎瓷回收：每三只普通击碎返钱（同时累计破罐工匠进度）
					if shop != null:
						gain = roundi(float(gain) * shop.score_mul()) # 筛金算筹：技能激活期间的收益倍率
						if shop.kill_bonus_mul() > 1.0: # 神秘盲盒：接下来三次击碎额外倍率
							gain = roundi(float(gain) * shop.kill_bonus_mul())
							shop.consume_kill()
					score += gain
					if gain > best_gain:
						best_gain = gain # 结算高光：本局最豪的一锤
				broken += 1
				build.progress("hunter", self) # 猎猪执照：击碎计数成长
				spawn_particles(pig.position, kind, gain)
				var pcolor := Color("#ffe092")
				if gain < 0:
					pcolor = Color("#e06c5c")
					Sound.play("stamp", 1.0, 0.95)
					Sound.play("tails", 1.0, 0.45) # 下坠音：这不是好事
				elif crit:
					pcolor = Color("#ffd76a")
					# 暴击的"重量"要从三个通道同时给：屏幕抖得更狠、顿帧更长、音更高、字更大
					shake = maxf(shake, float(settings.get("shake_duration", 0.12)) * 1.9)
					hit_stop = maxf(hit_stop, float(settings.get("hit_stop_crit", 0.15)))
					Sound.play("coin_land", 1.5, 0.95)
					Sound.play("pop", 1.55)
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
				var pop_text: String = ("+¥" + str(gain) if gain > 0 else "-¥" + str(-gain))
				if crit:
					pop_text = "暴击 " + pop_text
				popups.append({"position": pig.position + Vector2(0, -55), "life": 1.15 if crit else 0.9,
					"text": pop_text, "color": pcolor, "size": 38 if crit else 28})
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
			build.after_hit(pig, point, self) # 卡片2.0：重锤爆破 / 连锁破碎的波次伤害（击杀走 settle_card_break）
			break
	if wheel != null: # 转盘机会的连击计数：砸中 +1，漏砸（挥空）清零
		if landed:
			wheel.on_landed_hit()
		else:
			wheel.on_missed_swing()
	if not landed: # 挥空的“风声”要比命中轻，否则每次空挥都像打到了东西
		build.register_miss(self) # 卡片2.0：校准锤上膛 / 破罐保险计次
		stamina = maxf(0.0, stamina - float(settings.get("stamina_miss_extra", 0.0)))
		Sound.play("miss", 1.0, 0.7)
		if power >= 1.30:
			# 重锤砸在桌面上：手会震、桌子会响。轻锤打偏不罚（那是正常瞄偏），
			# 重锤打偏才罚 —— 这样"蓄力"才是个真正的决定。
			stamina = maxf(0.0, stamina - 2.0)
			shake = maxf(shake, 0.2)
			popups.append({"position": point + Vector2(-30, -70), "life": 0.9,
				"text": "砸空了", "color": Color("#d08f7a"), "size": 20})
			Sound.play("stamp", 0.6, 0.8)

## 重力锤：按下时按蓄力比例结算，伤害/范围递增，落地后自身短暂硬直。
## 只砸一个落点范围，不挑猪种 —— 范围越大越容易顺手把旁边的猪也带走。
func _gravity_strike(point: Vector2 = Vector2.INF) -> void:
	if shop == null:
		return
	if point == Vector2.INF: # 不传落点时用当前锤头位置：自动测试直接调这个入口
		point = hammer_position
	charge_time = maxf(0.05, float(shop.current_hammer().get("charge_time", 1.0)))
	var ratio := clampf(charge_t / charge_time, 0.0, 1.0)
	var dmg := lerpf(float(shop.current_hammer().get("damage_min", 1.0)), \
		float(shop.current_hammer().get("damage_max", 3.0)), ratio)
	var radius: float = 84.0 * lerpf(1.0, float(shop.current_hammer().get("radius_max", 1.6)), ratio)
	var landed := false
	for pig in pigs:
		if pig.hp <= 0 or float(pig.respawn) > 0.0:
			continue
		if pig.position.distance_to(point) <= radius:
			pig.hp -= dmg
			pig.flash = 0.14
			pig.hop = 0.24
			landed = true
			if pig.hp <= 0:
				settle_card_break(pig, false)
	if landed:
		impact_position = point
		impact_timer = 0.2
		shake = maxf(shake, 0.22)
		hit_stop = maxf(hit_stop, 0.07)
		Sound.play("pop", 0.7, 0.9)
	else:
		Sound.play("miss", 0.9, 0.6)
	stun_t = float(shop.current_hammer().get("stun", 0.45))
	charge_t = 0.0
	queue_redraw()


## 卡片2.0 的连锁/爆破击杀结算：与 strike 主结算同一套入账规则，
## 但不带蓄力倍率与猪种修正（连锁伤害本身就不挑猪种）。
func settle_card_break(pig: Dictionary, secondary: bool) -> void:
	if pig.hp > 0 or float(pig.respawn) > 0.0:
		return
	pig.respawn = float(settings.respawn_seconds)
	shake = float(settings.get("shake_duration", 0.12))
	var kind: String = String(pig.type.get("id", "piggy"))
	var gain := pig_value(pig.type)
	if gain > 0:
		gain = roundi(float(gain) * earnings_multiplier * build.income_multiplier())
		if secondary:
			gain += build.secondary_reward(self)
		if combo_count > 1:
			gain += (combo_count - 1) * combo_bonus_per_hit
			if earnings_multiplier > 1.0:
				gain += (combo_count - 1) * 2 # 贪婪 + 连击：连击层数继续放大收益
	if combo_count >= int(settings.get("combo_threshold_fever", 5)):
		for i in range(3): # 狂热：再撒两把，手气正旺的时候满桌是钱
			spawn_particles(pig.position, kind, gain)
	if gain < 0:
		# 催债猪：碎了要倒贴，但最多白干一场，不许一锤失误直接破产
		score = maxi(1, score + gain)
	else:
		if double_timer > 0.0:
			gain *= 2
		gain = roundi(float(gain) * wheel_score_mul()) # 转盘得分×2与卡片加成独立叠乘
		if shop != null:
			gain = roundi(float(gain) * shop.score_mul())
		score += gain
	broken += 1
	if tutorial_step == 2: # 新手引导：第一只猪碎了，收尾横幅展示入账金额
		tutorial_step = 3
		tutorial_t = 0.0
		tutorial_gain = gain
	build.progress("hunter", self) # 连锁击碎同样计入猎猪执照
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
		card_delay = float(settings.get("card_pop_delay", 0.45))

## 补上冷却期间按下、还没落下去的那一锤。
## 优先砸回玩家当时瞄准的那一只：它可能已经走了几步，但"我要砸它"这个意图没变；
## 那一只正好碎了/消失了，才退回原来的落点。
func fire_pending_strike() -> void:
	if pending_strike.is_empty():
		return
	var p: Dictionary = pending_strike
	pending_strike = {}
	pending_t = 0.0
	var idx := int(p.get("pig", -1))
	var power := float(p.get("power", 1.0))
	# 排队期间体力先见底了：这一锤直接作废，不能替玩家把这一局结束掉
	if stamina < swing_stamina_cost():
		return
	if idx >= 0 and idx < pigs.size() and int(pigs[idx].hp) > 0:
		strike(pig_visual_center(pigs[idx]), power)
	else:
		strike(p.get("point", Vector2.ZERO), power)

## 松手落锤的瞄准修正：按下那一刻瞄的是哪只猪，松手时只要它还在锤头附近，就砸它现在的位置。
## 按住的几百毫秒里猪自己走开，不该算玩家失手 —— 那是"锤子不准"里最冤的一种。
## 真跑远了（超出 2 倍判定范围）才按落点算：它是跑了，不是你手抖。
func strike_release(point: Vector2, power: float) -> void:
	var idx := charge_pig
	charge_pig = -1
	if idx >= 0 and idx < pigs.size() and int(pigs[idx].hp) > 0 \
			and hit_offset(point, pigs[idx]) <= 2.0:
		strike(pig_visual_center(pigs[idx]), power)
	else:
		strike(point, power)

## 暴击：连击越高越容易出，封顶 30%。只放大正收益（调用处保证）。
func crit_chance(combo: int) -> float:
	var base := float(settings.get("crit_base_chance", 0.06)) + 0.015 * legacy_level("ring") # 幸运戒指：永久暴击
	var per := float(settings.get("crit_per_combo", 0.015))
	var cap := float(settings.get("crit_max_chance", 0.30))
	return minf(cap, maxf(0.0, base + float(maxi(0, combo - 1)) * per))

func roll_crit(combo: int) -> bool:
	return randf() < crit_chance(combo)

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
		{"id":"cash", "name":"现金奖励", "desc":"立即获得 ¥" + str(int(settings.get("reward_card_amount", 35))), "icon":"＋", "color":"#efbc72"},
		# --- 代价型：不是把数字调大，而是改变这一局的打法 ---
		{"id":"allin", "name":"孤注一掷", "desc":"体力上限 -40%，敲猪收益 +80%", "icon":"!", "color":"#e0503f"},
		{"id":"glasshunter", "name":"玻璃猎人", "desc":"玻璃猪收益 ×3，其余猪种 -30%", "icon":"◆", "color":"#7fa8b4"},
		{"id":"onehand", "name":"断臂求生", "desc":"轻锤不再造成伤害，重锤伤害 ×2", "icon":"✂", "color":"#b06b8a"},
		{"id":"overdraft", "name":"透支信用", "desc":"立刻 +¥200，但多一张 ¥150 的账单", "icon":"▤", "color":"#d99b70"},
		{"id":"miser", "name":"守财奴", "desc":"每还掉一张账单，永久收益 +5%", "icon":"◈", "color":"#8fbf7a"}
	]
	if not pig_population_doubled:
		pool.append({"id":"herd", "name":"猪群翻倍", "desc":"桌上存钱罐数量翻倍，整体缩小", "icon":"×2", "color":"#69b88e"})
	# 一次性改造类不重复出：再抽到一次会把代价叠成死局（体力上限 ×0.6 两次 = 一局只够挥几锤）。
	for i in range(pool.size() - 1, -1, -1):
		var cid := String(pool[i].id)
		if (cid == "allin" and stamina_max_multiplier < 1.0) \
				or (cid == "glasshunter" and not type_value_bonus.is_empty()) \
				or (cid == "onehand" and light_hammer_off):
			pool.remove_at(i)
	for card in pool:
		if String(card.id) == "heavy" and combo_bonus_per_hit > 0:
			card.desc = "已有连击联动：连击达到 3 层后再 +1 伤害"
		elif String(card.id) == "combo" and earnings_multiplier > 1.0:
			card.desc = "已有贪婪联动：连击每层额外 +2 金钱"
		elif String(card.id) == "greed" and combo_bonus_per_hit > 0:
			card.desc = "已有连击联动：连击层数也计入收益"
		elif String(card.id) == "stamina" and stamina_cost_reduction > 0.0:
			card.desc = "轻型锤柄联动：上限额外 +10，恢复 45 点"
	pool = build.prepare_pool(pool) # 卡片2.0：抽掉基础重锤，混入进化/代价/任务卡（已持有的不再重复出）
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
		build.acquire(String(offer.id), self) # 卡片2.0：进化/代价/任务卡的等级与一次性效果在 build 里记账
		match String(offer.id):
			"heavy":
				pass # 重锤改造已进化化，加成由 acquire 按等级结算
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
			"allin":
				# 体力上限砍到六成，收益直接 ×1.8：一局能挥的锤数变少，但每一锤都值钱得多。
				stamina_max_multiplier *= 0.6
				settings["stamina_max"] = maxi(20, int(round(float(settings.get("stamina_max", 100)) * 0.6)))
				stamina = minf(stamina, float(settings.get("stamina_max", 20)))
				earnings_multiplier *= 1.8
			"glasshunter":
				# 从这一刻起，桌上只有玻璃猪值得砸。别的猪照砸不误，只是不值钱。
				type_value_bonus = {"glass": 3.0}
				type_value_penalty = 0.7
			"onehand":
				light_hammer_off = true
				heavy_hammer_multiplier = 2.0
			"overdraft":
				var debt_amount := int(settings.get("overdraft_bill", 150))
				score += int(settings.get("overdraft_cash", 200))
				bills.append({"name": "信用卡透支", "amount": debt_amount,
					"no": "OD" + str(game_day), "due": format_game_date(game_day + 3), "due_day": game_day + 3})
				bills_fx.sync(bills)
				sort_bills()
				Sound.play("cash")
			"miser":
				pay_greed_per_pay += 0.05
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

## 账单到期考核：接住 advance_calendar 挂上的那一次机会。
## 小额账单考「凑钱」，大额账单（房租、车险这种）考「躲催债」—— 越贵的账，催得越凶。
## 躲债不再有"主动接单"的入口：它只由条件触发 —— 大额账单到期，或者房租欠着时房东上门。
func _collection_bill_tag() -> String:
	# 催收效果挂在没还的房租上：找到那张房租，就是房东这次要堵你的人质。
	for bill in bills:
		if String(bill.get("effect_id", "")) == "collection" and BillManagerScript.is_special(bill):
			return String(BillManagerScript.tag_of(bill))
	return ""


func start_bill_challenge() -> void:
	if pending_challenge.is_empty():
		return
	challenge_bill_tag = String(pending_challenge.get("tag", ""))
	var kind := String(pending_challenge.get("kind", "collect"))
	collection_mode = bool(pending_challenge.get("collection", false))
	pending_challenge = {}
	challenge_warn_t = 0.0 # 开考即消费掉预告
	card_type = kind
	# 记住是哪张账单在催：玩家的第一反应一定是"谁到期了、多少钱"
	challenge_label = ""
	for bill in bills:
		if String(BillManagerScript.tag_of(bill)) == challenge_bill_tag:
			challenge_label = String(bill.name) + " ¥" + str(int(bill.amount))
			break
	start_challenge()
	Sound.play("stamp", 0.9)


## 按编号清掉一张账单（考核成功时用）：它带出来的利息单、滞纳单也一起作废。
func clear_bill_by_tag(tag: String) -> bool:
	if tag.is_empty():
		return false
	for i in range(bills.size()):
		if String(BillManagerScript.tag_of(bills[i])) != tag:
			continue
		bills.remove_at(i)
		for j in range(bills.size() - 1, -1, -1): # 倒着删，免得删完后面的下标全乱
			if String(bills[j].get("source", "")) == tag:
				bills.remove_at(j)
		paid_count += 1
		bills_fx.sync(bills)
		sort_bills()
		clamp_bill_page()
		return true
	return false


func start_challenge() -> void:
	phase = "challenge"
	bill_timer = bill_time
	sync_cursor() # 凑钱关要点桌面上的路子卡、躲债关是鼠标跟手，两种都留着系统箭头
	if card_type == "collect":
		collected = 0
		collect_round = 1
		collect_rounds = maxi(1, int(settings.get("collect_rounds", 4)))
		collect_debt = 0
		collect_pain = 0.0
		coins.clear()
		collect_deal() # 直接摊牌：第一轮的三张路子就在桌上
	else:
		coins.clear() # 上一个凑钱关剩下的钱不许带进躲债关：舞台干净地开演
		dodgers.clear()
		dodger_spawn_timer = 0.0
		dodge_lives = int(settings.dodge_lives)
		invincible_timer = 0.0
		escape.start() # 夺门而出：开场演出后进入双车道跑酷

func finish_challenge(success: bool) -> void:
	challenge_rest_t = float(bill_data.get("challenge_rest_seconds", 6.0)) # 喘息几秒：别背靠背连考，也别刚打完就突袭下一张
	coins.clear()
	collect_cards.clear()
	collect_pick_t = 0.0
	collect_picked = -1
	dodgers.clear()
	var bound_tag := challenge_bill_tag
	challenge_bill_tag = ""
	challenge_label = ""
	if collection_mode: # 房东上门：赢了是"拖延"（房租延期，债务还在），输了当场逾期 —— 躲债不是免单
		collection_mode = false
		var rent: Dictionary = {}
		for b in bills:
			if String(BillManagerScript.tag_of(b)) == bound_tag:
				rent = b
				break
		if success:
			var delay := int(bills_fx.number("collection", "dodge_delay_days", 2))
			if not rent.is_empty():
				rent["due_day"] = maxi(int(rent.get("due_day", game_day)), game_day) + delay
				rent["overdue"] = false # 甩掉房东：连逾期章也一并摘了
				rent["due"] = format_game_date(int(rent["due_day"]))
			popups.append({"position": Vector2(640, 420), "life": 1.6,
				"text": "房东被甩掉了 · 房租延期 " + str(delay) + " 天"})
			Sound.play("cash", 1.05)
		else:
			var drain := float(bills_fx.number("collection", "dodge_fail_stamina", 25))
			stamina = maxf(6.0, stamina - drain) # 留一口气：被堵住也不至于直接倒下
			stamina_flash = 0.6
			if not rent.is_empty():
				rent["overdue"] = true # 上门没躲掉：房租当场逾期
			popups.append({"position": Vector2(640, 420), "life": 1.6, "text": "被房东堵住了 · 房租当场逾期"})
			Sound.play("stamp", 0.7)
		phase = "playing"
		collected = 0
		bill_timer = 0.0
		bills_fx.sync(bills)
		sort_bills()
		return
	if success:
		var reward := int(settings.bill_reward)
		score += reward
		# 绑定了账单（到期催缴）：赢的是这张账的免单；没绑定（老式考核）就清最便宜的一张。
		if not clear_bill_by_tag(bound_tag):
			clear_cheapest_bill()
		popups.append({"position": Vector2(640, 420), "life": 1.4, "text": "付清 +¥" + str(reward)})
		phase = "playing"
		Sound.play("cash", 1.05)
	else:
		score -= bill_amount
		add_interest_bills() # 信用卡：每张没还的卡追加一笔利息（只此一处，不会重复计）
		add_overdue_bill() # 逾期：账单不但没消掉，还多出一张滞纳单
		# 到期催缴考砸了：这张账单当场正式逾期，不再等下一天日历再补一刀。
		# 不额外挂滞纳金 —— add_overdue_bill() 刚加的那张就是它的罚单。
		if not bound_tag.is_empty():
			for i in range(bills.size()):
				if String(BillManagerScript.tag_of(bills[i])) == bound_tag:
					bills[i]["overdue"] = true
					break
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

## ---------------------------------------------------------------- 摆钱凑整
## 凑钱关的核心问题不是"手快"，而是"这笔钱你打算从哪儿抠出来"。
## 桌上摊三张路子（稳 / 中 / 猛）：每张给一笔钱，代价也当场记上 ——
## 力气（砸猪的本钱）、或者一张新账（把窟窿挪到以后还）。
## 轮次有限、每轮还带倒计时：犹豫本身也是代价（这一轮就白过了）。

## 三张卡在屏幕上的位置：居中横排，从左到右危险度递增（玩家第二次就认得版式）。
func collect_card_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := collect_cards.size()
	if n <= 0:
		return out
	var total := COLLECT_CARD_SIZE.x * float(n) + COLLECT_CARD_GAP * float(n - 1)
	var x0 := 640.0 - total * 0.5
	for i in range(n):
		out.append(Rect2(x0 + float(i) * (COLLECT_CARD_SIZE.x + COLLECT_CARD_GAP),
			COLLECT_CARD_Y, COLLECT_CARD_SIZE.x, COLLECT_CARD_SIZE.y))
	return out

## 卡面金额按账单大小等比缩放：¥50 的单子和 ¥200 的单子，走的是同一套价目表。
func collect_gain(card: Dictionary) -> int:
	var base := float(card.get("gain", 10.0))
	return maxi(3, int(round(base * float(bill_amount) / 50.0)))

## "你现在必须付多少"：剩余轮次平摊下来，这一轮至少得进多少 —— 用于保证牌面不坑人。
func collect_need_now() -> int:
	var left := maxi(1, collect_rounds - collect_round + 1)
	return int(ceil(float(bill_amount - collected) / float(left)))

func collect_round_seconds() -> float:
	return maxf(3.0, float(settings.get("collect_round_seconds", 12.0)))

## 发牌：稳/中/猛各一张（顺序固定 = 玩家一眼看懂风险梯度）。
## 兜底规则：这一轮至少有一张"够用"的卡。否则玩家再会算也凑不够，
## 那就不叫决策、叫抽卡 —— 凑钱关的乐趣必须是"选"，不能是"运气"。
func collect_deal() -> void:
	collect_cards.clear()
	collect_picked = -1
	collect_pick_t = 0.0
	bill_timer = collect_round_seconds()
	var buckets := {1: [], 2: [], 3: []}
	var raw_pool: Variant = settings.get("collect_cards", [])
	if raw_pool is Array:
		for raw in raw_pool:
			if raw is Dictionary:
				var t := int(raw.get("tier", 2))
				if buckets.has(t):
					buckets[t].append(raw)
	for t in [1, 2, 3]:
		var pool: Array = buckets[t]
		if pool.is_empty():
			continue
		collect_cards.append(Dictionary(pool[randi() % pool.size()]).duplicate(true))
	if collect_cards.is_empty():
		return
	var need := collect_need_now()
	var best := 0
	for i in range(collect_cards.size()):
		if collect_gain(collect_cards[i]) > collect_gain(collect_cards[best]):
			best = i
	if collect_gain(collect_cards[best]) < need:
		# 反算回基准值（gain 会按账单大小缩放），让这张卡的实付金额刚好够
		collect_cards[best]["gain"] = float(need) * 50.0 / float(maxi(1, bill_amount))

## 选一张：钱进袋 → 代价立刻生效 → 停顿半秒（卡抬起来、飘字）→ 结算/发下一轮。
func collect_pick(index: int) -> void:
	if collect_pick_t > 0.0 or collect_picked >= 0:
		return
	if index < 0 or index >= collect_cards.size():
		return
	var card: Dictionary = collect_cards[index]
	var gain := collect_gain(card)
	collected += gain
	collect_picked = index
	collect_pick_t = 0.55
	var rect: Rect2 = collect_card_rects()[index]
	popups.append({"position": rect.get_center() + Vector2(0, -18), "life": 1.0, "text": "+¥" + str(gain)})
	Sound.play("cash", 1.0 + 0.04 * float(mini(collect_round, 4)), 0.6)
	var cost_text := collect_apply_cost(card)
	if cost_text != "":
		popups.append({"position": rect.get_center() + Vector2(0, 26), "life": 1.3, "text": cost_text})
	Sound.play("click", 0.9)

## 代价结算。返回飘字用的说明（空字符串 = 这张卡没代价）。
func collect_apply_cost(card: Dictionary) -> String:
	var kind := String(card.get("cost", "none"))
	if kind == "stamina":
		var drain := float(card.get("cost_value", 0.0))
		stamina = maxf(6.0, stamina - drain) # 留一口气：凑钱把自己凑晕就没意思了
		stamina_flash = 0.6
		collect_pain += drain
		return "力气 -" + str(int(drain))
	if kind == "bill":
		var amount := maxi(5, int(round(float(bill_amount) * float(card.get("cost_ratio", 0.4)))))
		bills.append({"name": String(card.get("debt_name", "欠条")), "amount": amount,
			"id": "iou", "no": str(9000 + randi() % 900),
			"due": format_game_date(game_day + 2), "due_day": game_day + 2})
		collect_debt += 1
		sort_bills()
		bills_fx.sync(bills)
		return "多一张 ¥" + str(amount) + " 的账"
	return ""

## 一轮走完：够了就兑现，轮次用尽还不齐就逾期，否则发下一轮。
func collect_advance() -> void:
	collect_pick_t = 0.0
	if collected >= bill_amount:
		finish_challenge(true)
		return
	if collect_round >= collect_rounds:
		finish_challenge(false)
		return
	collect_round += 1
	collect_deal()

func update_collect(delta: float) -> void:
	if collect_pick_t > 0.0: # 结算停顿：卡抬起来、飘字飞出去，这半秒不接受新点击
		collect_pick_t -= delta
		if collect_pick_t <= 0.0:
			collect_advance()
		return
	bill_timer -= delta
	if bill_timer <= 0.0: # 房东在门外砸门：你犹豫的这几秒，路子全凉了
		bill_timer = 0.0
		popups.append({"position": Vector2(640, 500), "life": 1.4, "text": "犹豫太久 · 这一轮白过"})
		Sound.play("stamp", 0.7)
		collect_pick_t = 0.45

## 点击：落在哪张卡上就选哪张。卡外的点击什么都不做（凑钱关没有"挥空"这回事）。
func click_collect(point: Vector2) -> void:
	if collect_pick_t > 0.0:
		return
	var rects := collect_card_rects()
	for i in range(rects.size()):
		if rects[i].has_point(point):
			collect_pick(i)
			return

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


## 装不下的长行：从给定字号往下缩，直到塞进 max_w 为止（下限 10）
func text_fit_center(value: String, center_x: float, y: float, size: int, max_w: float, color := Color("#f4e0b8")) -> void:
	var s := size
	while s > 10 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	text_center(value, center_x, y, s, color)


## 更长的句子：贪心折成多行居中画（折不动再靠 text_fit 缩），返回行数
func text_wrap_center(value: String, center_x: float, y: float, size: int, max_w: float, color := Color("#f4e0b8")) -> int:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		text_center(value, center_x, y, size, color)
		return 1
	var lines: Array[String] = []
	var cur := ""
	for ch in value.split(""):
		var test := cur + ch
		if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			lines.append(cur)
			cur = ch.lstrip(" ")
		else:
			cur = test
	if cur != "":
		lines.append(cur)
	var lh := size + 9
	var y0 := y - float(lines.size() - 1) * lh * 0.5
	for i in range(lines.size()):
		text_center(lines[i], center_x, y0 + float(i) * lh, size, color)
	return lines.size()

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
	var font_size := 21
	var center := rect.get_center()
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	text_center(label, center.x, baseline, font_size, Color("#252c2b"))

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
# Airborne coins: solid rim, embossed face and highlights that change on rotation.
func draw_burst_coin(c: Vector2, spin: float, alpha: float) -> void:
	var facing := cos(spin)
	var width := maxf(absf(facing), 0.08)
	var radius := 12.0
	var tilt := sin(spin * 0.43) * 0.45
	var edge := Color("#805013", alpha)
	var rim := Color("#e5aa35", alpha)
	var shine := Color("#fff0ae", alpha)
	var face := Color("#d69a29").lerp(Color("#ffe18a"), 0.35 + 0.35 * sin(spin + 0.8))
	face.a = alpha
	# Draw the thickness before the face; it remains visible edge-on.
	draw_set_transform(c, tilt, Vector2.ONE)
	draw_line(Vector2(2, -radius + 2), Vector2(2, radius - 2), edge, radius * width * 2.0 + 3.0, true)
	draw_line(Vector2(3, -radius + 3), Vector2(3, radius - 3), rim, radius * width * 2.0 + 1.0, true)
	draw_set_transform(c - Vector2(1, 1).rotated(tilt), tilt, Vector2(width, 1.0))
	draw_circle(Vector2.ZERO, radius, rim)
	draw_circle(Vector2.ZERO, radius * 0.83, face)
	draw_arc(Vector2.ZERO, radius * 0.88, -2.9, -0.55, 12, shine, 1.3, true)
	draw_arc(Vector2.ZERO, radius * 0.69, 0.2, 2.5, 12, edge, 0.8, true)
	if width > 0.3:
		for i in range(12):
			var direction := Vector2.RIGHT.rotated(float(i) * TAU / 12.0)
			draw_line(direction * radius * 0.9, direction * radius * 0.98, edge, 0.8, true)
		# Raised geometric currency mark, with a shadow offset for relief.
		var mark := PackedVector2Array([Vector2(-3, -4), Vector2(0, 0), Vector2(3, -4)])
		draw_polyline(mark, edge, 2.0, true)
		draw_line(Vector2(0, 0), Vector2(0, 5), edge, 2.0, true)
		draw_line(Vector2(-3, 1), Vector2(3, 1), shine, 1.0, true)
		draw_line(Vector2(-3, 3), Vector2(3, 3), shine, 1.0, true)
		draw_polyline(mark, shine, 0.8, true)
	draw_set_transform(Vector2.ZERO)

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
		# HUD 里的小图标也走真纸：只留毛边和一点点旧，不放霉斑（太小会看成脏点）
		paper_sheet(Rect2(base + off, Vector2(46, 30)),
			Color.WHITE if last else Color(0.82, 0.80, 0.77), 17 + i, 1.0, false, Vector2.ZERO)
	# 这里原来在纸右边写着「待还 ¥xxx」，正好压住中部那行提示：HUD 这一条只有 98px 高，
	# 横向再塞一个数字就撞车。待还总额在账本封面和桌上那沓纸上有（「合计 ¥」），不缺这一处。


## 电费没缴 = 停电：屋顶灯泡接触不良般地闪，房间的暗度跟着灯泡走。
## 不再把整屏压得很黑（观感差）：基础暗度从 0.38 降到 0.22，且灯泡蹞亮的瞬间
## 房间也跟着亮一点 —— 明暗节奏本身就是"快去交电费"的提醒。
func draw_blackout() -> void:
	if blackout_fade <= 0.01:
		return
	var b := bulb_brightness()
	var alpha: float = bills_fx.number("blackout", "darkness_alpha", 0.22) * blackout_fade * (1.0 - 0.5 * b)
	draw_rect(Rect2(0, 0, 1280, 800), Color(0.02, 0.011, 0.005, alpha))

## 灯泡亮度：纯函数（传入时间），测试可以精确采样不同时刻的明暗档。
## 缴清 = 恒 1.0；欠费 = 每 0.36 秒一段，段内明暗由确定性伪随机决定，
## 多数时候很暗、偶尔蹞亮 —— 再叠一点高频抖动，像接触不良。
func bulb_brightness_at(t: float) -> float:
	if blackout_fade <= 0.01:
		return 1.0
	var seg := floorf(t / 0.36)
	var r := fposmod(sin(seg * 127.1) * 43758.5453, 1.0)
	var base := 0.16
	if r > 0.82:
		base = 0.85 # 接触不良的"突然来电"
	elif r > 0.55:
		base = 0.45
	var jitter := 0.06 * sin(t * 47.0) + 0.04 * sin(t * 91.3)
	return clampf(lerpf(1.0, base, blackout_fade) + jitter * blackout_fade, 0.05, 1.0)

func bulb_brightness() -> float:
	return bulb_brightness_at(elapsed)

## 屋顶吊灯：优先用精绘贴图（tools/gen_bulb.py 离线生成，玻璃径向渐变 +
## 高斯模糊灯丝辉光 + 黄铜螺纹灯座都在图里），亮度靠调制色压暗 ——
## 暗态是关灯的玻璃剪影，只剩一点火头。贴图缺失时回退矢量画法。
## 画在 _draw 最上层（暗化矩形之后）：它是光源，不该被自己造成的暗压住。
func draw_bulb() -> void:
	var b := clampf(bulb_brightness(), 0.0, 1.0)
	var tip := Vector2(640, 100) # 玻璃泡中心（与贴图内灯丝位置对齐）
	# 天花板吸顶盘 + 吊线
	draw_circle(Vector2(640, 7), 8.0, Color("#3a2c20"))
	draw_arc(Vector2(640, 7), 8.0, 0.0, TAU, 20, Color("#241b13"), 1.5)
	draw_line(Vector2(640, 13), Vector2(640, 58), Color("#2e2620"), 3.0)
	# 三层辉光（径向渐变贴图，无硬边）：桌面大光池、拉长光锥、贴身光晕
	if b > 0.03 and glow_tex != null:
		draw_texture_rect(glow_tex, Rect2(tip.x - 330, tip.y - 60, 660, 660), false,
			Color(1.0, 0.80, 0.48, 0.34 * b))
		draw_texture_rect(glow_tex, Rect2(tip.x - 185, tip.y - 50, 370, 500), false,
			Color(1.0, 0.84, 0.52, 0.30 * b))
		draw_texture_rect(glow_tex, Rect2(tip.x - 92, tip.y - 92, 184, 184), false,
			Color(1.0, 0.88, 0.58, 0.55 * b))
	if bulb_tex != null:
		var lamp_mod := Color(0.30, 0.24, 0.20).lerp(Color.WHITE, b)
		draw_texture_rect(bulb_tex, Rect2(606, 50, 68, 85), false, lamp_mod)
		if b < 0.5: # 熄灭时灯丝只剩一点暗红火头
			draw_circle(tip, 9.0, Color(1.0, 0.45, 0.15, 0.20 * (1.0 - b)))
			draw_circle(tip, 3.5, Color(1.0, 0.55, 0.2, 0.55 * (1.0 - b)))
	else:
		_draw_bulb_vector(tip, b)

## 矢量兜底画法（贴图加载失败时用）：梨形泡 + W 形灯丝 + 简易灯座。
func _draw_bulb_vector(tip: Vector2, b: float) -> void:
	var glass := Color(0.24, 0.21, 0.19).lerp(Color(1.0, 0.94, 0.60), b)
	var pts := PackedVector2Array([
		tip + Vector2(0, -17), tip + Vector2(7, -14), tip + Vector2(11, -8), tip + Vector2(13, 0),
		tip + Vector2(12, 8), tip + Vector2(8, 15), tip + Vector2(0, 18),
		tip + Vector2(-8, 15), tip + Vector2(-12, 8), tip + Vector2(-13, 0),
		tip + Vector2(-11, -8), tip + Vector2(-7, -14),
	])
	draw_colored_polygon(pts, glass)
	var wire_col := Color("#3a2c22")
	draw_line(tip + Vector2(-6, -14), tip + Vector2(-4, -2), wire_col, 1.5)
	draw_line(tip + Vector2(6, -14), tip + Vector2(4, -2), wire_col, 1.5)
	var fil_col := Color(0.55, 0.20, 0.10).lerp(Color(1.0, 0.96, 0.72), b)
	draw_polyline(PackedVector2Array([
		tip + Vector2(-4, -2), tip + Vector2(-2, 4), tip + Vector2(0, -3),
		tip + Vector2(2, 4), tip + Vector2(4, -2),
	]), fil_col, 1.5 + 1.5 * b)
	if b > 0.5:
		draw_circle(tip + Vector2(0, 8), 9.0, Color(1.0, 0.9, 0.55, 0.30 * b))
	draw_circle(tip + Vector2(-6, -7), 4.0, Color(1.0, 1.0, 0.92, 0.65 * (0.25 + 0.75 * b)))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color("#4a382a"), 1.5)
	panel(Rect2(631, 60, 18, 20), Color("#8a6a42"), 4)
	for i in range(3):
		draw_line(Vector2(633, 66 + i * 4), Vector2(647, 66 + i * 4), Color("#5e4526"), 1.5)
	draw_rect(Rect2(629, 78, 22, 3), Color("#5e4526"))

## 考核预告横幅：日历撞到账单到期后先亮出「谁到期了 + 倒计时」，
## 给玩家喘口气、看清要来的是什么 —— 别在某个小游戏一结束就被突然拽进考核。
func draw_challenge_warning() -> void:
	if pending_challenge.is_empty() or challenge_warn_t <= 0.0 or phase != "playing":
		return
	var bill_name := "账单"
	for bill in bills:
		if String(BillManagerScript.tag_of(bill)) == String(pending_challenge.get("tag", "")):
			bill_name = String(bill.get("name", "账单"))
			break
	var kind := String(pending_challenge.get("kind", "collect"))
	var label := bill_name + " 到期 · " + ("躲催债考核 " if kind == "dodge" else "凑钱考核 ") \
		+ str(int(ceilf(challenge_warn_t))) + "s"
	var pulse := 0.72 + 0.28 * sin(elapsed * 9.0) # 红边呼吸：不刺眼但不可能没看见
	# 挂在 HUD 条下方（y≈190）：压不到体力/催收预警板，也不与连击字打架（考核要来时它让位）
	panel(Rect2(640 - 210, 190, 420, 42), Color("#3a1410"), 12)
	draw_rect(Rect2(640 - 210, 190, 420, 42), Color(0.88, 0.24, 0.12, 0.5 * pulse), false, 2)
	text_center(label, 640, 217, 19, Color("#ff9a76"))

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


## 灯泡辉光贴图：中心白、越靠边越透明的径向渐变。
## 光晕最忌讳叠几层恒定透明度的圆 —— 暗背景上会显出一圈圈硬边色带，
## 改成一张渐变图按需染色拉伸，光池 / 光锥 / 贴身光晕三个层共用。
func _make_glow_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var dx := (float(x) + 0.5) / n * 2.0 - 1.0
			var dy := (float(y) + 0.5) / n * 2.0 - 1.0
			var d := clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 2.6)))
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
	var intro_pages: Array = story.get("pages", [])
	if story_page < intro_pages.size(): # 剧情对话页：讲完才见标题
		_draw_story_page(intro_pages[story_page])
		return
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 800), Vector2(0, 800)]),
		PackedColorArray([Color("#24160f"), Color("#38241888"), Color("#2d1b12cf"), Color("#24160f")]))
	draw_rect(Rect2(48, 46, 1184, 708), Color("#be874d"), false, 2.0)
	draw_line(Vector2(112, 266), Vector2(179, 266), Color("#e6b673"), 3.0, true)

	var title := String(story.get("title", "敲猪还债"))
	text_at(title, Vector2(115, 354), 82, Color("#1a100a"))
	text_at(title, Vector2(112, 350), 82, Color("#ffe2a1"))
	text_at(String(story.get("subtitle", "最后缴费期限：今天")), Vector2(116, 403), 26, Color("#dfb889"))
	button(INTRO_RECT, String(story.get("intro_button", "敲开第一只")))
	button(INTRO_SHOP_RECT, "传承商店")
	text_at("碎片 " + str(meta_shards), Vector2(360, 598), 16, Color("#ffe092"))
	text_at("任意键开始", Vector2(116, 560), 15, Color("#c9a789"))

	# A bill, a pig and a hammer tell the story without another block of text.
	draw_set_transform(Vector2(813, 434), -0.18)
	panel(Rect2(-106, -138, 212, 276), Color("#cbb08a"), 8)
	draw_rect(Rect2(-86, -118, 172, 236), Color("#947254"), false, 2.0)
	text_center("催缴通知", 0, -79, 23, Color("#8c4637"))
	for row in range(5):
		var y := -52.0 + row * 25.0
		draw_line(Vector2(-76, y), Vector2(75 - row * 9, y), Color("#a58a68"), 2.0, true)
	draw_set_transform(Vector2.ZERO)

	draw_set_transform(Vector2(940, 560), 0.0, Vector2(1.0, 0.23))
	draw_circle(Vector2.ZERO, 146.0, Color("#170e0a99"))
	draw_set_transform(Vector2.ZERO)
	var pig_cover: Texture2D = pig_tex.get("piggy")
	if pig_cover != null:
		draw_cover_texture(pig_cover, Vector2(921, 445), 308.0)
	if hammer_tex != null:
		draw_cover_texture(hammer_tex, Vector2(1050, 308), 286.0)
	draw_coin_face(Vector2(823, 588), 23.0, 0.8, true)
	draw_coin_face(Vector2(882, 609), 18.0, 0.55, false)
	draw_coin_face(Vector2(1039, 588), 21.0, 0.76, true)


func draw_cover_texture(texture: Texture2D, center: Vector2, longest_side: float) -> void:
	var texture_size := texture.get_size()
	var cover_size := texture_size * (longest_side / maxf(texture_size.x, texture_size.y))
	draw_texture_rect(texture, Rect2(center - cover_size * 0.5, cover_size), false)


## ── 开场小剧情 + 新手引导 ────────────────────────────────────────────
## 老师反馈「别人直接玩不知道怎么玩」：序幕升级成对话式剧情（打字机 + 翻页 + 跳过），
## 进游戏后再用一条不打断操作的引导把「瞄准 → 蓄力 → 砸碎 → 入账」演一遍。
## 剧情文案在 data/story.json 的 pages；引导文案在 tutorial。存档记 tutorial_done 只教第一次。

func _story_page_len(page: Dictionary) -> int:
	return String(page.get("text", "")).length()


func _start_tutorial() -> void:
	# 从标题页进入游戏时启动。存档记 tutorial_done：只带第一次，之后直接开打
	if tutorial_done or not bool(story.get("intro_enabled", true)):
		return
	var tut: Dictionary = story.get("tutorial", {})
	if tut.is_empty():
		return
	tutorial_step = 1


func _tutorial_target() -> Dictionary:
	# 教学目标：挑离桌面中心最近、还活着的猪。碎了/被带走了就自动换目标
	var best: Dictionary = {}
	var best_d := 1e12
	for pig in pigs:
		if int(pig.hp) <= 0 or float(pig.respawn) > 0.0:
			continue
		var d: float = pig.position.distance_to(Vector2(640, 430))
		if d < best_d:
			best_d = d
			best = pig
	return best


func _draw_story_page(page: Dictionary) -> void:
	# 剧情对话页：暗底 + 说话人名牌 + 打字机正文 + 页点 + 跳过按钮
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 800), Vector2(0, 800)]),
		PackedColorArray([Color("#24160f"), Color("#38241888"), Color("#2d1b12cf"), Color("#24160f")]))
	draw_rect(Rect2(48, 46, 1184, 708), Color("#be874d"), false, 2.0)
	var body := String(page.get("text", ""))
	var shown: String = body.substr(0, int(story_t * 24.0))
	panel(Rect2(140, 470, 1000, 220), Color("#2a1a10"), 18)
	draw_rect(Rect2(140, 470, 1000, 220), Color("#be874d"), false, 2.0)
	var who := String(page.get("who", ""))
	panel(Rect2(172, 444, 46.0 + who.length() * 21.0, 46), Color("#8c4637"), 10)
	text_at(who, Vector2(196, 472), 20, Color("#ffe2a1"))
	text_wrap_center(shown, 640, 585, 25, 880, Color("#f4e0b8"))
	var intro_pages: Array = story.get("pages", [])
	for i in range(intro_pages.size()):
		draw_circle(Vector2(618 + i * 28, 662), 5.0, Color("#ffe2a1") if i == story_page else Color("#6b4a2e"))
	if int(story_t * 24.0) >= body.length():
		var blink := 0.55 + 0.45 * sin(elapsed * 5.0)
		text_at("点击继续 ▸", Vector2(1000, 664), 17, Color(0.95, 0.86, 0.66, blink))
	button(STORY_SKIP_RECT, "跳过剧情")


func _draw_tutorial() -> void:
	# 游戏内新手引导：只在真正游玩、且没有模态界面压顶时出现
	if tutorial_step <= 0 or tutorial_step >= 4 or phase != "playing":
		return
	if bill_open or bill_detail >= 0 or help_open or build.panel_open or shop_open or day_events.is_open() or (shop != null and shop.is_open()):
		return
	var tut: Dictionary = story.get("tutorial", {})
	if tut.is_empty():
		return
	if tutorial_step <= 2:
		var tgt: Dictionary = _tutorial_target()
		if tgt.is_empty():
			return
		var pulse := 0.5 + 0.5 * sin(elapsed * 4.0)
		var r := pig_size() * 0.5 + 14.0 + 6.0 * pulse
		draw_arc(tgt.position, r, 0, TAU, 48, Color(1.0, 0.9, 0.4, 0.85), 4.0)
		draw_arc(tgt.position, r + 10.0, 0, TAU, 48, Color(1.0, 0.9, 0.4, 0.3 + 0.2 * pulse), 2.0)
		var label := String(tut.get("aim", "移动鼠标，瞄准这只猪")) if tutorial_step == 1 else String(tut.get("charge", "按住左键蓄力，松手砸碎它！"))
		_tutorial_banner(label)
		text_center(String(tut.get("skip_hint", "Esc 跳过教学")), 640, 766, 14, Color(1, 1, 1, 0.55))
	else:
		var alpha := clampf(1.0 - (tutorial_t - 2.2) / 1.0, 0.0, 1.0)
		_tutorial_banner(String(tut.get("done", "金币入账！继续敲，攒钱还债")) + "　+" + str(tutorial_gain) + " 金币", alpha)


func _tutorial_banner(label: String, alpha := 1.0) -> void:
	# 顶部教学横幅：半透明黑底金边，不挡操作
	var w := 620.0
	var rect := Rect2(640 - w * 0.5, 92, w, 56)
	panel(rect, Color(0.10, 0.06, 0.03, 0.82 * alpha), 14)
	draw_rect(rect, Color(0.91, 0.72, 0.4, 0.55 * alpha), false, 2.0)
	text_wrap_center(label, 640, rect.position.y + 28.0, 21, w - 70.0, Color(1, 0.94, 0.78, alpha))


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
		draw_intro()
		if shop_open:
			# 传承商店从序幕打开：必须盖在序幕上面画出来。否则输入走商店分支、
			# 画面停在序幕 —— 玩家点哪都没反应，像"进不了游戏"（十三轮踩坑）。
			draw_legacy_shop()
		return
	text_at(String(story.get("title", "敲猪还债")), Vector2(54, 71), 36)
	var stamina_max := float(settings.get("stamina_max", 100))
	var low := stamina <= stamina_max * 0.15
	var bar_color := Color("#e06c5c") if low or stamina_flash > 0.0 else Color("#8fd0a8")
	if stamina_flash > 0.0:
		bar_color = Color("#e06c5c").lerp(Color.WHITE, 0.5 * sin(stamina_flash * 40) + 0.5)

	if Sound.muted: # 静音得有个可见的出口，否则玩家会以为游戏坏了
		text_at("已静音 · M 恢复", Vector2(975, 103), 16, Color("#b59a7c"))
	if double_timer > 0.0:
		text_at("双倍中 ×2 剩 " + ("%.0f" % double_timer) + "s", Vector2(975, 103), 20, Color("#a4d007"))
	button(RESET_RECT, "重新开始")
	if not intro_open: # 商店按钮：结算面板（finished/bankrupt）上可见
		if phase == "finished" or phase == "bankrupt":
			button(LEGACY_SHOP_RECT, "传承商店")
	# —— 顶部横梁：一条酒馆木梁 + 四块统一小铜牌（余额 / 体力 / 房东挂牌 / 日历） ——
	draw_beam(Rect2(52, 137, 1176, 98))
	draw_money_plate(Rect2(68, 150, 128, 72))
	draw_stamina_plate(Rect2(210, 150, 222, 72), stamina_max, bar_color)
	draw_date_plate(Rect2(592, 150, 98, 72))
	draw_collect_board() # 挂钉木牌最后画：晃起来的时候压在梁上才对
	# 猪的价目表移到底部整行：中部这块只有 220px 宽，四种猪的名字加金额会被账单纸压住
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
			# 独立绘制厚度和币面，侧身时保留金属边缘。
			draw_burst_coin(pp, float(p.get("spin", 0.0)), alpha)
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
	# 凑钱关的飘字（+¥18 / 多一张账）要盖在卡面之上，所以那一关留到最后由 draw_collect 自己画。
	if not (phase == "challenge" and card_type == "collect"):
		draw_popups()
	build.draw_effects(self) # 卡片2.0：连锁/爆破的闪电连线
	panel(Rect2(0, 664, 1280, 136), Color(0.06, 0.09, 0.09, 0.24), 0) # 3D 桌面是暖色，底部说明要压一条暗底才看得清
	if phase == "playing":
		draw_gamble_hint() # 赌徒心理的实时诱导，放在底部信息栏第一行
	var active_names := active_synergy_names()
	if active_names != "暂无":
		text_center(active_names, 640, 714, 15, Color("#ffb86b"))
	button(HELP_BUTTON, "帮助 [H]")
	if cursor_hidden:
		draw_hammer() # 锤子是光标：只在它真的顶掉了系统箭头时才画（躲催债那关也要看得见自己）
	if charging and phase == "playing":
		# 蓄满提示只留两个字：满蓄时准心旁浮出「重锤」。不做圈、不做力量条。
		# 画在锤子之后：锤子就是光标本体，画在它前面必然被锤头压住。
		var charge_ratio := clampf(charge_t / CHARGE_MAX, 0.0, 1.0)
		if charge_ratio >= CHARGE_DAMAGE_AT:
			text_at("重锤", get_global_mouse_position() + Vector2(52, 6), 14, Color("#ffd76a"))
	draw_bills()
	if phase == "playing":
		draw_gamble_coin() # 硬币画在锤子之后：鼠标移过去时锤子不能把硬币盖住
	elif phase == "challenge":
		if card_type == "collect":
			draw_collect()
		else:
			escape.draw(self) # 逃跑场面：横版 2D 自绘，不走 3D 舞台（十五轮）
	else:
		draw_rect(Rect2(0, 0, 1280, 800), Color(0.04, 0.07, 0.07, 0.78))
		if phase == "card":
			draw_card()
		elif phase == "finished":
			draw_finished()
		else:
			draw_bankrupt()
	draw_pig_tip() # 新猪的说明书：画在猪之上、卡片之下（打开卡片时别挡着）
	# 停电暗化先压：账单是模态界面，不能被房间的明暗闪到、也不该叠一层灰
	draw_blackout()
	if bill_open:
		draw_ledger()
	if bill_detail >= 0:
		draw_bill_detail()
	draw_collection_flash() # 催收警告：只在屏幕边缘画一圈，不挡任何操作
	draw_gamble_flip() # 抛硬币的翻面/落定动画，永远盖在最上层
	if not (bill_open or bill_detail >= 0): # 翻账单时吊灯和预告横幅都让位：账单是模态的
		draw_challenge_warning() # 考核预告横幅：压在暗化之上，断电时也看得见“考核要来了”
		draw_bulb() # 灯泡永远画在暗化之上：它是光源，不该被自己造成的暗压住
	_draw_tutorial() # 新手引导画在灯泡之后：教学横幅不能被吊灯灯泡盖住字
	if help_open:
		draw_rect(Rect2(0, 0, 1280, 800), Color(0, 0, 0, 0.75))
		panel(Rect2(190, 190, 900, 420), Color("#37251a"), 16)
		text_center("玩法与操作", 640, 250, 28)
		text_center("鼠标瞄准 · 左键敲猪 · 右侧直接还款", 640, 305, 21)
		text_center("B 全部账单    M 静音    R 重开    1 / 2 / 3 选卡", 640, 348, 18)
		text_center("攒到 ¥" + str(int(settings.round_target)) + " 获胜 · 挥空更耗体力", 640, 390, 19)
		var legend_lines := wrap_text_lines(pig_legend(), 42)
		for i in range(mini(3, legend_lines.size())):
			text_center(legend_lines[i], 640, 435 + i * 25, 16, Color("#c9b08a"))
		text_center("敲碎 " + str(broken) + " 只 · 成长碎片 " + str(meta_shards), 640, 531, 17)
		text_center("游戏已暂停 · 点击任意位置或按 H / Esc 返回", 640, 575, 16, Color("#efbc72"))
	build.draw_status(self) # 卡片2.0：C 面板提示与构筑清单，盖在最上层
	day_events.draw(self) # 天数小游戏弹窗（当铺/赌桌/电话）：盖在一切之上，输入已被转发
	if shop_open:
		draw_legacy_shop() # 传承商店：最顶层。商店只在序幕/结算画面打开，不会和小游戏弹窗同时存在

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
	if pig.flash > 0.0:
		var compression := sin(clampf(float(pig.flash) / 0.14, 0.0, 1.0) * PI)
		squash *= Vector2(1.0 + 0.22 * compression, 1.0 - 0.25 * compression)
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
	var sh: Vector2 = Vector2(shake_x, shake_y) if shake > 0.0 else Vector2.ZERO
	if sh.is_zero_approx():
		if pig.hp > 0:
			draw_pig(pig, index)
		else:
			draw_set_transform(pig.position)
			draw_arc(Vector2.ZERO, 36, 0, TAU, 32, Color("#765d45"), 2)
			draw_set_transform(Vector2.ZERO)
		return
	if pig.hp > 0:
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
	if HELP_BUTTON.has_point(p) or help_open:
		return true
	if RESET_RECT.has_point(p):
		return true
	if phase == "playing" and gamble_state == "ready" and gamble_t >= GAMBLE_ROLL_TIME:
		if COIN_THROW.has_point(p) or COIN_SKIP.has_point(p):
			return true
	if (phase == "card" or phase == "finished" or phase == "bankrupt") and CONTINUE_RECT.has_point(p):
		return true
	return bill_open or bill_detail >= 0 # 翻账本时手本来就该放下


func _draw_aim_reticle() -> void:
	# 准心画在锤子左下的击打面处（= 真正的命中判定点），且画在锤子之上才看得见
	if phase != "playing" or ui_hover_at(hammer_position):
		return
	var aim := hammer_position + AIM_OFFSET
	var aim_color := Color("#ffe092") if not strike_target(aim).is_empty() else Color(1, 1, 1, 0.65)
	draw_arc(aim, 7.0, 0.0, TAU, 24, aim_color, 1.5, true)
	draw_circle(aim, 2.0, aim_color)


func draw_hammer() -> void:
	var over := ui_hover_at(get_local_mouse_position())
	var swing_progress := clampf(1.0 - swing / 0.16, 0.0, 1.0)
	var punch := 0.0
	if swing > 0.0:
		# Instant impact, then an eased rebound; keep the click responsive.
		punch = pow(1.0 - swing_progress, 2.0)
	var angle := 0.28 * punch - sin(swing_progress * PI) * 0.42 # 静止斜角由 3D 模型本身负责，挥锤只叠加动画角度
	var k: float = 0.68 if over else 1.0 # 悬停按钮：缩小并往右下让开，别挡住按钮本身
	var pivot := hammer_position + Vector2(13, -5) + Vector2(-8, 24) * punch
	if impact_timer > 0.0:
		var progress := 1.0 - impact_timer / 0.18
		var radius := lerpf(9.0, 48.0 if impact_broken else 30.0, progress)
		var color := Color(1.0, 0.85, 0.48, (1.0 - progress) * 0.85)
		draw_arc(impact_position, radius, 0.0, TAU, 32, color, 3.0 * (1.0 - progress) + 1.0, true)
		for i in range(6):
			var direction := Vector2.RIGHT.rotated(float(i) * TAU / 6.0 + 0.2)
			draw_line(impact_position + direction * radius * 0.6, impact_position + direction * (radius + 9.0), color, 2.0, true)
	if over:
		pivot += Vector2(58, 46)
	if SHOW_HAND:
		# 握点取柄的下段（不是末端）：柄尾要露在拳头外面，"握着"才看得懂
		draw_shadow_arm(pivot + Vector2(19, 74).rotated(angle))
	if hammer_tex != null: # 贴图锤：皮手套握木柄锤，跟随鼠标，挥锤下压+旋转沿用 swing 动画
		var hs := hammer_tex.get_size()
		var hfit := 250.0 / maxf(hs.x, hs.y) # 最长边约 250：比原 3D 锤略大，握锤的手也进了画面
		# 贴图里锤头在左上（约 90,78）、手套在右下——命中点必须对准锤头，不是贴图中心。
		# 旋转支点放在手套握柄处：挥锤是绕着手腕转，锤头扫出弧线，而不是钉在原地打转。
		var head_px := Vector2(90, 78)
		var grip_px := Vector2(195, 235)
		var sc := k * hfit
		var tp := hammer_position + (grip_px - head_px) * sc + Vector2(-8, 24) * punch
		if over:
			tp += Vector2(58, 46)
		draw_set_transform(tp, angle, Vector2(sc, sc))
		draw_texture(hammer_tex, -grip_px)
		draw_set_transform(Vector2.ZERO)
		_draw_aim_reticle()
		return
	if hammer3d != null:
		draw_set_transform(pivot, angle, Vector2(k, k))
		draw_texture_rect(hammer3d.get_texture(), Rect2(-104, -104, 208, 208), false)
		draw_set_transform(Vector2.ZERO)
		if SHOW_HAND:
			draw_shadow_fist(pivot + Vector2(19, 74).rotated(angle), angle)
		_draw_aim_reticle()
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
	_draw_aim_reticle()


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
		text_center(str(int(settings.get("collect_rounds", 4))) + " 轮 · 每轮 "
			+ str(int(collect_round_seconds())) + " 秒", 640, 464, 18, Color("#c7d5e0"))
		text_center("摆钱凑整 · 点一张路子", 640, 486, 18, Color("#c9b08a"))
		text_center("代价会跟着钱一起记上", 640, 508, 16, Color("#e7a6a4"))
	else: # dodge
		card_badge(accent, "¥" + str(bill_amount), 32)
		text_center("限时 " + str(int(bill_time)) + " 秒", 640, 464, 18, Color("#c7d5e0"))
		text_center("夺门而逃 · 鼠标上下躲", 640, 486, 18, Color("#c9b08a"))
		text_center("被抓满 3 次就失败", 640, 508, 16, Color("#e7a6a4"))
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
		var description := TextParagraph.new()
		description.width = rect.size.x - 36.0
		description.alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		description.max_lines_visible = 3
		description.add_string(String(card.desc), font, 17)
		var description_top := rect.position.y + 231.0 - description.get_size().y * 0.5
		description.draw(get_canvas_item(), Vector2(rect.position.x + 18.0, description_top), Color("#e2e9e4"))
		text_center("选择 " + str(i + 1), rect.get_center().x, rect.end.y - 22, 16, accent.lightened(0.3))

## —— 顶部 HUD：一条酒馆木梁，上面钉四块统一小铜牌 ——
## 统一的容器感是 HUD 不显廉价的关键：同一底色、同一铜边、同一两级字号。

func draw_beam(rect: Rect2) -> void:
	panel(rect, Color("#2e1d12"), 12)
	# 上下沿各压一条受光/背光，木梁才有圆边体积
	panel(Rect2(rect.position.x + 8, rect.position.y + 3, rect.size.x - 16, 6), Color("#3d2a18"), 3)
	panel(Rect2(rect.position.x + 8, rect.end.y - 9, rect.size.x - 16, 6), Color("#1e1209"), 3)
	draw_rect(rect.grow(-2), Color("#4a3018"), false, 2.0)


func draw_hud_plate(rect: Rect2) -> void:
	panel(rect, Color("#1f130b"), 10)
	draw_rect(rect.grow(-2.5), Color("#8a6a42"), false, 1.6)
	draw_line(rect.position + Vector2(8, 5), rect.position + Vector2(rect.size.x - 8, 5),
		Color(0.85, 0.70, 0.45, 0.22), 1.5) # 左上一线受光


func draw_money_plate(rect: Rect2) -> void:
	draw_hud_plate(rect)
	var coin := rect.position + Vector2(27, 36)
	draw_circle(coin, 15.0, Color("#a8742a"))
	draw_circle(coin, 11.0, Color("#efbc72"))
	text_center("¥", coin.x, coin.y + 5.0, 12, Color("#7a4d16"))
	text_at("余额", rect.position + Vector2(50, 28), 13, Color("#c9b08a"))
	text_at("¥" + str(score), rect.position + Vector2(50, 58), 24, Color("#ffe092"))


func draw_stamina_plate(rect: Rect2, stamina_max: float, bar_color: Color) -> void:
	draw_hud_plate(rect)
	# 闪电图标
	var b := rect.position + Vector2(14, 14)
	draw_colored_polygon(PackedVector2Array([
		b + Vector2(10, 0), b + Vector2(2, 14), b + Vector2(8, 14),
		b + Vector2(4, 26), b + Vector2(16, 11), b + Vector2(9, 11), b + Vector2(15, 0)
	]), bar_color)
	text_at("体力", rect.position + Vector2(40, 30), 13, Color("#c9b08a"))
	var num := str(int(stamina)) + " / " + str(int(stamina_max))
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	text_at(num, Vector2(rect.end.x - 12.0 - nw, rect.position.y + 30), 13, Color("#e8f5e0"))
	var bar := Rect2(rect.position.x + 14, rect.position.y + 38, rect.size.x - 28, 15)
	panel(bar, Color("#120c07"), 7)
	draw_rect(bar.grow(-1), Color("#5a4126"), false, 1.2)
	var fill_w := bar.size.x * clampf(stamina / stamina_max, 0.0, 1.0)
	panel(Rect2(bar.position, Vector2(fill_w, bar.size.y)), bar_color, 6)
	# 低体力警戒刻度（15%）：条内嵌一道亮线，掉到线左就发红
	var tick_x := bar.position.x + bar.size.x * 0.15
	draw_line(Vector2(tick_x, bar.position.y - 1.0), Vector2(tick_x, bar.end.y + 1.0),
		Color("#ffe092"), 1.5)


func draw_date_plate(rect: Rect2) -> void:
	draw_hud_plate(rect)
	var head := Rect2(rect.position.x + 11, rect.position.y + 8, rect.size.x - 22, 17)
	panel(head, Color("#8a3030"), 5)
	text_center("第 " + str(game_day) + " 天", head.get_center().x, head.end.y - 4.0, 11, Color("#ffe0d0"))
	text_center(format_game_date(game_day), rect.get_center().x, rect.end.y - 11.0, 19, Color("#ffe092"))


## 催收预警牌：一块用麻绳挂在梁上的小木牌。只报信、不可点 —— 躲债只由条件触发，
## 这块牌子告诉玩家"房东还有多远来堵门"。房租还清就剩一块灰牌晃着。
## 上门那一瞬间（collection_flash>0）牌子绕挂钉来回晃，晃幅随脉冲衰减。
func draw_collect_board() -> void:
	if phase != "playing":
		return
	var rent_tag := _collection_bill_tag()
	var rent_due := not rent_tag.is_empty()
	var cap := int(bills_fx.number("collection", "max_triggers_per_run", 3))
	var left := maxi(0, cap - bills_fx.collection_count)
	var gap := maxi(0, int(ceilf(bills_fx.collection_next - earned_total))) if rent_due else 0
	var threshold := maxf(1.0, bills_fx.number("collection", "progress_threshold", 100.0))
	var imminent := rent_due and left > 0 and float(gap) <= threshold * 0.3
	var rect := COLLECT_BOARD_RECT
	var pivot := Vector2(rect.get_center().x, rect.position.y - 15.0) # 挂钉位置
	var swing := 0.0
	if collection_flash > 0.0:
		swing = sin(elapsed * 11.0) * 0.16 * clampf(collection_flash / 1.2, 0.0, 1.0)
	# 绕挂钉旋转：Translate(pivot)·Rotate·Translate(-pivot)。
	# draw_set_transform(pivot, swing) 只是平移不是旋转 —— 牌子会被平移出梁（踩过）。
	draw_set_transform_matrix(Transform2D(swing, pivot) * Transform2D(0.0, -pivot))
	var top_y := rect.position.y - 6.0
	var cx := rect.get_center().x
	draw_line(Vector2(pivot.x - 1.5, pivot.y), Vector2(cx - 20.0, top_y), Color("#6a5a44"), 2.0)
	draw_line(Vector2(pivot.x + 1.5, pivot.y), Vector2(cx + 20.0, top_y), Color("#6a5a44"), 2.0)
	draw_circle(pivot, 3.4, Color("#9a7a50"))
	draw_circle(pivot, 1.6, Color("#5a4126"))
	var body := Rect2(rect.position.x, top_y, rect.size.x, rect.size.y + 6.0)
	panel(body, Color("#3d2c1c") if rent_due else Color("#2c221a"), 9)
	draw_rect(body.grow(-3), Color("#8a6a42") if rent_due else Color("#4a3a2a"), false, 1.8)
	if imminent:
		draw_rect(body.grow(-3), Color(0.88, 0.30, 0.18, 0.55 + 0.45 * sin(elapsed * 6.0)), false, 2.4)
	text_center("房东催收" if rent_due else "租约已清", cx, body.position.y + 20, 15,
		Color("#efbc72") if rent_due else Color("#6a5a44"))
	# 状态胶囊
	var pill_w := 92.0
	var pill := Rect2(cx - pill_w * 0.5, body.position.y + 28, pill_w, 19)
	if rent_due and left > 0:
		panel(pill, Color("#57200f") if imminent else Color("#4a2c16"), 9)
		text_center("还差 ¥" + str(gap), cx, pill.end.y - 4.0, 12,
			Color("#ffb08a") if imminent else Color("#e7c98a"))
	elif rent_due:
		panel(pill, Color("#33251a"), 9)
		text_center("本局不再上门", cx, pill.end.y - 4.0, 12, Color("#b59a7c"))
	else:
		panel(pill, Color("#22301e"), 9)
		text_center("风平浪静", cx, pill.end.y - 4.0, 12, Color("#8fb89a"))
	text_center("本局还能来 " + str(left) + " 次" if rent_due and left > 0 else "房租还清就不来",
		cx, body.end.y - 6.0, 11, Color("#8a6a52"))
	draw_set_transform(Vector2.ZERO)


## 考核浮层的上半屏 HUD。两种玩法只差标题/说明，排版完全一致 ——
## 玩家第二次遇到账单时不用重新认一遍界面。lives = 0 时不画心（凑钱那关没有命）。
func draw_challenge_header(title: String, info: String, hint: String, lives: int) -> void:
	panel(CHALLENGE_PANEL, Color("#1b2838"), 22)
	var head := "账单到期 · " + title
	if challenge_label != "":
		head += "　" + challenge_label
	text_at(head, Vector2(78, 168), 30, Color("#efbc72"))
	text_at(info, Vector2(78, 210), 23, Color("#e2d3b4"))
	text_at(hint, Vector2(78, 242), 18, Color("#9fb2c4"))
	text_at("剩余 " + ("%.1f" % maxf(0.0, bill_timer)) + " 秒", Vector2(940, 210), 23, Color("#c9b08a"))
	for i in range(lives):
		draw_heart(Vector2(1180 - i * 26, 232))
	panel(Rect2(78, 266, 1124, 14), Color("#141a22"), 7)
	panel(Rect2(78, 266, 1124 * clampf(bill_timer / bill_time, 0.0, 1.0), 14), Color("#efbc72"), 7)


## 把 3D 舞台贴到 CHALLENGE_STAGE，再压一圈圆角内框：3D 视口是方的，
## 靠这圈和面板同色的粗边把直角藏进圆角里，看起来才像"一扇窗"而不是贴了张图。
## 返回 false = 这台机器上没有 3D 舞台（headless / challenge_3d:false），调用方走 2D 回退。
func draw_challenge_stage() -> bool:
	if challenge3d == null:
		panel(CHALLENGE_STAGE, Color("#131a24"), 16)
		return false
	draw_texture_rect(challenge3d.get_texture(), CHALLENGE_STAGE, false)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_corner_radius_all(18)
	frame.set_border_width_all(10)
	frame.border_color = Color("#1b2838")
	draw_style_box(frame, CHALLENGE_STAGE)
	return true


## 摆钱凑整的版式：上面是账目（已凑/应付 + 轮次 + 本轮倒计时），
## 中间是柜台（3D 舞台当背景板，压一层暗），上面横排三张路子卡，下面是一沓越攒越厚的钱。
func draw_collect() -> void:
	draw_collect_header()
	if draw_challenge_stage():
		panel(CHALLENGE_STAGE, Color(0.03, 0.05, 0.06, 0.58), 16) # 柜台还在，但视线要落在卡上
	draw_collect_pile()
	var rects := collect_card_rects()
	for i in range(rects.size()):
		draw_collect_card(rects[i], collect_cards[i], i)
	draw_popups() # 钱和代价的飘字必须压在这层卡面之上（HUD 那一层的飘字已被跳过）


func draw_popups() -> void:
	for p in popups:
		text_at(String(p.text), Vector2(p.position), int(p.get("size", 28)), p.get("color", Color("#ffe092")))


func draw_collect_header() -> void:
	panel(CHALLENGE_PANEL, Color("#1b2838"), 22)
	var head := "账单到期 · 摆钱凑整"
	if challenge_label != "":
		head += "　" + challenge_label
	text_at(head, Vector2(78, 168), 30, Color("#efbc72"))
	text_at("已凑 ¥" + str(collected) + " / 应付 ¥" + str(bill_amount), Vector2(78, 216), 24, Color("#e2d3b4"))
	if collected >= bill_amount:
		text_at("凑够了 —— 这就去交", Vector2(78, 250), 18, Color("#8fd05a"))
	else:
		text_at("点一张路子：钱进袋，代价也一起记上", Vector2(78, 250), 18, Color("#9fb2c4"))
	text_at("第 " + str(collect_round) + " / " + str(collect_rounds) + " 轮", Vector2(870, 216), 22, Color("#c9b08a"))
	var secs := maxf(0.0, bill_timer)
	# 倒计时压在右上角空位：再往上会和转盘/构筑按钮挤在一起
	text_at("本轮 %.1f 秒" % secs, Vector2(1046, 252), 20,
		Color("#ff9a76") if secs <= 3.0 else Color("#c9b08a"))
	# 凑钱进度：满格就是过关
	panel(Rect2(78, 272, 1124, 14), Color("#141a22"), 7)
	var frac := clampf(float(collected) / maxf(1.0, float(bill_amount)), 0.0, 1.0)
	if frac > 0.0:
		panel(Rect2(78, 272, 1124 * frac, 14), Color("#8fd05a") if collected >= bill_amount else Color("#efbc72"), 7)
	# 本轮倒计时：细细一条红线，快没了自己会缩
	var tfrac := clampf(bill_timer / collect_round_seconds(), 0.0, 1.0)
	panel(Rect2(78, 290, 1124, 4), Color("#141a22"), 2)
	if tfrac > 0.0:
		panel(Rect2(78, 290, 1124 * tfrac, 4), Color(0.90, 0.32, 0.20, 0.9), 2)


## 一张路子：一张摊在柜台上的纸。钱写在最上面（大），代价紧跟其下（红胶囊），
## 底下那句说明是"这条路子长什么样"，让人替这个角色心疼一下。
func draw_collect_card(rect: Rect2, card: Dictionary, index: int) -> void:
	var mouse := get_global_mouse_position()
	var picked := index == collect_picked
	var can_pick := collect_picked < 0 and collect_pick_t <= 0.0
	var hover := can_pick and rect.has_point(mouse)
	var accent := Color("#8fd05a")
	if index == 1:
		accent = Color("#efbc72")
	elif index >= 2:
		accent = Color("#e8836b")
	var lift := -12.0 if picked else (-7.0 if hover else 0.0)
	var r := Rect2(rect.position + Vector2(0, lift), rect.size)
	panel(Rect2(r.position + Vector2(5, 9), r.size), Color(0.02, 0.04, 0.05, 0.5), 8) # 纸落在柜台上的影子
	panel(r, Color("#f4ecd8"), 8)
	panel(Rect2(r.position.x, r.position.y, r.size.x, 7), accent.darkened(0.12), 4) # 顶边颜色 = 危险度
	text_center(String(card.get("title", "路子")), r.get_center().x, r.position.y + 40, 24, Color("#3b2c1e"))
	text_center("+¥" + str(collect_gain(card)), r.get_center().x, r.position.y + 104, 46, Color("#a8421c"))
	var cost_text := collect_cost_text(card)
	if cost_text != "":
		var cw := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		panel(Rect2(r.get_center().x - cw / 2.0 - 14, r.position.y + 124, cw + 28, 30), Color("#f6dbd4"), 15)
		text_center(cost_text, r.get_center().x, r.position.y + 145, 16, Color("#a8402c"))
	else:
		text_center("不欠人情", r.get_center().x, r.position.y + 145, 16, Color("#6f7f5f"))
	var desc := TextParagraph.new()
	desc.width = r.size.x - 44.0
	desc.alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	desc.add_string(String(card.get("desc", "")), font, 15)
	desc.draw(get_canvas_item(), Vector2(r.position.x + 22, r.position.y + 172), Color("#6b5a46"))
	if picked:
		draw_rect(r, Color("#ffd166"), false, 3.0)
	elif hover:
		draw_rect(r, accent.lightened(0.2), false, 3.0)
		text_center("选定", r.get_center().x, r.end.y - 10, 15, Color("#a8421c"))


## 卡面代价文案：同一套语义（力气 / 新账），卡面、飘字、结算小结都从这里出，不会说两套话。
func collect_cost_text(card: Dictionary) -> String:
	var kind := String(card.get("cost", "none"))
	if kind == "stamina":
		return "力气 -" + str(int(card.get("cost_value", 0.0)))
	if kind == "bill":
		var amount := maxi(5, int(round(float(bill_amount) * float(card.get("cost_ratio", 0.4)))))
		return "多一张 ¥" + str(amount) + " 的账"
	return ""


## 桌上那沓钱：张数跟着进度走 —— 不用看数字也知道还差多少。
func draw_collect_pile() -> void:
	var frac := clampf(float(collected) / maxf(1.0, float(bill_amount)), 0.0, 1.0)
	var base := Vector2(640, 660)
	var sheets := 2 + int(frac * 9.0)
	for i in range(sheets):
		draw_set_transform(base + Vector2(0, -5.0 * float(i)), sin(float(i) * 2.1) * 0.05, Vector2.ONE)
		var paper := Color("#e6ecd8").darkened(0.05 * float(i % 3))
		panel(Rect2(-50, -12, 100, 22), paper, 3)
		draw_line(Vector2(-42, -1), Vector2(42, -1), Color("#aab598"), 1.5)
		draw_set_transform(Vector2.ZERO)
	# 最上面压几枚硬币：钱堆得越高，硬币越多
	var coins_on_top := int(frac * 6.0)
	for i in range(coins_on_top):
		var p := base + Vector2(-58.0 + float(i) * 23.0, -6.0 - 5.0 * float(sheets) + sin(float(i)) * 3.0)
		draw_circle(p, 9.0, Color("#a8742a"))
		draw_circle(p, 7.0, Color("#efbc72"))
	text_center("凑到 ¥" + str(collected), 640, base.y + 22, 15, Color("#c9b08a"))

func draw_heart(pos: Vector2) -> void:
	draw_circle(pos + Vector2(-4, -2), 5, Color("#e7a6a4"))
	draw_circle(pos + Vector2(4, -2), 5, Color("#e7a6a4"))
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(8, 0), pos + Vector2(0, 10)]), Color("#e7a6a4"))

func draw_finished() -> void:
	panel(Rect2(355, 268, 570, 380), Color("#2a475e"), 25)
	if end_reason == "exhausted":
		text_center("体力耗尽！", 640, 345, 36, Color("#efbc72"))
		text_wrap_center(story_line("exhausted_line", "手停下来了。账单还在桌上。"), 640, 400, 22, 520)
	elif end_reason == "coin": # 靠抛硬币翻上去的：赢了，但是赢在运气上
		text_center("正面。", 640, 345, 36, Color("#ffe092"))
		text_wrap_center(story_line("win_coin_line", "一把就到手了 —— 你不会觉得这是运气，你会觉得自己有手感。"), 640, 400, 22, 520)
	else:
		text_center(story_line("win_title", "暂时安全"), 640, 345, 36, Color("#a4d007"))
		text_wrap_center(story_line("win_line", "目标达成，你甩开了催债电话 —— 但桌上那叠账单，一张都没少。"), 640, 400, 22, 520)
	text_center("余额 ¥" + str(score) + "    敲碎 " + str(broken) + " 只", 640, 452, 26, Color("#efbc72"))
	text_fit_center("已还 " + str(paid_count) + " 张 · 还剩 " + str(bills.size()) + " 张（¥" + str(bills_total()) + "）", 640, 492, 20, 520, Color("#c9b08a"))
	text_fit_center(highlight_line(), 640, 524, 17, 520, Color("#ffe092"))
	text_fit_center("永久成长：" + meta_unlock_summary() + "　·　碎片 " + str(meta_shards), 640, 550, 15, 520, Color("#efbc72"))
	button(LEGACY_SHOP_RECT, "传承商店")
	button(CONTINUE_RECT, "再来一轮")


## —— 结算高光：本局之最，让每一局都有值得记住的瞬间 ——
func highlight_line() -> String:
	return "本局高光：最高连击 ×" + str(combo_max) + " · 最大单笔 +¥" + str(best_gain) + " · 赌桌 " + str(gamble_wins) + "胜" + str(gamble_losses) + "负"


## —— 传承商店面板：碎片在这里换成永久饰品，下一局 reset_game 时生效 ——
func _legacy_buy_rect(i: int) -> Rect2:
	return Rect2(848, 200 + i * 78 + 12, 150, 42)


func draw_legacy_shop() -> void:
	panel(LEGACY_PANEL, Color("#24160f"), 22)
	draw_rect(LEGACY_PANEL.grow(-4), Color("#be874d"), false, 2.0)
	text_center("传承商店 · 碎片 " + str(meta_shards), 640, 128, 30, Color("#ffe092"))
	text_center("破产不是终点 —— 每一轮攒下的碎片，在这里换成下一轮的本钱", 640, 164, 15, Color("#c9a789"))
	for i in range(LEGACY_ITEMS.size()):
		var item: Dictionary = LEGACY_ITEMS[i]
		var y := 200 + i * 78
		panel(Rect2(264, y, 752, 66), Color("#2d1c12"), 10)
		var lv := legacy_level(String(item.id))
		text_at(String(item.name), Vector2(292, y + 14), 20, Color("#ffe092"))
		text_at(String("●").repeat(lv) + String("○").repeat(int(item.max) - lv), Vector2(392, y + 17), 15, Color("#e7a655"))
		text_at(String(item.desc), Vector2(292, y + 40), 15, Color("#b59a7c"))
		var cost := legacy_next_cost(String(item.id))
		if cost < 0:
			button(_legacy_buy_rect(i), "已满级", false)
		else:
			button(_legacy_buy_rect(i), "买入 ¥" + str(cost), meta_shards >= cost)
	button(LEGACY_CLOSE_RECT, "关闭")
	text_center("按 B 或 Esc 关闭", 640, 652, 13, Color("#8a6a4a"))


func legacy_shop_click(p: Vector2) -> void:
	for i in range(LEGACY_ITEMS.size()):
		if _legacy_buy_rect(i).has_point(p):
			legacy_buy(String(LEGACY_ITEMS[i].id))
			queue_redraw()
			return
	if LEGACY_CLOSE_RECT.has_point(p):
		shop_open = false
		sync_cursor()
	queue_redraw()


func draw_bankrupt() -> void:
	panel(Rect2(355, 268, 570, 380), Color("#3a2424"), 25)
	text_center(story_line("lose_title", "破产了"), 640, 345, 36, Color("#e7a6a4"))
	text_wrap_center(story_line("lose_line", "敲碎 {broken} 只存钱罐，账单反而又多了几张。"), 640, 400, 22, 520)
	text_center("余额 ¥" + str(score) + "    敲碎 " + str(broken) + " 只", 640, 452, 26, Color("#efbc72"))
	text_fit_center("已还 " + str(paid_count) + " 张 · 还剩 " + str(bills.size()) + " 张（¥" + str(bills_total()) + "）", 640, 492, 20, 520, Color("#c9b08a"))
	text_fit_center(highlight_line(), 640, 524, 17, 520, Color("#ffe092"))
	text_fit_center("永久成长：" + meta_unlock_summary() + "　·　碎片 " + str(meta_shards), 640, 550, 15, 520, Color("#efbc72"))
	button(LEGACY_SHOP_RECT, "传承商店")
	button(CONTINUE_RECT, "再来一轮")
