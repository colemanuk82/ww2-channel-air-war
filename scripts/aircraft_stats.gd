class_name AircraftStats
extends Resource
## Data-driven aircraft definition. Units: world units (1 unit = 1 m), seconds.
## Add new aircraft by creating data/aircraft/<id>.tres and registering a model in AircraftModels.

@export var id: String = "spitfire"
@export var display_name: String = "Supermarine Spitfire Mk I"
@export_enum("Allies", "Axis") var side: String = "Allies"
@export var nation: String = "RAF"  # RAF, USAAF, Luftwaffe... selects markings
@export var model_id: String = "spitfire"  # key used by AircraftModels.build()
@export var scene_path: String = "res://scenes/aircraft/aircraft_base.tscn"

@export_group("Speed")
@export var max_speed: float = 175.0       # level flight at full throttle (units/s)
@export var stall_speed: float = 48.0
@export var boost_bonus: float = 65.0
@export var accel: float = 7.0
@export var decel: float = 6.0
@export var gravity_accel: float = 18.0    # speed gained/lost per sin(pitch) (dive/climb)

@export_group("Handling")
@export var pitch_rate_deg: float = 75.0
@export var roll_rate_deg: float = 170.0
@export var yaw_rate_deg: float = 28.0
@export var bank_turn_rate: float = 0.85   # rad/s of heading change at 90 degrees of bank
@export var rate_response: float = 6.0     # how quickly rotation rates follow the stick
@export var assist_strength: float = 2.2   # auto-level gain

@export_group("Boost")
@export var boost_duration: float = 4.0
@export var boost_cooldown: float = 7.0

@export_group("Durability and weapons")
@export var max_health: float = 100.0
@export var ammo: int = 600
@export var bombs: int = 0
@export var gun_count: int = 8
@export var fire_rate: float = 14.0

@export_group("Weapons")
@export var gun_damage: float = 0.9        # per gun-round; each muzzle bullet carries gun_count/muzzles of them
@export var gun_speed: float = 650.0       # muzzle speed relative to the aircraft (units/s)
@export var gun_spread: float = 0.012      # radians, random cone
@export var gun_range: float = 1100.0      # bullet lifetime = gun_range / gun_speed
@export var gun_convergence: float = 450.0 # wing guns converge at this distance
@export var tracer_every: int = 4
@export var bomb_damage: float = 900.0     # direct / centre-of-blast damage
@export var bomb_radius: float = 42.0      # splash radius (units)
@export var rockets: int = 0               # fired in pairs with the bomb key when no bombs remain
@export var rocket_damage: float = 95.0
@export var rocket_radius: float = 18.0
@export var rocket_speed: float = 260.0

@export_group("Ground")
@export var gear_height: float = 1.6
@export var crash_vspeed: float = 38.0
@export var ground_turn_rate_deg: float = 45.0
@export var radius: float = 8.0

@export_group("Sound")
@export var engine_sound: String = "merlin"        # key of AudioSFX.ENGINES
@export var engine_count: int = 1                  # engines fitted; extra engines add detuned voices
@export var gun_sound: String = ""                 # key of AudioSFX.GUNS ("" = generic gun / cannon)
