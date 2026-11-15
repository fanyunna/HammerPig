extends SceneTree

## 工具：把 scripts/soundfx.gd 现场合成的音效各导出一份 wav 到 _sfx/，方便试听和校对，
## 同时自检有没有静音、削波（合成参数写错时最容易出的两种问题）。
## 用法：godot --headless --path . --script res://tests/export_sfx.gd
## 注意：游戏运行时不读 _sfx/ 里的文件，声音始终是实时合成的，这个目录纯粹是给耳朵用的。

func _initialize() -> void:
	run.call_deferred()

func peak(s: AudioStreamWAV) -> float:
	var d: PackedByteArray = s.data
	var m := 0
	for i in range(0, d.size(), 2):
		m = maxi(m, absi(d.decode_s16(i)))
	return float(m) / 32767.0

func save_wav(path: String, s: AudioStreamWAV) -> void:
	var data: PackedByteArray = s.data
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("RIFF")
	f.store_32(36 + data.size())
	f.store_string("WAVEfmt ")
	f.store_32(16)
	f.store_16(1) # PCM
	f.store_16(1) # mono
	f.store_32(int(s.mix_rate))
	f.store_32(int(s.mix_rate) * 2) # byte rate
	f.store_16(2) # block align
	f.store_16(16) # bits
	f.store_string("data")
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()

func run() -> void:
	var snd := root.get_node_or_null("Sound") # --script 模式下 autoload 在本脚本编译之后才挂载，只能运行时取
	if snd == null:
		print("问题: Sound autoload 没挂载")
		quit()
		return
	DirAccess.make_dir_recursive_absolute("res://_sfx")
	var names: Array = snd.LIST.keys()
	names.append("crack") # 走素材的那一声
	var bad: Array = []
	for n in names:
		var s: AudioStream = snd._make(n)
		if s == null:
			bad.append(n + ":生成失败")
			continue
		var p: float = peak(s)
		if p < 0.1:
			bad.append(n + ":几乎静音(" + str(p) + ")")
		if s is AudioStreamWAV:
			save_wav("res://_sfx/" + String(n) + ".wav", s)
		print(String(n).lpad(12), "%.2f" % float(snd.LIST.get(n, 0.0)), "s  peak=", "%.2f" % p)
	print("OK" if bad.is_empty() else ("问题: " + ", ".join(bad)))
	quit()
