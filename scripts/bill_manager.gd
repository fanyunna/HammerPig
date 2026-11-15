extends RefCounted

## 账单效果系统（P1）：把"账单"从单纯扣钱的 UI，变成会影响玩法的压力源。
##
## ⚠️ 这里故意不写 class_name：Godot 的全局类要等编辑器/扫描刷新才认，
## 而本工程的冒烟测试是 headless 直跑脚本，缓存没刷新就会报
## "Could not find type BillManager"。main.gd 用 preload 引，永远稳。
##
## 这个脚本只回答三个问题：某个效果现在生不生效、是谁让它生效的、该触发什么事件。
## 怎么画、怎么扣钱，全部留在 main.gd。
##
## ⚠️ 关键约束：main.gd 的 pay_bill() 是"付完就把账单 remove 掉"，所以效果来源
## 必须按"剩余账单里还有谁带这个 effect_id"来算，不能缓存一次就不管了。
## sync() 在每次账单变动后重建来源表，于是"付掉一张电费不会解除另一张电费的效果"、
## "还掉信用卡后它之前产生的利息一并作废"都是天然成立的，不需要额外分支。
##
## ⚠️ 数据兼容：catalog 项不带 effect_id 就是普通账单（旧 JSON 照样能读）；
## effects 段整个缺失也能跑，用下面的 DEFAULTS。

signal collection_triggered(text: String) # 房东催收：提示和音效交给 main.gd，它才知道 UI 在哪

## 效果的默认参数。bills.json 的 effects 段可以只覆盖其中某几项
const DEFAULTS := {
    "blackout": {
        "hint": "未缴费：桌面照明受限",
        "darkness_alpha": 0.38,
        "payment_bonus_duration": 8.0,
        "cooldown_multiplier": 0.9,
    },
    "interest": {
        "hint": "未还款：每次考核失败追加利息",
        "interest_per_failed_charge": 10,
        "interest_per_failed_challenge": 10,
    },
    "collection": {
        "hint": "未交租：房东会定期上门催收",
        "progress_threshold": 100.0,
        "max_triggers_per_run": 3,
        "cooldown_seconds": 45.0,
    },
    "broadband": {"hint": "未缴网费：等待组合账单效果"},
    "health": {"hint": "医保账单：与健身年卡拖欠时会影响体力恢复"},
    "gym": {"hint": "健身年卡：与医保账单拖欠时会影响体力恢复"},
    "fine": {"hint": "未缴罚款：与房租拖欠时会加快催收"},
}

var params: Dictionary = {} # effect_id -> 参数字典
var synergy_rules: Array[Dictionary] = []
var sources: Dictionary = {} # effect_id -> [账单 tag]：当前让这个效果生效的是哪些账单
var interest_total := 0 # 信用卡累计的、还没付掉的利息
var interest_by_tag: Dictionary = {} # 账单 tag -> 这张卡产生了多少利息（用于"只清自己的"）
var collection_count := 0 # 本局已经催过几次
var collection_cd := 0.0 # 催收冷却计时
var collection_next := 0.0 # 下一次催收的收入门槛


func setup(data: Dictionary) -> void:
    params.clear()
    synergy_rules.clear()
    var raw_synergies: Variant = data.get("synergies", [])
    if raw_synergies is Array:
        for raw_rule in raw_synergies:
            if raw_rule is Dictionary:
                synergy_rules.append(raw_rule)
    var conf: Variant = data.get("effects", {})
    for eid in DEFAULTS:
        var base: Variant = DEFAULTS.get(eid, {})
        var merged: Dictionary = base if base is Dictionary else {}
        merged = merged.duplicate()
        if conf is Dictionary:
            var over: Dictionary = conf
            var mine: Variant = over.get(eid, null)
            if mine is Dictionary:
                var od: Dictionary = mine
                for k in od:
                    merged[k] = od[k]
        params[eid] = merged
    reset()


func reset() -> void:
    sources.clear()
    interest_total = 0
    interest_by_tag.clear()
    collection_count = 0
    collection_cd = 0.0
    collection_next = number("collection", "progress_threshold", 100.0)


## 一张账单带不带效果（缺 effect_id / effect_enabled=false 都当普通账单）
static func is_special(bill: Dictionary) -> bool:
    return String(bill.get("effect_id", "")) != "" and bool(bill.get("effect_enabled", true))


## 账单的身份。随机生成的账单没有稳定主键，用"种类 id + 户号"拼一个
static func tag_of(bill: Dictionary) -> String:
    return String(bill.get("id", "")) + "#" + String(bill.get("no", ""))


func number(eid: String, key: String, fallback: float) -> float:
    var p: Variant = params.get(eid, null)
    var d: Dictionary = p if p is Dictionary else {}
    return float(d.get(key, fallback))


func text(eid: String, key: String, fallback: String) -> String:
    var p: Variant = params.get(eid, null)
    var d: Dictionary = p if p is Dictionary else {}
    return String(d.get(key, fallback))


## 账单列表上/详情里显示的那一句状态说明
func hint_of(bill: Dictionary) -> String:
    return text(String(bill.get("effect_id", "")), "hint", "")


func is_active(eid: String) -> bool:
    var arr: Variant = sources.get(eid, null)
    var a: Array = arr if arr is Array else []
    return a.size() > 0


func synergy_rule(sid: String) -> Dictionary:
    for rule in synergy_rules:
        if String(rule.get("id", "")) == sid:
            return rule
    return {}


func is_synergy_active(sid: String) -> bool:
    var rule := synergy_rule(sid)
    var required: Variant = rule.get("requires", [])
    if not (required is Array):
        return false
    var required_ids: Array = required
    if required_ids.is_empty():
        return false
    for raw_eid in required_ids:
        if not is_active(String(raw_eid)):
            return false
    return true


## 账单列表一有变动就调用：重建"哪些效果还在生效"。
## 顺带把"来源已经还掉"的信用卡利息清掉 —— 还了卡就不该继续被追着收利息。
## 返回这次清掉了多少利息（main.gd 拿去写提示）。
func sync(bills: Array) -> int:
    sources.clear()
    for i in range(bills.size()):
        var raw: Variant = bills[i]
        if not (raw is Dictionary):
            continue
        var bill: Dictionary = raw
        if not is_special(bill):
            continue
        var eid := String(bill.get("effect_id", ""))
        var arr: Variant = sources.get(eid, null)
        var list: Array = arr if arr is Array else []
        list.append(tag_of(bill))
        sources[eid] = list

    var stale: Array = []
    for tag in interest_by_tag:
        if not _bill_exists(bills, String(tag)):
            stale.append(tag)
    var cleared := 0
    for t in stale:
        cleared += int(interest_by_tag[t])
        interest_by_tag.erase(t)
    _refresh_interest_total()
    return cleared


func _bill_exists(bills: Array, tag: String) -> bool:
    for i in range(bills.size()):
        var raw: Variant = bills[i]
        if raw is Dictionary and tag_of(raw) == tag:
            return true
    return false


func _refresh_interest_total() -> void:
    var t := 0
    for k in interest_by_tag:
        t += int(interest_by_tag[k])
    interest_total = t


## 信用卡：一次考核失败追加一次利息。返回这次加了多少（0 = 这张卡不带利息效果）
func accrue_interest(bill: Dictionary, surcharge: int = 0) -> int:
    if String(bill.get("effect_id", "")) != "interest":
        return 0
    var amount := int(number("interest", "interest_per_failed_challenge", 10)) + maxi(0, surcharge)
    var tag := tag_of(bill)
    interest_by_tag[tag] = int(interest_by_tag.get(tag, 0)) + amount
    _refresh_interest_total()
    return amount


## 支付某张账单时，它带出来的附加单（目前只有信用卡利息）也该作废。
## 返回这些附加单的 source 标记，由 main.gd 去 bills 里删 —— 账单数组是 main.gd 的，
## 管理器不该自己动手改别人的数组。
func extra_source_tags(bill: Dictionary) -> Array:
    var tags: Array = []
    var tag := tag_of(bill)
    # 利息按来源账单追踪；逾期费由 main.gd 按 source 字段一并清除。
    for t in interest_by_tag:
        if String(t) == tag and int(interest_by_tag[t]) > 0:
            tags.append(tag)
            break
    return tags


## 支付信用卡后：清掉这张卡自己产生的利息，返回清掉了多少。
## ⚠️ 只清这一张卡的，其他卡的利息和滞纳金都不动
func clear_interest_of(bill: Dictionary) -> int:
    var tag := tag_of(bill)
    var cleared := int(interest_by_tag.get(tag, 0))
    interest_by_tag.erase(tag)
    _refresh_interest_total()
    return cleared


## 房租催收：累计收入每跨过一道门槛就来催一次，带冷却和每局上限。
## 触发时发信号，提示怎么显示由 main.gd 决定。
func update_collection(delta: float, earned: float) -> void:
    if collection_cd > 0.0:
        collection_cd = maxf(0.0, collection_cd - delta)
    if not is_active("collection"):
        return
    if collection_count >= int(number("collection", "max_triggers_per_run", 3)):
        return
    var effective_threshold := collection_next
    if is_synergy_active("rent_fine"):
        var multiplier := number("collection", "progress_threshold", 100.0)
        var rule := synergy_rule("rent_fine")
        effective_threshold -= multiplier * (1.0 - float(rule.get("threshold_multiplier", 1.0)))
    if earned < effective_threshold or collection_cd > 0.0:
        return
    collection_count += 1
    collection_cd = number("collection", "cooldown_seconds", 45.0)
    collection_next = earned + number("collection", "progress_threshold", 100.0)
    collection_triggered.emit(text("collection", "hint", "房东上门催收"))
