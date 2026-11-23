extends RefCounted
## ============================================================
## 程序化低多边形 3D 道具模型工厂（独立轮廓版）
## ------------------------------------------------------------
## 6 个商店道具各自独立结构、独立材质、独立识别点，杜绝同模换色：
##   dual    连打锤：短皮柄 + 弹簧 + 前后双圆柱锤头 + 橙色火花 + 黄色警示圈
##   gravity 重力锤：最长柄 + 最大黑铁锤头 + 圆形紫符文 + 红色绑带
##   magnet  磁吸锤：圆盘锤头蓝红双极 + N/S 标识 + 钢铁包边 + 铜线圈
##   hourglass 沙漏：古铜边框 + 透明玻璃双锥 + 淡蓝流沙
##   abacus  算筹：浅棕木底座 + 三根平行鎏金短棒 + 细刻度
##   box     盲盒：深棕木纹 + 四角暗金包边 + 正面大号金色问号
## 约定：模型原点居中、正面朝 +Z（相机位于 +Z 侧）、整体约 1 米。
## ============================================================

const FONT_PATH := "res://assets/fonts/NotoSansSC.ttf"
const SUPPORTED := ["iron", "dual", "gravity", "magnet", "hourglass", "abacus", "box"]


static func supports(id: String) -> bool:
	return id in SUPPORTED


static func make_node(id: String) -> Node3D:
	match id:
		"iron": return _hammer_iron()
		"dual": return _hammer_dual()
		"gravity": return _hammer_gravity()
		"magnet": return _hammer_magnet()
		"hourglass": return _hourglass()
		"abacus": return _abacus()
		"box": return _mystery_box()
	return null


# ---------- 材质 / 网格小工具 ----------

static func _mat(color: Color, metallic := 0.0, roughness := 0.65, emission := Color.TRANSPARENT, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission != Color.TRANSPARENT:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bottom: float, height: float, pos: Vector3, material: Material, radial := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = radial
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 正面 3D 文字（位于 XY 平面、法线朝 +Z），用于 N/S 与问号。
## 用 Label3D 而非 TextMesh：后者对部分字形（如「?」）会三角化失败导致残字。
static func _text3d(parent: Node3D, s: String, pos: Vector3, height: float, color: Color, _metallic := 0.3) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = load(FONT_PATH)
	l.font_size = 64
	l.pixel_size = height / 64.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.shaded = false           # 无着色：暗背景上也清晰，接近自发光描字效果
	l.double_sided = true
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l


## 四角星形火花（两根交叉细条，自发光）
static func _sparkle(parent: Node3D, center: Vector3, size: float, color: Color) -> void:
	var m := _mat(color, 0.2, 0.4, color, 2.2)
	var a := _box(parent, Vector3(size, size * 0.18, size * 0.12), center, m)
	a.rotation.z = PI / 4.0
	var b := _box(parent, Vector3(size, size * 0.18, size * 0.12), center, m)
	b.rotation.z = -PI / 4.0


# ---------- 1) 连打锤：短柄 + 弹簧 + 前后双锤头 ----------

static func _hammer_dual() -> Node3D:
	var root := Node3D.new()
	root.name = "model_dual"
	var leather := _mat(Color("#5d3d24"), 0.0, 0.85)
	var steel := _mat(Color("#aab2bd"), 0.9, 0.32)
	var steel_dark := _mat(Color("#6e7680"), 0.85, 0.4)
	var spring_mat := _mat(Color("#c8ccd2"), 0.95, 0.25)
	var warn := _mat(Color("#ffd23f"), 0.3, 0.45)
	# 短皮革握柄
	_cyl(root, 0.045, 0.055, 0.42, Vector3(0, -0.27, 0), leather)
	# 黄色警示圈（握柄上下各一）
	var ring1 := _cyl(root, 0.062, 0.062, 0.05, Vector3(0, -0.07, 0), warn, 20)
	var ring2 := _cyl(root, 0.058, 0.058, 0.045, Vector3(0, -0.45, 0), warn, 20)
	# 明显弹簧：四个加大环径的钢环叠放，确保 3/4 视角下不被锤头遮挡
	for i in range(4):
		var coil := _torus(root, 0.058, 0.092, Vector3(0, -0.03 + i * 0.062, 0), spring_mat)
		coil.rotation.x = PI / 2.0
	# 中央连接柱
	_cyl(root, 0.026, 0.026, 0.3, Vector3(0, 0.13, 0), steel_dark, 16)
	# 一前一后两个小圆柱锤头（柱轴沿 Z）
	var head_front := _cyl(root, 0.115, 0.115, 0.17, Vector3(0, 0.24, 0.15), steel, 24)
	head_front.rotation.x = PI / 2.0
	var head_back := _cyl(root, 0.115, 0.115, 0.17, Vector3(0, 0.24, -0.15), steel, 24)
	head_back.rotation.x = PI / 2.0
	# 锤头端面暗片增强层次
	var cap_f := _cyl(root, 0.085, 0.085, 0.02, Vector3(0, 0.24, 0.245), steel_dark, 20)
	cap_f.rotation.x = PI / 2.0
	# 橙色火花识别点
	_sparkle(root, Vector3(0.17, 0.36, 0.12), 0.12, Color("#ff8c3a"))
	return root


# ---------- 2) 重力锤：长柄 + 巨型黑铁锤头 + 重力符文 ----------

static func _hammer_gravity() -> Node3D:
	var root := Node3D.new()
	root.name = "model_gravity"
	var grip := _mat(Color("#33261c"), 0.0, 0.8)
	var dark_iron := _mat(Color("#2b2d36"), 0.85, 0.42)
	var iron_edge := _mat(Color("#45485a"), 0.9, 0.35)
	var red_band := _mat(Color("#a83232"), 0.2, 0.55)
	var rune := _mat(Color("#a06bff"), 0.3, 0.3, Color("#a06bff"), 1.8)
	# 长手柄（全场最长）
	_cyl(root, 0.05, 0.06, 0.78, Vector3(0, -0.16, 0), grip)
	# 红色绑带（下移到锤头下方，避免被锤头遮挡）
	_cyl(root, 0.068, 0.068, 0.08, Vector3(0, -0.06, 0), red_band, 20)
	# 巨型黑铁锤头（体积最大）
	_box(root, Vector3(0.56, 0.4, 0.36), Vector3(0, 0.32, 0), dark_iron)
	# 上下包边铁片
	_box(root, Vector3(0.6, 0.06, 0.4), Vector3(0, 0.55, 0), iron_edge)
	_box(root, Vector3(0.6, 0.06, 0.4), Vector3(0, 0.09, 0), iron_edge)
	# 四角铆钉
	for sx in [-0.22, 0.22]:
		for sy in [0.19, 0.45]:
			_sphere(root, 0.03, Vector3(sx, sy, 0.195), iron_edge)
	# 正面圆形重力符文：外环 + 内盘 + 核心
	var rune_ring := _torus(root, 0.12, 0.165, Vector3(0, 0.32, 0.195), rune)
	var rune_disc := _cyl(root, 0.095, 0.095, 0.02, Vector3(0, 0.32, 0.19), _mat(Color("#1c1430"), 0.4, 0.4), 24)
	rune_disc.rotation.x = PI / 2.0
	_sphere(root, 0.045, Vector3(0, 0.32, 0.215), _mat(Color("#c9a8ff"), 0.2, 0.3, Color("#b78bff"), 2.4), Vector3(1, 1, 0.5))
	return root


# ---------- 3) 磁吸锤：圆盘蓝红双极 + N/S ----------

static func _hammer_magnet() -> Node3D:
	var root := Node3D.new()
	root.name = "model_magnet"
	var metal := _mat(Color("#8a9099"), 0.9, 0.35)
	var steel_rim := _mat(Color("#c3c9d1"), 0.95, 0.25)
	var copper := _mat(Color("#b87333"), 0.9, 0.3)
	var blue := _mat(Color("#3f7de0"), 0.4, 0.4)
	var red := _mat(Color("#d94b4b"), 0.4, 0.4)
	# 金属手柄
	_cyl(root, 0.04, 0.05, 0.5, Vector3(0, -0.26, 0), metal)
	# 金属线圈：柄顶三圈铜环
	for i in range(3):
		var coil := _torus(root, 0.045, 0.066, Vector3(0, -0.02 + i * 0.06, 0), copper)
		coil.rotation.x = PI / 2.0
	# 圆盘磁铁锤头（盘面朝 +Z）
	var disc := _cyl(root, 0.26, 0.26, 0.13, Vector3(0, 0.18, 0), metal, 32)
	disc.rotation.x = PI / 2.0
	# 蓝红两极面板（半圆近似：两块半幅面板内嵌盘面）
	_box(root, Vector3(0.17, 0.34, 0.025), Vector3(-0.087, 0.18, 0.075), blue)
	_box(root, Vector3(0.17, 0.34, 0.025), Vector3(0.087, 0.18, 0.075), red)
	# 钢铁包边环
	var rim := _torus(root, 0.225, 0.262, Vector3(0, 0.18, 0.085), steel_rim)
	# N / S 标识
	_text3d(root, "N", Vector3(-0.09, 0.18, 0.105), 0.12, Color("#eaf2ff"), 0.2)
	_text3d(root, "S", Vector3(0.09, 0.18, 0.105), 0.12, Color("#fff0f0"), 0.2)
	return root


# ---------- 4) 凝时沙漏：古铜边框 + 玻璃 + 蓝流沙 ----------

static func _hourglass() -> Node3D:
	var root := Node3D.new()
	root.name = "model_hourglass"
	var bronze := _mat(Color("#b08a4a"), 0.85, 0.32)
	var bronze_dark := _mat(Color("#7d5f30"), 0.8, 0.4)
	# 上下盖板
	_box(root, Vector3(0.46, 0.06, 0.46), Vector3(0, 0.35, 0), bronze)
	_box(root, Vector3(0.46, 0.06, 0.46), Vector3(0, -0.35, 0), bronze)
	# 四根立柱
	for sx in [-0.18, 0.18]:
		for sz in [-0.18, 0.18]:
			_cyl(root, 0.022, 0.022, 0.64, Vector3(sx, 0, sz), bronze_dark, 12)
	# 透明玻璃双锥
	var glass := _mat(Color(0.85, 0.93, 1.0, 0.3), 0.0, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cyl(root, 0.155, 0.025, 0.27, Vector3(0, 0.145, 0), glass)
	_cyl(root, 0.025, 0.155, 0.27, Vector3(0, -0.145, 0), glass)
	# 淡蓝能量流沙
	var sand := _mat(Color("#8fd0ec"), 0.1, 0.55, Color("#5fb8e6"), 0.7)
	_cyl(root, 0.11, 0.015, 0.19, Vector3(0, 0.15, 0), sand, 20)
	_cyl(root, 0.015, 0.115, 0.2, Vector3(0, -0.16, 0), sand, 20)
	_cyl(root, 0.012, 0.012, 0.1, Vector3(0, 0, 0), _mat(Color("#bfe8ff"), 0.0, 0.4, Color("#9fdcff"), 1.2), 10)
	return root


# ---------- 5) 鎏金算筹：木底座 + 三根平行金棒 + 刻度 ----------

static func _abacus() -> Node3D:
	var root := Node3D.new()
	root.name = "model_abacus"
	var wood := _mat(Color("#b08968"), 0.0, 0.8)
	var wood_dark := _mat(Color("#8a684b"), 0.0, 0.85)
	var gold := _mat(Color("#d4a017"), 0.9, 0.28, Color("#d4a017"), 0.35)
	var gold_bright := _mat(Color("#ffe9a0"), 0.85, 0.22, Color("#ffe9a0"), 0.5)
	# 浅棕小木底座（带顶层暗槽）
	_box(root, Vector3(0.72, 0.12, 0.36), Vector3(0, -0.26, 0), wood)
	_box(root, Vector3(0.66, 0.03, 0.3), Vector3(0, -0.185, 0), wood_dark)
	# 底座正面细刻度
	for i in range(7):
		var x := -0.27 + i * 0.09
		_box(root, Vector3(0.012, 0.05, 0.012), Vector3(x, -0.27, 0.185), wood_dark)
	# 三根平行鎏金短棒（沿 X 轴，Z 向排开），两端金球
	var zs := [-0.1, 0.0, 0.1]
	for z in zs:
		var rod := _cyl(root, 0.026, 0.026, 0.56, Vector3(0, -0.07, z), gold, 16)
		rod.rotation.z = PI / 2.0
		_sphere(root, 0.038, Vector3(-0.3, -0.07, z), gold_bright)
		_sphere(root, 0.038, Vector3(0.3, -0.07, z), gold_bright)
	# 底座两端小金挡片
	_box(root, Vector3(0.04, 0.1, 0.34), Vector3(-0.35, -0.22, 0), gold)
	_box(root, Vector3(0.04, 0.1, 0.34), Vector3(0.35, -0.22, 0), gold)
	return root


# ---------- 6) 神秘盲盒：复古木箱 + 金属包边 + 金色问号 ----------

static func _mystery_box() -> Node3D:
	var root := Node3D.new()
	root.name = "model_box"
	var wood := _mat(Color("#4e3220"), 0.0, 0.82)
	var wood_lid := _mat(Color("#5d3d22"), 0.0, 0.78)
	var plank := _mat(Color("#33200f"), 0.0, 0.88)
	var trim := _mat(Color("#9c7a2e"), 0.85, 0.35)
	var gold := _mat(Color("#ffd76a"), 0.75, 0.25, Color("#ffd76a"), 0.6)
	# 箱体与盖板
	_box(root, Vector3(0.58, 0.5, 0.58), Vector3(0, -0.05, 0), wood)
	_box(root, Vector3(0.64, 0.1, 0.64), Vector3(0, 0.29, 0), wood_lid)
	# 正面木板纹理条
	for i in range(3):
		_box(root, Vector3(0.52, 0.025, 0.02), Vector3(0, -0.22 + i * 0.16, 0.295), plank)
	# 四角暗金包边（正面四根竖条 + 盖板四角小条）
	for sx in [-0.27, 0.27]:
		_box(root, Vector3(0.05, 0.52, 0.05), Vector3(sx, -0.05, 0.28), trim)
		_box(root, Vector3(0.06, 0.11, 0.06), Vector3(sx * 1.02, 0.29, 0.3), trim)
	# 金色打包带
	_box(root, Vector3(0.07, 0.56, 0.6), Vector3(0, -0.05, 0), trim)
	_box(root, Vector3(0.62, 0.03, 0.09), Vector3(0, 0.35, 0), gold)
	# 正面大号金色问号
	_text3d(root, "?", Vector3(0, -0.06, 0.325), 0.3, Color("#ffd76a"), 0.7)
	return root


# ---------- 附：普通铁锤（默认武器，商店不售但保留工厂入口） ----------

static func _hammer_iron() -> Node3D:
	var root := Node3D.new()
	root.name = "model_iron"
	_cyl(root, 0.045, 0.055, 0.7, Vector3(0, -0.14, 0), _mat(Color("#6b4a2f"), 0.0, 0.85))
	var steel := _mat(Color("#c9c9cf"), 0.85, 0.3)
	_box(root, Vector3(0.46, 0.18, 0.22), Vector3(0, 0.3, 0), steel)
	_box(root, Vector3(0.07, 0.2, 0.24), Vector3(-0.2, 0.3, 0), _mat(Color("#9aa0a8"), 0.9, 0.25))
	return root
