extends Node
## ============================================================
## 道具图标 3D 模型渲染器（单视口烘焙版）
## ------------------------------------------------------------
## 为什么不用「每个道具一个 SubViewport」：
##   运行时动态创建的多个 SubViewport，其 ViewportTexture 在
##   _draw() 中懒加载时会出现所有格子绑定到同一渲染目标的问题。
## 本方案：
##   只用一个持久 SubViewport，按 key 逐个放入模型 → 等两帧渲染
##   → get_image() 抓帧 → 生成独立 ImageTexture 缓存。
##   ImageTexture 是普通 2D 纹理，draw_texture_rect 绘制互不干扰，
##   烘焙完成后无每帧渲染开销，内存仅 7 张 256px 贴图。
##
## 模型来源：
##   buildin://<id>  → shop_models_builtin.gd 程序化低模
##   res://....glb   → 外部模型文件（未来精细资产，同一套烘焙管线）
## ============================================================

const VIEW_SIZE := 256          # 烘焙贴图边长（像素）
const CAM_PADDING := 1.18       # 取景留白倍数
const BUILTIN_PREFIX := "buildin://"
const BuiltinModels := preload("res://scripts/shop_models_builtin.gd")

var _paths: Dictionary = {}      # key -> 模型路径（buildin:// 或 res://）
var _textures: Dictionary = {}   # key -> ImageTexture（烘焙产物）

var _vp: SubViewport = null
var _pivot: Node3D = null
var _cam: Camera3D = null
var _baking := false


func setup(_host, data: Dictionary) -> void:
	var hammers: Dictionary = data.get("hammers", {})
	for id in hammers:
		_register("hammer:" + String(id), String(hammers[id].get("model", "")))
	var skills: Dictionary = data.get("skills", {})
	for id in skills:
		_register("skill:" + String(id), String(skills[id].get("model", "")))
	_register("box:box", String(data.get("box", {}).get("model", "")))
	# 节点已在树内，直接启动协程：同步建好视口与首模，首个 await 自然挂起。
	# 不用 call_deferred 启动协程——headless 下延迟消息启动的 async 函数不可靠。
	prebuild()


func _register(key: String, path: String) -> void:
	if path.strip_edges() != "":
		_paths[key] = path


## 运行时注册新模型（如活动皮肤）；已烘焙的旧贴图会清掉并重烘
func register(key: String, path: String) -> void:
	_register(key, path)
	_textures.erase(key)
	prebuild()


## shop.gd 绘制时调用；烘焙未完成返回 null，自动回退 2D 占位图
func get_texture(key: String) -> Texture2D:
	return _textures.get(key)


func has_model(key: String) -> bool:
	if not _paths.has(key):
		return false
	var path := String(_paths[key])
	if path.begins_with(BUILTIN_PREFIX):
		return BuiltinModels.supports(path.trim_prefix(BUILTIN_PREFIX))
	return ResourceLoader.exists(path)


# ---------- 烘焙流程 ----------

## 异步遍历所有已注册模型，逐个烘成 ImageTexture（可安全重复调用）
func prebuild() -> void:
	if _baking:
		return
	_baking = true
	_ensure_viewport()
	# while 重扫：烘焙过程中若 register() 新增了 key，下一轮自动补烘
	var pending := true
	while pending:
		pending = false
		for key in _paths:
			if not _textures.has(key) and has_model(key):
				await _bake_one(key)
				pending = true
	_baking = false


func _bake_one(key: String) -> void:
	var model: Node3D = _instantiate(key)
	if model == null:
		return
	_pivot.add_child(model)
	_frame_camera(_cam, _pivot)
	# 等待两个完整帧：第一帧提交节点/材质变更并绘制，第二帧确保画面刷新完成。
	# 用 SceneTree.process_frame 而非 RenderingServer.frame_post_draw——
	# 后者在 headless dummy 渲染器下永不触发，会让协程永久挂起。
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = _vp.get_texture().get_image()
	if img == null:
		# headless/dummy 渲染器不分配视口缓冲：用空 RGBA 图兜底，
		# 保证缓存键存在；真实渲染器下永远走上面的真实抓帧
		img = Image.create_empty(VIEW_SIZE, VIEW_SIZE, false, Image.FORMAT_RGBA8)
	_textures[key] = ImageTexture.create_from_image(img)
	model.free()


func _instantiate(key: String) -> Node3D:
	var path := String(_paths[key])
	if path.begins_with(BUILTIN_PREFIX):
		return BuiltinModels.make_node(path.trim_prefix(BUILTIN_PREFIX))
	var packed: Resource = load(path)
	if not (packed is PackedScene):
		push_warning("ShopIcons3D: 模型不是 PackedScene，已跳过：" + key)
		return null
	var node: Node = (packed as PackedScene).instantiate()
	if node is Node3D:
		return node
	push_warning("ShopIcons3D: 模型根节点不是 Node3D，已跳过：" + key)
	node.free()
	return null


func _ensure_viewport() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	_vp.transparent_bg = true
	_vp.handle_input_locally = false
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var env_node := WorldEnvironment.new()
	env_node.environment = _make_environment()
	_vp.add_child(env_node)

	# 暖调三灯：主光 + 补光 + 轮廓光，保证暗铁/深木也有层次
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42, -38, 0)
	key_light.light_energy = 1.3
	_vp.add_child(key_light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.2, 1.4, 2.2)
	fill.light_energy = 0.55
	fill.omni_range = 9.0
	_vp.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 140, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(1.0, 0.9, 0.78)
	_vp.add_child(rim)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)       # 透明背景，融入木架
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.83, 0.79)
	env.ambient_light_energy = 0.7
	return env


## 按模型合并 AABB 自动取景：正交相机 + 固定 3/4 俯视角
func _frame_camera(cam: Camera3D, world_root: Node3D) -> void:
	var aabb := _combined_aabb(world_root)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var center: Vector3 = aabb.get_center()
	var max_dim: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	cam.size = max_dim * CAM_PADDING
	var dir := Vector3(0.55, 0.62, 0.9).normalized()
	cam.position = center + dir * (max_dim * 2.5 + 1.0)
	cam.look_at(center, Vector3.UP)
	cam.near = 0.05
	cam.far = 64.0


func _combined_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for vi in root.find_children("*", "VisualInstance3D", true, false):
		var local_aabb: AABB = (vi as VisualInstance3D).get_aabb()
		var world_aabb: AABB = vi.global_transform * local_aabb
		result = world_aabb if first else result.merge(world_aabb)
		first = false
	return result


# ---------- 可选：烘焙成 PNG（发布期零运行时开销） ----------
## 调 await icons_3d.bake_png("hammer:dual", "res://assets/models/baked/dual.png")
## 导出后可改成直接 load PNG 绘制，彻底移除本渲染器。
func bake_png(key: String, out_path: String) -> bool:
	var tex: Texture2D = _textures.get(key)
	if tex == null:
		push_warning("ShopIcons3D: 尚未烘焙，无法导出 PNG：" + key)
		return false
	var img: Image = tex.get_image()
	if img == null:
		return false
	return img.save_png(out_path) == OK


## 释放全部烘焙贴图与视口（切局回收时可选）
func clear_all() -> void:
	_textures.clear()
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_pivot = null
	_cam = null
