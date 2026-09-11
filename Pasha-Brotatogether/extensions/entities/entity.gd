extends "res://entities/entity.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false
var network_id = 0
var is_host = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		is_host = steam_connection.is_host()
		network_id = brotatogether_options.current_network_id
		brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1


# Vanilla POOLS entities: EntitySpawner.spawn_entity reuses a dead node from the pool and
# calls respawn() -- _ready does NOT run again, so the recycled node would keep the
# network_id of the enemy that previously DIED in it. The host has already broadcast that
# id in BATCHED_ENEMY_DEATHS, and clients remember dead ids to reject stale roster rows,
# so every recycled enemy was permanently invisible on clients ("rows - alive grows with
# the kill count", soak run 5, 2026-09-09). Stamp a FRESH id on every pooled reuse so
# network ids stay unique for the host's lifetime, exactly like a fresh instance.
func respawn() -> void:
	.respawn()
	if in_multiplayer_game and is_host:
		network_id = brotatogether_options.current_network_id
		brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
