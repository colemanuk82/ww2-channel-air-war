extends Node3D
## Weapons/FX proving ground. Run (windowed):
##   godot --path F:\ww2 res://scenes/weapons/test_range.tscn -- --shot=out.png --frames=420
## Flat terrain stub in group "terrain"; a flying Spitfire strafes a dummy target, bombs a ground spot,
## and an enemy aircraft is shot down (smoke -> fire -> death spiral -> crash explosion, parachute).

class FlatTerrain extends Node3D:
	func get_height_at(_p: Vector3) -> float:
		return 0.0
	func is_water_at(_p: Vector3) -> bool:
		return false
	func get_terrain_y(_x: float, _z: float) -> float:
		return 0.0

class Dummy extends Node3D:
	var team: String = "Axis"
	var hit_radius: float = 6.0
	var hp: float = 100.0
	var hits: int = 0
	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount
		hits += 1
		if hp <= 0.0 and visible:
			visible = false
			remove_from_group("damageable")
			FX.explosion(global_position, 12.0)

var player: Aircraft
var enemy: Aircraft
var dummy: Dummy
var bomb_spot: Dummy
var cam: Camera3D
var t: float = 0.0
var shot_path: String = ""
var shot_frame: int = 100000
var shot_time: float = 8.0
var frame: int = 0
var _bombed: bool = false
var _shot_enemy: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			shot_frame = int(a.substr(9))
		elif a.begins_with("--at="):
			shot_time = float(a.substr(5))
	var terrain := FlatTerrain.new()
	terrain.add_to_group("terrain")
	add_child(terrain)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	ground.material_override = ToonUtil.make_toon(Color(0.35, 0.45, 0.25), {"outline": false})
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.65, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)

	dummy = Dummy.new()
	dummy.position = Vector3(0, 420, -650)
	dummy.add_to_group("damageable")
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.scale = Vector3(10, 10, 10)
	box.material_override = ToonUtil.make_toon(Color(0.7, 0.2, 0.2))
	dummy.add_child(box)
	add_child(dummy)

	bomb_spot = Dummy.new()
	bomb_spot.position = Vector3(0, 3, -1700)
	bomb_spot.hit_radius = 5.0
	bomb_spot.add_to_group("damageable")
	var b2 := MeshInstance3D.new()
	b2.mesh = BoxMesh.new()
	b2.scale = Vector3(12, 6, 12)
	b2.material_override = ToonUtil.make_toon(Color(0.4, 0.4, 0.5))
	bomb_spot.add_child(b2)
	add_child(bomb_spot)

	var packed: PackedScene = load("res://scenes/aircraft/aircraft_base.tscn")
	player = packed.instantiate() as Aircraft
	player.name = "Player"
	player.player_controlled = false   # scripted
	add_child(player)
	player.stats = player.stats.duplicate()
	player.stats.bombs = 4
	player.bombs = 4
	player.reset_pose(Vector3(0, 420, 0), 0.0, true, 140.0)
	player.throttle_target = 0.8

	enemy = packed.instantiate() as Aircraft
	enemy.name = "Enemy"
	enemy.team = "Axis"
	add_child(enemy)
	enemy.reset_pose(Vector3(60, 400, -400), 0.0, true, 70.0)
	enemy.throttle_target = 0.5

	cam = Camera3D.new()
	cam.far = 12000.0
	add_child(cam)
	cam.current = true


func _process(delta: float) -> void:
	t += delta
	frame += 1
	# camera: chase the player, then watch the enemy crash, then the bomb site
	var look: Vector3
	var want: Vector3
	if t > 3.8 and t < 8.0 and enemy.state != Aircraft.State.DEAD or (t > 3.8 and t < 6.0):
		look = enemy.global_position
		want = look + Vector3(40, 30, 160)
	elif t >= 6.0 and t < 16.0:
		look = bomb_spot.global_position + Vector3(0, 40, 0)
		want = look + Vector3(50, 40, 160)
	else:
		look = player.global_position + player.get_forward() * 80.0
		want = player.global_position + player.global_transform.basis.z * 55.0 + Vector3(0, 14, 0)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-6.0 * delta))
	cam.look_at(look, Vector3.UP)
	# strafe the dummy between t=1.2 and 3.4
	player.cmd_fire = t > 0.8 and t < 2.6
	player.cmd_pitch = 0.0
	if t > 3.6 and not _bombed:
		_bombed = true
		print("[test] dummy hp after strafe: %.1f hits=%d" % [dummy.hp, dummy.hits])
		player.cmd_pitch = 0.0
	if t > 3.0 and player.bombs > 0 and fmod(t, 0.6) < delta:
		var imp: Vector3 = Weapons.predict_bomb_impact(player.global_position, player.velocity)
		if Vector2(imp.x - bomb_spot.position.x, imp.z - bomb_spot.position.z).length() < 60.0:
			player.bomb_requested.emit(player)
	# the enemy gets hammered after the bombs
	if t > 3.5 and not _shot_enemy:
		_shot_enemy = true
		enemy.take_damage(45.0, player)
	if t > 4.5 and enemy.state == Aircraft.State.ALIVE:
		enemy.take_damage(40.0, player)
	if t > 5.5 and enemy.state == Aircraft.State.ALIVE:
		enemy.take_damage(60.0, player)
	if frame % 60 == 0:
		print("[test] t=%.1f bullets=%d enemy=%s hp=%.0f bombs=%d spot_hp=%.0f FPS=%d" % [t, Weapons.bullet_count, enemy.state, enemy.health, player.bombs, bomb_spot.hp, Engine.get_frames_per_second()])
	if shot_path != "" and (frame == shot_frame or t >= shot_time):
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()
	elif shot_path == "" and t > 20.0:
		get_tree().quit()
