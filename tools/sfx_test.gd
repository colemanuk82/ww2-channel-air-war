extends SceneTree
## Debug: godot --headless --path . --script res://tools/sfx_test.gd
## Builds every engine and gun voice and checks each loop is non-empty, in range and not clipping flat.

func _initialize() -> void:
	var a := AudioSFX.new()
	var bad: int = 0
	for id in AudioSFX.ENGINES:
		for voices in [1, 2, 3]:
			var s: AudioStreamWAV = a._stream("engine:%s:%d" % [id, voices]) as AudioStreamWAV
			var peak: float = _peak(s)
			print("engine %-15s x%d bytes=%d peak=%.2f" % [id, voices, s.data.size(), peak])
			if s.data.size() < 1000 or peak < 0.05:
				bad += 1
	for id in AudioSFX.GUNS:
		var g: AudioStreamWAV = a._stream("gun:" + id) as AudioStreamWAV
		var peak2: float = _peak(g)
		print("gun    %-15s bytes=%d peak=%.2f" % [id, g.data.size(), peak2])
		if g.data.size() < 100 or peak2 < 0.05:
			bad += 1
	print("SFX TEST ", "FAILED (%d)" % bad if bad > 0 else "OK")
	quit(1 if bad > 0 else 0)


func _peak(s: AudioStreamWAV) -> float:
	var d: PackedByteArray = s.data
	var m: float = 0.0
	for i in range(0, d.size() - 1, 2):
		var v: int = d.decode_s16(i)
		m = maxf(m, absf(float(v)) / 32768.0)
	return m
