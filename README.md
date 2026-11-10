# 敲猪还债 HammerPig

Godot 4.7.2 course project. Open `project.godot` in Godot to import the project. Press **F5** to run the game or **F6** to run the main scene.

## Gameplay

Earn money by striking moving piggy banks, choose reward upgrades, and manage bills as their due dates approach. Unpaid bills can trigger gameplay effects such as a blackout, credit-card interest, and rent collection. The project also includes stamina, combos, coin-flip rewards, and challenge cards.

## Project contents

- `scripts/` game logic and procedural 3D pig, hammer, and table rendering.
- `data/` balance, bill, and story configuration.
- `scenes/` Godot scenes.
- `assets/` application icon and hit sound.
- `tests/` smoke-check and sound export scripts.
- `HANDOFF.md` implementation notes and development handoff details.

## Smoke checks

Run the checks with the Godot 4.7.2 console executable:

```powershell
& 'path-to-Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/smoke.gd
```

The last recorded result in the source project is 132 checks passed on 2026-11-02. Headless checks do not validate rendered visuals or play feel; inspect those in a windowed run.

## 卡片构筑 2.0（待引擎验收）

新增代价卡、重复选择进化卡和任务成长卡；游玩时按 `C` 暂停并查看等级与任务进度。
详见 [模块交接](docs/card-build-2.0.md) 与 [施晨煜个人工作记录](docs/lucian-contribution.md)。
新增测试：`godot --headless --path . --script res://tests/card_build.gd`。
本轮仅通过静态语法检查，尚未运行引擎测试；中文字体显示问题仍待修复。
