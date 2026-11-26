extends SceneTree

## 用改造后的 3D 木猪渲染出各猪种的贴图，替换 assets/art 里的 AI 陶瓷粉猪贴图。
## 猪 id → 贴图文件 与 main.gd 的 PIG_TEXTURE_FILES 对应（stripe/debt/glass/fat
## 本来就没有贴图文件，直接走 3D 实时渲染，不用导）。
## 用法：Godot --path . --script tests/dump_pig_sprites.gd （必须非 headless 跑）

const OUT := {
	"piggy": "res://assets/art/pig_normal.png",
	"mini": "res://assets/art/pig_mini.png",
	"gold": "res://assets/art/pig_gold.png",
}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var types: Array = game.settings.get("pig_types", [])
	for id in OUT:
		var t := {}
		for e in types:
			if String(e.get("id", "")) == id:
				t = e
				break
		var vp := Pig3D.new()
		root.add_child(vp)
		await process_frame # 等 _ready 建好场景再换皮
		vp.apply_type(t)
		for i in range(6):
			await process_frame
		var img: Image = vp.get_texture().get_image()
		img.save_png(OUT[id])
		print("SAVED ", OUT[id])
		vp.queue_free()
	quit()
