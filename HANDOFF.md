# 敲猪还债 (HammerPig) — 开发交接文档

> 本文档面向「接手本项目的下一个人 / AI」，把项目定位、已锁定的设计、代码架构、当前进度和下一步全部固化。看完即可无缝继续开发，无需翻阅对话历史。

---

## 0. 一句话现状

一个 **Godot 4.7.2** 课程项目（计科2403），玩法是「砸猪赚钱 → 应付账单」的循环。

- **当前工程**：已包含账单压力效果、赌场风格赌桌、3D 存钱罐与从上向下挥击的锤子，以及奖励卡构筑、债务日历和耐力系统。
- **当前经济调整**：猪种收益已提高；胜利目标调整为 ¥950，第一张构筑卡阈值为 ¥160，后续每 ¥135 出一张，抛硬币阈值为 ¥475。具体猪种数值以 `data/balance.json` 为准。
- **新增奖励卡**：「猪群翻倍」将桌上猪的数量翻倍并缩小、重新排布；每局只会生效一次，重开后重置。
- 测试数量以 `tests/smoke.gd` 实际运行结果和文档末尾最新验证记录为准；下方旧轮次记录仅供追溯。
- **猪游走与耐力系统**：小猪在赌桌活动区域内随机游走、每挥一锤消耗体力、体力见底本轮结束（默认开启，见 §6 / §8.3）。
- **3D 开关**：`balance.json` 的 `pig_3d` / `desk_3d`（默认都 true）；关掉或 headless 下自动回退 2D 自绘（小猪 `draw_pig_flat()`、桌面三层面板），见 §9。

---

## 1. 项目定位与参考游戏

- 游戏名：**敲猪还债**（副标题「账单今天到期」；内部目录名 `HammerPig`）
- 参考 Steam 独立游戏 **《账单必须支付》(Bills Must Be Paid, Rike Games)**：扮演破产负债者，砸碎小猪存钱罐赚钱去付不断到期的账单，付不上就破产。
- 本项目的「砸猪 +¥10」对应原作的「砸存钱罐」，本项目的「账单卡/考核小游戏」对应原作的「账单送达」。
- 项目根目录（Windows 绝对路径，已合并到 qiaozhu-main）：
  `E:\game\qiaozhu-main\qiaozhu-main\03-工程项目\HammerPig`

---

## 2. 技术环境

- 引擎：**Godot 4.7.2**（GL Compatibility 渲染，2D）
- 语言：**GDScript**，纯代码绘制画面（无任何美术贴图，只有一张 app 图标和一个 hit.wav 音效）
- 本机 Godot 可执行文件（**不在 PATH 里，必须用绝对路径**）：
  - 带窗口：`e:/game/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`
  - 控制台版（跑测试用）：`e:/game/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`
- 主场景：`project.godot` 里 `run/main_scene="res://scenes/main.tscn"`，窗口 1280×800。

### 跑冒烟测试（headless）

```bash
cd "E:\game\qiaozhu-main\qiaozhu-main\03-工程项目\HammerPig" && \
"e:/game/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/smoke.gd
```

最近验证输出：`ALL 132 CHECKS PASSED`（见 `01-团队协作/验证记录.md`）。

> ⚠️ 注意：`_draw()` 在 headless 模式下**不会被调用**，所以画面相关的改动（draw_* 函数）无法被测试覆盖，只能靠人工开窗口检查或逻辑推演。

---

## 3. 核心玩法与已锁定的设计

### 3.1 经济模型（当前配置）

- **余额 = 积分 = 金币**，同一个变量 `score`。
- **开局破产（¥0）**，通过敲猪一点点赚回来。
- 攒够 `card_first_at`（160）弹出**第一张**奖励卡，之后每攒 `card_interval`（135）再弹一张。
  - ⚠️ 达到阈值**不当场弹卡**：先记 `card_delay = card_pop_delay`（0.45s），由 `_process()` 递减到 0 才真正 `open_card()`。原因见 §3.6 的「半秒缓冲」。
  - ⚠️ 调整卡片阈值时要一起考虑 `round_target`，避免玩家还没看到构筑卡就已通关。当前配置在一局内安排了多次奖励卡选择。
- 攒够 `round_target`（950）分 → **摆脱破产（赢）**；余额被扣到 0 → **破产（输）**。体力耗尽也会结束本局。
  - ⚠️ 这个目标**不显示在 HUD 上**。`round_target` 达成后进入胜利结算。

### 3.2 卡片系统（奖励构筑 + 保留的小游戏入口）

| `card_type` | 显示名 | 分类 | 效果 |
|---|---|---|---|
| `"reward"` | 奖励构筑 | 奖励 | 从三张升级卡中选一张；可强化锤子、体力、收益或翻倍猪群 |
| `"double"` | 双倍卡 | 奖励 | 接下来 15 秒敲猪收益 ×2（保留旧卡逻辑） |
| `"collect"` | 限时凑钱 | 考核小游戏 | 点金币凑够应付金额，躲假币 |
| `"dodge"` | 躲催债 | 考核小游戏 | 移动鼠标躲开红色「催」图标，3 条命坚持到时间结束 |

- 旧版加权出卡与考核卡规则仍留在配置/代码中，常规流程已改为奖励构筑选择。
- 当前 `roll_card()` 将常规弹卡统一导向 `reward` 构筑选择；凑钱和躲催债小游戏仍由独立入口及旧逻辑保留。不要把旧加权出卡规则描述成当前常规流程。
- 奖励构筑池含「重锤改造」「轻型锤柄」「宽面锤头」「顺手轴承」「贪婪本能」「连击奖励」「体力扩容」「慢燃咖啡」「双倍收益」「现金奖励」；「猪群翻倍」每局至多出现并生效一次，扩大猪群后全体缩至原尺寸的 0.68 倍并重新排布。
- **弹卡的半秒缓冲**（`card_delay` / `card_pop_delay`）：卡片从来不在得分的那一帧弹。越过 `next_card` 时只把 `next_card += card_interval`、`card_delay = card_pop_delay`（0.45s），由 `_process()` 递减到 0 才 `open_card()`。三个理由：
  1. **别糊掉爆钱的反馈**：猪碎的那一刻，钱票刚飘起来、`+¥13` 刚弹出、粒子刚炸开、`pop` + `cash` 两段音效还没响完。这一帧糊一张全屏卡片上去，玩家最爽的那 0.4 秒被吃掉了 —— 反馈没播完就打断，是所有"弹窗式"设计最容易犯的错。
  2. **这半秒还能继续砸**：`card_delay` 期间 `_process()` 只 `queue_redraw()` 后 `return`，但玩家可以照常挥锤。于是这 0.45 秒里往往会多出一锤，钱又多攒一点 —— 正好是"多砸一点钱再弹卡"。
  3. **达标优先**：`phase == "playing"` 时才弹。玩家在缓冲里凑够 `round_target`，那就直接进结算，不许再糊一张卡到通关画面上。
  - ⚠️ `card_delay` 的递减必须排在 `update_gamble(delta)` **之后**：抛硬币时整局是暂停的，缓冲也该跟着停，否则卡片会在硬币落地动画里冒出来。
  - ⚠️ 但它要排在 `cooldown` / `swing` / `double_timer` **之后**：缓冲分支是 `return` 结尾的，排在这些计时器之前会把挥锤冷却一起冻住 —— 那这半秒就只能干等，第二锤挥不出去，白留了。
- 考核卡通关 → 余额不变 + `bill_reward`；失败/超时 → 余额扣 `bill_amount`。
- 奖励卡与考核卡的统一逻辑入口：`apply_card()`；考核小游戏的统一生命周期：`start_challenge()` → 每帧 `update_xxx()` → `finish_challenge(success)`。
- **卡片外观**：`draw_card()` 只用「卡头 + 徽章 + 说明 + 按钮」四个部件拼装，每种卡只换一套主色和文案：
  - `card_shell(title, accent)`：投影 + 描边外框 + 深色卡面 + 顶部卡头（标题在**卡内**，不再浮在卡片上方）。
  - `card_badge(accent, value, size)`：卡面中间的圆形徽章，展示每张升级卡自己的图标与效果信息。
  - `text_center(value, center_x, y, size, color)`：按字体实际宽度居中的 `text_at()`；`button()` 新增第 4 个参数可换按钮主色。
  - 主色：奖励 `#8fd05a` 绿 / 双倍 `#ffd166` 金 / 账单 `#efbc72` 橙 / 催债 `#e8836b` 红橙。
  - 弹出动画：`card_pop`（`open_card()` 置 0，`_process()` 里 `phase == "card"` 时累加），`draw_card()` 用它做 0.16 秒 ease-out 缩放（0.9 → 1.0）。⚠️ 用 `draw_set_transform(center * (1 - s), 0, s)` 让缩放绕卡片中心，别写成 `center * s`，否则会往右下飘。

### 3.3 背景叙事与赌徒提示（`data/story.json`）

设定：一个欠了一屁股债的人，桌上摞着一叠没付的账单，手里只剩一只存了三年、说好「以后再用」的存钱罐。敲碎它换钱还债 —— 但真正驱动他的是**赌徒心理**：第一只已经敲了，再多敲一只，说不定就凑够了。

- **文案全在 `data/story.json`**，改字不用动代码；键缺失时 `main.gd` 里有内置兜底句，文件丢了也不会崩。
- **开场序幕**：`intro_open` 在 `_ready()` 里按 `intro_enabled` 决定。序幕期间 `_draw()` 只铺桌面 + 序幕文案就 `return`，不画 HUD / 猪 / 锤子；`_unhandled_input()` 把一切输入当成「开始」并 `return` 吞掉。⚠️ headless 下强制关闭，否则自动化测试第一下点击会被序幕吃掉。
- **账单 `bills`（`data/bills.json`）**：开局按 `start_count`（24）从 `catalog`（16 种：水/电/燃气/宽带/话费/物业/会员/疫苗/医保/罚款/信用卡/房租/车险/助学贷款/健身卡/牙科）随机生成，同类型重复出现会带期数（「电费 第2期」），每张金额在基准值上浮 0.75~1.3 倍，并带 `no`（户号）与 `due`（缴费期限）。按金额升序；`unpaid_bills` 就等于 `bills.size()`。
  - **三层界面，全部纸质化**：
    1. **桌上那一沓**（`draw_bills()`）：层数 `ceili(张数/2)`（最多 12 层，每层露 6px），最上面那张印「催缴通知单 / 名字 等 / N 张 / 合计 ¥ / 点开查账 →」。点它 → 摊开账本。
    2. **摊开的账本**（`draw_ledger()`）：4 列 × 5 行 = 20 张一页，`←/→` 翻页，`bill_page` 用 `clamp_bill_page()` 夹在 `ledger_page_count()` 内；点某张纸 → 放大。
    3. **单张大账单**（`draw_bill_detail()`）：抬头红条、户号、缴费期限、超大金额、三行明细、「未付」红章（旋转 `-0.18` rad）、`还 ¥xx` / `放回桌上` 两个按钮。钱不够时按钮变灰，底部写「手上只有 ¥X，还差 ¥X」。
  - **摊开账本时整局暂停**：`_process()` 开头 `if bill_open or bill_detail >= 0: queue_redraw(); return` —— 猪不游走、账单卡不计时，可以慢慢看。键位：`B` 开关、`Esc` 逐层退出（大账单 → 账本 → 桌面）、`←/→` 翻页，点账本外面也收起。
  - 还款走 `pay_bill(index)`：扣钱、移除、回 `pay_stamina_bonus`（18）体力、`clamp_bill_page()`。
  - **考核卡通关**不是凭空"付清"，而是 `clear_cheapest_bill()` 真的付掉最便宜的一张；**逾期**则 `add_overdue_bill()` 追加「滞纳金 ¥30」—— 越输账单越多。
  - **核心张力**：还债会减少冲 `round_target`（950）的余额，"先还一张，还是继续砸猪冲目标"是本局的核心选择。账单规模与目标金额以当前数据文件为准。
  - ⚠️ `draw_bill_paper()` 改成**比例排版**（`r.size.y * 0.40 / 0.44 / 0.86`），因为纸沓、账本格（236×74）、大账单三种尺寸共用它。曾经写成 `-half + Vector2(13, -half.y + ...)`，y 多减了一个 `half.y`，文字全跑到纸外面。
  - ⚠️ 纸片用 `draw_set_transform(纸心 + 抬起偏移, tilt, ONE)` 绕纸心旋转，画完必须 `draw_set_transform(Vector2.ZERO)`，否则后面的东西全跟着歪。
  - ⚠️ 账单画在 `_draw()` 最末（锤子、结算弹窗之后），否则鼠标停在纸沓上时锤子会盖住它；还款飘字固定在 `(780,300)`。
  - 结算面板显示「已还 X 张 · 还剩 Y 张（¥总额）」。
- **赌徒提示 `gamble_hint()`**：底部信息栏第一行，同一时刻只显示一句，按「最该煽动哪一个」排优先级：
  1. 体力 < 3 次挥锤 → `gamble_tired`（手抬不起来了……再挥一次？）
  2. 连击 ≥ `combo_threshold_fever` → `gamble_fever`（手感正热，趁现在多敲几只）
  3. 距目标 ≤ 3 只猪 → `gamble_near`（就差 ¥X 了 —— 再敲一只就够了）
  4. 余额 < 下一张账单 → `gamble_behind`（下一张账单 ¥30，你手上只有 ¥10）
  5. 敲碎 ≥ 5 只 → `gamble_debt`（已经敲碎 N 只了，你还在敲）
- **结算文案**：胜利叫「暂时安全」而不是「还清了」—— 目标达成只是甩开了催债电话，账单一张没少（`win_line` 明说）；失败则是「账单反而又多了几张」。这是这个设定里唯一诚实的部分。
- 占位符：`{broken}` `{score}` `{bill}` `{gap}` `{unpaid}`，统一由 `story_line()` 替换。

### 3.4 状态机

`phase` 取值：

```
"playing"   → 敲猪（主循环）
"card"      → 弹出卡片，等玩家确认（奖励卡直接领，考核卡进入 challenge）
"challenge" → 小游戏进行中（按 card_type 分 collect / dodge）
"finished"  → 胜利结算（摆脱破产）
"bankrupt"  → 失败结算（余额归 0）
```

### 3.5 视觉基调：赌场桌面与第一人称锤手

- **桌面**（`scripts/desk3d.gd`）：3D 胡桃木桌体、绿色绒面、黄铜装饰线与下注区；2D 回退桌面也保持绿绒与金色装饰的赌场风格。
- **存钱罐**（`scripts/pig3d.gd`）：通过程序化网格与独立 SubViewport 渲染；配置 `pig_3d` 可关闭并回退 2D 绘制。
- **锤子与手**（`scripts/hammer3d.gd`）：透明 SubViewport 中从上向下呈现锤子和手部。手部由连贯轮廓、掌丘与指节细节构成，跟随鼠标作为自绘光标；挥击旋转由 `main.gd` 控制。Headless 测试不能确认实际构图和手型，视觉调整后需要开窗口检查。
- **桌后观众与特效**（`main.gd`）：剪影观众、桌面震动、金币和账单压力提示叠加在桌面场景上。

> 下方锤子剪影手的实现笔记属于旧版 2D 方案，仅供追溯。当前运行时使用 `hammer3d.gd`；修正锤头方向和握柄位置时请改 3D 节点局部朝向与视口绘制角度。

整局发生在**赌场赌桌上**，玩家以第一人称从上向下挥锤；锤手由 3D 视口呈现，下注装饰和桌后观众强化赌徒氛围。

- **桌子**（`desk3d.gd`）：
  - 桌板 = 墨绿**绒面**（`_felt_texture()` 用 FastNoiseLite 现场生成：高频颗粒做毛绒 + 低频噪声做压痕），`roughness 0.97` 不反光。
  - 包边 = 深色皮革 `#2b1d18`（木纹只留给桌腿和地板）。
  - `_decorate()` 在桌面上摆赌桌装饰：沿桌沿一圈**金色细线**、中央**两圈同心下注环**（`TorusMesh`）、四角各一摞**筹码**、近端散落**三张牌**。全部压到 y≈0.014，猪走过不会穿模。
  - ⚠️ `TorusMesh.rings` 是**沿大圈的段数**，给 6 会渲染成多边形折线（看起来像乱画的折线）；必须 64+。
  - 2D 回退桌面（`desk_3d: false`）也改成绿绒 + 金线，风格不至于跳。
- **桌后的黑影 `draw_watchers()`**：`settings.watchers`（8）个人形剪影站在桌子后面，画在 `draw_desk()` **之前**（否则会盖在桌上）。每人用 `sin(i*12.9898)` 这类哈希算出固定的体型/明暗/位置抖动，所以每次开局站位一致但不整齐；`shoulder_y` 范围拉到 152~200、`head_r` 22~36，高的只露一颗头、矮的露出半肩，才有"好多人挤在后面"的层次。`elapsed` 驱动轻微起伏与摇晃（别站成雕像）。头在 y≈60-150，身体下半截被 HUD 面板压住。约 2/3 的人有一对极淡的眼神光（`Color("#e2cd96", 0.26~0.46)`）。
- **锤子 `draw_hammer()`**：目前就是一把浮在桌上的锤子 —— 因为没有做出像样的手，`SHOW_HAND = false` 先关着。
  - 试过一版"从画外伸进来的黑影手臂 + 攥拳"（`draw_shadow_arm` / `draw_shadow_fist` / `draw_limb` / `draw_finger_bent` 都还在代码里），用多边形硬拼始终不像手：手指像平行的面条、拳头像一团黑。已关闭，改一行 `SHOW_HAND` 就能回来。
  - **要重做就别再手工拼图元**，两条更靠谱的路：
    1. **剪影贴图**：一张透明 PNG（前臂 + 握拳的手），按 `angle` 旋转贴上去，最省事也最像；
    2. **3D 手**：像 `desk3d` 那样单独一个 SubViewport 渲染手模型，复用同一个 `pivot/angle` 变换。
  - 已经验证过的三条经验（无论哪条路都适用）：
    - **指缝要暗，不要亮** —— 画成亮线时四根手指会糊成一条毛毛虫，光进不去的地方本来就该是最暗的；
    - **柄尾必须露在拳头外面** —— 握点取柄的下段（`Vector2(19, 74)`）而不是末端，否则完全读不出"握着"这个动作；
    - **手要比手臂亮一档**（`#2b221d` vs 纯黑）并加 0.4 以上的边缘光，否则暗背景上的黑手就是一块剪影。
  - ⚠️ 手/锤在 `draw_bills()` 之前画，所以账单纸沓会盖住锤子 —— 这是有意的（账单永远压在你手上）。
  - ⚠️ `_process()` 每帧把 `hammer_position` 覆盖成鼠标位置，写截图脚本时要先 `set_process(false)` 才能指定锤子位置。

### 3.6 那枚硬币：赌一把（`gamble_threshold`）

攒到一定数额，桌边会滚来一枚硬币 —— **正面存款翻倍，反面一分不剩**。玩家可以不用，但一旦推到一边，本局它就不会再出现。这是整局最直白的赌徒时刻。

- **触发**：`balance.json` 的 `gamble_threshold`（475），`score >= 阈值` 且 `phase == "playing"` 且 `gamble_used == false` 时，`update_gamble()` 把 `gamble_state` 置为 `"ready"`，桌边左下角**滚进来**一枚金币，并飘一句「一枚硬币滚过来」。
  - **没攒够的时候，画面上根本没有这枚硬币。** 早期版本在那里画了个灰影 + 「还差 ¥X」，等于开局就把阈值剧透了，惊喜全没了；底部说明里那行常驻的规则解释一并删掉，只在硬币滚到位后才给「正面翻倍 / 反面清零」。`draw_gamble_coin()` 只画 `ready` 这一态，其余状态直接 `return`。
  - 滚入途中不接点击（要 `gamble_t >= GAMBLE_ROLL_TIME`），免得手滑点到一枚还在路上的硬币。
  - ⚠️ 阈值必须**小于** `round_target`（950），否则胜利前不会触发。当前阈值 ¥475 与卡片节奏分开，避免刚弹卡就立即进入抛硬币流程。
- **状态机**：`gamble_state` = `none`（还没攒够/已用过） → `ready`（可以抛） → `flip`（空中翻） → `result`（已落定，2.2 秒后回 `none`）。`gamble_used` 表示本局是否用掉。
- **两种选择**：
  - 点硬币本身或「抛一次」→ `start_gamble()`：正反面在出手那一刻就定了（`randf() < 0.5`），但玩家要等它落下来才知道。
  - 点「不要」→ `skip_gamble()`：飘「你把它推到一边」，`gamble_used = true`，本局不再出现（错过的机会也是叙事的一部分）。
- **结算 `resolve_gamble()`**：
  - **正面**：`score *= 2`；若因此达到 `round_target`，则 `end_reason = "coin"`、`phase = "finished"`，胜利面板换成「正面。」+ `win_coin_line`（"你不会觉得这是运气，你会觉得自己有手感"）。
  - **反面**：`score = 0` + 屏幕震动，**游戏继续**（不是破产 —— 玩家还能接着敲，只是白干一场）。
  - 无论正反，硬币都算用掉了。
- **暂停**：`flip` / `result` 期间 `_process()` 走到 `update_gamble()` 就 `return`（猪不走、卡不计时），和翻账本一样。
- **绘制**：`draw_gamble_coin()`（桌边那枚 + 两个按钮 + 没攒够时的灰影与「还差 ¥X」）、`draw_coin_face(c, r, sx, heads, dim)`（`sx` 是横向压缩，模拟绕竖轴翻转；`sx < 0.3` 时画成一条侧面厚度）、`draw_gamble_flip()`（屏幕中央抛起 → 翻转 → 定格，带随高度变化的影子）。硬币画在 `draw_hammer()` **之后**，否则鼠标移过去时锤子会把它盖住。
- ⚠️ **变量名不能叫 `coins`** —— 那已经是「凑钱小游戏」里满地跑的硬币了（见 §5.2）。这套一律用 `gamble_*`。
- ⚠️ **抛硬币时吞输入要只加在鼠标分支**：写在键盘处理之前会把 `R` 重开一起吞掉（测试就卡在这上面，表现为一大串连锁失败）。
- ⚠️ 测试里要把 `next_card` 拉高（10000）再设 `score`，否则越过阈值会让卡片在半秒后弹出、把 `phase` 变成 `card`。想测硬币本身时还要 `game.gamble_used = true` 之外的注意点：`card_delay` 挂在 `_process` 上，测试请勿推进超过 `card_pop_delay`（0.45s）的时间，否则卡片会突然插入。

### 3.7 听觉与指针（`scripts/soundfx.gd`，autoload 名 `Sound`）

**整个项目的音频素材只有 `assets/hit.wav` 一个**，其余 13 个声音全部是运行时合成的（`AudioStreamWAV` 手写 PCM）。理由和绒面贴图一样：这个项目能用代码生成的就不放进素材目录，改参数就能调手感，也不用担心版权。

- **两个原语**（`soundfx.gd`）：
  - `_tone(buf, f0, f1, dur, wave, amp, decay, delay)`：扫频振荡器（0 正弦 / 1 三角 / 2 方波）+ 指数衰减。**相位是逐样本累加的**（`ph += f / RATE`），用 `t * f` 那种写法在变频时会有相位跳变，听起来是"咔"的一声。
  - `_noise(buf, dur, cutoff, amp, decay, delay)`：白噪声过一阶低通（`lp += (w - lp) * cutoff`），`cutoff` 越小越闷：0.5 是风声，0.05 是低沉的轰。
  - 最后统一归一化到 0.95 再量化成 16bit，多声叠加不会爆。
- **手感规律**（改音效时照这个调）：
  - 撞击类 = 低频 `tone` 下行 + 短 `noise`：低频给体积感，噪声给"接触"的毛边。例：`pop`（猪碎）用 200→55Hz 的三角波 + 0.14 cutoff 的噪声。
  - 钱/金属类 = 高频三角波 + 大 `decay`（衰减慢）。三角波没有谐波，听感才"干净"，像硬币而不是像铃铛。
  - **空挥必须明显比命中轻**（`miss` 只有 0.12 振幅），否则每次挥空都像打到了东西，玩家就失去了命中反馈。
- **播放池**：6 个 `AudioStreamPlayer` 轮转，连打时前一声不会被掐断。`Sound.play("cash", pitch, gain)`，`pitch` 用来做连击升调（`strike()` 里按 combo 算），`gain` 用来压轻次要音。
- **已接入的位置**：`strike()`（crack / miss / pop / cash）、`open_card()`（card）、`pay_bill()`（cash 0.85 降调：交出去的钱）、`finish_challenge()`（cash / stamp，破产再叠 lose）、`end_round_exhausted()`（fail）、目标达成（win）、硬币（coin_roll / coin_land / flip / heads / tails / click）、UI 按钮（click）。
- **`M` 键静音**（`Sound.toggle()`），静音时 HUD 右上角显示「已静音 · M 恢复」—— 无声状态下必须有个可见的出口，否则玩家会以为游戏坏了。
- **`_sfx/` 是试听目录，不是素材目录**：`tests/export_sfx.gd` 把每个音效导出成 wav 并自检（静音 / 削波），调完参数跑一次用耳朵校对。游戏运行时不读它们。
- ⚠️ Godot 4 的类名是 **`AudioStreamWAV`**（全大写），写成 `AudioStreamWav` 会编译报错。
- ⚠️ `--script` 模式下 autoload 在本脚本**编译之后**才挂载，所以工具脚本里不能直接写 `Sound.xxx`，要在运行时 `root.get_node_or_null("Sound")`。

**指针与悬停**：
- 锤子只在「鼠标就是你的身体」的那两段顶替系统箭头：敲猪（`playing`）和躲催债（`challenge`）。`sync_cursor()` 每帧同步 `Input.set_mouse_mode()`，并且**必须排在所有提前 return 之前** —— 翻账本时整局是停的（`_process` 直接 return），但箭头得还回来。
- ⚠️ **绝不能无条件隐藏系统光标**。序幕 / 卡片 / 结算 / 账本这些界面不画锤子，再把箭头藏掉就是一个指针都没有，玩家连「继续」都点不到；躲催债那关尤其致命——你得靠鼠标躲人却看不见自己在哪。`cursor_hidden` 同时是 `draw_hammer()` 的开关，保证「藏箭头」和「画锤子」永远是同一个条件，不会再分家。
- `balance.json` 的 `hammer_cursor: false` 可以彻底用回系统箭头（有人就是更习惯真指针；藏光标是氛围，不是必需）。
- 代价是**锤子会挡住按钮**，所以 `ui_hover_at(p)` 判断鼠标是否停在按钮上，`draw_hammer()` 据此把锤子缩到 0.68 并往右下偏移 (58, 46)，像"把手举起来让开"。
- `button()` 悬停时填色 `lightened(0.16)` + 一圈 2px 亮边（`panel()` 新增 `border` / `border_color` 参数）。隐藏光标之后，悬停高亮就是玩家唯一的位置反馈。
- `project.godot` 补了 `window/stretch/aspect="keep"`：之前只有 `stretch/mode`，拉窗口或全屏时画面会被拉变形。

### 3.8 桌上不止一种猪（`balance.json` 的 `pig_types`）

桌上是「七种存钱罐」，敲哪只成了每帧都要做的取舍：

| id | 名字 | 权重 | 锤数 | 面额 | 速度 | 体型 | 定位 |
|----|------|------|------|------|------|------|------|
| `piggy` | 白猪（粉陶） | 50 | 2 | +¥14 | 1.0× | 1.00 | 常见基础猪 |
| `stripe` | 花猪（蓝白搪瓷条纹） | 16 | 2 | +¥17 | 1.05× | 1.05 | 常见进阶收益 |
| `mini` | 青猪 | 15 | 1 | +¥9 | 1.85× | 0.70 | 一锤即碎，小而快 |
| `gold` | 金猪（哑光黄釉） | 11 | 3 | +¥34 | 1.30× | 1.16 | 高收益，需三锤 |
| `debt` | 黑猪（催债） | 10 | 1 | **-¥9** | 1.60× | 0.95 | 不是存钱罐：碎了要倒贴，别打 |
| `glass` | 玻璃猪 | 9 | 1 | +¥17 | 1.15× | 0.85 | 看得到罐内硬币，一锤即碎 |
| `fat` | 大肚猪（赤陶） | 7 | 4 | +¥36 | 0.70× | 1.30 | 慢、耐久高，收益也高 |

- **收益调整**：各猪种面额已上调（配置见下表），以减轻还债与达成本局目标的压力；黑猪仍是负收益风险猪，生成前要求余额达到 `min_score`。
- **判定跟着体型走**：命中判定是 `Vector2(84, 64) × (pig_size/138) × pig_scale(type)`，所以青猪真的比看起来更难打中、大肚猪更好打 —— 视觉和手感一致，不做"看起来小、实际判定一样大"的欺骗。整体尺寸那一项是"满桌小猪"加的：猪画小了判定必须跟着小（见 §5.1）。
- **黑猪的三条约束**（少一条都会变成坑）：
  1. `min_score: 15` —— 兜里没到 15 块时根本不会生成。否则开局第一锤就把人打成破产，纯属被系统坑。
  2. 倒贴用 `score = maxi(1, score + gain)` —— 最多把你打回「白干一场」，不当场破产。
  3. 双倍卡只放大正收益（`if gain > 0`），不放大损失：那张卡写的是"收益翻倍"，不是"损失翻倍"。
- **材质是哑光的**（`_ceramic()`）：`clearcoat = 0`（那道晃眼的清漆高光）、`metallic = 0`、`metallic_specular = 0.16`、`roughness` 0.5~0.68。这是陶土烧出来的存钱罐，不是电镀件。压完反光必须补 `rim = 0.07`（边缘补光），否则物体失去体积感、"糊"进背景。
- **视觉差异化**（`apply_type()`）：只改材质（身体 / 鼻耳腿尾 / 眼珠 / 腮红四色 + `roughness`）、整体 `_root3d.scale`，以及把投币口那枚币藏起来（黑猪头上不插币：它根本不是存钱罐）。**不重建整只猪** —— 重生时复用模型（当前 `respawn_seconds` 为 1.05）。
  - **花猪**：`striped: true`，`_stripe_texture(base, stripe)` 现场画一张双色条纹图（按颜色组合缓存）。贴图会**乘**在底色上，所以两种颜色都要传全，不能只给灰度。
  - **玻璃猪**：`glass: true` + `alpha`，`_glassify()` 打开 `TRANSPARENCY_ALPHA`，并把 `normal_enabled = false` —— 陶土颗粒法线会把玻璃糊成磨砂，里面的钱就看不见了。罐子里那堆钱是 `_build_inner_coins()` 造的 9 枚歪硬币，只有玻璃猪才 `visible`，并给了一点**自发光**（隔着半透明罐壁也看得见，靠的不是反光）。
  - ⚠️ 玻璃的透明度必须写进 `_base_color.a`（不只是材质）：`update_visual()` 每帧都拿 `_base_color` 覆盖材质颜色，只改材质的话第一帧之后就被刷回不透明。
- **2D 回退**（`draw_pig_flat()`）同样读 `pig.type`：颜色 + `pig_scale`，另外给花猪画三条竖道、给玻璃猪先画内部硬币再盖半透明罐壁。
- **裂纹按伤害画**：`dmg = max_hp - hp`，第一锤一道、第二锤两道。金猪（3 锤）能裂两次、大肚猪（4 锤）第三次还是两道，这就是"它还没碎"的进度提示。
- **学会规则靠反馈，不靠说明书**：碎金猪的音效是 `pop` 降调 + `coin_land`（金属余韵），碎黑猪是 `stamp` + `tails`（下坠音），飘字按种类上色（金 ¥ 亮黄、倒贴红 `-¥9`），粒子也按种类染色。
- **碎掉的是存钱罐，撒出来的是钱**（`spawn_particles()`）：一次爆裂 = **若干金币 + 若干陶片**，两者视觉上必须分得开：
  - 金币数跟面额走：`burst_coin_base`(5) + `value / burst_coin_per`(6)，封顶 `burst_coin_max`(10)。金猪碎一把钱、青猪叮当两声、黑猪（负收益）只有底数 —— 数量本身就是"这一锤值不值"的读数。
  - 金币用 `draw_coin_simple()`：**只画三笔**（边 + 面 + 一道内圈高光），不做齿边也不印"¥"。桌上那枚和抛起的硬币才用完整的 `draw_coin_face()`（12 颗齿边 + 文字）—— 它们在镜头前停着，飞出去的金币看不清细节，每枚省 13 次绘制，狂热时满屏金币才不会掉帧。
  - **横向必须有分量**：初速不能只用 `cos(均匀角度)`，那样大多数金币是直上直下的，屏幕上是一柱"喷泉"。现在是左右各 50% × `0.35~1.0` 的横向速度，钱才会往两边撒。`sx` 下限 0.36：翻到正侧面只剩一根竖条，看着像针不像钱。
  - 陶片是旋转的小四边形，颜色跟着猪的陶色走（金猪的陶片压暗到 `#c99a4a`，别和它自己撒出的金币抢眼）。
  - `MAX_PARTICLES`(70) 是逐颗判断的：一批就是十几颗，只在批次开始判一次能从 65 一口气冲过 70。
- **首次提示是分层的**（`note_pig_type()`）：开局那批只预警**会让你亏钱**的黑猪（不预警等于坑人）；其它六种等**重生**时才轮到介绍。提示排队显示，一条 2.8 秒，不做一次性糊一堆。文案在 `story.json` 的 `pig_tip_*`。
- **HUD 价目表**（`pig_legend()`）从 `pig_types` 直接生成，**但只列已经见过的那几种**，末尾还会写「还有 N 种没见过」。七种猪的名字加金额全排开这一行放不下（还会被锤子压住），而且一次全告诉你就没得发现了。它放在底部说明栏那一整行 —— 顶部中间只有 220px 宽。
- ⚠️ **顶部那条 HUD（`Rect2(52, 137, 1176, 98)`）横向已经排满了**：余额 / 敲碎数 / 中部提示 / 未付账单纸叠。纸叠右边原本还有一句「待还 ¥xxx」，正好压住中部提示的「中途」两个字，已删除（待还总额在账本封面和桌上那沓纸的「合计 ¥」上都有）。纸叠本身也压字，从 x=700 挪到了 x=880。**往这条里再加东西之前先算清楚宽度**，98px 高、一排字，没有第三行可以退。
- ⚠️ 测试必须隔离：老断言假设"每只猪两锤 +¥10"，随机种类会让它们随机失败。`tests/smoke.gd` 开头先 `game.settings["pig_types"] = []`（`pick_pig_type()` 会回退到 `pig_hp` / `points_per_pig`），新机制在文件末尾单独测。
- ⚠️ `pig.hp < settings.pig_hp` 这类写死 2 的写法全部改成 `pig.max_hp` —— 否则金猪的三锤永远显示不出裂纹、也不会变暗。
- ⚠️ `Dictionary.get()` 返回 `Variant`，在 `:=` 推断处会触发"Variant 类型推断"警告，而本项目**警告即错误**。取色一律写 `var raw: Variant = t.get(...)`。

### 3.9 账单压力系统（P1，`scripts/bill_manager.gd`）

账单不再只是"列表里的一笔钱"。没还的账单会**改规则**，还掉的那一刻规则恢复，还顺手给一点甜头。
数据全在 `data/bills.json`，代码不动就能调数值或关掉效果。

- **数据长这样**：`catalog` 的某一项加 `"id"` + `"effect_id"` 就成特殊账单，`effects` 段放参数（可只覆盖其中几项，整个段缺失也能跑）。
  - 电费 → `blackout`，信用卡还款 → `interest`，房租 → `collection`；其余 13 种照旧是普通账单（不带 `effect_id` = 普通，旧数据天然兼容）。
  - 生成时会带期数（「电费 第2期」），所以效果按 `id` 匹配而不是按名字 —— 期数不影响它照样停电。
- **效果来源每次都重算**（`sync(bills)`）：`main.gd` 的 `pay_bill()` 是"付完就 `remove_at`"，所以"哪个效果还在生效"只能按**剩余账单里还有谁带这个 effect_id** 来算，不能缓存一次就不管。好处是两条硬要求天然成立：付掉 3 张电费里的 1 张，灯还是黑的；还掉信用卡，它自己产生的利息一并作废，而别的卡的利息和滞纳金一根手指都不碰。
- **三种效果**：
  - **电费·停电**：`draw_blackout()` 把桌面压暗 + 一圈暗角，`blackout_fade` 在 0.6 秒内渐入渐出（任务书要求"平滑，避免闪烁"）。支付后给 8 秒挥锤冷却减免 10%（`cooldown_multiplier`）。
  - **信用卡·利息**：`finish_challenge(false)` 是全局唯一的考核失败结算点，所以"一次失败只计一次息"不需要额外去重。利息会并进**同一张**「信用卡利息」单，不每次都新开一张刷屏；单子上带 `source`（= 那张卡的 `id#户号`），还卡时按 `source` 精确清掉。
  - **房租·催收**：按**累计收入**跨阈值触发（阈值 100，每局最多 3 次，冷却 45 秒），只弹提示 + 盖章音效 + 红色警告，**不扣钱也不凭空生新猪**（避免和生成逻辑、经济平衡打架）。累计收入靠 `_process` 里盯 `score` 增量反推，不依赖每个加钱的地方都记得累加。
- **⚠️ 电费奖励不能是"回体力"**：`pay_bill()` 本来就返还 `pay_stamina_bonus`(18) 点体力，再补一次就是白给 —— 正好踩中任务书 §3.1 警告的重复叠加。所以奖励做成冷却减免。
- **⚠️ 暗化的绘制位置是硬要求**：`draw_blackout()` 必须紧跟 `draw_desk()`、画在 HUD 和小猪**之前**。盖在猪身上会遮挡要打的目标，盖在 UI 上会挡住按钮 —— 两个都不能碰。只压桌面反而让猪更显眼。
- **⚠️ 不要给 `bill_manager.gd` 加 `class_name`**：Godot 的全局类要等编辑器扫描刷新才认，而冒烟测试是 headless 直跑脚本，缓存没刷新就报 `Could not find type BillManager`。`main.gd` 用 `const BillManagerScript := preload(...)` 引用，永远稳。
- **⚠️ 缩进别用 tab**：`main.gd` / `bill_manager.gd` / `smoke.gd` 都是 4 空格。混一个 tab 进去，Godot 直接 `Parse Error: Used tab character for indentation`，而且报错行号指在第一个 tab 处、不告诉你有几处 —— 老老实实全文统一。

---

## 4. 文件结构

```
HammerPig/
├── project.godot          # 主场景 + 窗口配置
├── HANDOFF.md             # 本文档
├── export_presets.cfg
├── data/
│   ├── balance.json       # ★ 所有可调数值（唯一配置来源）
│   ├── story.json         # ★ 背景设定与全部叙事文案（序幕 / 赌徒提示 / 结算）
│   └── bills.json         # ★ 账单目录（水费/电费/燃气/房租…）+ 开局张数 + 账单效果参数（effects）
├── scenes/
│   └── main.tscn          # 只有一个 Node2D，挂 main.gd
├── scripts/
│   ├── main.gd            # ★ 全部游戏逻辑 + 全部绘制（单文件）
│   ├── bill_manager.gd    # ★ 账单效果（P1）：停电 / 利息 / 催收 的生效判定与事件，见 §3.9
│   ├── pig3d.gd           # ★ 3D 小猪存钱罐：程序化网格 + 每只猪一个 SubViewport
│   ├── desk3d.gd          # ★ 3D 赌桌背景：透视相机 + 屏幕像素反投影决定桌板尺寸
│   └── soundfx.gd         # ★ 程序化音效（autoload 名 `Sound`）：合成 buffer + 播放池 + 静音
├── tests/
│   ├── smoke.gd           # ★ 冒烟测试（当前 132 项断言，headless 跑）
│   └── export_sfx.gd      # 工具：把合成音效导出成 wav 到 _sfx/ 供试听（游戏不读它）
├── _sfx/                  # 试听用的 wav 导出（可随时删除，不是素材目录）
└── assets/
    ├── app_icon.png
    └── hit.wav            # 敲猪音效（唯一素材音；其余声音在 soundfx.gd 里合成）
```

---

## 5. 代码架构（scripts/main.gd）

单文件 Node2D，`_draw()` 用 `draw_*` 系列 API 手绘整个画面。

### 5.1 关键成员变量

```gdscript
score           # 余额/积分/金币（经济核心，唯一）
phase           # 状态机：playing/card/challenge/finished/bankrupt
next_card       # 下一次出卡阈值（开局 = card_first_at，每出卡 +card_interval）
card_delay      # 卡片的半秒缓冲：>0 表示已达标但还没弹（见 §3.6）
card_type       # 当前卡片类型："reward"/"double"/"collect"/"dodge"
story / unpaid_bills / intro_open   # 背景叙事：文案字典 / 未付账单张数 / 序幕是否正在显示
bill_data / bills / paid_count      # 账单：目录 / 当前账单（按金额升序）/ 本局已还张数
bill_open / bill_page / bill_detail # 账单界面：账本是否摊开 / 第几页 / 正在放大第几张（-1=没开）
gamble_state / gamble_t            # 那枚硬币：none/ready/flip/result / 滚入与抛的动画计时
gamble_heads / gamble_used         # 这一抛是正面吗 / 本局是否已经赌过（赌过就没了）
challenge_streak  # 连续考核卡计数（保底用）
bill_amount / bill_time / bill_timer   # 账单金额 / 限时 / 剩余
collected       # collect 小游戏已凑金额
coins[]         # collect 小游戏的金币/假币
double_timer    # 双倍卡剩余时间（>0 时敲猪收益 ×2）
dodgers[]       # dodge 小游戏的催债图标
dodge_lives / invincible_timer  # dodge 命数 / 被撞后无敌时间
stamina / stamina_flash  # 体力值 / 体力不足闪烁计时（第一轮并入）
end_reason       # 结算原因："target"=达标胜利 / "exhausted"=体力耗尽
combo_count / combo_timer / combo_max   # 连击数 / 连击窗口计时 / 本局最高连击
shake / shake_x / shake_y   # 桌面震动剩余时间 / 当前帧偏移
pig3d[] / use_3d   # 每只猪一个 Pig3D（SubViewport），数量 = pig_rows × pig_cols / 是否启用 3D 小猪
desk3d / use_desk_3d   # 3D 赌桌 SubViewport / 是否启用 3D 桌面（可单独关，保留 3D 猪）
```

`pigs[]` 字典字段：`position / hp / respawn / flash / hop / seed / velocity`（`velocity` 与 `hop` 为猪游走与受击跳动所用）；游走范围由常量 `PIG_BOUNDS = Rect2(270, 320, 740, 310)` 限定。

⚠️ `PIG_BOUNDS` 现在有**两个用途**：限制猪的游走 + 反投影出 3D 桌板的大小。3D 化时为了"视角放远、桌子四周露出来"，它从 `Rect2(210,330,860,270)` 收窄到过 `(270,350,740,230)`；满桌小猪之后纵向又撑回 310（3 行猪要铺满整张桌子，挤在中间一条带子里看不出"满桌都是猪"）。再改它，桌子会跟着变大变小。

**满桌小猪（密度三件套）**：`pig_rows` / `pig_cols` / `pig_draw_size`，全在 `balance.json`，改配置就换密度，不用碰代码。

- 生成按网格均分：`PIG_BOUNDS.position + (index + 0.5) * size / count`，不再写死 `300 + col * 225` 这种坐标。
- `pig_size()` 是绘制边长，**判定、阴影、裂纹、受击抖动全部按它等比缩放**（`pig_size() / PIG3D_SIZE`）。只改绘制不改判定，就会变成"看着小、其实判定还是原来那么大"，还会跟邻居的判定打架。
- **`separate_pigs()` 不能省**：一群没有碰撞的猪随机游走，几十秒后必然漂成一坨，桌面上只剩一团猪。它给一点互相排斥的力道（`min_dist = 76 × 尺寸比例`，系数 2.6），O(n²)，18 只 = 324 次/帧。实测跑满两秒后任意两只猪的间距仍 > 35px。
- **`Pig3D.VIEW_SIZE` 从 256 降到 160**：猪在屏幕上只画 92px，256 是纯浪费；而 18 只 × 256² × `UPDATE_ALWAYS` 一帧要渲 1.2M 像素。160 下总渲染量仍比原来 8 只 × 256 更小，实测 140+ fps（6.7ms/帧）。

### 5.2 关键函数

| 函数 | 作用 |
|---|---|
| `reset_game()` | 重置整局（R 键 / 结算按钮） |
| `strike(point)` | 挥锤判定：命中扣血，敲碎 +收益（双倍卡时 ×2）、触发出卡/胜利 |
| `open_card()` | 开卡：`roll_card()` 决定类型、**`phase = "card"`**。由 `_process()` 在 `card_delay` 归零时调用，不在得分那一帧 |
| `roll_card()` | 加权随机 + 保底，返回 `card_type` |
| `is_challenge(t)` | 判断是否是考核卡（collect/dodge） |
| `apply_card()` | 处理卡片：reward→+¥、double→开双倍、考核→`start_challenge()` |
| `start_challenge()` | 进入 challenge，按类型初始化状态 |
| `finish_challenge(success)` | 结算小游戏：成功 +reward / 失败扣钱（≤0→bankrupt） |
| `update_collect(delta)` | collect 小游戏每帧：刷金币、移动、判定胜负 |
| `update_dodge(delta)` | dodge 小游戏每帧：刷催债、追踪鼠标、碰撞扣命、判定胜负 |
| `spawn_coin()` / `spawn_dodger()` | 生成金币 / 催债图标 |
| `click_coin(point)` | collect 小游戏点击金币 |
| `random_pig_velocity()` | 生成小猪游走速度：随机方向 × `pig_speed` × 0.7~1.3 |
| `end_round_exhausted()` | 体力见底结算：`end_reason = "exhausted"`、`phase = "finished"`（余额保留，不算破产） |
| `draw_pig(pig, index)` | 3D 开启时贴该猪 SubViewport 的纹理（含桌面投影、裂纹叠加）；否则转 `draw_pig_flat()` |
| `draw_pig_flat(pig)` | 原始的 2D 自绘小猪（`pig_3d: false` 或 headless 时的回退） |
| `Pig3D.update_visual(pig, elapsed)` | 3D 猪每帧：呼吸起伏、受伤变暗、被打闪白、朝向随游走速度偏转 |
| `_draw()` + `draw_*` | 全部画面绘制 |

### 5.3 如何新增一种卡片 / 小游戏（扩展配方）

接手后最可能的扩展方向，照这个 checklist 做：

1. 在 `balance.json` 加新类型权重（若是考核还要加它的参数）。
2. `roll_card()` 里纳入新类型。
3. `is_challenge()` 若是考核卡则返回 true。
4. `apply_card()` 里加分叉（奖励卡）；`start_challenge()` 里初始化状态（考核卡）。
5. 若是考核小游戏：加 `update_xxx(delta)`，并在 `_process()` 的 challenge 分支调用。
6. 加 `draw_xxx()`，并在 `_draw()` 的 challenge 分支调用；若是卡片外观，在 `draw_card()` 里给 `card_type` 补一套 `title / accent / label / hint` 和内容分支即可（外壳与徽章复用 `card_shell()` / `card_badge()`）。
7. 若小游戏需要点击，在 `_unhandled_input()` 的 challenge 分支处理。
8. 在 `tests/smoke.gd` 加断言。

### 5.4 猪游走与耐力（第一轮并入，默认开启）

**猪游走**：`_process()` 的 `playing` 分支里，满血的猪按 `velocity` 移动，越界即反向并夹回 `PIG_BOUNDS`；被敲碎时停止移动，`respawn_seconds` 后重生并重取一个随机方向。受击时 `hop = 0.24`，`draw_pig()` 按 `sin` 抬起一段（纯视觉）。移动之后紧跟 `separate_pigs(delta)` —— 猪之间互相推开，否则会漂成一坨（见 §5.1「满桌小猪」）。

**耐力**：`strike()` 先检查 `stamina >= stamina_cost`，不足则弹「体力不足」并调用 `end_round_exhausted()`；足够则先扣体力再做命中判定（**空挥也扣**）。`_process()` 的 `playing` 分支兜底再查一次。`draw_finished()` 按 `end_reason` 区分「摆脱破产！」与「体力耗尽！」。

**关闭方式**：`pig_speed` 设 `0` 即静止；`stamina_max` 调得远大于一局的挥锤总数即等于取消体力限制。

---

## 6. balance.json 字段说明（当前值）

> **叙事文案不在这里**，另见 `data/story.json`：`intro_*` 开场序幕 / `gamble_*` 赌徒提示 / `win_*` `lose_*` `exhausted_*` 结算，见 §3.3。
> **账单数据也不在这里**，见 `data/bills.json`：`catalog`（账单名与金额）、`start_count`（开局张数）、`pay_stamina_bonus`（还一张回的体力）。

```jsonc
// —— 敲猪核心 ——
"pig_hp": 2,              // 每只猪血量（2 锤敲碎）
"points_per_pig": 10,     // 敲碎一只的基础收益
// —— 满桌小猪（见 §5.1）——
"pig_rows": 4,            // 摆几行（和 pig_cols 相乘 = 桌上总只数）
"pig_cols": 6,            // 每行几只
"pig_draw_size": 92,      // 一只猪画多大（像素）。判定/阴影/裂纹都按它等比缩，改小才塞得下更多
"respawn_seconds": 1.05,  // 猪重生时间
"swing_cooldown": 0.18,   // 挥锤冷却
// —— 出卡 / 目标 ——
"card_first_at": 160,     // 第一张奖励构筑卡出现的余额阈值
"card_interval": 135,     // 后续奖励构筑卡的余额间隔
"card_pop_delay": 0.45,   // 达标后半秒才弹卡：等爆钱的反馈播完（见 §3.6）
"round_target": 950,      // 胜利目标（摆脱破产）
"max_challenge_streak": 2,// 连续考核卡上限（保底）
// —— 账单 / 考核通用 ——
"bill_amount": 50,        // 账单金额（失败扣这么多）
"bill_time": 55.0,        // 考核小游戏限时（秒）
"bill_reward": 25,        // 考核通关奖励
// —— 奖励卡 ——
"reward_card_amount": 35, // 现金奖励 +¥
"double_duration": 15.0,  // 双倍卡持续秒数
// —— 限时凑钱(collect) ——
"coin_value": 5,          // 每个金币价值
"coin_spawn_interval": 0.55, // 金币刷新间隔
"coin_fake_chance": 0.3,  // 假币概率
// —— 躲催债(dodge) ——
"dodge_lives": 3,         // 命数
"dodger_speed": 170.0,    // 催债逼近速度
"dodger_spawn_interval": 0.8, // 催债刷新间隔
"dodge_invincible": 0.6,  // 被撞后无敌时间
// —— 出卡概率权重 ——
"reward_weight": 40,
"double_weight": 15,
"collect_weight": 25,
"dodge_weight": 20,
// —— 连击 / 屏幕震动（第三轮新增）——
"combo_window": 1.5,          // 连击窗口（秒），超时未命中则连击清零
"combo_threshold_fever": 5,   // 连击达此值触发「狂热」额外粒子
"shake_duration": 0.12,       // 敲碎猪时桌面震动持续（秒）
"shake_intensity": 4.0,       // 震动最大像素偏移
// —— 碎猪爆金币（见 §3.8）——
"burst_coin_base": 5,         // 爆裂时的金币底数
"burst_coin_per": 6,          // 每多值这么多钱，多撒一枚金币
"burst_coin_max": 10,         // 单次爆裂的金币上限
"burst_shards": 8,            // 陶片数量
"combo_pitch_step": 0.05,     // 每级连击抬升的音调（封顶 1.5）
// —— 猪游走 / 耐力（第一轮并入，默认开启）——
"pig_speed": 70,          // 小猪游走速度（像素/秒）；设 0 = 静止
"stamina_max": 260,       // 体力上限
"stamina_cost": 2.0,      // 每挥一锤消耗的体力；见底则本轮结束
"pig_3d": true,           // 小猪用 3D 渲染；false 回退 2D 自绘（headless 下自动 false）
"desk_3d": true,          // 桌面用 3D 赌桌；false 回退 2D 的绿绒桌面 + 金线
"watchers": 8,            // 桌后那群黑影的人数（0 = 全都没有，1~12 比较合适）
"gamble_threshold": 475,  // 攒到这个数，桌边滚来一枚硬币：正面翻倍 / 反面清零（必须 < round_target）

"pig_types": [            // 猪的种类表（见 §3.8）。清空 = 回退到 pig_hp / points_per_pig 的老行为（测试用）
  { "id": "piggy",  "label": "白猪",   "weight": 50, "hp": 2, "value": 14, "speed": 1.0,  "scale": 1.0 },
  { "id": "stripe", "label": "花猪",   "weight": 16, "hp": 2, "value": 17, "speed": 1.05, "scale": 1.05, "striped": true },
  { "id": "mini",   "label": "青猪",   "weight": 15, "hp": 1, "value": 9,  "speed": 1.85, "scale": 0.70 },
  { "id": "gold",   "label": "金猪",   "weight": 11, "hp": 3, "value": 34, "speed": 1.30, "scale": 1.16 },
  { "id": "debt",   "label": "黑猪",   "weight": 10, "hp": 1, "value": -9, "speed": 1.60, "scale": 0.95, "min_score": 15 },
  { "id": "glass",  "label": "玻璃猪", "weight": 9,  "hp": 1, "value": 17, "speed": 1.15, "scale": 0.85, "glass": true },
  { "id": "fat",    "label": "大肚猪", "weight": 7,  "hp": 4, "value": 36, "speed": 0.70, "scale": 1.30 }
]
```

`pig_types` 每一项还带视觉字段：`color` / `accent`（鼻耳腿尾）/ `eye` / `blush` / `rough`，以及三个开关——`striped`（搪瓷条纹，配 `stripe` 色）、`glass`（半透明罐身，配 `alpha`）、`min_score`（兜里到这个数才会出现）。`value` 为负 = 敲碎要倒贴。

> 全部是哑光材质（`metallic = 0`、`clearcoat = 0`）：这是陶土罐子，不是电镀件。别再往配置里加 `metallic` 来"显得值钱"，金猪是靠颜色笑的，不是靠反光。

> 所有数值改这里即可，游戏和测试都会自动读取。JSON 数字会被 Godot 解析成 float，代码里已用 `int()`/`float()` 显式转换。

---

## 7. 测试（tests/smoke.gd）

`extends SceneTree`，headless 无窗口运行。用 `check(ok, msg)` 做断言，失败即 `push_error` + `quit(1)`。

覆盖链路：敲猪基础（打空/打裂/打碎/防连击/重生）→ 奖励卡与小游戏逻辑 → 账单支付/逾期 → 破产与重置 → 双倍卡 → 躲催债 → 胜利 → 连击 / 震动 → 猪游走与体力 → 账单压力效果 → 猪群翻倍及重开恢复。

**测试里强制指定 `game.card_type` 来绕过随机出卡**，保证确定性。例如：

```gdscript
game.card_type = "collect"
game.phase = "card"
game.apply_card()
```

---

## 8. 各轮改动总结（历史记录）

> 本节记录各阶段当时的实现与数值；不代表当前配置。当前数值和玩法以 §3.1、§3.2、§3.5、§3.8、§6 及 `data/*.json` 为准。

### 8.1 第二轮（梅泽伟）

最初原型只有一个「敲猪 → 积分 → 空白卡占位 → 满 120 分完成」的骨架。本轮改动：

1. **经济模型**：`score` 语义从「积分」改为「余额/金币」，开局 ¥0，UI 文案改为「余额 ¥」。
2. **卡片系统**：空白卡 → 4 种真实卡片（2 奖励 + 2 考核小游戏）。
3. **考核小游戏**：新增「限时凑钱」「躲催债」两套完整的 update/draw/点击逻辑。
4. **双倍卡**：新增 `double_timer`，`strike()` 里收益 ×2，顶部显示绿色倒计时。
5. **破产结算**：新增 `bankrupt` 阶段 + `draw_bankrupt()`；`finished` 改为「摆脱破产」胜利文案。
6. **配置化**：`balance.json` 从 6 个字段扩到 23 个。
7. **测试**：从 21 断言扩到 26 断言。

### 8.2 第三轮（范云娜，进行中）

在第二轮基础上做增量，**只动体验层，不动经济数值**：

1. **连击系统**：新增 `combo_count / combo_timer / combo_max`。`strike()` 命中时累加连击，`combo_window` 秒内不再命中则清零。
2. **屏幕震动**：新增 `shake / shake_x / shake_y`。敲碎猪时触发，`_process()` 里按 `shake_duration` 衰减，桌面面板、木纹、猪、粒子整体跟随偏移。
3. **狂热模式**：连击 ≥ `combo_threshold_fever` 时额外喷 3 团粒子，中央显示「狂热！」。
4. **连击 UI**：中央浮动「连击 ×N」，字号随连击增大，透明度随 `combo_timer` 衰减；≥ 狂热阈值转绿色。
5. **音调渐变**：`sound.pitch_scale` 随连击升高（每级 `combo_pitch_step`，封顶 1.5）。
6. **新增辅助函数**：`draw_pig_shaken(pig)`——统一处理活猪 / 死猪的震动偏移绘制。
7. **配置化**：`balance.json` 加 5 个字段（见 §6）。
8. **测试**：从 26 断言扩到 **33 断言**（新增 7 条连击 / 震动断言）。

> ⚠️ **连击不参与收益计算**（`gain` 仍为 `points_per_pig`），纯视觉反馈。这样避免破坏第二轮的经济平衡与既有断言。若日后想让连击影响收益，改 `strike()` 里 `var gain` 一行即可。

### 8.3 合并：第一轮的猪游走与耐力系统并回主干

`qiaozhu-main` 与 `smash-the-pig-cs2403` 是同一工程的前后两个包：前者保留第一轮原型独有玩法，后者含第二、三轮成果。已把前者独有的两项并入当前主干（默认开启）：

1. **猪游走**：新增常量 `PIG_BOUNDS`（围栏，并入时为 `Rect2(210,330,860,270)`，3D 化后收窄为 `Rect2(270,350,740,230)`，见 §5.1）与 `random_pig_velocity()`；满血的猪在围栏内游走、碰壁反弹，破碎时静止、复活时换方向。
2. **耐力系统**：新增 `stamina / stamina_flash / end_reason` 与 `end_round_exhausted()`；每挥一锤扣 `stamina_cost`，不足时弹「体力不足」并结束本轮，结算页显示「体力耗尽！」（余额保留、不算破产）。
3. **配置化**：`balance.json` 加 3 个字段（见 §6），从 28 个扩到 **31 个**。
4. **测试**：从 33 断言扩到 **39 断言**（新增 2 条游走、4 条体力断言）。
5. **数值取舍**：第一轮原 `stamina_cost` 为 10（只够挥 10 锤 ≈ ¥50），与现有 ¥120 目标冲突，已改为 **4**（25 锤 ≈ ¥120，恰好卡住通关线）。想放松就调小 `stamina_cost` 或调大 `stamina_max`。

> ⚠️ 游走与体力都会改变手感：猪会跑、锤数有上限。后续做 3D 化（§9）或改经济数值时，要重新评估 `points_per_pig / round_target / stamina_cost` 三者的平衡。

### 8.4 第四轮：三处手感修补（旧版记录）

1. **弹卡别抢戏**：越过阈值后不立刻弹卡，先加 `card_pop_delay`(0.45s) 缓冲，让"猪碎 → 钱票飞起 → +¥ → 粒子 → pop/cash"这套反馈播完。⚠️ 缓冲块必须排在 `cooldown/swing/double/combo` 之后 `return`，否则半秒内挥不出第二锤；同时要在 `update_gamble()` 之后，抛硬币时一起暂停。⚠️ 别靠堆高 `card_first_at` 来"延后"——70/45 会让第二张卡落在 115，而 120 就结算，一局只剩一张卡。
2. **碎猪撒真钱**：`spawn_particles()` 从"16 个圆点涂金"改成"金币数随面额 + 陶片"，金币三笔画法，横向初速左右各 50%（否则是一柱喷泉）。见 §3.8。
3. **满桌小猪**：`pig_rows`/`pig_cols`/`pig_draw_size` 配置化，默认 3×6=18 只、每只 92px；判定/阴影/裂纹按尺寸等比缩；`separate_pigs()` 防止几十秒后漂成一坨；`Pig3D.VIEW_SIZE` 256→160（18 只 × 256² 会掉帧）。见 §5.1。
4. **顶部 HUD 去掉「待还 ¥」**：它和纸叠一起压住了中部提示的「中途」两个字，详见 §3.8 的 ⚠️ 条目。

### 8.5 P1：账单压力系统（`bill_manager.gd`，初版记录）

按 `HammerPig_WorkBuddy_开发任务书.md` 做的最小可玩版本：**账单不只是要还的钱，它会改你正在玩的游戏**。详细机制见 §3.9，这里只记决策：

1. **数据驱动**：`bills.json` 的 `catalog` 项加 `id` + `effect_id`，`effects` 段放参数；不带 `effect_id` 的仍是普通账单（13 种），旧数据零改动可读。
2. **效果来源每次重建**（`sync(bills)`）而不是维护 activate/deactivate 状态机 —— 因为 `pay_bill()` 会 `remove_at`，按"剩余账单里还有谁带这个 effect_id"算，才能保证"付一张电费不会解除另一张电费"、"还卡只清自己的利息"。
3. **电费**：桌面压暗 + 暗角（0.6s 渐入），付后 8 秒冷却减免 10%。⚠️ 奖励不能是回体力，`pay_bill()` 已经返还 18 点。
4. **信用卡**：只在 `finish_challenge(false)` 计息，利息并进同一张单、带 `source` 回溯。
5. **房租**：按累计收入跨阈值催收，每局 ≤3 次、冷却 45s，只提示不扣钱（避免和生成逻辑/经济平衡打架）。
6. **测试**：109 → **127 断言**（电费激活/解除/余额不足、利息一次性与来源归属、还卡清息不误伤滞纳金、催收阈值/冷却/上限、重开重置）。

> 验收状态：自动化断言全过；暗化与满桌小猪用窗口截图目视确认；**未做人工完整试玩**（任务书 §5 的"手动测试"只完成了截图这一部分）。

---

## 9. 3D 视口实现（小猪、桌面与锤子）

> 当前版本已将存钱罐、赌场桌面和第一人称锤手接入独立 3D 视口；卡片和账单等界面仍由 2D 自绘。小猪的程序化网格实现细节记录在本节，桌面与锤手当前结构见 §3.5。
>
> **当前状态：已接入并实测出图。** 因本机没有 Blender、也没有现成 `.glb`，采用**程序化网格**方案：
> `scripts/pig3d.gd` 用 Godot 内置图元拼出**小猪存钱罐**（不是活猪）：陶瓷釉面圆罐体（`clearcoat` + 低粗糙度）、顶部投币口 + 插着的金色硬币、短圆猪鼻 + 两个鼻孔、压扁小球做的耳朵、腮红、四条短粗腿、卷尾、带高光的黑眼睛。
> 表面不是完美光滑：`_grain_texture()` 用 `FastNoiseLite` 的梯度**现场算一张法线贴图**（128×128，`strength 1.5`），配 `normal_scale 0.2` 做轻微釉面起伏 —— 注意别调大，超过 0.5 会变成毛绒/砂纸质感。
> 腿的衔接：腿高 0.52、中心 `y = -0.69`，把上半截埋进罐体（罐底约 `-0.78`），只在外面露出约 0.17，所以看不到接缝、也不像桌腿。
> 每只猪一个 `SubViewport`（256×256，正交相机略微俯视 + 主光/补光），`main.gd` 的 `draw_pig()` 把 viewport 纹理贴到 `pig.position`（`PIG3D_SIZE = 138`，阴影半径 / 受击跳动 / 裂纹坐标都按 `PIG3D_SIZE / 190` 等比缩放）。
> 开关为 `balance.json` 的 `pig_3d`（headless 下自动关闭，回退 `draw_pig_flat()` 的 2D 自绘）。
> 后续若拿到 `pig.glb`，只需把 `_build_bank()` 里的图元换成 `load("res://assets/pig.glb").instantiate()`，其余（相机/灯光/纹理贴图/动画）不用动。
>
> **三个踩过的坑（改这块必看）**：
> 1. `SubViewport` 必须 `own_world_3d = true`，否则父节点是 2D、没有 3D 世界，猪不会渲染。
> 2. 灯光/相机在 `add_child()` 之前不能调 `look_at()`（报 `Node not inside tree`），要用 `look_at_from_position()`。
> 3. 相机若与罐体几乎等高，看不到罐顶的投币口，硬币会像“顶在头上的小黄点”；相机 `y ≈ 0.75` 略微俯视才有存钱罐的辨识度。
>
> **3D 赌桌（`scripts/desk3d.gd`，同批实现）**：全屏 `SubViewport`（1280×800），`_draw()` 用 `draw_texture()` 贴在最底层，`desk_3d: false` 时回退 2D 的绿绒桌面。桌面材质与装饰见 §3.5。
> - **为什么用透视相机**：正交投影下无论把相机拉多远都不会有"远近"变化，桌子像贴脸的面板；透视才有纵深收敛，桌腿和地板才进画面。代价是矩形桌板在屏幕上变成梯形、不能再靠线性换算对齐，改用 `_screen_to_desk()`：`project_ray_origin/normal` 与桌面平面 `y=0` 求交，把**屏幕像素**精确反投影成桌面世界坐标。
> - **桌板大小由猪活动区决定，不是 `DESK_RECT`**：`_desk_frame()` 把 `PIG_BOUNDS.grow(76)` 的屏幕矩形反投影、取外接矩形当桌板世界尺寸。所以不管 `PITCH / FOV / CAM_DIST` 怎么调，桌板都恰好盖住猪的活动区，猪不会跑到桌子外。
> - **相机参数**：`PITCH 45°`、`FOV 30°`、`CAM_DIST 16`。⚠️ 俯角调到 40° 以下，桌板近端会被透视放大得过头、下沿顶到屏幕底部压住说明文字；`FOV` 越大近端放大越猛（38° 时左右会铺满整屏）。
> - **性能**：桌子是静止的，渲染模式设为 `UPDATE_ONCE`（只画一帧），比猪那些每帧都要更新的 viewport 省得多。
> - **木纹**：`FastNoiseLite` 现场生成 256×256 贴图（年轮条纹 + 纤维噪声），`uv1_scale` 控条纹疏密与方向；扭曲幅度（`warp`）超过 2 会变成“蛇皮”，`rings` 的 `pow` 指数太大则像百叶窗。
> - **桌面上没有围栏**（曾经有过四根木条的猪圈，已按要求去掉）：猪直接在桌面上游走，靠 `_desk_frame()` 里那圈 `grow(76)` 余量（猪半径约 69px）保证猪不会踩到桌沿外。
> - 桌面没有边界线，所以 `PIG_BOUNDS` 只影响猪能走多远，视觉上看不出硬边；想再收一点游走范围时直接改它即可（桌板会跟着一起变）。
> - 底部两行说明文字下面压了一条半透明暗底（`Rect2(0,702,1280,98)`，在 `main.gd` 的 `_draw()` 里），3D 桌板/地板是暖色，浅色小字直接压上去看不清。

### 9.1 早期方案比较（历史记录）

| 方案 | 工作量 | 结论 |
|---|---|---|
| 全量 3D（猪+锤+桌面+卡牌+UI） | 15–20 天，且会清空第三轮刚做的连击 / 震动绘制 | ❌ 不划算 |
| **仅小猪 3D + 其余 2D** | **5–6 天** | ✅ 推荐 |
| 保持全 2D 自绘 | 0 天，但缺质感 | 保守方案 |

「3D 角色 + 2D UI」是成熟混搭风格（如《星之卡比 探索发现》《塞尔达传说 织梦岛》），**比全 3D 更有记忆点**。

### 9.2 当前 3D 视口结构

```
HammerPig（Node2D，main.gd）
├── 每只猪 → Pig3D / SubViewport(192×192)
│                ├── Camera3D + 灯光
│                └── 程序化存钱罐网格
├── Desk3D / SubViewport（赌场桌面）
└── Hammer3D / 透明 SubViewport（俯视锤头与手）
```

- 每只猪一个 viewport，`UPDATE_ALWAYS`；默认 24 只，猪群翻倍后最多 48 只。翻倍卡同时缩小猪的绘制尺寸，但会增加视口渲染负载；低配设备上应实际测帧率。
- 每只猪可独立做呼吸 / 被砸缩放 / 破裂动画
- 与第三轮新增的 `shake_x / shake_y` 自然叠加

### 9.3 主要渲染接缝（当前实现）

| 位置 | 当前实现 | 说明 |
|---|---|---|
| `draw_pig(pig, index)` | 取该猪 SubViewport 的纹理绘制到 `pig.position` | `draw_pig_flat()` 保留作 2D 回退 |
| `draw_pig_shaken(pig, index)` | 绘制猪纹理并叠加 `Vector2(shake_x, shake_y)` | 与桌面震动同步 |
| `_ready()` / `reset_game()` | 创建基础 `Pig3D` 视口并清除多余实例 | 翻倍卡新增的视口在重开时移除 |
| `pig` 字典 | 保存 `position/hp/flash/hop/respawn/seed/velocity` | 逻辑状态与视口分离，猪重生时复用视口 |

**必须保留、不可改的行为**（当前冒烟脚本覆盖 132 项断言）：
- `pig.hp`（2 血）、`pig.flash`（被砸闪白）、`pig.respawn`（重生计时）
- `pigs` 数组结构与坐标 `Vector2(300 + col*225, 350 + row*190)`
- `strike()` 的椭圆命中判定（`/ Vector2(84.0, 64.0)`）
- `combo_count / shake_x / shake_y` 的联动

### 9.4 初版建模计划（历史记录，已由程序化网格实现）

| 天 | 任务 | 产出 |
|---|---|---|
| 1 | Blender 做**一只**猪低模（球体+鼻子+耳朵+腿），粉色，UV 分组 | `pig.glb` |
| 2 | Godot 最小验证：1 个 SubViewport + Camera3D + 光照，猪能转起来 | 单猪场景跑通 |
| 3 | 做 3 个动画 clip：呼吸 / 被砸缩放 / 破裂 | `AnimationPlayer` |
| 4 | 复制成 8 只，改 `draw_pig` 与 `draw_pig_shaken` | 8 只 3D 猪上桌 |
| 5 | 对齐光照方向、阴影、碎裂粒子；跑 39 测试确认无回归 | `ALL 39 CHECKS PASSED` |
| 6 | 重新导出 Win / Mac 包 | `04-可直接游玩/` 更新 |

### 9.5 风险与注意

- ⚠️ **headless 测不到画面**：`_draw()` 与 3D 渲染在 headless 下都不执行，改完必须**开窗口肉眼检查**。
- ⚠️ 3D 渲染改动不应破坏 `score / phase / hp / stamina` 等逻辑；运行当前冒烟脚本检查回归。
- ⚠️ **猪现在会跑**：3D 化后 `draw_pig` 仍读 `pig.position`，游走逻辑在 `_process()` 里，不要为了 3D 而把猪钉死在原位。
- 若 Blender → Godot 管道出坑（法线翻转 / scale / 阴影），**第 1 天就会暴露**，不影响主线推进。
- 导出前确认 `assets/` 里的 `.glb` 与 `.import` 已生成，否则打包后猪是空的。

---

## 10. 未来规划（尚未实现，按优先级排序）

1. **破产 → 传承点 / 永久升级**（最贴近原作灵魂）：破产结算时给「传承点」，买戒指/手镯等永久属性，下局更强。
2. ~~**耐力系统**~~：**✅ 已实现**（见 §8.3）：每挥一锤扣 `stamina_cost`，见底结束本轮。剩余方向是「耐力随时间恢复」和「耐力上限 / 消耗做成升级卡」。
3. **多种存钱罐**：会逃跑的、不动的、藏大量黑钱的（对应多种猪）。
4. **多种大锤**：暴击概率 / 攻击范围 / 攻速差异。
5. **技能树**：握力、咖啡因、练腕、运气等分支。
6. **更多考核小游戏**：候选有「找假账单」（几张账单点出金额算错那张）、「心算还债」（找零选择题）。
7. **更多奖励卡**：候选有「折扣券」（下次账单减半）、「加时券」（下次考核 +5 秒）。

---

## 11. 给下一个 AI 的接手提示

- **改玩法数值**：只改 `data/balance.json`（现 31 个字段），不用动代码。`pig_speed`（设 0 猪静止）、`stamina_max`、`stamina_cost` 控制游走与耐力手感。
- **改画面**：所有绘制在 `main.gd` 的 `draw_*` 函数；注意 headless 测不到 `_draw`，改完要开窗口看。
- **小猪 3D 化**：按 §9 的接入指南做，只换 `draw_pig` / `draw_pig_shaken` 的渲染方式，不许动逻辑层。
- **改/加小游戏**：严格按第 5.3 节的扩展配方做，每加一个都要同步更新 `tests/smoke.gd`。
- **改声音**：全部配方在 `scripts/soundfx.gd` 的 `_build()`，改完跑 `tests/export_sfx.gd` 导出 wav 用耳朵校对；`Sound.play(name, pitch, gain)` 是唯一入口，`crack` 例外走素材 `hit.wav`。
- **跑测试**：用第 2 节的 headless 命令；最近一次结果为 `ALL 132 CHECKS PASSED`。
- **不要**在对话里依赖任何「Claude 记忆」——本项目的全部上下文都在这份 HANDOFF.md 和代码注释里。
