"""生成旧报纸质感的账单纸：撕边、缺角、毛茬、油渍、折痕、边缘氧化。

用法：python tools/gen_newsprint.py
产出：assets/art/billpaper_<w>x<h>_<i>.png（每种显示尺寸若干变体）

为什么是"整张带 alpha 的纸"而不是一张可平铺的纹理：
- 用户要的是"边角破破烂烂"，纸的外形本身不规则（缺角、撕口、外伸的纸茬），
  这类形状没法用矩形贴图 + 代码描边做出来，只能烘在 alpha 通道里；
- 账单的显示尺寸只有四种（账本卡 / 桌上卡 / 放大单 / HUD 图标），全部固定，
  所以每种尺寸各生成几张变体、按账单号挑一张即可，绘制时一次 draw_texture_rect。
- 纸色、污渍、折痕都烘进 RGB；字和红线由 GDScript 排在纸的安全区里。
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(BASE, 'assets', 'art')

# 逻辑尺寸 (w, h)、放大倍数、变体数、是否画折痕、是否画水渍
SHEETS = [
    (236, 74, 3, 4, True, False),    # 账本里摊开的小卡（有淡折痕）
    (182, 100, 3, 3, True, False),   # 桌上快捷那一沓
    (420, 570, 2, 3, True, True),    # 点开放大的催缴单
    (46, 30, 3, 2, False, False),    # HUD 里的小纸叠
]

NEWSPRINT = np.array([233, 226, 208], np.float32)  # 新闻纸：偏灰的米黄，不是奶油
STAIN = np.array([152, 130, 90], np.float32)       # 水渍/油渍
EDGE = np.array([146, 117, 72], np.float32)        # 边缘氧化（发黄发褐）


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


def torn_mask(W, H, margin, scale, rng):
    """按四条边各自的不规则曲线拼出一张撕过的纸（L 掩膜）。四个角各自独立地缺一块。"""
    amp = 1.9 * scale
    depth = 7.0 * scale
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
    for i in range(0, len(pts), 5):
        if rng.random() > 0.18:
            continue
        x, y = pts[i]
        ang = np.arctan2(y - cy, x - cx) + rng.uniform(-0.3, 0.3)
        length = rng.uniform(0.8, 3.6) * scale
        dr.line([(x, y), (x + np.cos(ang) * length, y + np.sin(ang) * length)],
                fill=int(rng.uniform(170, 255)), width=max(1, int(round(scale * 0.6))))

    return mask.filter(ImageFilter.GaussianBlur(0.5 * scale))


def make_sheet(w, h, scale, seed, creases, water):
    rng = np.random.default_rng(seed)
    W, H = int(w * scale), int(h * scale)
    margin = max(2.0, min(w, h) * 0.045) * scale

    mask_img = torn_mask(W, H, margin, scale, rng)
    alpha = np.asarray(mask_img, np.float32) / 255.0

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # 斑驳：报纸最典型的就是深浅不匀的灰块
    field = np.zeros((H, W), np.float32)
    for _ in range(9):
        fx, fy = rng.uniform(0.7, 3.5), rng.uniform(0.7, 3.5)
        field += np.sin(2 * np.pi * (fx * xx / W + fy * yy / H) + rng.uniform(0, 6.28)) * rng.uniform(0.3, 1.0)
    field /= max(np.abs(field).max(), 1e-6)

    # 滚筒压出的横向细纹 + 纸浆颗粒
    # 颗粒按半分辨率生成再放大、并量化到 2 的步长：肉眼看不出差别，
    # 但 PNG 熵大幅下降（放大单从 1.2MB 掉到几分之一）
    streak = np.sin(2 * np.pi * yy / H * rng.integers(26, 54) + rng.uniform(0, 6.28))
    gh, gw = max(2, H // 2), max(2, W // 2)
    grain_small = rng.normal(0.0, 4.2, (gh, gw)).astype(np.float32)
    grain = np.repeat(np.repeat(grain_small, 2, axis=0), 2, axis=1)[:H, :W]
    grain = np.round(grain / 2.0) * 2.0

    shade = 1.0 + 0.045 * field + 0.010 * streak
    rgb = NEWSPRINT[None, None, :] * shade[..., None] + grain[..., None]

    # 油渍 / 水渍：几块柔和脏斑
    blot = Image.new('L', (W, H), 0)
    bd = ImageDraw.Draw(blot)
    for _ in range(int(rng.integers(3, 6))):
        bw = rng.uniform(0.10, 0.30) * W
        bh = rng.uniform(0.06, 0.22) * H
        bx = rng.uniform(0.04, 0.86) * W
        by = rng.uniform(0.04, 0.86) * H
        bd.ellipse([bx, by, bx + bw, by + bh], fill=int(rng.uniform(45, 110)))
    if water:  # 一杯水放上去过：留一圈边
        rx = rng.uniform(0.15, 0.55) * W
        ry = rng.uniform(0.12, 0.40) * H
        rc = rng.uniform(0.18, 0.34) * min(W, H)
        bd.ellipse([rx, ry, rx + rc * 1.9, ry + rc], outline=int(rng.uniform(90, 150)), width=max(1, int(2 * scale)))
    blot = blot.filter(ImageFilter.GaussianBlur(6 * scale))
    ba = (np.asarray(blot, np.float32) / 255.0)[..., None] * 0.55
    rgb = rgb * (1 - ba) + STAIN[None, None, :] * ba

    # 报纸的十字折痕（只给大张）：一亮一暗，才有折过的体积感
    if creases:
        for pos, axis in ((0.5, 'v'), (0.46, 'h')):
            if axis == 'v':
                c = int(W * pos)
                rgb[:, c - 1:c + 1] *= 1.05
                rgb[:, c + 1:c + 3] *= 0.94
                rgb[:, c - 3:c - 1] *= 0.965
            else:
                c = int(H * pos)
                rgb[c - 1:c + 1, :] *= 1.05
                rgb[c + 1:c + 3, :] *= 0.94
                rgb[c - 3:c - 1, :] *= 0.965

    # 边缘氧化：距边越近越黄褐，角落再叠一层更重的氧化
    dist = distance_transform_edt(alpha > 0.5)
    near = np.clip(1.0 - dist / (9.0 * scale), 0.0, 1.0)[..., None]
    rgb = rgb * (1 - near * 0.42) + EDGE[None, None, :] * near * 0.42
    corner = np.clip(1.0 - dist / (30.0 * scale), 0.0, 1.0)[..., None]
    rgb = rgb * (1 - corner * 0.16) + EDGE[None, None, :] * corner * 0.16

    # 被翻旧的细划痕
    scratch = Image.new('L', (W, H), 0)
    sd = ImageDraw.Draw(scratch)
    for _ in range(int(9 * scale)):
        x0 = rng.uniform(0, W)
        y0 = rng.uniform(0, H)
        ln = rng.uniform(0.04, 0.18) * W
        ang = rng.uniform(-0.5, 0.5)
        sd.line([(x0, y0), (x0 + np.cos(ang) * ln, y0 + np.sin(ang) * ln)],
                fill=int(rng.uniform(28, 76)), width=1)
    sa = (np.asarray(scratch.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0)[..., None] * 0.10
    rgb = rgb * (1 - sa)

    out = np.concatenate([rgb, (alpha * 255.0)[..., None]], axis=2)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for w, h, scale, variants, creases, water in SHEETS:
        for i in range(variants):
            img = make_sheet(w, h, scale, 1200 + w * 7 + i * 131, creases, water)
            path = os.path.join(OUT_DIR, 'billpaper_%dx%d_%d.png' % (w, h, i))
            img.save(path, optimize=True, compress_level=9)
            print('saved', os.path.basename(path), img.size)


if __name__ == '__main__':
    main()
