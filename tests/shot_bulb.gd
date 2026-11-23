extends SceneTree

## 临时截图工具：停电灯泡的三种状态 —— 欠费闪亮的瞬间 / 闪到最暗的瞬间 / 缴清常亮。

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
	game.blackout_fade = 1.0 # 直接拉满停电渐入
	game.set_process(false) # 冻结 elapsed：否则每帧都在推进，截到的不是目标亮度
	# 用纯函数扫出最亮 / 最暗的时刻，各截一张
	var bright_t := 0.0
	var dim_t := 0.0
	for i in range(600):
		var t := 0.01 * i
		if game.bulb_brightness_at(t) > game.bulb_brightness_at(bright_t):
			bright_t = t
		if game.bulb_brightness_at(t) < game.bulb_brightness_at(dim_t):
			dim_t = t
	game.elapsed = bright_t
	await snap("tmp_bulb_bright.png")
	game.elapsed = dim_t
	await snap("tmp_bulb_dim.png")
	game.blackout_fade = 0.0
	game.set_process(true)
	await snap("tmp_bulb_lit.png")
	quit()
