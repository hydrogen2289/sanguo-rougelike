extends Node
## Sfx —— 音频 autoload(M0 立骨架;M6 实装)。
## 音频文件由 tools/gen_audio.gd 程序化生成(16bit PCM 44100Hz,01 §12);
## 总线:SFX / BGM 两条子总线(运行时创建,均路由 Master,BGM 压低);
## 文件缺失时静默降级不报错;同名音效 60ms 限频防刷屏(普攻/受击高频调用)。

const POOL_SIZE := 10
const SAME_SFX_COOLDOWN_MS := 60

var _players: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _last_ms := {}                  # sfx_name -> 上次播放 msec

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时音效照常可停
	_ensure_bus("SFX", -5.0)
	_ensure_bus("BGM", -12.0)                 # BGM 音量压低作氛围(01 §12)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "BGM"
	add_child(_bgm)

## 运行时建总线(project 无 default_bus_layout.tres,代码创建保证存在)
func _ensure_bus(bus_name: String, vol_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, vol_db)

func play(sfx_name: String, volume_db := 0.0) -> void:
	var path := "res://assets/audio/sfx_%s.wav" % sfx_name
	if not ResourceLoader.exists(path):
		return                                  # 静默降级:无音频文件不报错
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sfx_name, -100000)) < SAME_SFX_COOLDOWN_MS:
		return                                  # 同名限频
	_last_ms[sfx_name] = now
	var stream = load(path)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	_players[0].stream = stream
	_players[0].volume_db = volume_db
	_players[0].play()

func play_bgm() -> void:
	if _bgm.playing:
		return
	var path := "res://assets/audio/bgm_camp.wav"
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		# 五声音阶循环:头尾相位衔接由 gen_audio 保证,此处设循环点
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2      # 16bit 单声道:2 字节/帧
	_bgm.stream = stream
	_bgm.play()
