extends Node
## Original, procedurally synthesised audio (CC0 by construction): a synthwave loop
## whose low-pass filter opens with speed, an airtime whoosh, a score chime and a
## glass shatter. Music is synthesised in slices over several frames so start-up
## never stalls, including on single-threaded Web builds.

const RATE := 22050
const BPM := 112.0
const BARS := 4
const SLICE := 6000

var music: AudioStreamPlayer
var whoosh: AudioStreamPlayer
var chime: AudioStreamPlayer
var shatter: AudioStreamPlayer

var _music_bus := -1
var _sfx_bus := -1
var _lowpass: AudioEffectLowPassFilter
var _music_data := PackedByteArray()
var _music_samples: int = 0
var _music_pos: int = 0
var _cutoff: float = 1200.0
var _cutoff_goal: float = 1200.0
var _noise := RandomNumberGenerator.new()
## Headless runs (tests, servers) synthesise everything but never start playback:
## the dummy driver does not mix, so playbacks would never be released.
var _silent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	_music_bus = _ensure_bus(&"Music")
	_sfx_bus = _ensure_bus(&"SFX")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = _cutoff
	_lowpass.resonance = 0.6
	AudioServer.add_bus_effect(_music_bus, _lowpass)
	music = _player(&"Music")
	whoosh = _player(&"SFX")
	chime = _player(&"SFX")
	chime.max_polyphony = 4
	shatter = _player(&"SFX")
	whoosh.stream = _wav(_synth_whoosh(), false)
	chime.stream = _wav(_synth_chime(), false)
	shatter.stream = _wav(_synth_shatter(), false)
	var beat := 60.0 / BPM
	_music_samples = int(beat * 4.0 * BARS * RATE)
	_music_data.resize(_music_samples * 2)
	Save.setting_changed.connect(func(_k: String, _v: Variant) -> void: apply_volumes())
	apply_volumes()


## Stops every player so the audio thread can release its playbacks before exit.
func shutdown() -> void:
	_music_pos = _music_samples
	for p: AudioStreamPlayer in [music, whoosh, chime, shatter]:
		p.stop()
		p.stream = null


func _process(delta: float) -> void:
	if _music_pos < _music_samples:
		_synth_music_slice()
		if _music_pos >= _music_samples:
			var stream := AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.mix_rate = RATE
			stream.data = _music_data
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = _music_samples
			music.stream = stream
			if not _silent:
				music.play()
	_cutoff = lerpf(_cutoff, _cutoff_goal, 1.0 - exp(-5.0 * delta))
	_lowpass.cutoff_hz = _cutoff


## 0 = calm (menus / slow), 1 = full speed. Opens the music low-pass filter.
func set_intensity(t: float) -> void:
	_cutoff_goal = 500.0 * pow(36.0, clampf(t, 0.0, 1.0))


func play_whoosh() -> void:
	if not _silent:
		whoosh.play()


func play_chime() -> void:
	if not _silent:
		chime.play()


func play_shatter() -> void:
	if not _silent:
		shatter.play()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(Save.get_setting("master_volume")), 0.0001)))
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(float(Save.get_setting("music_volume")), 0.0001)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(float(Save.get_setting("sfx_volume")), 0.0001)))


func music_ready() -> bool:
	return _music_pos >= _music_samples


func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	return idx


func _player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s


static func _note(semitones_from_a4: float) -> float:
	return 440.0 * pow(2.0, semitones_from_a4 / 12.0)


func _synth_music_slice() -> void:
	# Progression (one chord per bar): Am - F - C - G, voiced in semitones from A4.
	var chords := [[0.0, 3.0, 7.0], [-4.0, 0.0, 3.0], [3.0, 7.0, 10.0], [-2.0, 2.0, 5.0]]
	var roots := [-24.0, -28.0, -21.0, -26.0]
	var beat := 60.0 / BPM
	var end := mini(_music_pos + SLICE, _music_samples)
	for i in range(_music_pos, end):
		var t := float(i) / RATE
		var bar := int(t / (beat * 4.0)) % BARS
		var in_beat := fmod(t, beat)
		var eighth := fmod(t, beat * 0.5)
		var sixteenth_idx := int(t / (beat * 0.25))
		var sixteenth := fmod(t, beat * 0.25)
		var chord: Array = chords[bar]
		# Bass: saw on eighth notes with a plucky envelope.
		var fb := _note(roots[bar])
		var bass := (fmod(t * fb, 1.0) * 2.0 - 1.0) * exp(-eighth * 9.0) * 0.32
		# Pad: three detuned saws per chord tone, slow swell.
		var pad := 0.0
		for n in chord:
			var f := _note(float(n) - 12.0)
			pad += (fmod(t * f, 1.0) * 2.0 - 1.0) + (fmod(t * f * 1.004, 1.0) * 2.0 - 1.0)
		pad *= 0.035
		# Arp: square wave stepping through the chord in sixteenths.
		var arp_note: float = chord[sixteenth_idx % 3] + 12.0 * float(int(sixteenth_idx / 3.0) % 2)
		var fa := _note(arp_note)
		var arp := (1.0 if fmod(t * fa, 1.0) < 0.5 else -1.0) * exp(-sixteenth * 14.0) * 0.07
		# Kick on every beat, noise hat on the off-beats.
		var kick := sin(TAU * (45.0 * in_beat + 60.0 * (1.0 - exp(-in_beat * 30.0)) / 30.0)) * exp(-in_beat * 7.0) * 0.55
		var hat := 0.0
		var since_off := in_beat - beat * 0.5
		if since_off >= 0.0 and since_off < 0.05:
			hat = _noise.randf_range(-1.0, 1.0) * exp(-since_off * 60.0) * 0.06
		var s := clampf(bass + pad + arp + kick + hat, -1.0, 1.0)
		_music_data.encode_s16(i * 2, int(s * 30000.0))
	_music_pos = end


func _synth_whoosh() -> PackedFloat32Array:
	var n := int(0.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / n
		var cutoff := lerpf(0.02, 0.25, sin(t * PI))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		out[i] = lp * sin(t * PI) * 0.8
	return out


func _synth_chime() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 6.0) * minf(t * 200.0, 1.0)
		out[i] = (sin(TAU * 1318.5 * t) * 0.5 + sin(TAU * 1975.5 * t) * 0.3 + sin(TAU * 2637.0 * t) * 0.12) * env * 0.5
	return out


func _synth_shatter() -> PackedFloat32Array:
	var n := int(1.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pings: Array = []
	for k in 28:
		pings.append([rng.randf_range(0.0, 0.5), rng.randf_range(2500.0, 7500.0), rng.randf_range(0.15, 0.4)])
	var hp_prev := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		hp = 0.85 * (hp + noise - hp_prev)
		hp_prev = noise
		var s := hp * exp(-t * 14.0) * 0.6
		for p in pings:
			var dt: float = t - float(p[0])
			if dt >= 0.0:
				s += sin(TAU * float(p[1]) * dt) * exp(-dt * 30.0) * float(p[2])
		out[i] = s * 0.45
	return out
