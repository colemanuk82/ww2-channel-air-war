class_name NewsreelCard
extends CanvasLayer
## Newsreel-style title card: black screen, a reel header and a headline in cinema-caption type, fading in and out.
## Text only, no archive footage. Any key or click skips it. Played once per launch from the start menu.

static var shown_this_launch: bool = false

const HOLD := 4.0
const FADE := 0.6

var _root: Control
var _elapsed: float = 0.0
var _done: bool = false


## Play the card once per launch. Returns the card, or null if it was already shown.
static func play_once(parent: Node, headline: String, sub: String) -> NewsreelCard:
	if shown_this_launch:
		return null
	shown_this_launch = true
	return play(parent, headline, sub)


static func play(parent: Node, headline: String, sub: String) -> NewsreelCard:
	var c := NewsreelCard.new()
	c.layer = 70
	parent.add_child(c)
	c._build(headline, sub)
	return c


func _build(headline: String, sub: String) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var reel := UIKit.label("CHANNEL AIR WAR  -  WEEKLY REVIEW", 16, Color(0.8, 0.78, 0.7, 0.8), true)
	reel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	reel.position = Vector2(48, 36)
	_root.add_child(reel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(UIKit.label(headline, 44, Color(0.97, 0.95, 0.88), true))
	var s := UIKit.label(sub, 20, Color(0.85, 0.82, 0.72))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(760, 0)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(s)
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE)
	tw.tween_interval(HOLD)
	tw.tween_property(_root, "modulate:a", 0.0, FADE)
	tw.tween_callback(_finish)


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	queue_free()


# ------------------------------------------------------------------ headlines from the pilot's own logbook

const _WORDS := ["NO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE",
	"THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN", "TWENTY"]


static func _num(n: int) -> String:
	return _WORDS[n] if n >= 0 and n < _WORDS.size() else str(n)


## [headline, sub] built from what the player has done since the newsreel last reported (decoration, promotion,
## kills, ships, sorties), or [] when there is nothing new. Marks the news as reported.
static func headline_from_log() -> Array:
	var best: Array = []
	var best_score: int = 0
	for side in ["Allies", "Axis"]:
		var c: Dictionary = PilotLog.career(side)
		var seen: Dictionary = c.get("news_seen", {})
		var rank: String = PilotLog.rank_of(side, int(c["points"]))
		var who: String = "%s %s" % [rank, Radio.player_callsign]
		var raf: bool = side == "Allies"
		var air_new: int = int(c["air"]) - int(seen.get("air", 0))
		var ship_new: int = int(c["ships"]) - int(seen.get("ships", 0))
		var gnd_new: int = int(c["ground"]) - int(seen.get("ground", 0))
		var ops_new: int = int(c["missions"]) + int(c["done"]) - int(seen.get("ops", 0))
		var awards: Array = PilotLog.award_names(side, c)
		var aw_new: int = awards.size() - int(seen.get("awards", 0))
		var rank_new: bool = str(seen.get("rank", rank)) != rank and seen.has("rank")
		var h: Array = []
		var score: int = 0
		if aw_new > 0:
			h = ["%s DECORATED" % who.to_upper(), "%s is awarded the %s. %s" % [who, str(awards[awards.size() - 1]),
				"Fighter Command congratulates its pilots on another week of hard fighting over the Channel." if raf else "The Luftwaffe honours its fliers over the Channel coast."]]
			score = 100
		elif rank_new:
			h = ["%s PROMOTED" % Radio.player_callsign.to_upper(), "Now %s, after %d sorties over the Channel." % [rank, int(c["missions"]) + int(c["done"])]]
			score = 80
		elif air_new > 0:
			h = ["%s DOWNS %s" % [who.to_upper(), _num(air_new)], "%s enemy aircraft destroyed since our last report, %d in all.%s" % [_num(air_new).capitalize(), int(c["air"]),
				" The coastal stations hold firm." if raf else ""]]
			score = 40 + air_new
		elif ship_new > 0:
			h = ["%s SHIP%s SUNK" % [_num(ship_new), "S" if ship_new > 1 else ""], "%s goes in low against shipping off the coast: %d vessels sunk in all." % [who, int(c["ships"])]]
			score = 35 + ship_new
		elif gnd_new >= 5:
			h = ["STRAFING RAIDS HIT THE ENEMY", "%s shoots up %d targets on the ground." % [who, gnd_new]]
			score = 20
		elif ops_new > 0:
			h = ["ANOTHER WEEK ON OPERATIONS", "%s flies %d more sorties over the Channel." % [who, ops_new]]
			score = 10
		if score > best_score:
			best_score = score
			best = h
		c["news_seen"] = {"air": int(c["air"]), "ships": int(c["ships"]), "ground": int(c["ground"]), "ops": int(c["missions"]) + int(c["done"]),
			"awards": awards.size(), "rank": rank}
		if not PilotLog.debug_run():
			PilotLog.save_career(side, c)
	return best
