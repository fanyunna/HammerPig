# 商店 / 背包 / 锤子 / 技能系统实现方案

## Context（背景）

当前「敲猪还债」是单文件 `scripts/main.gd`（Node2D，约 2800 行）+ 低侵入扩展模块（`lucky_wheel.gd`、`card_build.gd`）的结构。经济统一用 `score`（余额，即敲猪攒的钱）作为货币，弹窗通过 `_process` 提前 `return` 实现全局暂停。

本次要新增一套**单局肉鸽**系统：商店（锤子/技能/盲盒）、背包（仅技能道具）、快捷栏（1/2/3）、三款可替换锤子、两款技能与若干本局 buff。货币沿用 `score`，全部资源对局结束清空重置。

***

## 一、总体架构（低侵入，对齐 lucky\_wheel 模式）

新增一个自包含模块 `scripts/shop.gd`（Node2D，作为 `main` 的最后一个子节点挂载），负责**全部数据与 UI**：商店、背包、快捷栏、技能、buff、冷却、盲盒、以及商店/背包面板绘制。`main.gd` 只加少量「钩子」接入点。

### 新增文件

1. `scripts/shop.gd` — 核心模块（数据 + 状态 + 逻辑 + UI 绘制 + 输入分发 + 查询接口）
2. `data/shop.json` — 商店/锤子/技能/盲盒的数值与中文文案（可注入，便于测试）
3. `tests/shop.gd` — headless 回归测试

### 修改文件

1. `scripts/main.gd` — 接入钩子（详见第四节）

***

## 二、数据模型（`data/shop.json`）

```jsonc
{
  "hammer_price": 220, "skill_price": 180, "box_price": 200,
  "backpack_capacity": 3, "quickbar_size": 3,
  "hammers": {
    "iron":   { "name": "普通铁锤", "hits": 1, "damage": 1.0,  "radius": 1.0, "desc": "基础铁锤" },
    "dual":   { "name": "连打锤",   "hits": 2, "damage": 0.65, "radius": 1.0, "desc": "自动连砸 2 次，单下伤害较低", "accent": "#ff8c3a" },
    "gravity":{ "name": "重力锤",   "charge": true, "damage_min": 1.0, "damage_max": 3.0, "radius_max": 1.6, "stun": 0.45, "desc": "长按蓄力，范围与伤害随蓄力增大，落地硬直", "accent": "#8b5cf6" },
    "magnet": { "name": "磁吸锤",   "damage": 1.0, "pull_radius": 150.0, "falloff_min": 0.4, "desc": "砸落吸附附近小猪，范围递减伤害", "accent": "#4f8ef7" }
  },
  "hammer_pool": ["dual", "gravity", "magnet"],
  "skills": {
    "hourglass": { "name": "凝时沙漏", "cooldown": 10.0, "duration": 2.5, "slow_mul": 0.4, "desc": "全场小猪移速降至 40%" },
    "abacus":    { "name": "鎏金算筹", "cooldown": 12.0, "duration": 4.0, "score_mul": 2.0, "desc": "击杀得分 ×2" }
  },
  "skill_pool": ["hourglass", "abacus"],
  "box_pool": [
    { "type": "hammer", "weight": 1 },
    { "type": "skill",  "weight": 1 },
    { "type": "coins",  "weight": 1, "amount": 25 },
    { "type": "damage_up", "weight": 1, "pct": 0.15 },
    { "type": "triple_kill", "weight": 1, "kills": 3, "mult": 3.0 }
  ]
}
```

* 背包：`Array[Dictionary]`，元素 = 技能实例 `{id, cd, cd_max, active}`（冷却/持续时间挂在实例上，拖拽不重置）。
* 快捷栏：`Array[Variant]`（长度 3），元素为技能实例或 `null`。
* 拖拽 = 把技能实例的引用在背包数组与快捷栏槽位之间搬移，冷却字段随实例走。
* 锤子状态：单一 `current_hammer_id`（`"iron"` 默认），购买/盲盒直接替换，旧锤子丢弃。

***

## 三、`scripts/shop.gd` 职责与接口

仿 `lucky_wheel.gd`：`setup(host)` 注入 main 引用并加载 `data/shop.json`；`_draw()` 自绘 UI（作为最上层子节点天然覆盖在 main 之上）；`_process` 里处理自己的动画。

对外接口（main 调用）：

* `setup(main)`, `reset_run()`, `tick(delta)`, `is_open()`
* `handle_click(point) -> bool`（商店/背包面板内点击分发）
* `try_open_shop()`, `try_open_backpack()`, `try_activate_skill(slot)`
* 数值查询：`speed_mul()`, `score_mul()`, `kill_bonus_mul()`, `hammer_damage_mul()`（含盲盒 +15%）
* 锤子行为：`current_hammer() -> Dictionary`（hits/damage/radius/charge/magnet 参数）、`is_charging()`、`charge_power()`、`pull_radius()`、`falloff_min()`、`stun_after()`

### 内部逻辑要点

1. **商店**：每次 `try_open_shop()` 重刷——锤子区随机 2（候选 `hammer_pool` 去重/可重复）、技能区随机 2（`skill_pool`）、盲盒 1；上次未购不保留。
2. **购买**：
   * 锤子：`score >= 220` 扣款并 `current_hammer_id = id`（替换）；不足置灰。
   * 技能：`score >= 180 且背包 < 3` 扣款入背包；背包满置灰并弹「背包已满」。
   * 盲盒：`score >= 200` 扣款抽奖（见下）。
3. **盲盒池**：随机锤子→替换；随机技能→入背包（满则作废+提示）；`+25` 加 `score`；`+15% 伤害` 设 `damage_bonus_pct=0.15`（本局永久）；`3 次击杀分数×3` 设 `triple_kills=3`。
4. **技能冷却**：仅在游戏运行（`tick` 被调用）时递减；面板打开时 `tick` 不调用 → 冷却天然暂停。释放后设 `cd = cd_max`，效果持续 `duration`，重复释放刷新持续不叠加。
5. **快捷栏/背包 UI**：空槽灰色占位；冷却中贴图变暗且不可点击释放；背包与商店展示贴图一致（同一套程序化绘制函数）。

### UI 绘制（程序化自绘，风格统一）

* 商店面板：全屏压暗 + 面板，三区（锤子×2 / 技能×2 / 盲盒×1）+「关闭商店」按钮；每个商品用程序化图标 + 名称 + 价格 + 说明；不足金额置灰。
* 背包面板：背包 3 格 + 快捷栏 3 格；支持拖拽。
* 快捷栏 HUD：平时常驻显示 3 格 + 冷却倒计时暗化。
* 商品图标程序化绘制（含发光色）：连打锤橙、重力锤黑紫、磁吸锤蓝红、沙漏古铜+淡蓝流沙、算筹金色、盲盒深棕木纹+金色「?」。

***

## 四、`scripts/main.gd` 改动点（钩子）

1. **`_ready()`（约 L143-178）**：顶部 `const ShopScript := preload("res://scripts/shop.gd")`；`wheel.setup(self)` 之后 `shop = ShopScript.new(); add_child(shop); shop.setup(self)`（挂在最上层）。
2. **`reset_game()`（约 L873-968）**：`wheel.reset_run()` 附近加 `shop.reset_run()`；重置 main 侧的锤子充能/硬直状态（`charging`, `charge_t`, `stun_t`）。
3. **`_process()`（约 L970）**：
   * 在 `wheel.is_open()` 提前返回之后、`build.panel_open` 判断之前，加 `if shop != null and shop.is_open(): queue_redraw(); return`（商店/背包打开即全局暂停）。
   * 运行路径（`wheel.tick(delta)` 附近约 L1004）加 `shop.tick(delta)`。
   * 猪移动（L1042）：`pig.position += pig.velocity * delta * wheel_speed_mul()` → 追加 `* shop.speed_mul()`。
   * 重力锤充能：`phase=="playing"` 且装备重力锤时，长按左键累计 `charge_t`，松手触发蓄力挥击；`stun_t` 递减期间禁止移动/攻击。
4. **`sync_cursor()`（约 L732-741）**：hide 条件追加 `and not (shop != null and shop.is_open())`（面板内还回系统箭头）。
5. **`_unhandled_input()`（约 L1100）**：
   * 商店/背包打开时：把输入转发给 `shop.handle_click` / 关闭热键，`return`（模态，仿 `wheel.is_open()` 分支）。
   * 热键：`T` 开商店、`I` 开背包（仅在 `phase=="playing"` 且无其它弹窗时）。
   * 技能键：`phase=="playing"` 且非面板打开时，`KEY_1/2/3` 调 `shop.try_activate_skill(slot)`（与卡片阶段 1/2/3 不同 phase，无冲突）。
6. **点击路由（约 L1183-1257）**：在 `bill_open`/`bill_detail` 分支前加 `if shop.is_open(): shop.handle_click(point); queue_redraw(); return`。
7. **`strike()`（约 L1293）与 `strike_target()`（约 L1267）**：抽出「对单只猪结算一次伤害」为 `_apply_hit(pig, point, damage)`；`strike_target` 半径 × `shop.radius_mul()`。按 `shop.current_hammer()` 分支：
   * **普通**：单目标 1 击。
   * **连打**：对同一目标连算 2 击（共用一套冷却，每击计入连击/得分）。
   * **重力**：按 `charge_power()` 计算伤害与范围，落地后设 `stun_t`。
   * **磁吸**：先把落点附近（`pull_radius()`）猪吸向中心，再对吸附范围内每只按距离递减结算伤害（用户已确认递减 AOE）。
8. **`settle_card_break()`（约 L1376）**：正收益分支追加 `gain = roundi(gain * shop.score_mul() * shop.kill_bonus_mul())`；「3 次击杀×3」在每次击碎时 `kill_bonus` 递减一次；负收益（催债猪）不放大（沿用现有「损失不翻倍」规则）。
9. **`pig.hp` 转 float**：`strike` 里 `pig.hp -= hit_damage`（hit\_damage 为 float，支持连打 0.65/重力递增/磁吸递减）。涉及 `reset_game`、`_process` 存活判断、`strike_target`、`settle_card_break`、裂纹绘制 `pig.max_hp - int(pig.hp)` 等处的类型兼容（改动小）。
10. **`draw_hammer()`（约 L2527）**：按 `shop.current_hammer()` 分支程序化绘制三款锤子外观（含发光色/符号），叠加充能发光、重力落地裂纹/冲击波、磁吸环形吸力场+牵引箭头、连打橙色残影/火花等特效（用短生命周期特效状态，仿 `impact_timer`）。

***

## 五、关键默认决定（实现时以此为准，可改）

* **货币**：统一为 `score`（余额）。「金币/得分」在本作等同；盲盒 `+25`、锤子/技能扣款均操作 `score`。
* **鎏金算筹「金币不翻倍」**：因本作 `score` 即货币，效果即「击杀收益(score) ×2」；与既有 `double_timer`/转盘×2 叠乘，自身重复释放仅刷新不叠加。
* **快捷键**：`T` 商店、`I` 背包、`1/2/3` 技能（均可改）。
* **连打锤**：0.65×2=1.3 总伤害，单下低于普通（1.0），共用一套冷却。
* **磁吸锤**：吸附半径内按距离递减伤害（中心 1.0 → 边缘 0.4）。
* **盲盒伤害 +15%**：本局永久，对所有锤子伤害乘 1.15。
* 商店每次打开重刷、上次未购不保留；盲盒技能奖励背包满则作废。

***

## 六、验证方案

1. **新增回归测试** `tests/shop.gd`（仿 `tests/card_build.gd` 直接操作 `game.shop`，仿 `tests/smoke.gd` 的 `check()` 断言），覆盖：
   * 商店打开→暂停；关闭→恢复；每次打开重刷。
   * 锤子购买：扣款、装备、替换（旧锤消失）、不足置灰。
   * 技能购买：入背包、容量上限 3、满包置灰提示。
   * 盲盒：5 种奖励各自结算（用注入/固定随机），背包满作废。
   * 技能：冷却倒计时、面板打开冷却暂停、释放生效（减速/得分×2）、拖拽后冷却保留。
   * 三款锤子行为：连打 2 击、重力蓄力伤害/范围/硬直、磁吸吸附+递减伤害。
   * buff：+15% 伤害、3 击杀×3 递减、+25。
   * `reset_game` 后所有商店/背包/锤子/buff/冷却清空。
2. **回归**：跑 README 现有 headless 命令（`smoke.gd` 与 `card_build.gd`），确认 132+ 条既有断言不回归。
3. **窗口手动验证**：F5 跑主场景，人工确认商店/背包打开即暂停、拖拽、三款锤子手感与特效、技能冷却暗化、结算清零。

> 说明：新脚本 `shop.gd` 缺 `.uid` 文件时 Godot 4.7 会在导入时自动生成；headless 下 `preload` 按路径可正常工作。若 CI 严格校验 `.uid`，可补生成。
