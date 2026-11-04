extends SceneTree
## gen_audio.gd —— 程序化音效/音乐生成(M6,01 §12 / 02 §5 同管线)。
## 全部音频由本脚本合成:16bit PCM 44100Hz 单声道 WAV → assets/audio/。
## 固定 seed(噪声/脆响位置可复现);色彩性参数与贴图管线同理「离线烘焙进仓库」。
## 清单(01 §12):挥砍/命中/敌兵死亡/拾取军资 + 7 技能音色 + 波次号角/按钮/
## 胜利五声音阶短句/失败低音锣 + BGM 五声音阶循环(音量压低)= 15 sfx + 1 BGM。
## 运行:godot.cmd --headless --path <工程> --script res://tools/gen_audio.gd

const SR := 44100
const OUT_DIR := "res://assets/audio/"
const SEED := 20261104
const TAU := 6.283185307179586

var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var made: Array = []
	var ok := true
	ok = _gen("sfx_slash.wav", _slash()) and ok
	made.append("sfx_slash.wav 挥砍(短噪声脉冲)")
	ok = _gen("sfx_hit.wav", _hit()) and ok
	made.append("sfx_hit.wav 命中(低频 thud)")
	ok = _gen("sfx_die.wav", _die()) and ok
	made.append("sfx_die.wav 敌兵死亡(闷响)")
	ok = _gen("sfx_coin.wav", _coin()) and ok
	made.append("sfx_coin.wav 拾取军资(短叮)")
	ok = _gen("sfx_rende.wav", _rende()) and ok
	made.append("sfx_rende.wav 刘备·仁德之泽(温暖琶音)")
	ok = _gen("sfx_qinglong.wav", _qinglong()) and ok
	made.append("sfx_qinglong.wav 关羽·青龙偃月扫(重挥劈)")
	ok = _gen("sfx_dangyang.wav", _dangyang()) and ok
	made.append("sfx_dangyang.wav 张飞·当阳桥吼(低频扫频)")
	ok = _gen("sfx_qijin.wav", _qijin()) and ok
	made.append("sfx_qijin.wav 赵云·七进七出(哨音冲锋)")
	ok = _gen("sfx_eastwind.wav", _eastwind()) and ok
	made.append("sfx_eastwind.wav 诸葛亮·借东风(风声+火噼啪)")
	ok = _gen("sfx_miaoshou.wav", _miaoshou()) and ok
	made.append("sfx_miaoshou.wav 华佗·妙手回春(上行琶音)")
	ok = _gen("sfx_fangtian.wav", _fangtian()) and ok
	made.append("sfx_fangtian.wav 吕布·方天乱舞(三段斩)")
	ok = _gen("sfx_horn.wav", _horn()) and ok
	made.append("sfx_horn.wav 波次号角")
	ok = _gen("sfx_button.wav", _button()) and ok
	made.append("sfx_button.wav 按钮")
	ok = _gen("sfx_win.wav", _win()) and ok
	made.append("sfx_win.wav 胜利五声音阶短句")
	ok = _gen("sfx_lose.wav", _lose()) and ok
	made.append("sfx_lose.wav 失败低音锣")
	ok = _gen("bgm_camp.wav", _bgm()) and ok
	made.append("bgm_camp.wav BGM 五声音阶循环(音量压低)")
	if not ok:
		printerr("[gen_audio] 有文件写出失败,见上方报错。")
		quit(1)
		return
	print("[gen_audio] 完成:共 %d 个 WAV(seed=%d)→ %s" % [made.size(), SEED, OUT_DIR])
	for m in made:
		print("  - " + m)
	var expect := 16
	if made.size() != expect:
		printerr("[gen_audio] 文件数 %d ≠ 01 §12 清单 %d" % [made.size(), expect])
		quit(1)
		return
	quit(0)

# ---------------------------------------------------------------- WAV 写盘(16bit PCM 单声道)

func _gen(fname: String, samples: PackedFloat32Array) -> bool:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var f := FileAccess.open(OUT_DIR + fname, FileAccess.WRITE)
	if f == null:
		printerr("[gen_audio] 打不开输出:%s(err=%d)" % [OUT_DIR + fname, FileAccess.get_open_error()])
		return false
	_fourcc(f, "RIFF")
	f.store_32(36 + data.size())
	_fourcc(f, "WAVE")
	_fourcc(f, "fmt ")
	f.store_32(16)
	f.store_16(1)                   # PCM
	f.store_16(1)                   # 单声道
	f.store_32(SR)
	f.store_32(SR * 2)              # byte rate
	f.store_16(2)                   # block align
	f.store_16(16)                  # bits per sample
	_fourcc(f, "data")
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	return true

## FOURCC 按字符序写(store_32 是小端整型,直接写会倒序)
func _fourcc(f: FileAccess, tag: String) -> void:
	for i in 4:
		f.store_8(tag.unicode_at(i))

# ---------------------------------------------------------------- 合成基元

func _new(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * SR))
	return s

func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array, at_s: float) -> void:
	var off := int(at_s * SR)
	var n := mini(src.size(), dst.size() - off)
	for i in n:
		dst[off + i] += src[i]

## 归一化到峰值 peak,再做首尾 2ms 淡入淡出防爆音
func _finish(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var mx := 0.0001
	for i in s.size():
		mx = maxf(mx, absf(s[i]))
	var k := peak / mx
	for i in s.size():
		s[i] *= k
	var fade := int(0.002 * SR)
	for i in mini(fade, s.size()):
		s[i] *= float(i) / float(fade)
	for j in mini(fade, s.size()):
		var i2 := s.size() - 1 - j
		s[i2] *= float(j) / float(fade)
	return s

func _env(t: float, dur: float, attack: float, tau: float) -> float:
	if t < attack:
		return t / maxf(0.001, attack)
	return exp(-(t - attack) / tau)

## 锯齿感和声正弦(基频 + 泛音),soft 参数控制"方波感"
func _tone(ph: float, soft := 0.0) -> float:
	var v := sin(ph)
	v += 0.35 * sin(ph * 2.0)
	if soft > 0.0:
		v += soft * (sin(ph * 3.0) * 0.2)
	return v

## 一极低通系数(截止 fc)
func _lp_alpha(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / SR)

# ---------------------------------------------------------------- 音效(逐条对应 01 §12)

## 挥砍:短噪声脉冲——高通白噪急衰
func _slash() -> PackedFloat32Array:
	var dur := 0.15
	var s := _new(dur)
	var lp := 0.0
	var a := _lp_alpha(1400.0)
	for i in s.size():
		var t := float(i) / SR
		var n := rng.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		var hp := n - lp                        # 高通 = 原始 - 低通
		s[i] = hp * _env(t, dur, 0.002, 0.030)
	return _finish(s, 0.8)

## 命中:低频 thud + 噪声click
func _hit() -> PackedFloat32Array:
	var dur := 0.17
	var s := _new(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / SR
		var f := 105.0 - 60.0 * (t / dur)       # 105→45Hz 下扫
		ph += TAU * f / SR
		s[i] = sin(ph) * _env(t, dur, 0.002, 0.045)
	var click := _new(0.03)
	var lp := 0.0
	var a := _lp_alpha(900.0)
	for i in click.size():
		var t2 := float(i) / SR
		var n := rng.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		click[i] = lp * _env(t2, 0.03, 0.001, 0.010)
	_mix_at(s, click, 0.0)
	return _finish(s, 0.85)

## 敌兵死亡:闷响——深扫频 + 低通噪声
func _die() -> PackedFloat32Array:
	var dur := 0.32
	var s := _new(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / SR
		var f := 85.0 - 45.0 * (t / dur)
		ph += TAU * f / SR
		s[i] = sin(ph) * _env(t, dur, 0.004, 0.09)
	var no := _new(0.14)
	var lp := 0.0
	var a := _lp_alpha(320.0)
	for i in no.size():
		var t2 := float(i) / SR
		var n := rng.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		no[i] = lp * _env(t2, 0.14, 0.002, 0.045)
	_mix_at(s, no, 0.0)
	return _finish(s, 0.85)

## 拾取军资:短叮(双音上行 E6→A6)
func _coin() -> PackedFloat32Array:
	var s := _new(0.20)
	for part in [[0.0, 1318.5, 0.05, 0.02], [0.055, 1760.0, 0.11, 0.05]]:
		var at: float = part[0]
		var f: float = part[1]
		var d: float = part[2]
		var tau: float = part[3]
		var seg := _new(d)
		for i in seg.size():
			var t := float(i) / SR
			seg[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * _env(t, d, 0.002, tau)
		_mix_at(s, seg, at)
	return _finish(s, 0.7)

## 刘备 仁德之泽:温暖三音琶音 C5-E5-G5
func _rende() -> PackedFloat32Array:
	var s := _new(0.55)
	var notes := [[0.0, 523.25], [0.12, 659.26], [0.24, 783.99]]
	for nt in notes:
		var at: float = nt[0]
		var f: float = nt[1]
		var seg := _new(0.3)
		for i in seg.size():
			var t := float(i) / SR
			seg[i] = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t)) * _env(t, 0.3, 0.01, 0.11)
		_mix_at(s, seg, at)
	return _finish(s, 0.6)

## 关羽 青龙偃月扫:重挥劈——低通噪声下扫 + 尾部钝击
func _qinglong() -> PackedFloat32Array:
	var dur := 0.34
	var s := _new(dur)
	var lp := 0.0
	var a0 := _lp_alpha(2600.0)
	var a1 := _lp_alpha(260.0)
	for i in s.size():
		var t := float(i) / SR
		var k := t / dur
		var n := rng.randf_range(-1.0, 1.0)
		lp += (a0 + (a1 - a0) * k) * (n - lp)   # 截止 2600→260 下扫
		s[i] = lp * _env(t, dur, 0.015, 0.10)
	var thump := _new(0.12)
	var ph := 0.0
	for i in thump.size():
		var t2 := float(i) / SR
		ph += TAU * 150.0 / SR
		thump[i] = sin(ph) * _env(t2, 0.12, 0.002, 0.035)
	_mix_at(s, thump, 0.17)
	return _finish(s, 0.85)

## 张飞 当阳桥吼:低频扫频 220→60Hz + 软削波失真(01 §12 吼=低频扫频)
func _dangyang() -> PackedFloat32Array:
	var dur := 0.6
	var s := _new(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / SR
		var k := t / dur
		var f := 220.0 - 160.0 * k
		ph += TAU * f / SR
		var v := sin(ph) + 0.5 * sin(ph * 2.0) + 0.25 * sin(ph * 3.0)
		s[i] = tanh(v * 2.2) * _env(t, dur, 0.045, 0.22)
	return _finish(s, 0.85)

## 赵云 七进七出:哨音上扫 + 气声(01 §12 箭=哨音口径的冲锋呼啸)
func _qijin() -> PackedFloat32Array:
	var dur := 0.28
	var s := _new(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / SR
		var k := t / dur
		var f := 620.0 + 900.0 * k              # 620→1520Hz 上扫
		var vib := 1.0 + 0.01 * sin(TAU * 34.0 * t)
		ph += TAU * f * vib / SR
		s[i] = sin(ph) * _env(t, dur, 0.01, 0.09)
	var air := _new(dur)
	var hp_lp := 0.0
	var ah := _lp_alpha(500.0)
	for i in air.size():
		var t2 := float(i) / SR
		var n := rng.randf_range(-1.0, 1.0)
		hp_lp += ah * (n - hp_lp)
		air[i] = (n - hp_lp) * 0.4 * _env(t2, dur, 0.02, 0.08)
	_mix_at(s, air, 0.0)
	return _finish(s, 0.7)

## 诸葛亮 借东风:风声涌起 + 火噼啪脆响(01 §12 火=噼啪)
func _eastwind() -> PackedFloat32Array:
	var dur := 0.95
	var s := _new(dur)
	var lp := 0.0
	var a := _lp_alpha(420.0)
	for i in s.size():
		var t := float(i) / SR
		var n := rng.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		# 慢起快收的风包络
		var env := 1.0
		if t < 0.3:
			env = t / 0.3
		elif t > dur - 0.25:
			env = maxf(0.0, (dur - t) / 0.25)
		s[i] = lp * 1.4 * env
	for c in 12:                                  # 脆响:随机时刻衰减脉冲
		var at := rng.randf_range(0.28, dur - 0.1)
		var off := int(at * SR)
		var amp := rng.randf_range(0.4, 0.9)
		for j in mini(int(0.006 * SR), s.size() - off):
			s[off + j] += amp * sin(float(j) * 0.9) * exp(-float(j) / (0.0012 * SR))
	return _finish(s, 0.75)

## 华佗 妙手回春:上行五声琶音 C5-D5-E5-G5(01 §12 治疗=上行琶音)
func _miaoshou() -> PackedFloat32Array:
	var s := _new(0.6)
	var notes := [[0.0, 523.25], [0.1, 587.33], [0.2, 659.26], [0.3, 783.99]]
	for nt in notes:
		var at: float = nt[0]
		var f: float = nt[1]
		var seg := _new(0.28)
		for i in seg.size():
			var t := float(i) / SR
			seg[i] = (sin(TAU * f * t) + 0.22 * sin(TAU * f * 3.0 * t)) * _env(t, 0.28, 0.008, 0.09)
		_mix_at(s, seg, at)
	return _finish(s, 0.6)

## 吕布 方天乱舞:三段斩——三组噪声脉冲 + 钝击
func _fangtian() -> PackedFloat32Array:
	var s := _new(0.55)
	for k in 3:
		var at := 0.17 * float(k)
		var seg := _new(0.1)
		var lp := 0.0
		var a := _lp_alpha(1600.0)
		for i in seg.size():
			var t := float(i) / SR
			var n := rng.randf_range(-1.0, 1.0)
			lp += a * (n - lp)
			seg[i] = (n - lp) * _env(t, 0.1, 0.002, 0.024)
		_mix_at(s, seg, at)
		var th := _new(0.08)
		var ph := 0.0
		for i in th.size():
			var t2 := float(i) / SR
			ph += TAU * 130.0 / SR
			th[i] = sin(ph) * _env(t2, 0.08, 0.002, 0.026)
		_mix_at(s, th, at + 0.02)
	return _finish(s, 0.8)

## 波次号角:G3+D4 双音锯齿感号角,颤音收尾
func _horn() -> PackedFloat32Array:
	var dur := 0.9
	var s := _new(dur)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in s.size():
		var t := float(i) / SR
		var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t) * clampf((t - 0.35) / 0.2, 0.0, 1.0)
		ph1 += TAU * 196.0 * vib / SR
		ph2 += TAU * 293.66 * vib / SR
		var v := _tone(ph1) + 0.7 * _tone(ph2)
		s[i] = v * 0.5 * _env(t, dur, 0.12, 0.28)
	# 柔化:一极低通整体过一遍
	var lp := 0.0
	var alpha := _lp_alpha(1800.0)
	for i in s.size():
		lp += alpha * (s[i] - lp)
		s[i] = lp
	return _finish(s, 0.75)

## 按钮:短促确认音
func _button() -> PackedFloat32Array:
	var s := _new(0.08)
	for i in s.size():
		var t := float(i) / SR
		s[i] = sin(TAU * 950.0 * t) * _env(t, 0.08, 0.001, 0.012)
	var click := _new(0.012)
	for i in click.size():
		click[i] = rng.randf_range(-1.0, 1.0) * exp(-float(i) / (0.0008 * SR)) * 0.5
	_mix_at(s, click, 0.0)
	return _finish(s, 0.55)

## 胜利:五声音阶短句 宫商角徵羽 → 高宫收束(01 §12)
func _win() -> PackedFloat32Array:
	var s := _new(1.6)
	var scale := [523.25, 587.33, 659.26, 783.99, 880.0]   # C5 D5 E5 G5 A5
	for k in scale.size():
		var at := 0.15 * float(k)
		var seg := _note_seg(scale[k], 0.24, 0.09)
		_mix_at(s, seg, at)
	# 收束:高宫 C6 长音 + C5/E5/G5 和弦垫
	_mix_at(s, _note_seg(1046.5, 0.7, 0.16), 0.78)
	for f in [523.25, 659.26, 783.99]:
		_mix_at(s, _note_seg(f, 0.6, 0.2), 0.78)
	return _finish(s, 0.8)

## 失败:低音锣——多分音缓慢衰减 + 敲击噪声头
func _lose() -> PackedFloat32Array:
	var dur := 2.4
	var s := _new(dur)
	var partials := [[98.0, 1.0], [147.3, 0.7], [197.0, 0.5], [262.5, 0.35], [311.0, 0.25], [418.0, 0.15]]
	var phases: Array = []
	for p in partials:
		phases.append(rng.randf_range(0.0, TAU))
	for i in s.size():
		var t := float(i) / SR
		var v := 0.0
		for k in partials.size():
			var f: float = partials[k][0]
			var amp: float = partials[k][1]
			var detune := 1.0 + 0.0015 * sin(TAU * 0.7 * float(k) * t)   # 缓慢失谐产生锣面颤动
			v += amp * sin(TAU * f * detune * t + float(phases[k]))
		var env := 1.0
		if t < 0.06:
			env = t / 0.06
		else:
			env = exp(-(t - 0.06) / 0.75)
		s[i] = v * env * 0.4
	var strike := _new(0.05)
	var lp := 0.0
	var a := _lp_alpha(700.0)
	for i in strike.size():
		var n := rng.randf_range(-1.0, 1.0)
		lp += a * (n - lp)
		strike[i] = lp * exp(-float(i) / (0.008 * SR))
	_mix_at(s, strike, 0.0)
	return _finish(s, 0.85)

## 单音符段:sine + 泛音,attack/tau 包络
func _note_seg(f: float, dur: float, tau: float) -> PackedFloat32Array:
	var seg := _new(dur)
	for i in seg.size():
		var t := float(i) / SR
		seg[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t) + 0.12 * sin(TAU * f * 3.0 * t)) * _env(t, dur, 0.006, tau)
	return seg

# ---------------------------------------------------------------- BGM:五声音阶循环(音量压低)

## 12.0s @120bpm 24 拍:C 宫五声(C D E G A)旋律 + 根音拨弦低音。
## 固定旋律不走 rng(结构化作曲);尾拍留白,循环头尾干净。
func _bgm() -> PackedFloat32Array:
	var dur := 12.0
	var s := _new(dur)
	var beat := 0.5
	# C 宫五声音阶:宫 C 商 D 角 E 徵 G 羽 A
	var C4 := 261.63
	var D4 := 293.66
	var E4 := 329.63
	var G4 := 392.0
	var A4 := 440.0
	var C5 := 523.25
	# 24 拍旋律(0 = 休止),两句问答式
	var melody := [
		C4, E4, G4, A4, G4, E4, D4, C4,
		D4, E4, G4, C5, A4, G4, E4, G4,
		A4, G4, E4, D4, C4, D4, C4, 0,
	]
	for k in melody.size():
		var f: float = melody[k]
		if f <= 0.0:
			continue
		var seg := _note_seg(f, 0.42, 0.16)
		_mix_at(s, seg, float(k) * beat)
	# 低音:每 2 拍一个根音/五音拨弦(C3/G3/A3 轮替)
	var bass := [130.81, 196.0, 220.0, 196.0]
	for k in 12:
		var f2: float = bass[k % bass.size()]
		var seg2 := _new(0.7)
		for i in seg2.size():
			var t := float(i) / SR
			seg2[i] = sin(TAU * f2 * t) * _env(t, 0.7, 0.006, 0.22) * 0.9
		_mix_at(s, seg2, float(k) * beat * 2.0)
	return _finish(s, 0.34)   # BGM 音量压低(再叠加 BGM 总线 -12dB,01 §12)
