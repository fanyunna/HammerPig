# -*- coding: utf-8 -*-
"""精绘吊灯灯泡贴图：输出 assets/art/bulb_lit.png（透明背景、全亮状态）。

设计要点：
- 梨形玻璃用显式宽度剖面 w(y)（cos 插值），轮廓平滑不带棱角
- 玻璃着色 = 径向暖光渐变 + 轮廓边缘暗色带 + 底部内透光
- 灯丝 = 暗红支撑线 + 三层高斯模糊辉光（橙晕 -> 中层 -> 白热芯）
- 黄铜灯座 = 垂直渐变 + 圆柱横向明暗 + 螺纹亮暗条 + 底部接触帽
- 整图在 Godot 里以 68x85 屏幕像素绘制（8 倍缩小，天然抗锯齿）
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

BASE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
OUT = os.path.join(BASE, 'assets', 'art', 'bulb_lit.png')

W, H = 512, 640
CX = 256.0

# 玻璃形状按真实白炽灯泡（A19）量：圆球 + 短颈插进灯座，肩部是球和圆柱
# 相交出来的 S 过渡，底部是圆弧收拢 —— 绝不是收成尖点的水滴形。
BULB_CY, RX, RY = 432.0, 205.0, 196.0   # 球部椭圆（球心/半径）
NECK_HW, NECK_BOT = 74.0, 345.0          # 颈部半宽 / 颈长（半宽略小于灯座，玻璃是插进座里的）
GLASS_TOP = 230.0


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def build_glass():
    """玻璃：球部椭圆 + 颈部圆柱重叠后模糊取阈 —— 肩部自然 S 形，圆底无尖点。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ball = (((xx - CX) / RX) ** 2 + ((yy - BULB_CY) / RY) ** 2) <= 1.0
    neck = (np.abs(xx - CX) <= NECK_HW) & (yy >= GLASS_TOP) & (yy <= NECK_BOT)
    m = Image.fromarray(((ball | neck) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    mask = np.asarray(m, np.float32) > 140
    half = mask.sum(axis=1).astype(np.float32) * 0.5  # 每行半宽

    # 径向暖光渐变（光心 = 灯丝位置，球心略偏下）
    d = np.sqrt((xx - CX) ** 2 + (yy - 430.0) ** 2) / 150.0
    stops = [(0.0, (255, 246, 208)), (0.5, (255, 230, 156)),
             (0.9, (243, 206, 118)), (1.2, (206, 164, 88))]
    r = np.zeros_like(d)
    g = np.zeros_like(d)
    b = np.zeros_like(d)
    for i in range(len(stops) - 1):
        d0, c0 = stops[i]
        d1, c1 = stops[i + 1]
        sel = (d >= d0) & (d <= d1)
        t = ((d[sel] - d0) / (d1 - d0))[..., None]
        c0a = np.array(c0, np.float32)
        c1a = np.array(c1, np.float32)
        r[sel] = (c0a[0] + (c1a[0] - c0a[0]) * t[..., 0])
        g[sel] = (c0a[1] + (c1a[1] - c0a[1]) * t[..., 0])
        b[sel] = (c0a[2] + (c1a[2] - c0a[2]) * t[..., 0])
    hi = d > 1.2
    r[hi], g[hi], b[hi] = stops[-1][1]

    # 轮廓边缘暗色带：离边缘越近越暗，像玻璃厚度
    edge = half[:, None] - np.abs(xx - CX)
    ef = np.clip(edge / 30.0, 0.0, 1.0)
    dark = np.array([148, 110, 58], np.float32)
    mix = ((1.0 - ef) * 0.62)[..., None]
    rgb = np.stack([r, g, b], axis=-1) * (1 - mix) + dark * mix

    # 底部内透光：光从灯丝往玻璃底聚
    dg = np.sqrt((xx - CX) ** 2 + (yy - 505.0) ** 2)
    add = (110.0 * np.exp(-(dg / 52.0) ** 2))[..., None]
    rgb = np.clip(rgb + add * np.array([1.0, 0.82, 0.42]), 0, 255)

    alpha = np.where(mask, 255, 0).astype(np.uint8)
    img = Image.fromarray(np.dstack([rgb.astype(np.uint8), alpha]), 'RGBA')

    # 3px 深色描边（玻璃厚度感）
    m = Image.new('L', (W, H), 0)
    m.paste(255, mask=Image.fromarray(alpha))
    outline = ImageChops.subtract(m, m.filter(ImageFilter.MinFilter(7)))
    solid = Image.new('RGBA', (W, H), (58, 42, 26, 255))
    transparent = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ol = Image.composite(solid, transparent, outline)
    img.alpha_composite(ol)
    return img, Image.fromarray(alpha)


def glass_mask_soft(alpha_img):
    """玻璃遮罩（边缘微模糊），用来裁灯丝辉光。"""
    return alpha_img.filter(ImageFilter.GaussianBlur(4))


def add_filament(img, glass_alpha):
    """灯丝：暗支撑线 + 三层辉光，全部裁进玻璃内。"""
    clip = glass_mask_soft(glass_alpha)

    def line_layer(points, color, width, blur, alpha_mul=1.0):
        layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        dr = ImageDraw.Draw(layer)
        dr.line(points, fill=color + (255,), width=width, joint='curve')
        if blur:
            layer = layer.filter(ImageFilter.GaussianBlur(blur))
        if alpha_mul < 1.0:
            a = layer.getchannel('A').point(lambda v: int(v * alpha_mul))
            layer.putalpha(a)
        return Image.composite(layer, Image.new('RGBA', (W, H), (0, 0, 0, 0)), clip)

    # 支撑线（从颈内垂下来，末端挂在球心附近）
    sup = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sup)
    sd.line([(235, 255), (243, 400)], fill=(92, 70, 46, 255), width=7, joint='curve')
    sd.line([(277, 255), (269, 400)], fill=(92, 70, 46, 255), width=7, joint='curve')
    img.alpha_composite(Image.composite(sup, Image.new('RGBA', (W, H), (0, 0, 0, 0)), clip))

    coil = [(242, 415), (251, 478), (256, 392), (261, 478), (270, 415)]
    img.alpha_composite(line_layer(coil, (255, 138, 48), 30, 30, 0.9))
    img.alpha_composite(line_layer(coil, (255, 196, 100), 16, 12, 0.95))
    img.alpha_composite(line_layer(coil, (255, 250, 222), 8, 2))


def add_specular(img):
    """左上柔和高光 + 右下微弱次高光，玻璃质感的关键。"""
    lay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(lay)
    dr.ellipse([(198, 342), (262, 424)], fill=(255, 255, 248, 240))
    lay = lay.rotate(-18, center=(230, 383), resample=Image.BICUBIC)
    lay = lay.filter(ImageFilter.GaussianBlur(8))
    img.alpha_composite(lay)

    lay2 = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dr2 = ImageDraw.Draw(lay2)
    dr2.ellipse([(308, 400), (342, 478)], fill=(255, 250, 230, 105))
    lay2 = lay2.filter(ImageFilter.GaussianBlur(9))
    img.alpha_composite(lay2)


def build_socket():
    """黄铜螺纹灯座：垂直渐变 + 圆柱明暗 + 螺纹 + 接触帽 + 描边。"""
    x0, x1, y0, y1 = 168, 344, 10, 238
    sw, sh = x1 - x0, y1 - y0

    ys = np.linspace(0, 1, sh, dtype=np.float32)[:, None]
    xs = np.linspace(0, 1, sw, dtype=np.float32)[None, :]
    top = np.array([172, 128, 70], np.float32)
    bot = np.array([212, 174, 104], np.float32)
    grad = top[None, None, :] + (bot - top)[None, None, :] * ys[..., None]
    # 圆柱横向明暗：两侧压暗、中轴提亮
    cyl = (0.68 + 0.32 * np.sin(np.pi * xs))[..., None]
    rgb = np.clip(grad * cyl, 0, 255).astype(np.uint8)
    body = Image.fromarray(np.dstack([np.broadcast_to(rgb, (sh, sw, 3)),
                                      np.full((sh, sw), 255, np.uint8)]), 'RGBA')

    dr = ImageDraw.Draw(body)
    # 螺纹：暗条 + 亮条成对
    for ry in (44, 84, 124, 164, 204):
        dr.rectangle([0, ry - y0, sw, ry - y0 + 6], fill=(112, 80, 40, 255))
        dr.rectangle([0, ry - y0 + 6, sw, ry - y0 + 12], fill=(246, 222, 170, 255))
    # 顶部进线帽压暗（不透明，避免 ImageDraw 替换 alpha 透底）
    dr.rectangle([0, 0, sw, 26], fill=(104, 72, 38, 255))

    # 圆角裁切 + 描边
    mask = Image.new('L', (sw, sh), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, sw - 1, sh - 1], radius=24, fill=255)
    socket = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    socket.paste(body, (x0, y0), mask)
    od = ImageDraw.Draw(socket)
    od.rounded_rectangle([x0, y0, x1, y1], radius=24, outline=(58, 42, 26, 255), width=5)
    # 底部封口：座底本身就是金属底盖，压一道暗条即可，不再突出一块
    od.rectangle([x0 + 6, y1 - 18, x1 - 6, y1 - 6], fill=(96, 66, 36, 255))
    od.rectangle([x0 + 6, y1 - 18, x1 - 6, y1 - 16], fill=(214, 178, 110, 255))
    return socket


def main():
    img, glass_alpha = build_glass()
    add_filament(img, glass_alpha)
    add_specular(img)
    img.alpha_composite(build_socket())
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print('saved', OUT, img.size)


if __name__ == '__main__':
    main()
