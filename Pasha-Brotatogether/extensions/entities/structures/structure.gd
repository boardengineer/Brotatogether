extends Structure

var network_id
var my_data

func _ready():
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		return
	
	var game_controller = $"/root/GameController"
	if game_controller and game_controller.is_source_of_truth:
		network_id = game_controller.id_count
		game_controller.id_count = network_id + 1

func set_data(data:Resource) -> void :
	base_stats = data.stats
	effects = data.effects
	my_data = data
	
	make_fake_stats()
	
	call_deferred("reload_data")

func make_fake_stats() -> void:
	# satisfy the setup
	stats = RangedWeaponStats.new()
	
	stats.max_range = 100
	stats.cooldown = 100

func reload_data() -> void:
	if not $"/root".has_node("GameController") or not $"/root/GameController".is_coop():
		.reload_data()
		return
		
	var multiplayer_weapon_service = $"/root/MultiplayerWeaponService"
	var run_data_node = $"/root/MultiplayerRunData"
	
	if not run_data_node.effect_to_owner_map.has(my_data):
		.reload_data()
		return
	
	var player_id = run_data_node.effect_to_owner_map[my_data]
	
	stats = multiplayer_weapon_service.init_ranged_stats_multiplayer(player_id, base_stats, "", [], effects, true)
	
	for effect in effects:
		if effect is BurningEffect:
			var base_burning = BurningData.new(
				effect.burning_data.chance, 
				max(1.0, effect.burning_data.damage + multiplayer_weapon_service.get_scaling_stats_value_multiplayer(player_id, stats.scaling_stats)) as int, 
				effect.burning_data.duration, 
				effect.burning_data.spread, 
				effect.burning_data.type
			)
			
			stats.burning_data = multiplayer_weapon_service.init_burning_data_multiplayer(player_id, base_burning, false, true)
			
	_ready()
