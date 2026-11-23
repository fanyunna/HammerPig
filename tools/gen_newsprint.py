"""生成旧报纸质感的账单纸：撕边缺角、边缘氧化、水渍、油污、折痕、卷角、印刷残留。

用法：python tools/gen_newsprint.py
产出：assets/art/billpaper_<w>x<h>_<i>.png（每种显示尺寸若干变体）
      顺带拼一张 tmp_paper_<w>x<h>.png 深灰底预览图，方便一眼比对（不入库）。

为什么是"整张带 alpha 的纸"而不是一张可平铺的纹理：
- 要的是"边角破破烂烂"，纸的外形本身不规则（缺角、撕口、外伸纸茬、翘起来的角），
  这类形状没法用矩形贴图 + 代码描边做出来，只能烘在 alpha 通道里；
- 账单的显示尺寸只有四种（账本卡 / 桌上卡 / 放大单 / HUD 图标），全部固定，
  所以每种尺寸各生成几张变体、按账单号挑一张即可，绘制时一次 draw_texture_rect。
- 纸色、污渍、折痕、印刷残留都烘进 RGB；字和红线由 GDScript 排在纸的安全区里。

质感参照那张道具概念图：中心米黄 → 边缘暗褐的氧化渐变、带"水线"的水渍、
成簇的油污点、十字折痕上的磨损、纸纤维毛茬、卷起来的纸角、淡灰的印刷表格残留。
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(BASE, 'assets', 'art')
PREVIEW_DIR = BASE

# 每种显示尺寸一份配方：
#   w/h     逻辑尺寸（游戏里 draw_texture_rect 的矩形大小，不能改）
#   scale   渲染倍数（高分辨率生成，游戏里缩小 = 天然抗锯齿）
#   variants变体张数
#   folds   折痕（v 竖 / h 横 / v2 偏左的竖折）
#   stains  水渍块数（0 = 不画）
#   specks  是否撒油污点
#   ghost   印刷残留种类（rules 横格线 / table 表格+印章 / 空 = 无）
#   curl    卷角强度（0 = 不卷）
#   oxide   氧化带系数：卡片上文字要能读，氧化压轻些；大张可以重
SHEETS = [
    dict(w=236, h=74, scale=3, variants=4, folds=('v',), stains=3, specks=True, ghost='rules', curl=0.0, oxide=0.62),
    dict(w=182, h=100, scale=3, variants=3, folds=('v', 'h'), stains=3, specks=True, ghost='rules', curl=0.55, oxide=0.62),
    dict(w=420, h=570, scale=2, variants=3, folds=('v', 'h', 'v2'), stains=4, specks=True, ghost='table', curl=1.0, oxide=1.0),
    dict(w=46, h=30, scale=3, variants=2, folds=(), stains=0, specks=False, ghost='', curl=0.0, oxide=0.8),
]

# 调色：新闻纸偏灰的米黄，不是奶油白；氧化到边缘变成脏褐
PAPER = np.array([196, 183, 158], np.float32)      # 中心纸色
PAPER_OUT = np.array([168, 150, 118], np.float32)  # 往外一圈的暖调
PAPER_BACK = np.array([200, 189, 166], np.float32)  # 纸背面（卷起来那面）
EDGE = np.array([80, 57, 33], np.float32)          # 边缘氧化暗褐
STAIN = np.array([138, 106, 62], np.float32)       # 水渍
GRIME = np.array([52, 43, 31], np.float32)         # 污垢 / 油污
DIRT = np.array([148, 136, 116], np.float32)       # 大块灰脏（低频斑驳的暗面）
INK = np.array([56, 50, 42], np.float32)           # 印刷残墨


def near(dist, d):
    """距纸边越近越接近 1（dist 是到纸边的距离），超过 d 就是 0。"""
    return np.clip(1.0 - dist / max(d, 1e-6), 0.0, 1.0)


def edge_profile(n, length, scale, amp, depth, rng, bite_start=0.0, bite_end=0.0):
    """一条边的撕痕：低频起伏 + 一两处窄而深的撕口 + 角上被咬掉的圆弧缺口。"""
    t = np.linspace(0.0, 1.0, n)
    f = np.zeros(n)
    for freq in (1.5, 3.0, 6.5, 11.0):
        f += np.sin(2 * np.pi * freq * t + rng.uniform(0, 2 * np.pi)) * rng.uniform(0.3, 1.0) / freq ** 0.6
    f = f / max(np.abs(f).max(), 1e-6) * amp
    for _ in range(int(rng.integers(0, 2))):
        center = rng.uniform(0.2, 0.8)
        width = rng.uniform(0.012, 0.040)
        f -= np.exp(-((t - center) / width) ** 2) * depth * rng.uniform(0.6, 1.2)
    # 角上咬掉一块：四分之一圆弧的凹陷（离角越近咬得越深），叠上噪声就是撕的
    x = t * length
    for bite, sign in ((bite_start, 1.0), (bite_end, -1.0)):
        if bite <= 0.0:
            continue
        d = x if sign > 0 else length - x
        arc = bite - np.sqrt(np.maximum(bite * bite - np.minimum(d, bite) ** 2, 0.0))
        f -= arc * scale
    return f


def torn_alpha(W, H, margin, scale, rng):
    """按四条边各自的不规则曲线拼出一张撕过的纸（0~1 浮点 alpha）。"""
    amp = 2.3 * scale
    depth = 8.5 * scale
    # 每个角 55% 概率被撕掉一块，半径 4~15 逻辑像素；小纸咬小口，太小就不咬
    max_bite = min(15.0, min(W, H) / scale * 0.16)
    if max_bite >= 4.0:
        corners = []
        for _ in range(4):
            if rng.random() < 0.55:
                corners.append(float(rng.uniform(4.0, max_bite)))
            else:
                corners.append(0.0)
    else:
        corners = [0.0, 0.0, 0.0, 0.0]
    # corners: [左上, 右上, 右下, 左下]
    xs = np.arange(W, dtype=np.float32)
    ys = np.arange(H, dtype=np.float32)

    top = np.clip(margin + edge_profile(W, W / scale, scale, amp, depth, rng, corners[0], corners[1]), 1.0, H * 0.40)
    right = np.clip(W - 1 - margin - edge_profile(H, H / scale, scale, amp, depth, rng, corners[1], corners[2]), W * 0.55, W - 2.0)
    bottom = np.clip(H - 1 - margin - edge_profile(W, W / scale, scale, amp, depth, rng, corners[2], corners[3]), H * 0.60, H - 2.0)
    left = np.clip(margin + edge_profile(H, H / scale, scale, amp, depth, rng, corners[3], corners[0]), 1.0, W * 0.45)

    pts = [(float(x), float(top[i])) for i, x in enumerate(xs)]
    pts += [(float(right[i]), float(y)) for i, y in enumerate(ys)]
    pts += [(float(x), float(bottom[i])) for i, x in reversed(list(enumerate(xs)))]
    pts += [(float(left[i]), float(y)) for i, y in reversed(list(enumerate(ys)))]

    mask = Image.new('L', (W, H), 0)
    dr = ImageDraw.Draw(mask)
    dr.polygon(pts, fill=255)

    # 毛茬：沿着撕口随机伸出细纸纤维，纸边才不是一条干净的曲线
    cx, cy = W / 2.0, H / 2.0
    for i in range(0, len(pts), 4):
        if rng.random() > 0.26:
            continue
        x, y = pts[i]
        ang = np.arctan2(y - cy, x - cx) + rng.uniform(-0.32, 0.32)
        length = rng.uniform(0.7, 4.2) * scale
        dr.line([(x, y), (x + np.cos(ang) * length, y + np.sin(ang) * length)],
                fill=int(rng.uniform(150, 255)), width=max(1, int(round(scale * 0.55))))

    return np.asarray(mask.filter(ImageFilter.GaussianBlur(0.5 * scale)), np.float32) / 255.0


def smooth_field(W, H, rng):
    """低频斑驳：报纸最典型的就是深浅不匀的灰块。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    field = np.zeros((H, W), np.float32)
    for _ in range(9):
        fx, fy = rng.uniform(0.7, 3.5), rng.uniform(0.7, 3.5)
        field += np.sin(2 * np.pi * (fx * xx / W + fy * yy / H) + rng.uniform(0, 6.28)) * rng.uniform(0.3, 1.0)
    return field / max(np.abs(field).max(), 1e-6)


def ghost_print(W, H, scale, rng, mode):
    """残留在纸上的印刷痕迹：淡到几乎看不见的表格线、印章圈、压扁的字迹。"""
    if not mode:
        return np.zeros((H, W), np.float32)
    layer = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(layer)
    if mode == 'rules':  # 小卡片：两三道横格 + 一条竖栏线 + 一排压扁的字
        for f in (0.30, 0.62, 0.90):
            y = H * f + rng.uniform(-1, 1) * H * 0.012
            d.line([(W * 0.03, y), (W * 0.97, y)], fill=int(rng.uniform(28, 44)), width=1)
        x = W * rng.uniform(0.12, 0.22)
        d.line([(x, H * 0.05), (x, H * 0.95)], fill=int(rng.uniform(20, 32)), width=1)
        for _ in range(int(rng.integers(4, 8))):
            y = H * rng.uniform(0.10, 0.92)
            x0 = W * rng.uniform(0.06, 0.55)
            d.line([(x0, y), (x0 + W * rng.uniform(0.05, 0.18), y)],
                   fill=int(rng.uniform(24, 40)), width=max(1, int(scale * 0.7)))
    else:  # 大张：完整表格网格 + 圆形印章的淡环
        for i in range(4):
            x = W * (0.14 + 0.21 * i) + rng.uniform(-1, 1) * 2 * scale
            d.line([(x, H * 0.04), (x, H * 0.96)], fill=int(rng.uniform(24, 38)), width=max(1, int(scale * 0.6)))
        for i in range(7):
            y = H * (0.10 + 0.125 * i) + rng.uniform(-1, 1) * 2 * scale
            d.line([(W * 0.06, y), (W * 0.94, y)], fill=int(rng.uniform(24, 38)), width=max(1, int(scale * 0.6)))
        cx, cy = W * rng.uniform(0.55, 0.75), H * rng.uniform(0.58, 0.84)
        rr = min(W, H) * rng.uniform(0.10, 0.15)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=int(rng.uniform(34, 54)), width=max(2, int(scale)))
        d.ellipse([cx - rr * 0.72, cy - rr * 0.72, cx + rr * 0.72, cy + rr * 0.72],
                  outline=int(rng.uniform(20, 34)), width=max(1, int(scale * 0.7)))
        d.line([(cx - rr * 0.58, cy + rr * 0.34), (cx + rr * 0.58, cy + rr * 0.34)],
               fill=int(rng.uniform(26, 42)), width=max(1, int(scale * 0.7)))
        # 印刷残留的字：一行行压扁的短线，像被水泡过的表格
        for _ in range(int(rng.integers(7, 12))):
            y = H * rng.uniform(0.08, 0.92)
            x0 = W * rng.uniform(0.06, 0.45)
            for k in range(int(rng.integers(3, 8))):
                x = x0 + k * W * 0.026
                if x > W * 0.93:
                    break
                d.line([(x, y), (x + W * rng.uniform(0.008, 0.016), y)],
                       fill=int(rng.uniform(24, 42)), width=max(1, int(scale * 0.6)))
    a = np.asarray(layer.filter(ImageFilter.GaussianBlur(0.4 * scale)), np.float32) / 255.0
    return a * 0.34


def water_stains(W, H, scale, rng, count):
    """水渍：边缘有明显的"水线"（一圈深色），中间反而浅，形状是波浪边的。"""
    if count <= 0:
        return np.zeros((H, W, 1), np.float32)
    inner = Image.new('L', (W, H), 0)
    rim = Image.new('L', (W, H), 0)
    di, dr = ImageDraw.Draw(inner), ImageDraw.Draw(rim)
    theta = np.linspace(0.0, 2 * np.pi, 72, endpoint=False)
    for _ in range(count):
        cx = rng.uniform(0.05, 0.95) * W
        cy = rng.uniform(0.05, 0.95) * H
        rx = rng.uniform(0.08, 0.20) * min(W, H) * rng.uniform(0.8, 1.9)
        ry = rx * rng.uniform(0.55, 1.0)
        wave = np.ones_like(theta)
        for freq, amp in ((3, 0.13), (5, 0.08), (8, 0.045), (13, 0.025)):
            wave += amp * np.sin(freq * theta + rng.uniform(0, 6.28))
        pts = [(cx + np.cos(t) * rx * wave[i], cy + np.sin(t) * ry * wave[i]) for i, t in enumerate(theta)]
        di.polygon(pts, fill=int(rng.uniform(52, 86)))
        dr.polygon(pts, outline=int(rng.uniform(170, 230)), width=max(2, int(2.2 * scale)))
    inner = inner.filter(ImageFilter.GaussianBlur(4.5 * scale))
    rim = rim.filter(ImageFilter.GaussianBlur(1.6 * scale))
    a = np.maximum(np.asarray(inner, np.float32) / 255.0 * 0.55,
                   np.asarray(rim, np.float32) / 255.0 * 0.62)
    return a[..., None]


def oil_specks(W, H, scale, rng):
    """油污 / 墨点：成簇的小暗点，散开比均匀撒更像真的。"""
    layer = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(layer)
    for _ in range(int(rng.integers(4, 7))):
        cx, cy = rng.uniform(0.1, 0.9) * W, rng.uniform(0.1, 0.9) * H
        spread = rng.uniform(0.05, 0.16) * W
        for _ in range(int(rng.integers(8, 20))):
            x = cx + rng.normal(0.0, spread)
            y = cy + rng.normal(0.0, spread)
            r = rng.uniform(0.4, 1.4) * scale
            d.ellipse([x - r, y - r, x + r, y + r], fill=int(rng.uniform(90, 200)))
    a = np.asarray(layer.filter(ImageFilter.GaussianBlur(0.5 * scale)), np.float32) / 255.0
    return (a * 0.50)[..., None]


def paper_fibers(W, H, scale, rng):
    """纸纤维：短促的浅色细丝，让纸面不像塑料。返回亮度加法层。"""
    layer = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(layer)
    count = int(60 * scale * (W * H) / (400.0 * 400.0) * 40)
    for _ in range(max(6, min(count, 900))):
        x0, y0 = rng.uniform(0, W), rng.uniform(0, H)
        ln = rng.uniform(1.5, 7.0) * scale
        ang = rng.uniform(-0.35, 0.35)
        d.line([(x0, y0), (x0 + np.cos(ang) * ln, y0 + np.sin(ang) * ln)],
               fill=int(rng.uniform(60, 130)), width=1)
    a = np.asarray(layer.filter(ImageFilter.GaussianBlur(0.4 * scale)), np.float32) / 255.0
    return (a[..., None] - 0.0) * 9.0  # 亮度加一点点


def apply_folds(rgb, W, H, scale, rng, folds):
    """折痕：一道暗槽 + 紧挨着的受光棱。线本身带一点弯（纸不是铁板折的）。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for name in folds:
        if name == 'v':
            pos, axis = 0.5 + rng.uniform(-0.02, 0.02), 'v'
        elif name == 'h':
            pos, axis = 0.46 + rng.uniform(-0.02, 0.02), 'h'
        elif name == 'v2':
            pos, axis = 0.24 + rng.uniform(-0.03, 0.03), 'v'
        else:
            continue
        c = (W if axis == 'v' else H) * pos
        # 折线不是笔直的：沿长度方向叠两层低频正弦弯过去
        if axis == 'v':
            off = (0.010 * W) * np.sin(2 * np.pi * yy / H + rng.uniform(0, 6.28)) \
                + (0.005 * W) * np.sin(2 * np.pi * 2.3 * yy / H + rng.uniform(0, 6.28))
            t = xx - c - off
        else:
            off = (0.010 * H) * np.sin(2 * np.pi * xx / W + rng.uniform(0, 6.28)) \
                + (0.005 * H) * np.sin(2 * np.pi * 2.3 * xx / W + rng.uniform(0, 6.28))
            t = yy - c - off
        w = max(1.4, 1.7 * scale)
        groove = np.exp(-(t / w) ** 2) * 0.16
        ridge = np.exp(-((t - 2.2 * scale) / (1.4 * scale)) ** 2) * 0.09
        rgb *= (1.0 - groove + ridge)[..., None]
        # 折痕上的磨损：沿弯折线撒的细灰点
        layer = Image.new('L', (W, H), 0)
        d = ImageDraw.Draw(layer)
        for _ in range(int(26 * scale)):
            if axis == 'v':
                x = c + rng.normal(0.0, 1.6 * scale)
                y = rng.uniform(0, H)
            else:
                x = rng.uniform(0, W)
                y = c + rng.normal(0.0, 1.6 * scale)
            r = rng.uniform(0.4, 1.2) * scale
            d.ellipse([x - r, y - r, x + r, y + r], fill=int(rng.uniform(60, 140)))
        a = (np.asarray(layer.filter(ImageFilter.GaussianBlur(0.5 * scale)), np.float32) / 255.0 * 0.22)[..., None]
        rgb *= (1.0 - a)
    return rgb


def apply_curl(rgb, alpha, W, H, scale, rng, amount):
    """把某个角卷起来：沿对角线折一刀、缺掉一角，翻起来的那半张补在里侧。
    折线上补一道亮棱、翻面上做一道渐暗，才读得出"纸角翘起来了"而不是糊了块色。"""
    if amount <= 0.0:
        return rgb, alpha
    r = min(W, H) * rng.uniform(0.17, 0.24) * amount
    sx = -1.0 if rng.random() < 0.5 else 1.0     # 从右边卷还是左边
    sy = -1.0 if rng.random() < 0.72 else 1.0    # 多数卷下角
    cx = (W - 1.0) if sx < 0 else 0.0
    cy = (H - 1.0) if sy < 0 else 0.0
    A = (cx + sx * r, cy)          # 沿水平边退 r
    B = (cx, cy + sy * r)          # 沿垂直边退 r
    C = (cx + sx * r, cy + sy * r)  # 翻过去之后的自由角
    mid = ((A[0] + B[0]) * 0.5, (A[1] + B[1]) * 0.5)
    # 折线朝角外微鼓：软纸折出来是弧的，不是直线
    dv = np.array([cx - mid[0], cy - mid[1]], np.float32)
    dv /= max(float(np.linalg.norm(dv)), 1e-6)
    bulge = rng.uniform(0.05, 0.11) * r
    m = (mid[0] + float(dv[0]) * bulge, mid[1] + float(dv[1]) * bulge)
    # 法向：后面给两条边都加撕痕抖动用
    nrm = np.array([-(B[1] - A[1]), B[0] - A[0]], np.float32)
    nrm /= max(float(np.linalg.norm(nrm)), 1e-6)

    def jag(pts_in, amp):
        out = []
        for p in pts_in:
            j = rng.uniform(-amp, amp) * r
            out.append((p[0] + float(nrm[0]) * j, p[1] + float(nrm[1]) * j))
        return out

    fold_pts = jag([((1 - t / 18.0) ** 2 * A[0] + 2 * (1 - t / 18.0) * (t / 18.0) * m[0] + (t / 18.0) ** 2 * B[0],
                     (1 - t / 18.0) ** 2 * A[1] + 2 * (1 - t / 18.0) * (t / 18.0) * m[1] + (t / 18.0) ** 2 * B[1])
                    for t in range(19)], 0.06)
    # 自由边（B→C→A）：不是两条直边，是一段朝外鼓的弧线 + 撕痕，
    # 否则翻面像一块边角笔直的补丁贴在纸上
    dc = np.array([C[0] - mid[0], C[1] - mid[1]], np.float32)
    dc /= max(float(np.linalg.norm(dc)), 1e-6)
    c_out = (C[0] + float(dc[0]) * 0.10 * r, C[1] + float(dc[1]) * 0.10 * r)
    free_pts = jag([((1 - t / 12.0) ** 2 * B[0] + 2 * (1 - t / 12.0) * (t / 12.0) * c_out[0] + (t / 12.0) ** 2 * A[0],
                     (1 - t / 12.0) ** 2 * B[1] + 2 * (1 - t / 12.0) * (t / 12.0) * c_out[1] + (t / 12.0) ** 2 * A[1])
                    for t in range(13)], 0.05)

    cut = Image.new('L', (W, H), 0)
    ImageDraw.Draw(cut).polygon(fold_pts + [(cx, cy)], fill=255)
    cut_a = np.asarray(cut.filter(ImageFilter.GaussianBlur(1.0 * scale)), np.float32) / 255.0

    flap = Image.new('L', (W, H), 0)
    ImageDraw.Draw(flap).polygon(fold_pts + free_pts, fill=255)
    flap_a = np.asarray(flap.filter(ImageFilter.GaussianBlur(1.0 * scale)), np.float32) / 255.0
    # 翻面只准画在实心纸上：撕口毛茬区（alpha 不到 0.9）不许伸出去，
    # 否则卷角会像一块贴到纸外的白补丁
    flap_a = flap_a * (alpha >= 0.9)

    a_out = np.clip(alpha * (1.0 - cut_a) + flap_a, 0.0, 1.0)

    # 翻面：折线附近受光偏亮，越到自由角越暗；背面没印过东西，偏干净浅灰
    py, px = np.mgrid[0:H, 0:W].astype(np.float32)
    ux, uy = C[0] - mid[0], C[1] - mid[1]
    un = max(float(np.hypot(ux, uy)), 1e-6)
    proj = np.clip(((px - mid[0]) * (ux / un) + (py - mid[1]) * (uy / un)) / max(r * 0.85, 1e-6), 0.0, 1.0)
    tone = (0.94 - 0.20 * proj)[..., None]
    rgb_flap = rgb * tone * 0.72 + PAPER_BACK[None, None, :] * 0.28 * tone
    rgb = rgb * (1.0 - flap_a[..., None]) + rgb_flap * flap_a[..., None]

    # 折线亮棱
    hi = Image.new('L', (W, H), 0)
    ImageDraw.Draw(hi).line(fold_pts, fill=210, width=max(1, int(scale * 0.9)))
    hi_a = (np.asarray(hi.filter(ImageFilter.GaussianBlur(0.5 * scale)), np.float32) / 255.0)[..., None]
    rgb = rgb + (np.array([255, 250, 236], np.float32) - rgb) * hi_a * 0.22

    # 自由角那一侧的边缘阴影：翻面压在自己身上，边缘压暗一圈
    edge_sh = Image.new('L', (W, H), 0)
    ImageDraw.Draw(edge_sh).polygon([A, C, B], outline=170, width=max(2, int(scale * 1.4)))
    es = (np.asarray(edge_sh.filter(ImageFilter.GaussianBlur(1.2 * scale)), np.float32) / 255.0)[..., None]
    rgb = rgb * (1.0 - es * 0.30)
    return rgb, a_out


def make_sheet(cfg, seed):
    rng = np.random.default_rng(seed)
    scale = cfg['scale']
    W, H = int(cfg['w'] * scale), int(cfg['h'] * scale)
    margin = max(2.0, min(cfg['w'], cfg['h']) * 0.045) * scale

    alpha = torn_alpha(W, H, margin, scale, rng)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dist = distance_transform_edt(alpha > 0.5)
    dmax = max(float(dist.max()), 1e-6)

    # ---- 纸底：低频斑驳 + 滚筒横纹 + 纸浆颗粒
    # 颗粒按半分辨率生成再放大、并量化到 2 的步长：肉眼看不出差别，
    # 但 PNG 熵大幅下降（放大单从 1MB 级掉到几分之一）
    field = smooth_field(W, H, rng)
    streak = np.sin(2 * np.pi * yy / H * float(rng.integers(26, 54)) + rng.uniform(0, 6.28))
    gh, gw = max(2, H // 2), max(2, W // 2)
    grain_small = rng.normal(0.0, 4.4, (gh, gw)).astype(np.float32)
    grain = np.repeat(np.repeat(grain_small, 2, axis=0), 2, axis=1)[:H, :W]
    grain = np.round(grain / 2.0) * 2.0

    shade = 1.0 + 0.075 * field + 0.011 * streak
    rgb = PAPER[None, None, :] * shade[..., None] + grain[..., None]

    # 大范围暖化：离纸心越远越黄褐，中心保持米黄
    t_body = near(dist, 0.50 * dmax) ** 1.2
    rgb = rgb * (1.0 - t_body[..., None] * 0.62) + PAPER_OUT[None, None, :] * t_body[..., None] * 0.62
    # 低频斑驳的暗面压一层灰脏：报纸不会整张均匀，总有几块发灰
    dirty = (np.clip(-field, 0.0, 1.0) * 0.20)[..., None]
    rgb = rgb * (1.0 - dirty) + DIRT[None, None, :] * dirty

    # ---- 印刷残留（压在污渍下面：污渍会盖掉墨迹，这才是真实顺序）
    ghost = ghost_print(W, H, scale, rng, cfg['ghost'])
    if ghost.any():
        g = ghost[..., None]
        rgb = rgb * (1.0 - g) + INK[None, None, :] * g

    # ---- 水渍、油污
    st = water_stains(W, H, scale, rng, int(cfg['stains']))
    rgb = rgb * (1.0 - st) + STAIN[None, None, :] * st
    if cfg['specks']:
        sp = oil_specks(W, H, scale, rng)
        rgb = rgb * (1.0 - sp) + GRIME[None, None, :] * sp

    # ---- 纸纤维
    rgb = rgb + paper_fibers(W, H, scale, rng)

    # ---- 折痕
    rgb = apply_folds(rgb, W, H, scale, rng, cfg['folds'])

    # ---- 边缘氧化：近处一圈重褐，再往外一圈轻黄，最外一线几乎发黑
    # 卡片上要排字，氧化带按 oxide 收窄压轻；大张随便重
    oxide = float(cfg.get('oxide', 1.0))
    t_edge = near(dist, 26.0 * scale * oxide) ** 1.0
    s_edge = 0.88 * (0.55 + 0.45 * oxide)
    rgb = rgb * (1.0 - t_edge[..., None] * s_edge) + EDGE[None, None, :] * t_edge[..., None] * s_edge
    t_corner = near(dist, 48.0 * scale * oxide) * (0.30 + 0.20 * oxide)
    rgb = rgb * (1.0 - t_corner[..., None]) + EDGE[None, None, :] * t_corner[..., None]
    # 撕口最外一线：污垢压黑（纸被手摸过、被墙蹭过）
    t_rim = near(dist, 1.6 * scale)
    rgb = rgb * (1.0 - t_rim[..., None] * 0.40) + GRIME[None, None, :] * t_rim[..., None] * 0.40

    # ---- 卷角（放在最后：翻面有自己的明暗，不该再被氧化糊一遍）
    rgb, alpha = apply_curl(rgb, alpha, W, H, scale, rng, float(cfg['curl']))

    out = np.concatenate([rgb, (alpha * 255.0)[..., None]], axis=2)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')


def preview(key, paths):
    """把所有变体拼到深灰底上，跟概念图同一个视角看，方便判断质感。"""
    imgs = [Image.open(p) for p in paths]
    pad = 24
    w = sum(i.width for i in imgs) + pad * (len(imgs) + 1)
    h = max(i.height for i in imgs) + pad * 2
    canvas = Image.new('RGB', (w, h), (46, 46, 44))
    x = pad
    for i in imgs:
        canvas.paste(i, (x, pad), i)
        x += i.width + pad
    path = os.path.join(PREVIEW_DIR, 'tmp_paper_%s.png' % key)
    canvas.save(path)
    print('preview', os.path.basename(path), canvas.size)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for cfg in SHEETS:
        key = '%dx%d' % (cfg['w'], cfg['h'])
        paths = []
        for i in range(cfg['variants']):
            img = make_sheet(cfg, 1200 + cfg['w'] * 7 + cfg['h'] * 13 + i * 131)
            path = os.path.join(OUT_DIR, 'billpaper_%s_%d.png' % (key, i))
            img.save(path, optimize=True, compress_level=9)
            paths.append(path)
            print('saved', os.path.basename(path), img.size)
        preview(key, paths)


if __name__ == '__main__':
    main()
