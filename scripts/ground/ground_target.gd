class_name GroundTarget
extends Node3D
## Base for every destructible ground/sea object. Follows the DAMAGE CONTRACT (mode_base.gd):
## group "damageable", `team`, `hit_radius`, take_damage(amount, source), signal destroyed(node, killer).
## Mission targets additionally join "mission_target" (set is_mission_target + target_id before add_child).
## Subclasses override _build_intact(root) / _build_wreck(root) / _on_destroyed(killer).
## Destroyed state: intact visuals hidden, wreck shown, explosion + persistent smoke/fire.

signal destroyed(node: Node, killer: Node)

var team: String = "Axis"
var hit_radius: float = 5.0
var max_health: float = 100.0
var health: float = 100.0
var damage_mult: float = 1.0        # scales ALL damage
var small_mult: float = 1.0         # extra scale for hits < 30 dmg (bullets/cannon vs armour & concrete)
var min_damage: float = 0.0         # hits smaller than this are ignored (e.g. MG vs bunker)
var target_id: String = ""
var display_name: String = ""
var kind: String = ""
var points: int = 100
var is_dead: bool = false
var is_mission_target: bool = false
var start_wrecked: bool = false
var swap_on_death: bool = true
var explosion_size: float = 1.0
var smoke_scale: float = 1.0
var smoke_height: float = 2.0
var fire_on_death: bool = true
var wreck_color: Color = Color(0.1, 0.09, 0.08)

var _intact: Node3D
var _wreck: Node3D
var _smoke: Node3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("ground_target")
	add_to_group("team_" + team)
	if is_mission_target:
		add_to_group("mission_target")
	_intact = Node3D.new()
	_intact.name = "Intact"
	add_child(_intact)
	_wreck = Node3D.new()
	_wreck.name = "Wreck"
	_wreck.visible = false
	add_child(_wreck)
	health = max_health
	_build_intact(_intact)
	_build_wreck(_wreck)
	_post_ready()
	if start_wrecked:
		set_wrecked_silently()


func _post_ready() -> void:
	pass


func _build_intact(_root: Node3D) -> void:
	GroundKit.box(_root, Vector3(hit_radius, hit_radius * 0.6, hit_radius), Vector3(0, hit_radius * 0.3, 0), GroundKit.COL_GREY)


func _build_wreck(root: Node3D) -> void:
	var r: float = maxf(hit_radius * 0.5, 1.0)
	GroundKit.box(root, Vector3(r * 1.4, r * 0.35, r * 1.1), Vector3(0, r * 0.17, 0), wreck_color, Vector3(0, 20, 4))
	GroundKit.box(root, Vector3(r * 0.7, r * 0.3, r * 0.6), Vector3(r * 0.2, r * 0.45, 0), wreck_color, Vector3(8, -15, 12))


func _on_destroyed(_killer: Node) -> void:
	pass


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount < min_damage:
		return
	if WeaponWorld.is_player_source(source):
		Weapons.player_hit.emit(self, amount)
	var a: float = amount * (small_mult if amount < 30.0 else 1.0)
	health -= a * damage_mult
	if health <= 0.0:
		die(source)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	if swap_on_death:
		if _intact:
			_intact.visible = false
		if _wreck:
			_wreck.visible = true
	if is_inside_tree():
		GroundKit.explosion(global_position + Vector3(0, smoke_height * 0.5, 0), explosion_size)
		if fire_on_death:
			_smoke = GroundKit.persistent_smoke(self, Vector3(0, smoke_height, 0), smoke_scale, true)
	remove_from_group("damageable")
	add_to_group("destroyed_target")
	_on_destroyed(killer)
	destroyed.emit(self, killer)
	if WeaponWorld.is_player_source(killer):
		Weapons.player_kill.emit(self)


## Put the object straight into its wrecked state without effects (used when streaming back in).
func set_wrecked_silently() -> void:
	is_dead = true
	health = 0.0
	if _intact:
		_intact.visible = false
	if _wreck:
		_wreck.visible = true
	remove_from_group("damageable")
	add_to_group("destroyed_target")


func is_destroyed() -> bool:
	return is_dead
