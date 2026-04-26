extends Node

# Procedural SFX. Generates short waveforms (no audio assets required) and plays
# them via a small pool of AudioStreamPlayer nodes. Easy to swap real .wav/.ogg
# files in later — the public API stays Sfx.fire() / Sfx.hit() / etc.

const SAMPLE_RATE := 22050
const POOL_SIZE := 8
const MASTER_VOLUME_DB := -6.0

enum Wave { SINE, SQUARE, TRI, NOISE }

var _pool: Array[AudioStreamPlayer] = []
var _pool_idx: int = 0
var _cache: Dictionary = {}  # event_name -> AudioStreamWAV


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = MASTER_VOLUME_DB
		add_child(p)
		_pool.append(p)
	_build_cache()


func _build_cache() -> void:
	# Each entry: name -> stream. Tweak these to taste; cheap to regenerate.
	_cache["fire"] = _build_sweep(420.0, 240.0, 0.10, Wave.SQUARE, -8.0)
	_cache["hit"] = _build_sweep(880.0, 1200.0, 0.06, Wave.SQUARE, -6.0)
	_cache["miss"] = _build_sweep(220.0, 140.0, 0.18, Wave.TRI, -10.0)
	_cache["bounce"] = _build_sweep(1300.0, 900.0, 0.08, Wave.SINE, -8.0)
	_cache["net_catch"] = _build_chord([520.0, 660.0, 780.0], 0.20, Wave.SINE, -7.0)
	_cache["cash_small"] = _build_sweep(900.0, 1400.0, 0.10, Wave.SINE, -10.0)
	_cache["cash_big"] = _build_chord([660.0, 880.0, 1320.0], 0.30, Wave.SINE, -6.0)
	_cache["splash"] = _build_noise(0.25, -10.0, 0.6)
	_cache["resurface"] = _build_sweep(180.0, 360.0, 0.30, Wave.SINE, -9.0)
	_cache["unlock"] = _build_chord([523.0, 659.0, 784.0, 1047.0], 0.45, Wave.TRI, -5.0)


func play(event: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _cache.get(event)
	if stream == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.4, 2.5)
	p.volume_db = MASTER_VOLUME_DB + volume_db
	p.play()


# --- Public convenience wrappers ---

func fire() -> void: play("fire")
func hit() -> void: play("hit")
func miss() -> void: play("miss")
func bounce() -> void: play("bounce")
func net_catch() -> void: play("net_catch")
func cash(value: int) -> void:
	if value >= 25:
		play("cash_big", 1.0 + clampf(value * 0.005, 0.0, 0.4))
	else:
		play("cash_small", 1.0 + randf_range(-0.05, 0.15))
func splash() -> void: play("splash")
func resurface() -> void: play("resurface")
func unlock() -> void: play("unlock")


# --- Waveform generators ---

# Pitch-sweep tone with attack-release envelope.
func _build_sweep(freq_start: float, freq_end: float, duration: float, wave: int, peak_db: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var amp := db_to_linear(peak_db)
	for i in n:
		var t: float = float(i) / float(n)
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / SAMPLE_RATE
		var s: float = _wave_sample(wave, phase) * amp * _envelope(t, 0.05, 0.6)
		_write_sample(data, i, s)
	return _wrap_wav(data)


# Multi-frequency stack — bright cash chime / fanfare.
func _build_chord(freqs: Array, duration: float, wave: int, peak_db: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases := []
	for _f in freqs:
		phases.append(0.0)
	var amp := db_to_linear(peak_db) / float(freqs.size())
	for i in n:
		var t: float = float(i) / float(n)
		var s := 0.0
		for k in freqs.size():
			phases[k] += TAU * float(freqs[k]) / SAMPLE_RATE
			s += _wave_sample(wave, phases[k])
		s *= amp * _envelope(t, 0.05, 0.45)
		_write_sample(data, i, s)
	return _wrap_wav(data)


# Filtered-noise burst — splashy / impact-y.
func _build_noise(duration: float, peak_db: float, decay: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var amp := db_to_linear(peak_db)
	# Single-pole low-pass to round off the noise.
	var prev := 0.0
	var alpha := 0.35
	for i in n:
		var t: float = float(i) / float(n)
		var raw := randf_range(-1.0, 1.0)
		prev = alpha * raw + (1.0 - alpha) * prev
		var env: float = pow(1.0 - t, decay)
		_write_sample(data, i, prev * amp * env)
	return _wrap_wav(data)


func _wave_sample(wave: int, phase: float) -> float:
	match wave:
		Wave.SINE:
			return sin(phase)
		Wave.SQUARE:
			return 1.0 if sin(phase) >= 0.0 else -1.0
		Wave.TRI:
			# Triangle: triangle wave from a phase angle.
			var p := fmod(phase, TAU) / TAU
			return 4.0 * abs(p - 0.5) - 1.0
		Wave.NOISE:
			return randf_range(-1.0, 1.0)
	return 0.0


# Attack-release envelope: t in [0, 1]; attack is the rising portion fraction,
# release shapes the decay tail.
func _envelope(t: float, attack: float, release: float) -> float:
	if t < attack:
		return t / attack
	# Soft exponential release.
	var rt: float = (t - attack) / max(0.001, 1.0 - attack)
	return pow(1.0 - rt, release * 4.0)


func _write_sample(data: PackedByteArray, idx: int, sample: float) -> void:
	var s: int = clampi(int(sample * 32767.0), -32767, 32767)
	if s < 0:
		s += 65536
	data[idx * 2] = s & 0xFF
	data[idx * 2 + 1] = (s >> 8) & 0xFF


func _wrap_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
