extends SceneTree

## 临时截图工具：开场小剧情 + 新手引导的画面状态各存一张 PNG。

var game

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# 序幕现在是多页剧情：第一页（房东催租）
	game.story_t = 999.0
	await snap("tmp_story_page1.png")
	# 翻到第三页（老板教学）
	game.story_page = 2
	game.story_t = 999.0
	await snap("tmp_story_page3.png")
	# 标题页（原来那张海报）
	game.story_page = 99
	await snap("tmp_story_title.png")
	# 进游戏：教学第一步（瞄准），把鼠标挪开远处
	game.intro_open = false
	game.tutorial_step = 1
	Input.warp_mouse(Vector2(1100, 700))
	await snap("tmp_tutorial_aim.png")
	# 教学第二步（蓄力）：鼠标放到目标猪上
	game.tutorial_step = 2
	Input.warp_mouse(game._tutorial_target().position)
	game.charging = true
	game.charge_t = 0.3
	await snap("tmp_tutorial_charge.png")
	game.charging = false
	game.charge_t = 0.0
	game.tutorial_step = 3
	game.tutorial_t = 0.5
	game.tutorial_gain = 7
	await snap("tmp_tutorial_done.png")
	print("DONE")
	quit(0)
