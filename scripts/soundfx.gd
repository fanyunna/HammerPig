extends Node

## 程序化音效：项目里只有 assets/hit.wav 一个素材，其余声音全部在这里现合成 buffer（AudioStreamWav）。
## 为什么这么做：这个项目的风格就是"能用代码生成的就别放素材"（看 desk3d.gd 的绒面贴图），
## 音效同理 —— 不用去找音频资源，改参数就能调手感。

## 两个合成原语：
##   tone  —— 扫频振荡器（正弦/三角/方波）+ 指数衰减包络：彭、叮、金属脆响、下行失败音
##   noise —— 白噪声过一阶低通 + 指数衰减：风、碎裂、纸张、摩擦
## 用法：Sound.play("pop")；单个音想变调就 Sound.play("cash", 1.2)。"crack" 例外 —— 走素材 hit.wav。

const RATE := 44100
const LIST := {
    "miss": 0.16,       # 挥空：一道风
    "pop": 0.34,        # 猪碎：闷响 + 碎裂
    "cash": 0.16,       # 进账：一声清脆的"叮"
    "coin_roll": 0.42,  # 硬币滚过桌面：持续的摩擦声
    "coin_land": 0.30,  # 停稳：金属余韵
    "flip": 0.34,       # 抛起来：呼的一声上行
    "heads": 0.55,      # 正面：上扬
    "tails": 0.70,      # 反面：下坠
    "stamp": 0.24,      # 盖章 / 账单砸下来
    "fail": 0.60,       # 考核失败：下行 + 噪声
    "lose": 1.10,       # 破产：长下坠
    "win": 0.90,        # 摆脱破产：三音上行
    "card": 0.26,       # 翻牌：纸张
    "click": 0.06,      # UI 点击：极轻的一声
}

var muted := false

var _players: Array = []
var _next := 0
var _cache := {}


func _ready() -> void:
    for i in range(6): # 轮转使用：连打时前一个音不会被后一个掐断
        var p := AudioStreamPlayer.new()
        p.volume_db = 0.0
        add_child(p)
        _players.append(p)


func play(name: String, pitch := 1.0, gain := 1.0) -> void:
    if muted or _players.is_empty() or gain <= 0.0:
        return
    var stream: AudioStream = _make(name)
    if stream == null:
        return
    var p: AudioStreamPlayer = _players[_next]
    _next = (_next + 1) % _players.size()
    p.stream = stream
    p.pitch_scale = pitch
    p.volume_db = linear_to_db(gain)
    p.play()


func toggle() -> bool:
    muted = not muted
    if muted:
        for p in _players: # 静音要立刻生效，正在响的音也停掉
            (p as AudioStreamPlayer).stop()
    return muted


func _make(name: String) -> AudioStream:
    if _cache.has(name):
        return _cache[name]
    if name == "crack": # 保留原有素材：这一声的手感已经调好了
        var wav: AudioStream = load("res://assets/hit.wav")
        _cache["crack"] = wav
        return wav
    if not LIST.has(name):
        push_warning("Sound: 没有这个音效 " + name)
        return null
    var buf := PackedFloat32Array()
    buf.resize(int(float(LIST[name]) * RATE))
    buf.fill(0.0)
    _build(name, buf)
    var stream := _wav(buf)
    _cache[name] = stream
    return stream


## —— 合成原语 ——

func _tone(buf: PackedFloat32Array, f0: float, f1: float, dur: float, wave: int, amp: float, decay: float, delay := 0.0) -> void:
    var n := int(dur * RATE)
    var start := int(delay * RATE)
    var ph := 0.0 # 累加相位才是真正的扫频：用 t*f 会在变频时产生相位跳变
    for i in range(n):
        if start + i >= buf.size():
            break
        var p := float(i) / float(n)
        ph += lerpf(f0, f1, p) / RATE
        var v: float
        match wave:
            0: v = sin(ph * TAU)
            1: v = 4.0 * absf(ph - floorf(ph + 0.5)) - 1.0 # 三角
            _: v = 1.0 if (ph - floorf(ph)) < 0.5 else -1.0 # 方波
        buf[start + i] += v * amp * exp(-decay * p)


## cutoff 越小越闷（可听 nyquist）：0.5 是沙沙的风声，0.05 是低沉的轰
func _noise(buf: PackedFloat32Array, dur: float, cutoff: float, amp: float, decay: float, delay := 0.0) -> void:
    var n := int(dur * RATE)
    var start := int(delay * RATE)
    var lp := 0.0
    for i in range(n):
        if start + i >= buf.size():
            break
        lp += ((randf() * 2.0 - 1.0) - lp) * cutoff
        buf[start + i] += lp * amp * exp(-decay * float(i) / float(n))


func _wav(buf: PackedFloat32Array) -> AudioStreamWAV: # 注意类名是全大写 WAV（Godot 4 的老写法 AudioStreamSample 已废弃）
    var peak := 0.0
    for v in buf:
        peak = maxf(peak, absf(v))
    var g: float = 0.95 / peak if peak > 0.001 else 1.0 # 归一化到 0.95，多个音叠加时不会爆
    var bytes := PackedByteArray()
    bytes.resize(buf.size() * 2)
    for i in range(buf.size()):
        bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
    var s := AudioStreamWAV.new()
    s.format = AudioStreamWAV.FORMAT_16_BITS
    s.mix_rate = RATE
    s.data = bytes
    return s


## —— 每个音效的配方 ——
## 手感规律：撞击类用"低频 tone 下行 + 短 noise"（低频给体积感，噪声给"接触"的毛边）；
## 钱/金属类用"高频三角波 + 大 decay"（没有谐波，听感才干净）。

func _build(name: String, buf: PackedFloat32Array) -> void:
    match name:
        "miss": # 挥空：什么都没打到的风声，要比命中轻得多
            _noise(buf, 0.14, 0.42, 0.5, 9.0)
            _tone(buf, 300.0, 120.0, 0.10, 1, 0.12, 7.0)
        "pop": # 猪碎：闷响（低频下行）+ 一层碎裂
            _tone(buf, 200.0, 55.0, 0.26, 1, 0.85, 5.0)
            _noise(buf, 0.20, 0.14, 0.55, 11.0)
            _tone(buf, 900.0, 420.0, 0.09, 0, 0.25, 12.0, 0.02) # 碎裂的那一点脆
        "cash": # 进账：三角波的高音"叮"，干净才像钱
            _tone(buf, 940.0, 1450.0, 0.13, 1, 0.5, 6.0)
            _tone(buf, 1880.0, 2900.0, 0.10, 0, 0.14, 9.0)
        "coin_roll": # 滚：持续摩擦 + 一点点金属颤动
            _noise(buf, 0.40, 0.30, 0.34, 2.6)
            for i in range(7):
                _tone(buf, 1500.0 + randf() * 900.0, 900.0, 0.06, 0, 0.1, 14.0, 0.03 + float(i) * 0.055)
        "coin_land": # 停稳：金属余韵长，所以 decay 给小值
            _tone(buf, 2600.0, 1500.0, 0.26, 0, 0.42, 13.0)
            _tone(buf, 1200.0, 900.0, 0.20, 1, 0.2, 16.0, 0.01)
            _noise(buf, 0.05, 0.5, 0.2, 25.0)
        "flip": # 抛起来：呼的一声上行
            _tone(buf, 520.0, 1900.0, 0.30, 1, 0.42, 5.0)
            _noise(buf, 0.16, 0.35, 0.22, 8.0)
        "heads": # 正面：上扬，多一层高八度才显得"赚了"
            _tone(buf, 784.0, 1046.0, 0.30, 1, 0.45, 3.0)
            _tone(buf, 1568.0, 2093.0, 0.26, 0, 0.16, 4.0, 0.02)
            _tone(buf, 523.0, 784.0, 0.34, 1, 0.3, 2.6, 0.14)
        "tails": # 反面：下坠到底，最后加一层低沉的轰（钱没了）
            _tone(buf, 320.0, 88.0, 0.62, 1, 0.5, 2.4)
            _noise(buf, 0.30, 0.06, 0.4, 3.0, 0.10)
        "stamp": # 盖章：一记实心闷击
            _tone(buf, 150.0, 52.0, 0.20, 2, 0.8, 8.0)
            _noise(buf, 0.11, 0.09, 0.5, 11.0)
        "fail": # 考核失败：下行 + 一口气叹出去的噪声
            _tone(buf, 260.0, 90.0, 0.46, 1, 0.5, 3.0)
            _noise(buf, 0.30, 0.12, 0.28, 4.0, 0.06)
        "lose": # 破产：最长的下坠，最后落在噪声里
            _tone(buf, 180.0, 38.0, 1.00, 1, 0.55, 1.8)
            _tone(buf, 90.0, 30.0, 0.90, 2, 0.22, 2.2, 0.06)
            _noise(buf, 0.55, 0.05, 0.3, 2.4, 0.14)
        "win": # 摆脱破产：三音上行
            _tone(buf, 523.0, 523.0, 0.20, 1, 0.4, 4.0, 0.00)
            _tone(buf, 659.0, 659.0, 0.20, 1, 0.4, 4.0, 0.16)
            _tone(buf, 784.0, 784.0, 0.34, 1, 0.45, 3.0, 0.32)
            _tone(buf, 1568.0, 1568.0, 0.30, 0, 0.12, 4.0, 0.32)
        "card": # 翻牌：纸张摩擦，两下
            _noise(buf, 0.13, 0.55, 0.5, 9.0, 0.00)
            _noise(buf, 0.10, 0.45, 0.36, 11.0, 0.11)
        "click": # UI：短到几乎只是一个"搭"
            _tone(buf, 1500.0, 1150.0, 0.05, 1, 0.28, 20.0)
