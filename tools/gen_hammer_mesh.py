"""程序化生成《敲猪还债》里的木槌网格（OBJ + MTL）。

不依赖任何建模软件/付费服务：纯几何计算，输出 Godot 4 可直接导入的 .obj。
坐标系：锤头沿 X 轴，木柄沿 -Y，单位米（真实木槌尺度，总长 ≈ 0.46m）。
"""

import math
import os

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")

# 材质：与游戏贴图同源的木色/皮革色（取自截图）
MATS = {
    "wood_head": (0.725, 0.522, 0.306),   # #b9854e 锤头暖棕木
    "wood_band": (0.490, 0.310, 0.173),   # #7d4f2c 端箍深棕
    "wood_grip": (0.851, 0.725, 0.549),   # #d9b98c 浅色木柄
    "leather":   (0.541, 0.310, 0.169),   # #8a4f2b 皮手套
}

verts: list[tuple[float, float, float]] = []
norms: list[tuple[float, float, float]] = []
groups: list[tuple[str, list[list[int]]]] = []  # (材质, 面列表[顶点索引])


def add_quad(idx: list[int]):
    return idx


def emit_face(mat: str, face: list[int]):
    for g_mat, faces in groups:
        if g_mat == mat:
            faces.append(face)
            return
    groups.append((mat, [face]))


def circle_pts(radius: float, segs: int, axis: str, offset: float):
    """在垂直于 axis 的平面上生成一圈点。axis='x' 时在 YZ 平面。"""
    pts = []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        u, v = radius * math.cos(a), radius * math.sin(a)
        if axis == "x":
            pts.append((offset, u, v))
        elif axis == "y":
            pts.append((u, offset, v))
        else:
            pts.append((u, v, offset))
    return pts


def add_cylinder(axis: str, center: float, half_len: float, r0: float, r1: float,
                 segs: int, mat: str, cap0: bool = True, cap1: bool = True):
    """沿 axis 的圆台：center 为中心坐标，r0/r1 为两端半径（允许锥度）。"""
    a = center - half_len
    b = center + half_len
    ring_a = circle_pts(r0, segs, axis, a)
    ring_b = circle_pts(r1, segs, axis, b)
    base = len(verts)
    verts.extend(ring_a)
    verts.extend(ring_b)
    # 侧面：每段用平面法线（低模风味）
    for i in range(segs):
        j = (i + 1) % segs
        p0 = ring_a[i]
        p1 = ring_a[j]
        p2 = ring_b[j]
        # 法线取该段中点径向方向
        if axis == "x":
            n = (0.0, p0[1] + p1[1], p0[2] + p1[2])
        elif axis == "y":
            n = (p0[0] + p1[0], 0.0, p0[2] + p1[2])
        else:
            n = (p0[0] + p1[0], p0[1] + p1[1], 0.0)
        ln = math.sqrt(sum(c * c for c in n)) or 1.0
        n = tuple(c / ln for c in n)
        norms.append(n)
        ni = len(norms)
        emit_face(mat, [base + i + 1, base + j + 1, base + segs + j + 1, base + segs + i + 1])
        # OBJ 的面法线索引与顶点索引并行
        _face_norm[tuple(sorted([base + i + 1, base + j + 1]))] = ni
    if cap0 or cap1:
        for side, ring, radius, sign in (("cap0", ring_a, r0, -1.0), ("cap1", ring_b, r1, 1.0)):
            if (side == "cap0" and not cap0) or (side == "cap1" and not cap1):
                continue
            n = (sign, 0.0, 0.0) if axis == "x" else (0.0, sign, 0.0) if axis == "y" else (0.0, 0.0, sign)
            norms.append(n)
            ni = len(norms)
            # 扇形三角：以圆环中心为扇心（法线一次性使用，靠 fi 引用）
            cx = a if side == "cap0" else b
            if axis == "x":
                center_pt = (cx, 0.0, 0.0)
            elif axis == "y":
                center_pt = (0.0, cx, 0.0)
            else:
                center_pt = (0.0, 0.0, cx)
            verts.append(center_pt)
            ci = len(verts)
            _face_norm[("center", ci)] = ni
            for i in range(segs):
                j = (i + 1) % segs
                # Godot 以顺时针为正面：端帽绕向按端面朝向翻转
                if sign > 0:
                    tri = [ci, base + j + 1, base + i + 1]
                else:
                    tri = [ci, base + i + 1, base + j + 1]
                emit_face(mat, tri)


_face_norm: dict = {}


def add_box(cx, cy, cz, sx, sy, sz, mat: str):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    corners = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    base = len(verts)
    verts.extend(corners)
    faces = [
        ([0, 1, 2, 3], (0, 0, -1)), ([4, 5, 6, 7], (0, 0, 1)),
        ([0, 4, 7, 3], (-1, 0, 0)), ([1, 2, 6, 5], (1, 0, 0)),
        ([3, 7, 6, 2], (0, 1, 0)), ([0, 1, 5, 4], (0, -1, 0)),
    ]
    for idxs, n in faces:
        norms.append(n)
        ni = len(norms)
        face = [base + k + 1 for k in idxs]
        emit_face(mat, face)
        for k in face:
            _face_norm[k] = ni


def normal_index_for(face: list[int]) -> int:
    if len(face) == 3:
        key = ("center", face[0])
        if key in _face_norm:
            return _face_norm[key]
    for i in range(len(face)):
        for j in range(i + 1, len(face)):
            key = tuple(sorted([face[i], face[j]]))
            if key in _face_norm:
                return _face_norm[key]
    return 1


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    R = 0.062
    # 锤头：沿 X 的圆柱（端帽省略：两端箍的外端面盘半径更大，已完全封住端口）
    add_cylinder("x", 0.0, 0.14, R, R, 24, "wood_head", cap0=False, cap1=False)
    # 两端箍：贴在锤头两端面，外端面凸出 1mm 避免与锤头端面共面 z-fighting
    add_cylinder("x", 0.130, 0.011, R * 1.06, R * 1.06, 24, "wood_band", cap0=True, cap1=True)
    add_cylinder("x", -0.130, 0.011, R * 1.06, R * 1.06, 24, "wood_band", cap0=True, cap1=True)
    # 木柄：从锤头中心向下延伸，带锥度
    add_cylinder("y", -0.24, 0.24, 0.017, 0.020, 14, "wood_grip")
    # 柄尾帽
    add_cylinder("y", -0.487, 0.008, 0.024, 0.024, 14, "wood_band")
    # 皮手套：握在柄中后段（简化方块，可删）
    add_box(0.0, -0.33, 0.0, 0.055, 0.095, 0.05, "leather")

    obj = ["# HammerPig mallet - procedurally generated", "mtllib hammer.mtl"]
    for v in verts:
        obj.append("v %.4f %.4f %.4f" % v)
    for n in norms:
        obj.append("vn %.4f %.4f %.4f" % n)
    cur = None
    for mat, faces in groups:
        if mat != cur:
            obj.append("usemtl %s" % mat)
            cur = mat
        for f in faces:
            ni = normal_index_for(f)
            obj.append("f " + " ".join("%d//%d" % (i, ni) for i in f))
    with open(os.path.join(OUT_DIR, "hammer.obj"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(obj) + "\n")

    mtl = ["# HammerPig mallet materials"]
    for name, (r, g, b) in MATS.items():
        mtl += [f"newmtl {name}", f"Kd {r:.3f} {g:.3f} {b:.3f}", "Ka 0 0 0", "Ks 0.08 0.08 0.08",
                "Ns 12.0", "illum 2", ""]
    with open(os.path.join(OUT_DIR, "hammer.mtl"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(mtl))

    tri = sum(len(f) - 2 for _, faces in groups for f in faces)
    print(f"wrote hammer.obj: {len(verts)} verts, {len(groups)} material groups, ~{tri} tris")


if __name__ == "__main__":
    main()
