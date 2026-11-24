extends SceneTree

## 临时截图工具：贴图锤的命中点对齐验证 —— 把 hammer_position 定在已知点，
## 冻结 _process（否则它每帧被真实鼠标坐标覆盖），看锤头是否落在命中点上。

var game

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	game.queue_redraw() # _process 被冻结时没人调 queue_redraw，必须手动触发重绘
	for i in range(3):
		await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.phase = "playing"
	game.reset_game()
	game.sync_cursor() # _process 马上要被冻结，手动让锤子顶替系统箭头
	game.set_process(false) # 冻结：hammer_position 不再被真实鼠标覆盖
	game.hammer_position = Vector2(640, 420)
	game.queue_redraw()
	await snap("tmp_hammer_rest.png")
	# 挥锤中段：swing=0.08（半程），看旋转是否绕着手套握柄转
	game.swing = 0.08
	game.queue_redraw()
	await snap("tmp_hammer_swing.png")
	game.swing = 0.0
	# 悬停按钮态：锤子缩小让位
	game.hammer_position = Vector2(1148, 74) # 帮助按钮附近
	game.queue_redraw()
	await snap("tmp_hammer_hover.png")
	quit()