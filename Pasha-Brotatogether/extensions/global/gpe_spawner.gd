extends "res://global/gpe_spawner.gd"

# PUDDLES row kinds (see main.gd _host_puddles_array).
enum PuddleKind { ACID, PETROL, FIRE }


# Main._ready calls init() immediately before the wave's map is rolled with the GLOBAL RNG:
# spawn_holes_full_scene picks one of several hole layouts (StaticBody2D walls, jungle waves
# 4/10/16) and the background's structures_generation shuffles and scatters its decor. Each
# machine runs its own Main._ready, so unseeded the client walked into a different set of walls
# than the host simulates. Seed both machines identically here; the Main extension's _ready
# (which runs after the base _ready) calls randomize() again.
func init() -> void :
	.init()
	var opts = get_node_or_null("/root/BrotogetherOptions")
	var sc = get_node_or_null("/root/SteamConnection")
	if opts != null and sc != null and opts.in_multiplayer_game and sc.game_lobby_id > 0:
		seed(hash([sc.game_lobby_id, RunData.current_zone, RunData.current_wave]))
		opts.map_rng_seeded = true


# Puddles are host-authoritative: the host simulates every source (enemy dashes and deaths,
# mutant projectiles, plants, player fire effects) and ships the live set every snapshot.
# A client's local copies of those sources would drop their own, differently timed puddles,
# so every spawn request on a client is refused here (all callers accept null -- the base
# returns it too when the pool is full) and Main replays the host's rows via spawn_replica.
func _bt_is_client() -> bool:
	var opts = get_node_or_null("/root/BrotogetherOptions")
	var sc = get_node_or_null("/root/SteamConnection")
	return opts != null and sc != null and opts.in_multiplayer_game and not sc.is_host()


func get_new_acid_puddle_at_pos(pos: Vector2, no_lifeTime: bool, small_acid: bool) -> Node2D:
	if _bt_is_client():
		return null
	return _real(.get_new_acid_puddle_at_pos(pos, no_lifeTime, small_acid))


func get_new_petrol_puddle_at_pos(pos: Vector2, no_lifeTime: bool, small_petrol: bool) -> Node2D:
	if _bt_is_client():
		return null
	return _real(.get_new_petrol_puddle_at_pos(pos, no_lifeTime, small_petrol))


func get_new_fire_puddle_at_pos(pos: Vector2, burning_data: BurningData, size: Vector2 = FIRE_PUDDLE_SCALE, puddle_lifetime: float = FIRE_PUDDLE_LIFETIME, player_index: = - 1) -> Node2D:
	if _bt_is_client():
		return null
	return _real(.get_new_fire_puddle_at_pos(pos, burning_data, size, puddle_lifetime, player_index))


# Replicas and real puddles share the pools. In a solo test (host and replay in one process)
# a pooled replica can come back as a real puddle: strip the replica marks so it is shipped
# and hurts again.
func _real(puddle):
	if puddle != null and puddle.has_meta("bt_replica"):
		puddle.remove_meta("bt_replica")
		puddle.monitoring = true
	return puddle


# Host: the kind of an active puddle, or -1 for anything else in the containers.
func puddle_kind(puddle: Node) -> int:
	if not puddle.has_meta("pool_id") or puddle.has_meta("bt_replica"):
		return - 1
	var pool_id = puddle.get_meta("pool_id")
	if acid_puddle != null and pool_id == acid_puddle.get_instance_id():
		return PuddleKind.ACID
	if petrol_puddle != null and pool_id == petrol_puddle.get_instance_id():
		return PuddleKind.PETROL
	if fire_puddle != null and pool_id == fire_puddle.get_instance_id():
		return PuddleKind.FIRE
	return - 1


# Client: draw one host puddle. No lifetime (the host's row disappearing despawns it), no
# burning data (fire puddles only burn enemies, which the host simulates), and the size the
# host's puddle grew to, which already includes any fire-size stat.
func spawn_replica(kind: int, pos: Vector2, target_scale: Vector2) -> Node2D:
	var puddle
	match kind:
		PuddleKind.ACID:
			puddle = _get_pooled_puddle(acid_puddle, max_acid_puddles, _gpe_container)
		PuddleKind.PETROL:
			puddle = _get_pooled_puddle(petrol_puddle, max_petrol_puddles, _gpe_container)
		PuddleKind.FIRE:
			puddle = _get_pooled_puddle(fire_puddle, max_fire_puddles, _main._fire_puddles_container)
	if puddle == null:
		return null
	puddle.set_meta("bt_replica", true)
	puddle.global_position = pos
	puddle.lifetime = - 1
	var size = target_scale / puddle._base_scale
	if kind == PuddleKind.FIRE:
		puddle.init(null, size, - 1)
	else:
		puddle.init(size)
	return puddle


# The brachiosaurus boss's feet leave a permanent hole (a StaticBody2D wall) where each one
# stomps. A client's copy of a foot runs its own stomp timing at its own position, so on a
# client the call is refused and the host's holes arrive as BATCHED_HOLES events instead.
func spawn_single_hole_at_position(position: Vector2) -> void :
	if _bt_is_client():
		return
	var opts = get_node_or_null("/root/BrotogetherOptions")
	if opts != null and opts.in_multiplayer_game:
		opts.batched_holes.push_back([int(round(position.x)), int(round(position.y))])
	.spawn_single_hole_at_position(position)


# Client: build one of the host's stomp holes.
func spawn_hole_replica(position: Vector2) -> void :
	.spawn_single_hole_at_position(position)
