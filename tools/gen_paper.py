"""生成旧纸贴图（四边无缝，可按格拼贴而不被拉伸）。

用法：python tools/gen_paper.py
产出：assets/art/paper_grain.png  256x256 RGBA

为什么是"斑点贴图"而不是一张整纸：
- 纸的底色、轮廓、折角、边缘发黄都在 main.gd 里按每张账单实时画（尺寸和旋转每次都不同），
  贴图只负责"纤维 / 灰点 / 浅色纸筋"这层不随形状变化的微纹理；
- 贴图四边无缝，所以 236px 的小卡片和整屏的催缴单都能用同一张，不会被拉长变形。
"""
import os

import numpy as np
from PIL import Image, ImageDraw

W = H = 256
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BASE, 'assets', 'art', 'paper_grain.png')

# 旧纸上的脏东西都是暖褐色的，浅色纸筋则是米白 —— 两种颜色分开画，最后合成
DIRT = (104, 82, 56)
FIBER = (255, 252, 242)


def sinus_mottle():
    """低频斑驳：用整数频率的正弦叠加，天然以 W/H 为周期 —— 四边无缝。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    field = np.zeros((H, W), np.float32)
    rng = np.random.default_rng(7)
    for _ in range(9):
        fx = int(rng.integers(1, 5))
        fy = int(rng.integers(1, 5))
        amp = float(rng.uniform(0.35, 1.0))
        phase = float(rng.uniform(0, 2 * np.pi))
        field += amp * np.sin(2 * np.pi * (fx * xx / W + fy * yy / H) + phase)
    field -= field.min()
    field /= max(field.max(), 1e-6)
    return field


def build():
    rng = np.random.default_rng(11)

    # 1) 低频斑驳 → 淡淡的脏块（alpha 0~18）
    mottle = sinus_mottle()
    alpha = (mottle ** 2.2) * 18.0

    # 2) 细颗粒：纸浆纤维之间的空隙（alpha 0~26）
    grain = rng.normal(0.0, 1.0, (H, W)).astype(np.float32)
    alpha += np.clip(grain * 7.0 + 9.0, 0.0, 26.0)

    # 3) 少量顽固污点（比周围明显一点，但绝不该像噪点）
    for _ in range(90):
        x = int(rng.integers(0, W))
        y = int(rng.integers(0, H))
        r = float(rng.uniform(0.4, 1.3))
        strength = float(rng.uniform(28, 70))
        yy, xx = np.mgrid[-3:4, -3:4].astype(np.float32)
        d = np.sqrt(xx * xx + yy * yy)
        stamp = np.clip(1.0 - d / (r + 1.0), 0.0, 1.0)
        ys = (y + np.arange(-3, 4)) % H
        xs = (x + np.arange(-3, 4)) % W
        sub = alpha[np.ix_(ys, xs)]
        alpha[np.ix_(ys, xs)] = np.clip(sub + stamp * strength * 0.5, 0.0, 92.0)

    a = np.clip(alpha, 0, 255).astype(np.uint8)
    img = Image.new('RGBA', (W, H), DIRT + (0,))
    img.putalpha(Image.fromarray(a, 'L'))

    # 4) 浅色纸筋（纤维）：细短弧线，画九次保证跨边的也接得上
    fib = Image.new('RGBA', (W, H), FIBER + (0,))
    dr = ImageDraw.Draw(fib)
    for _ in range(46):
        x = float(rng.uniform(0, W))
        y = float(rng.uniform(0, H))
        ang = float(rng.uniform(0, np.pi))
        length = float(rng.uniform(9, 34))
        bend = float(rng.uniform(-0.5, 0.5))
        pa = int(rng.uniform(18, 46))
        dx, dy = np.cos(ang), np.sin(ang)
        pts = []
        for t in np.linspace(0.0, 1.0, 5):
            pts.append((x + dx * length * t - dy * bend * np.sin(np.pi * t) * 5,
                        y + dy * length * t + dx * bend * np.sin(np.pi * t) * 5))
        for ox in (-W, 0, W):
            for oy in (-H, 0, H):
                dr.line([(px + ox, py + oy) for px, py in pts], fill=FIBER + (pa,), width=1)

    img = Image.alpha_composite(img, fib)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print('saved', OUT, img.size)


if __name__ == '__main__':
    build()
