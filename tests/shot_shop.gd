extends SceneTree

## 临时截图工具：开真实窗口，打开商店/背包面板各存一张 PNG。

var game

func _initialize() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("res://" + file)
	print("SAVED ", file)


func click_tab(point: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = point
	game.shop.handle_input(ev)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = point
	game.shop.handle_input(ev2)
	await process_frame


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.intro_open = false
	game.phase = "playing"
	game.score = 620
	game.broken = 12
	game.combo_count = 5
	await process_frame
	# 打开商店（默认锤子区）
	game.shop.try_open_shop()
	await snap("tmp_shop_hammers.png")
	# 切到技能区页签
	game.shop._set_tab(1)
	await snap("tmp_shop_skills.png")
	# 关商店，开背包
	game.shop.try_open_shop()
	await process_frame
	game.shop.try_open_backpack()
	await snap("tmp_shop_backpack.png")
	print("ALL SHOTS DONE")
	quit()
