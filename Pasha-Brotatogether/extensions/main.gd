extends "res://main.gd"

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")
var ClientAttackBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_attack_behavior.gd")
var ClientTargetBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_target_behavior.gd")
var explosion_scene = load("res://projectiles/explosion.tscn")
var DataNode = load("res://mods-unpacked/Pasha-Brotatogether/data_node.gd")

var steam_connection
var brotatogether_options
var in_multiplayer_game = false

# If true, the steam logic will be skipped to avoid duplicate rpc chains.
var is_self_call = false

var player_in_scene = [true, false, false, false]
var waiting_to_start_round = false

const SEND_RATE : float = 1.0 / 60.0   # was 1/30; payload is ~1KB so 2x is trivial and halves snapshot staleness
var send_timer = SEND_RATE
var my_player_index
# hb counters (client): host-HP drops seen for the local slot / unit flashes applied to players.
var _bt_local_hits := 0
var _left_chooser_tick := 0   # host: rate limiter for _resolve_left_players_chooser
var _bt_player_flashes := 0
var _bt_player_flash_ok := 0   # flashes where sprite.material == flash_mat right after flash()

# Split-channel state sync: positional snapshot goes unreliable and carries a monotonic
# sequence so the client drops out-of-order packets; deaths/effects go reliable. SEQ resets
# per wave because both Main scenes are recreated each wave (these are scene-instance vars).
var _state_seq : int = 0        # host: increments per snapshot sent
var _last_state_seq : int = 0   # client: highest SEQ applied so far
# Client: enemy/boss ids reported dead -> the physics frame the death event arrived.
# Blocking is TIME-BOUNDED (DEAD_ID_BLOCK_FRAMES): a genuinely dead enemy leaves the host's
# rows within a frame, so the block only needs to cover the in-flight cross-channel window.
# Run 5 proved the host keeps sending LIVE rows for ids it batched deaths for (die() calls
# that don't remove the unit) -- an unbounded block turned the whole kill count invisible.
# After expiry the id may respawn; its statics were erased on death, so the BTMISS backstop
# re-requests them and the enemy re-renders. See _is_dead_blocked.
const DEAD_ID_BLOCK_FRAMES = 120
var client_dead_ids := {}       # network_id -> physics frame of the death event
# BTMISS backstop: ids seen in positional rows with no statics to instance them (value =
# physics frame first noticed / last re-requested). The _physics_process pump re-requests
# them from the host; entries clear when statics arrive or the enemy dies.
var _missing_statics := {}
var _last_enemy_rows : int = 0   # enemies in the most recently applied snapshot (hb rows= field)
const STATICS_FRESH_TICKS = 12  # ~200ms at 60Hz: how long a new id's statics ride the snapshot
var _statics_fresh := {}        # host: id -> [[filename, stats_path], ticks_left] for snapshot-carried statics
var _deaths_reported := {}      # host: every id ever batched into BATCHED_ENEMY_DEATHS this wave
var _batched_player_deaths := []   # host: player indexes that died since the last events send
var _run_ended_by_host := false    # client: host_run_ended received (drives _on_EndWaveTimer_timeout)
var _btdead_tick : int = 0      # host: 1/s cadence for the BTDEAD audit print


# True while a death event for this id is fresh (< DEAD_ID_BLOCK_FRAMES). Expired entries
# are dropped so the client converges to whatever the host actually keeps sending.
func _is_dead_blocked(enemy_id) -> bool:
	if not client_dead_ids.has(enemy_id):
		return false
	if Engine.get_physics_frames() - client_dead_ids[enemy_id] < DEAD_ID_BLOCK_FRAMES:
		return true
	client_dead_ids.erase(enemy_id)
	return false

var client_players = {}
var client_enemies = {}
var client_births = {}
var client_player_projectiles = {}
var client_enemy_projectiles = {}
var client_items = {}
var client_consumables = {}
var client_neutrals = {}
var client_structures = {}
var client_pets = {}

# Used to dedupe spawns
var client_pending_ids = {}

# Enemies ride the unreliable snapshot as fixed-order int ROWS (see _append_enemy_row /
# _apply_enemy_rows): [network_id, x, y, move_x*100, move_y*100, mod_a, mod_r, mod_g, mod_b].
# The per-enemy string statics (scene filename + stats resource_path) are ~9x the row's bytes,
# never change, and so are hoisted out of the 60 Hz snapshot into a one-shot RELIABLE spawn
# event (BATCHED_ENEMY_SPAWNS) keyed by network_id.
const ENEMY_ROW_STRIDE := 9
# On the wire the int rows are packed to bytes (see _pack_enemy_rows): u32 id, i16 x, i16 y,
# i16 move_x*100, i16 move_y*100, u8 a/r/g/b = 16 B per enemy vs 36 B as PoolIntArray. At
# 60-70 live enemies (danger 0, two bots, wave 9+) the int rows alone were 2.1-2.6 KB and
# every snapshot fell back to the reliable channel (BTSIZE run 28).
const ENEMY_ROW_BYTES := 16
# ENEMY_PROJECTILES: packed bytes u32 id, i16 x, i16 y, i16 rot*1000, u8 file_idx (11 B) with the
# distinct scene paths in a per-snapshot EP_FILES table. CONSUMABLES: int rows [id, x, y, file_idx]
# + CS_FILES table. Each used to carry its ~50 B path string per object per tick (BTSIZE run 30:
# ENEMY_PROJECTILES 4.6 KB at wave 8 with 100+ live enemies, CONSUMABLES ~1 KB).
const EP_ROW_BYTES := 11
const CS_ROW_STRIDE := 4
var _ep_files_out : Array = []   # EP_FILES for the snapshot being built (host)
var _cs_files_out : Array = []   # CS_FILES for the snapshot being built (host)
# ITEMS row: [network_id, x, y, scale_x*100, scale_y*100]. Materials used to ride as a
# 5-key string dict each (~70 B); two danger-0 bots litter 40+ materials -> the snapshot
# outgrew the ~1200 B unreliable MTU every tick from wave 3 (10k+ reliable fallbacks,
# host at ~27 snapshots/s, client visibly slow -- run 25, 2026-09-10).
const ITEM_ROW_STRIDE := 5
# BIRTHS row: [network_id, x, y, type]. Colors were dead weight (client start() derives them
# from type). WEAPON row (inside each PLAYERS entry): [sprite_rot*1000, rot*1000, sprite_x*100,
# sprite_y*100, is_shooting]. BTSIZE run 27: PLAYERS 1.5 KB (weapon dicts) + BIRTHS 1.0-1.4 KB
# spikes were the two fattest sections once ITEMS shrank.
const BIRTH_ROW_STRIDE := 4
const WEAPON_ROW_STRIDE := 5
var _enemy_statics_sent := {}   # host: network_ids whose spawn statics have been sent this wave
var client_enemy_statics := {}  # client: network_id -> [filename, resource_path] from spawn events

var _spawning_ghosts: bool = false
const GHOST_DELAY_MSEC: int = 100
var _ghost_queue: Array = []
var _ghost_players: Dictionary = {}
var _ghost_births: Dictionary = {}

var server_player_projectile_ids = {}
var server_enemy_projectile_ids = {}

var ENTITY_BIRTH_SCENE = load("res://entities/birth/entity_birth.tscn")
var TREE_SCENE = load("res://entities/units/neutral/tree.tscn")
var CLIENT_TURRET_STATS = load("res://entities/structures/turret/turret_stats.tres")

const ENABLE_DEBUG = false
const LOG_SLOW_US: int = 5000
const LOG_INTERVAL: int = 300
const LOG_FRAME_SLOW_US: int = 25000
const LOG_WAVE_END_WINDOW: float = 15.0
const LOG_WAVE_END_INTERVAL: int = 30

var debug_frame_counter : int = 0
var _frame_log_counter: int = 0
var _physics_step_count: int = 0

# This is currently a half-completed attempt ot shrink some of the overhead
# in messaging.  With a bit of testing, the gains weren't that great given
# compression so it may not get done.
enum EntityState {
	ENTITY_STATE_NETWORK_ID,

	ENTITY_STATE_X_POS,
	ENTITY_STATE_Y_POS,
	ENTITY_STATE_X_MOVE,
	ENTITY_STATE_Y_MOVE,
	ENTITY_STATE_CURRENT_HP,
	ENTITY_STATE_MAX_HP,
	ENTITY_STATE_SPRITE_SCALE,

	# Player-specific entity state.
	ENTITY_STATE_PLAYER_GOLD,
	ENTITY_STATE_PLAYER_CURRENT_XP,
	ENTITY_STATE_PLAYER_NEXT_LEVEL_XP,
	ENTITY_STATE_PLAYER_NUM_UPGRADES,
	ENTITY_STATE_PLAYER_WEAPONS,
	ENTITY_STATE_PLAYER_LEVEL,
}

enum WeaponState {
	WEAPON_STATE_X_POS,
	WEAPON_STATE_Y_POS,
	WEAPON_STATE_ROTATION,
	WEAPON_STATE_SPRITE_ROTATION,
	WEAPON_STATE_IS_SHOOTING,
}

enum ProjectileState {
	PROJECTILE_STATE_NETWORK_ID,

	PROJECTILE_STATE_X_POS,
	PROJECTILE_STATE_Y_POS,
	PROJECTILE_STATE_ROTATION,
	PROJECTILE_STATE_FILENAME,
}



func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game

	if in_multiplayer_game:
		steam_connection.connect("client_status_received", self, "_client_status_received")
		steam_connection.connect("host_starts_round", self, "_host_starts_round")
		steam_connection.connect("state_update", self, "_state_update")
		steam_connection.connect("state_events", self, "_state_events")
		steam_connection.connect("enemy_statics_requested", self, "_on_enemy_statics_requested")
		steam_connection.connect("host_run_ended", self, "_host_run_ended")
		steam_connection.connect("player_left_run", self, "_on_player_left_run")
		# Replay reliable one-shot events (spawn statics, deaths) that arrived while this
		# scene was still loading -- steam_connection buffers them when nobody listens
		# (the shop->Main window used to silently eat them: invisible enemies / ghosts).
		steam_connection.drain_pending_state_events()
		steam_connection.connect("client_position", self, "_update_player_position")
		steam_connection.connect("client_menu_focus", self, "_update_client_focus")

		steam_connection.connect("client_main_scene_reroll_button_pressed", self, "_client_reroll_button_pressed")
		steam_connection.connect("client_main_scene_choose_upgrade_pressed", self, "_client_choose_upgrade_button_pressed")
		steam_connection.connect("client_main_scene_take_button_pressed", self, "_client_take_button_pressed")
		steam_connection.connect("client_main_scene_discard_button_pressed", self, "_client_discard_button_pressed")

		steam_connection.connect("host_entered_shop", self, "_host_entered_shop")

		my_player_index = steam_connection.get_my_index()

		call_deferred("multiplayer_ready")


func _physics_process(delta : float):
	if not in_multiplayer_game:
		return

	# BTMISS backstop pump (client): every ~0.5s re-request spawn statics for ids we keep
	# receiving rows for but cannot instance (ids clear when statics arrive or the enemy
	# dies). Must be empty at steady state -- the harness hb exposes it as cli=.../mN.
	if not steam_connection.is_host() and not _missing_statics.empty() \
			and Engine.get_physics_frames() % 30 == 0:
		var now_f = Engine.get_physics_frames()
		var req_ids = []
		for mid in _missing_statics:
			if now_f - _missing_statics[mid] >= 20:
				req_ids.push_back(mid)
				_missing_statics[mid] = now_f
		if not req_ids.empty():
			print("BTMISS request n=%d" % req_ids.size())
			steam_connection.request_enemy_statics(req_ids)

	if steam_connection.is_host() and not steam_connection.left_players.empty():
		_left_chooser_tick += 1
		if _left_chooser_tick % 15 == 0:
			_resolve_left_players_chooser()

	send_timer -= delta
	if send_timer <= 0.0:
		send_timer = SEND_RATE
		if steam_connection.is_host():
			if ENABLE_DEBUG:
				var send_before_us = Time.get_ticks_usec()
				_send_game_state()
				var send_us = Time.get_ticks_usec() - send_before_us
				if send_us > LOG_SLOW_US:
					var enemy_count = _entity_spawner.enemies.size() if is_instance_valid(_entity_spawner) else -1
					print("BTPROF type=send send_us=%d enemies=%d" % [send_us, enemy_count])
			else:
				_send_game_state()
		else:
			_send_client_position()

	if ENABLE_DEBUG:
		_physics_step_count += 1

	if brotatogether_options.is_solo_test:
		var now = Time.get_ticks_msec()
		while _ghost_queue.size() > 0 and now - _ghost_queue[0]["time"] >= GHOST_DELAY_MSEC:
			_spawning_ghosts = true
			var entry = _ghost_queue.pop_front()
			_ghost_state_update(entry["state"], now - entry["time"])
			_spawning_ghosts = false


func _process(_delta):
	if in_multiplayer_game:
		if ENABLE_DEBUG:
			var frame_us = int(_delta * 1_000_000)
			var wave_time_left = _wave_timer.time_left if is_instance_valid(_wave_timer) else -1.0
			var near_wave_end = wave_time_left >= 0.0 and wave_time_left < LOG_WAVE_END_WINDOW
			_frame_log_counter += 1
			if frame_us > LOG_FRAME_SLOW_US or (near_wave_end and _frame_log_counter % LOG_WAVE_END_INTERVAL == 0):
				print("BTPROF type=frame frame_us=%d wave_time=%.1f physics_steps=%d" % [frame_us, wave_time_left, _physics_step_count])
			_physics_step_count = 0
		if waiting_to_start_round:
			if steam_connection.is_host():
				var all_players_entered = true
				for player_index in RunData.get_player_count():
					if not player_in_scene[player_index] and not steam_connection.left_players.has(player_index):
						all_players_entered = false
						break
				if all_players_entered:
					waiting_to_start_round = false
					_wave_timer.start()
					_wave_timer.paused = false
					steam_connection.send_round_start()


func _send_game_state() -> void:
	var state_dict = {}

	state_dict["WAVE_TIME"] = _wave_timer.time_left
	state_dict["BONUS_GOLD"] = RunData.bonus_gold

	var players = []
	for player_index in _players.size():
		var player = _players[player_index]
		players.push_back(_dictionary_for_player(player, player_index))
	state_dict["PLAYERS"] = players

	# Enemies + bosses go out as flat int rows; first sight of an id also emits its statics
	# into enemy_spawns, which is attached to the reliable events packet below.
	var enemy_spawns := {}
	var enemy_rows := PoolIntArray()
	for enemy in _entity_spawner.enemies:
		# Skip corpses: a dead enemy plays its ~0.5s death animation before being freed or
		# pooled, and serializing it wastes bytes -- the client already killed its copy via
		# the reliable death event and ignores the row (dead-id guard). Skipping also makes
		# the rows-vs-alive parity check exact (BTDEAD run-6 finding).
		if is_instance_valid(enemy) and not enemy.dead:
			enemy_rows.append_array(_enemy_row(enemy, enemy_spawns))
	# Snapshot-carried statics for ids first seen in the last STATICS_FRESH_TICKS sends
	# (same-channel with their rows -- see _enemy_row). Dropped once the budget runs out.
	var snap_spawns = {}
	for fresh_id in _statics_fresh.keys():
		snap_spawns[fresh_id] = _statics_fresh[fresh_id][0]
		_statics_fresh[fresh_id][1] -= 1
		if _statics_fresh[fresh_id][1] <= 0:
			_statics_fresh.erase(fresh_id)
	if not snap_spawns.empty():
		state_dict["BATCHED_ENEMY_SPAWNS"] = snap_spawns
	state_dict["ENEMIES"] = _pack_enemy_rows(enemy_rows)
	# BTDEAD: once per second, audit live rows against the dead-reported set. A nonzero
	# rows_reported_dead names the second hole: die() was batched for a unit the spawner
	# still lists as alive. The sample names the mechanic.
	_btdead_tick += 1
	if _btdead_tick >= 60:
		_btdead_tick = 0
		var rows_dead_flag = 0
		var rows_reported_dead = 0
		var sample = ""
		if is_instance_valid(_entity_spawner):
			for e in _entity_spawner.enemies + _entity_spawner.bosses:
				if not is_instance_valid(e):
					continue
				if e.dead:
					rows_dead_flag += 1
				if _deaths_reported.has(e.network_id):
					rows_reported_dead += 1
					if sample == "":
						sample = "%s#%d dead=%s" % [e.filename.get_file(), e.network_id, str(e.dead)]
		if rows_reported_dead > 0 or rows_dead_flag > 0:
			print("BTDEAD live_rows=%d rows_dead_flag=%d rows_reported_dead=%d sample=%s" % [int(enemy_rows.size() / ENEMY_ROW_STRIDE), rows_dead_flag, rows_reported_dead, sample])

	var boss_rows := PoolIntArray()
	for boss in _entity_spawner.bosses:
		if is_instance_valid(boss) and not boss.dead:
			boss_rows.append_array(_enemy_row(boss, enemy_spawns))
	state_dict["BOSSES"] = _pack_enemy_rows(boss_rows)

	state_dict["BIRTHS"] = _host_births_array()
	state_dict["PLAYER_PROJECTILES"] = _host_player_projectiles_array()
	state_dict["ITEMS"] = _host_items_array()
	state_dict["CONSUMABLES"] = _host_consumables_array()
	state_dict["CS_FILES"] = _cs_files_out
	state_dict["NEUTRALS"] = _host_neutrals_array()
	state_dict["STRUCTURES"] = _host_structures_array()
	state_dict["PETS"] = _host_pets_array()
	state_dict["ENEMY_PROJECTILES"] = _host_enemy_projectiles_array()
	state_dict["EP_FILES"] = _ep_files_out
	state_dict["UPGRADE_MENU_STATUS"] = _host_menu_status()

	# One-shot deltas -> reliable events channel (see steam_connection.send_game_events).
	# These MUST NOT be dropped (a lost death leaves a ghost enemy), so they never ride
	# the unreliable snapshot below. Batches are drained here at the send cadence.
	var events_dict = {}
	events_dict["BATCHED_ENEMY_DEATHS"] = brotatogether_options.batched_enemy_deaths.duplicate()
	brotatogether_options.batched_enemy_deaths.clear()
	# Player deaths (see _on_player_died): clients never simulate player damage, so
	# without this a dead tato kept walking around on every client.
	events_dict["BATCHED_PLAYER_DEATHS"] = _batched_player_deaths.duplicate()
	_batched_player_deaths.clear()
	# BTDEAD diagnostic: remember every id we EVER reported dead this wave, to detect
	# live rows still flowing for "dead" ids (the run-5 rows-vs-alive deficit).
	for dead_id in events_dict["BATCHED_ENEMY_DEATHS"]:
		_deaths_reported[dead_id] = true
	events_dict["BATCHED_HIT_EFFECTS"] = brotatogether_options.batched_hit_effects.duplicate()
	brotatogether_options.batched_hit_effects.clear()
	events_dict["BATCHED_HIT_PARTICLES"] = brotatogether_options.batched_hit_particles.duplicate()
	brotatogether_options.batched_hit_particles.clear()
	events_dict["BATCHED_FLOATING_TEXT"] = brotatogether_options.batched_floating_text.duplicate()
	brotatogether_options.batched_floating_text.clear()
	events_dict["BATCHED_UNIT_FLASHES"] = brotatogether_options.batched_unit_flashes.duplicate()
	brotatogether_options.batched_unit_flashes.clear()
	events_dict["BATCHED_2D_SOUNDS"] = brotatogether_options.batched_2d_sounds.duplicate()
	brotatogether_options.batched_2d_sounds.clear()
	events_dict["BATCHED_SOUNDS"] = brotatogether_options.batched_sounds.duplicate()
	brotatogether_options.batched_sounds.clear()
	events_dict["BATCHED_EXPLOSIONS"] = brotatogether_options.batched_explosions.duplicate()
	brotatogether_options.batched_explosions.clear()
	# Per-enemy statics (filename + resource_path) for ids first seen this tick. Reliable so the
	# client can decode the enemy's int rows once it knows how to instance it. Empty most ticks.
	events_dict["BATCHED_ENEMY_SPAWNS"] = enemy_spawns

	_state_seq += 1
	state_dict["SEQ"] = _state_seq
	state_dict["SENT_AT_MS"] = Time.get_ticks_msec()
	steam_connection.send_game_state(state_dict)

	# Only send the reliable events packet when something actually happened this tick.
	var has_events = false
	for k in events_dict:
		if events_dict[k].size() > 0:
			has_events = true
			break
	if has_events:
		steam_connection.send_game_events(events_dict)

	if brotatogether_options.is_solo_test:
		# Solo ghost replay expects one combined dict (positions + batches together).
		var merged = state_dict.duplicate()
		for k in events_dict:
			merged[k] = events_dict[k]
		_ghost_queue.push_back({"time": Time.get_ticks_msec(), "state": merged})


func _state_update(state_dict : Dictionary) -> void:
	# Unreliable snapshots can arrive out of order; only apply a strictly newer SEQ so a
	# late packet never rewinds positions. SEQ resets each wave (fresh Main scene instance).
	var seq = state_dict.get("SEQ", 0)
	if seq <= _last_state_seq:
		return
	_last_state_seq = seq

	var start_time : int = Time.get_ticks_usec()
	var before : int

	before = Time.get_ticks_usec()
	var wait_time = float(state_dict["WAVE_TIME"])
	if wait_time > 0:
		_wave_timer.start(wait_time)
	var _wave_timer_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	var bonus_gold = state_dict["BONUS_GOLD"]
	if bonus_gold > 0:
		_ui_bonus_gold.show()
	RunData.bonus_gold = bonus_gold
	_ui_bonus_gold.update_value(bonus_gold)
	on_bonus_gold_changed(bonus_gold)
	var _bonus_gold_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	var players_array = state_dict["PLAYERS"]
	for player_index in players_array.size():
		_update_player_position(players_array[player_index], player_index)
	var _player_update_time = Time.get_ticks_usec() - before

	# Fold snapshot-carried statics (fresh ids ride them with their own rows -- same
	# channel, no reliable-vs-unreliable race) before decoding the rows that need them.
	for spawn_id in state_dict.get("BATCHED_ENEMY_SPAWNS", {}):
		client_enemy_statics[spawn_id] = state_dict["BATCHED_ENEMY_SPAWNS"][spawn_id]
		_missing_statics.erase(spawn_id)

	before = Time.get_ticks_usec()
	_last_enemy_rows = 0   # per-snapshot reset: _apply_enemy_rows accumulates ENEMIES + BOSSES
	_apply_enemy_rows(state_dict["ENEMIES"])
	var enemies_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_apply_enemy_rows(state_dict["BOSSES"])
	var bosses_update_time = Time.get_ticks_usec() - before

	# Enemy deaths + flashes + explosions moved to _state_events (reliable channel).
	var enemy_deaths_update_time = 0

	before = Time.get_ticks_usec()
	_update_player_projectiles(state_dict["PLAYER_PROJECTILES"])
	var player_projectiles_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	call_deferred("_update_births", state_dict["BIRTHS"])
	var births_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_items(state_dict["ITEMS"])
	var items_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_consumables(state_dict["CONSUMABLES"], state_dict.get("CS_FILES", []))
	var consumables_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_neutrals(state_dict["NEUTRALS"])
	var neutrals_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_structures(state_dict["STRUCTURES"])
	var structures_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_pets(state_dict["PETS"])
	var pets_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_enemy_projectiles(state_dict["ENEMY_PROJECTILES"], state_dict.get("EP_FILES", []))
	var enemy_projectiles_update_time = Time.get_ticks_usec() - before

	# Hit effects/particles/floating-text/sounds moved to _state_events (reliable channel).
	var enemy_hit_effects_update_time = 0
	var enemy_hit_particles_update_time = 0
	var floating_text_update_time = 0
	var sound_update_time = 0
	var sound_2d_update_time = 0

	before = Time.get_ticks_usec()
	_update_menu(state_dict["UPGRADE_MENU_STATUS"])
	var _menu_update_time = Time.get_ticks_usec() - before

	if ENABLE_DEBUG:
		var total_us = Time.get_ticks_usec() - start_time
		var net_ms = Time.get_ticks_msec() - state_dict.get("SENT_AT_MS", Time.get_ticks_msec())
		debug_frame_counter += 1
		if debug_frame_counter % LOG_INTERVAL == 0 or total_us > LOG_SLOW_US:
			print("BTPROF type=client frame=%d net_ms=%d total_us=%d enemies_us=%d bosses_us=%d items_us=%d consumables_us=%d proj_us=%d births_us=%d neutrals_us=%d structures_us=%d pets_us=%d effects_us=%d sounds_us=%d deaths_us=%d players=%d enemies=%d bosses=%d projectiles=%d items=%d consumables=%d neutrals=%d structures=%d pets=%d births=%d" % [
				debug_frame_counter, net_ms, total_us,
				enemies_update_time, bosses_update_time,
				items_update_time, consumables_update_time,
				player_projectiles_update_time + enemy_projectiles_update_time,
				births_update_time, neutrals_update_time, structures_update_time, pets_update_time,
				enemy_hit_effects_update_time + enemy_hit_particles_update_time + floating_text_update_time,
				sound_update_time + sound_2d_update_time,
				enemy_deaths_update_time,
				state_dict["PLAYERS"].size(), int(state_dict["ENEMIES"].size() / ENEMY_ROW_BYTES), int(state_dict["BOSSES"].size() / ENEMY_ROW_BYTES),
				state_dict["PLAYER_PROJECTILES"].size() + int(state_dict["ENEMY_PROJECTILES"].size() / EP_ROW_BYTES),
				int(state_dict["ITEMS"].size() / ITEM_ROW_STRIDE), int(state_dict["CONSUMABLES"].size() / CS_ROW_STRIDE),
				state_dict["NEUTRALS"].size(), state_dict["STRUCTURES"].size(),
				state_dict["PETS"].size(), int(state_dict["BIRTHS"].size() / BIRTH_ROW_STRIDE)])


func _state_events(events_dict : Dictionary) -> void:
	# Reliable one-shot deltas split out of the positional snapshot. Deaths are recorded in
	# client_dead_ids so a late/reordered unreliable roster snapshot can't respawn a killed
	# enemy (_update_enemy consults it). Effects/sounds are cosmetic and simply applied.
	# Record enemy statics before positional rows for these ids can spawn them (this reliable
	# packet may arrive a tick before/after the unreliable snapshot; _apply_enemy_rows defers
	# any row whose statics aren't here yet).
	for spawn_id in events_dict.get("BATCHED_ENEMY_SPAWNS", {}):
		client_enemy_statics[spawn_id] = events_dict["BATCHED_ENEMY_SPAWNS"][spawn_id]
		_missing_statics.erase(spawn_id)

	for enemy_id in events_dict["BATCHED_ENEMY_DEATHS"]:
		client_dead_ids[enemy_id] = Engine.get_physics_frames()
		client_enemy_statics.erase(enemy_id)
		_missing_statics.erase(enemy_id)
		if client_enemies.has(enemy_id):
			if not client_enemies[enemy_id].dead:
				client_enemies[enemy_id].die()
			client_enemies.erase(enemy_id)

	# Host-authoritative player deaths (own player included: the client's local sim
	# only moves it, all damage is computed on the host). .get: older hosts omit the key.
	for player_index in events_dict.get("BATCHED_PLAYER_DEATHS", []):
		if player_index < _players.size():
			var dead_player = _players[player_index]
			if is_instance_valid(dead_player) and not dead_player.dead:
				dead_player.die(Entity.DieArgs.new())

	for flashing_unit_id in events_dict["BATCHED_UNIT_FLASHES"]:
		var flashing_unit
		if client_enemies.has(flashing_unit_id):
			flashing_unit = client_enemies[flashing_unit_id]
		elif client_players.has(flashing_unit_id):
			flashing_unit = client_players[flashing_unit_id]
			_bt_player_flashes += 1
		elif client_neutrals.has(flashing_unit_id):
			flashing_unit = client_neutrals[flashing_unit_id]
		if flashing_unit and is_instance_valid(flashing_unit):
			flashing_unit.flash()
			# diag: did the flash material actually land on a player sprite?
			if flashing_unit is Player and ("flash_mat" in flashing_unit) and flashing_unit.flash_mat != null \
					and flashing_unit.sprite.material == flashing_unit.flash_mat:
				_bt_player_flash_ok += 1

	for explosion in events_dict["BATCHED_EXPLOSIONS"]:
		call_deferred("spawn_explosion", explosion)

	_update_batched_hit_effects(events_dict["BATCHED_HIT_EFFECTS"])
	_update_batched_hit_particles(events_dict["BATCHED_HIT_PARTICLES"])
	_update_batched_floating_text(events_dict["BATCHED_FLOATING_TEXT"])

	for sound in events_dict["BATCHED_SOUNDS"]:
		SoundManager.call_deferred("play", load(sound["RESOURCE_PATH"]))
	for sound in events_dict["BATCHED_2D_SOUNDS"]:
		SoundManager2D.call_deferred("play", load(sound["RESOURCE_PATH"]), Vector2(sound["X_POS"], sound["Y_POS"]))


func _input(event) -> void:
	if not ENABLE_DEBUG:
		return
	if event is InputEventKey:
		if event.scancode == KEY_F1:
#			on_levelled_up(0)
			var consumable = consumable_scene.instance()
			var consumable_to_spawn = load("res://items/consumables/item_box/item_box_data.tres")
			consumable.consumable_data = consumable_to_spawn
			consumable.set_texture(consumable_to_spawn.icon)
			on_consumable_picked_up(consumable , 0)


func _send_client_position() -> void:
	var in_postwave_menu = _coop_upgrades_ui.visible
	if in_postwave_menu:
		var player_container = _coop_upgrades_ui._get_player_container(my_player_index)
		var focus_string = _string_for_menu_focus(player_container)
		steam_connection.send_client_menu_focus(
			{
				"FOCUS" : focus_string
			}
		)
	else:
		steam_connection.send_client_position(_dictionary_for_player(_players[my_player_index], my_player_index))


func _dictionary_for_player(player, player_index) -> Dictionary:
	var player_run_data = RunData.players_data[player_index]
	var player_dict = {
		EntityState.ENTITY_STATE_NETWORK_ID : player.network_id,

		EntityState.ENTITY_STATE_X_POS : player.position.x,
		EntityState.ENTITY_STATE_Y_POS : player.position.y,

		EntityState.ENTITY_STATE_X_MOVE : player._current_movement.x,
		EntityState.ENTITY_STATE_Y_MOVE : player._current_movement.y,

		EntityState.ENTITY_STATE_SPRITE_SCALE: player.sprite.scale.x,
		EntityState.ENTITY_STATE_PLAYER_LEVEL: player_run_data.current_level
	}

	var weapon_rows := PoolIntArray()
	for weapon in player.current_weapons:
		weapon_rows.push_back(int(round(weapon.sprite.rotation * 1000.0)))
		weapon_rows.push_back(int(round(weapon.rotation * 1000.0)))
		weapon_rows.push_back(int(round(weapon.sprite.position.x * 100.0)))
		weapon_rows.push_back(int(round(weapon.sprite.position.y * 100.0)))
		weapon_rows.push_back(1 if weapon._is_shooting else 0)
	player_dict[EntityState.ENTITY_STATE_PLAYER_WEAPONS] = weapon_rows

	if steam_connection.is_host():
		player_dict[EntityState.ENTITY_STATE_PLAYER_GOLD] = RunData.players_data[player_index].gold
		player_dict[EntityState.ENTITY_STATE_PLAYER_CURRENT_XP] = RunData.players_data[player_index].current_xp
		player_dict[EntityState.ENTITY_STATE_PLAYER_NEXT_LEVEL_XP] = RunData.get_next_level_xp_needed(player_index)
		player_dict[EntityState.ENTITY_STATE_CURRENT_HP] = player.current_stats.health
		player_dict[EntityState.ENTITY_STATE_MAX_HP] = player.max_stats.health

		var things_to_process = _things_to_process_player_containers[player_index]
		player_dict[EntityState.ENTITY_STATE_PLAYER_NUM_UPGRADES] = things_to_process.upgrades._elements.size()

	return player_dict


func _update_player_position(player_dict : Dictionary, player_index : int) -> void:
	# A packet for a slot this scene never spawned (stale roster, race on a leave/rejoin)
	# must not index past _players -- that was the "Invalid get index 2" crash loop.
	if player_index < 0 or player_index >= _players.size():
		return
	var player = _players[player_index]
	var network_id = player_dict[EntityState.ENTITY_STATE_NETWORK_ID]

	if not client_players.has(network_id):
		client_players[network_id] = player

	if player_index != my_player_index:
		if player.dead:
			return
		player.call_deferred("update_external_player_position", player_dict)

	if not steam_connection.is_host():
		_players_ui[player_index].call_deferred("update_level_label")
		# Clients never run take_damage (unit.gd ext returns early), so the vanilla
		# took_damage -> Screenshaker wiring never fires here. Mirror the host's shake for
		# the LOCAL slot off the authoritative HP drop (flash/floating text/hit fx already
		# arrive batched from the host, so do not emit took_damage: that would double them).
		if player_index == my_player_index and is_instance_valid(_screenshaker) 				and player_dict.has(EntityState.ENTITY_STATE_CURRENT_HP) 				and player_dict[EntityState.ENTITY_STATE_CURRENT_HP] < player.current_stats.health:
			_screenshaker.shake(5, 0.1)
			_bt_local_hits += 1
		player.call_deferred("update_client_player", player_dict, player_index)

		var things_to_process = _things_to_process_player_containers[player_index]
		if player_dict[EntityState.ENTITY_STATE_PLAYER_NUM_UPGRADES] > things_to_process.upgrades._elements.size():
			things_to_process.upgrades.add_element(ItemService.get_icon(Keys.icon_upgrade_to_process_hash), 1)


# Quantize a movement/facing component to an int (x100). Preserves sign for any non-zero
# input so the client's facing never collapses to zero from rounding.
static func _quantize_dir(v : float) -> int:
	if v > 0.0:
		return int(max(1, round(v * 100.0)))
	elif v < 0.0:
		return int(min(-1, round(v * 100.0)))
	return 0


# Build one enemy's 9-int row. On first sight of an id this tick, records its statics (scene
# filename + stats resource_path) into `spawns` so they ride the reliable spawn event exactly
# once instead of on every snapshot. Positions are quantized to whole pixels and movement to a
# signed x100 int -- ints gzip far better than float bit patterns and sub-pixel precision is
# imperceptible at 60 Hz (_quantize_dir never rounds a nonzero to 0, so the client's facing
# survives). Field order MUST match _apply_enemy_rows' reader. Returns the row (PoolIntArray is
# passed/returned BY VALUE in Godot 3.x, so the caller appends it -- a mutate-through-param
# helper would silently write to a throwaway copy).
func _enemy_row(enemy, spawns : Dictionary) -> PoolIntArray:
	var enemy_id = enemy.network_id
	if not _enemy_statics_sent.has(enemy_id):
		_enemy_statics_sent[enemy_id] = true
		spawns[enemy_id] = [enemy.filename, enemy.stats.resource_path]
		# Also ride the statics in the UNRELIABLE snapshot for the id's first ticks
		# (see _statics_fresh in _send_game_state): the reliable events channel can lag
		# the unreliable rows by 100 ms+ on an asymmetric link, and with pooled reuse
		# stamping fresh ids EVERY spawn depends on statics -- clients visibly spawned
		# enemies late (Pasha, role-reversed session 2026-09-09). Same-channel delivery
		# removes the race; the events copy still covers the scene-load buffer window.
		_statics_fresh[enemy_id] = [spawns[enemy_id], STATICS_FRESH_TICKS]

	var modulate = enemy.sprite.self_modulate
	var row := PoolIntArray()
	row.push_back(enemy_id)
	row.push_back(int(round(enemy.position.x)))
	row.push_back(int(round(enemy.position.y)))
	row.push_back(_quantize_dir(enemy._current_movement.x))
	row.push_back(_quantize_dir(enemy._current_movement.y))
	row.push_back(modulate.a8)
	row.push_back(modulate.r8)
	row.push_back(modulate.g8)
	row.push_back(modulate.b8)
	return row


# BTMISS backstop (host): a client received rows for these ids but never got their spawn
# statics (its Main was still loading when the one-shot event went out, or any other loss).
# Rebuild and resend them. Every other batch key must be present -- the client's
# _state_events indexes them unconditionally. An id no longer alive is simply skipped: the
# reliable death event (buffered too, now) clears it on the client.
func _on_enemy_statics_requested(ids) -> void:
	if not steam_connection.is_host():
		return
	var spawns = {}
	if is_instance_valid(_entity_spawner):
		for enemy in _entity_spawner.enemies:
			if is_instance_valid(enemy) and enemy.network_id in ids:
				spawns[enemy.network_id] = [enemy.filename, enemy.stats.resource_path]
		for boss in _entity_spawner.bosses:
			if is_instance_valid(boss) and boss.network_id in ids:
				spawns[boss.network_id] = [boss.filename, boss.stats.resource_path]
	if spawns.empty():
		return
	print("BTMISS host resending statics for %d id(s)" % spawns.size())
	steam_connection.send_game_events({
		"BATCHED_ENEMY_DEATHS": [], "BATCHED_HIT_EFFECTS": [], "BATCHED_HIT_PARTICLES": [],
		"BATCHED_FLOATING_TEXT": [], "BATCHED_UNIT_FLASHES": [], "BATCHED_2D_SOUNDS": [],
		"BATCHED_SOUNDS": [], "BATCHED_EXPLOSIONS": [], "BATCHED_ENEMY_SPAWNS": spawns,
	})


# Decode a flat enemy/boss int-row buffer (see _append_enemy_row) and feed each enemy to the
# existing dict-based _update_enemy. Statics for a not-yet-seen id arrive on the reliable spawn
# event; if a positional row for a brand-new id beats its spawn event (unreliable can outrun
# reliable), we skip it this tick -- the enemy simply appears one snapshot later once its
# statics are known. Already-known and already-dead ids never need statics.
# Wire packing for enemy rows (host side). Field order matches _enemy_row / _apply_enemy_rows.
func _pack_enemy_rows(rows : PoolIntArray) -> PoolByteArray:
	var buf := StreamPeerBuffer.new()
	var count = int(rows.size() / ENEMY_ROW_STRIDE)
	for k in count:
		var base = k * ENEMY_ROW_STRIDE
		buf.put_u32(rows[base])
		buf.put_16(rows[base + 1])
		buf.put_16(rows[base + 2])
		buf.put_16(rows[base + 3])
		buf.put_16(rows[base + 4])
		buf.put_u8(rows[base + 5])
		buf.put_u8(rows[base + 6])
		buf.put_u8(rows[base + 7])
		buf.put_u8(rows[base + 8])
	return buf.data_array


# Inverse of _pack_enemy_rows (client side): bytes back to the 9-int rows the reader expects.
func _unpack_enemy_rows(bytes : PoolByteArray) -> PoolIntArray:
	var rows := PoolIntArray()
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var count = int(bytes.size() / ENEMY_ROW_BYTES)
	for _k in count:
		rows.push_back(buf.get_u32())
		rows.push_back(buf.get_16())
		rows.push_back(buf.get_16())
		rows.push_back(buf.get_16())
		rows.push_back(buf.get_16())
		rows.push_back(buf.get_u8())
		rows.push_back(buf.get_u8())
		rows.push_back(buf.get_u8())
		rows.push_back(buf.get_u8())
	return rows


func _apply_enemy_rows(rows) -> void:
	if rows == null:
		return
	if rows is PoolByteArray:
		rows = _unpack_enemy_rows(rows)
	var enemy_count = int(rows.size() / ENEMY_ROW_STRIDE)
	_last_enemy_rows += enemy_count   # accumulates across the ENEMIES and BOSSES calls per snapshot
	for k in enemy_count:
		var base = k * ENEMY_ROW_STRIDE
		var enemy_id = rows[base]
		if _is_dead_blocked(enemy_id):
			continue
		var is_known = client_enemies.has(enemy_id)
		if not is_known and not client_enemy_statics.has(enemy_id):
			# BTMISS: remember the id so the backstop pump can re-request its statics --
			# without this the row is skipped forever and the enemy never renders here.
			if not _missing_statics.has(enemy_id):
				_missing_statics[enemy_id] = Engine.get_physics_frames()
			continue
		var enemy_dict = {
			"NETWORK_ID": enemy_id,
			"X_POS": rows[base + 1],
			"Y_POS": rows[base + 2],
			"MOVE_X": rows[base + 3],
			"MOVE_Y": rows[base + 4],
			"MODULATE_A": rows[base + 5],
			"MODULATE_R": rows[base + 6],
			"MODULATE_G": rows[base + 7],
			"MODULATE_B": rows[base + 8],
		}
		if not is_known:
			var statics = client_enemy_statics[enemy_id]
			enemy_dict["FILENAME"] = statics[0]
			enemy_dict["RESOURCE_PATH"] = statics[1]
		_update_enemy(enemy_dict)


func _update_enemy(enemy_dict : Dictionary) -> void:
	var enemy_id = enemy_dict["NETWORK_ID"]
	# A reliable death for this id already arrived; ignore any lingering/reordered roster
	# entry so we never respawn a corpse (deaths ride a separate reliable channel now).
	if _is_dead_blocked(enemy_id):
		return
	if client_enemies.has(enemy_id):
		var enemy = client_enemies[enemy_id]

		enemy.call_deferred("update_client_enemy", enemy_dict)
	else:
		if not client_pending_ids.has(enemy_id):
			client_pending_ids[enemy_id] = true
			call_deferred("spawn_enemy", enemy_dict)


func spawn_enemy(enemy_dict) -> void:
	if not is_instance_valid(_entities_container):
		return

	var filename = enemy_dict["FILENAME"]
	var resource_path = enemy_dict["RESOURCE_PATH"]
	var enemy_id = enemy_dict["NETWORK_ID"]

	# Death may have landed between _update_enemy's check and this deferred call.
	if _is_dead_blocked(enemy_id):
		client_pending_ids.erase(enemy_id)
		return

	var enemy = load(filename).instance()
	enemy._entity_spawner_ref = _entity_spawner

	var position : Vector2 = Vector2(enemy_dict["X_POS"], enemy_dict["Y_POS"])
	enemy.position = position
	enemy.stats = load(resource_path)

	client_enemies[enemy_id] = enemy
	client_pending_ids.erase(enemy_id)

	var movement_behavior = enemy.get_node("MovementBehavior")
	enemy.remove_child(movement_behavior)
	var client_movement_behavior = ClientMovementBehavior.new()
	client_movement_behavior.set_name("MovementBehavior")
	enemy.add_child(client_movement_behavior, true)
	enemy._current_movement_behavior = client_movement_behavior

	var attack_behaviors_to_replace = []
	for child in enemy.get_children():
		if child is AttackBehavior:
			attack_behaviors_to_replace.push_back(child)
	for ab in attack_behaviors_to_replace:
		var ab_name = ab.name
		enemy.remove_child(ab)
		var client_ab = ClientAttackBehavior.new()
		client_ab.set_name(ab_name)
		enemy.add_child(client_ab, true)
	var replaced_ab = enemy.get_node_or_null("AttackBehavior")
	if replaced_ab:
		enemy._current_attack_behavior = replaced_ab

	if brotatogether_options.is_solo_test:
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		var hurtbox = enemy.get_node_or_null("Hurtbox")
		if hurtbox:
			hurtbox.monitoring = false
			hurtbox.monitorable = false
			for shape in hurtbox.get_children():
				if shape is CollisionShape2D or shape is CollisionPolygon2D:
					shape.disabled = true

	_entities_container.add_child(enemy)
	enemy.set_meta("btg_ghost_enemy", true)


func _ghost_state_update(state_dict: Dictionary, queue_delay_ms: int = 0) -> void:
	var ghost_start_us: int = Time.get_ticks_usec()
	var before: int

	before = Time.get_ticks_usec()
	_update_ghost_players(state_dict["PLAYERS"])
	var _player_update_time = Time.get_ticks_usec() - before

	# Solo ghost replay gets state + events merged into one dict, so the spawn statics for this
	# tick are right here -- fold them in before decoding the rows that reference them.
	for spawn_id in state_dict.get("BATCHED_ENEMY_SPAWNS", {}):
		client_enemy_statics[spawn_id] = state_dict["BATCHED_ENEMY_SPAWNS"][spawn_id]
		_missing_statics.erase(spawn_id)

	before = Time.get_ticks_usec()
	_last_enemy_rows = 0   # per-snapshot reset: _apply_enemy_rows accumulates ENEMIES + BOSSES
	_apply_enemy_rows(state_dict["ENEMIES"])
	var enemies_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_apply_enemy_rows(state_dict["BOSSES"])
	var bosses_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	for enemy_id in state_dict["BATCHED_ENEMY_DEATHS"]:
		if client_enemies.has(enemy_id):
			if not client_enemies[enemy_id].dead:
				client_enemies[enemy_id].die()
			else:
				push_warning("BT: ghost enemy %s already dead at death batch time" % str(enemy_id))
			client_enemies.erase(enemy_id)
	var enemy_deaths_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_enemy_projectiles(state_dict["ENEMY_PROJECTILES"], state_dict.get("EP_FILES", []))
	_update_player_projectiles(state_dict["PLAYER_PROJECTILES"])
	var proj_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	call_deferred("_update_ghost_births", state_dict["BIRTHS"])
	var births_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_items(state_dict["ITEMS"])
	var items_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_consumables(state_dict["CONSUMABLES"], state_dict.get("CS_FILES", []))
	var consumables_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_neutrals(state_dict["NEUTRALS"])
	var neutrals_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_structures(state_dict["STRUCTURES"])
	var structures_update_time = Time.get_ticks_usec() - before

	before = Time.get_ticks_usec()
	_update_pets(state_dict["PETS"])
	var pets_update_time = Time.get_ticks_usec() - before

	for explosion in state_dict["BATCHED_EXPLOSIONS"]:
		call_deferred("spawn_explosion", explosion)

	before = Time.get_ticks_usec()
	_apply_ghost_modulate()
	var modulate_us = Time.get_ticks_usec() - before

	if ENABLE_DEBUG:
		var total_us = Time.get_ticks_usec() - ghost_start_us
		debug_frame_counter += 1
		var wave_time_left = _wave_timer.time_left if is_instance_valid(_wave_timer) else -1.0
		var near_wave_end = wave_time_left >= 0.0 and wave_time_left < LOG_WAVE_END_WINDOW
		if debug_frame_counter % LOG_INTERVAL == 0 or total_us > LOG_SLOW_US or near_wave_end:
			print("BTPROF type=ghost frame=%d queue_delay_ms=%d total_us=%d modulate_us=%d enemies_us=%d bosses_us=%d items_us=%d consumables_us=%d proj_us=%d births_us=%d neutrals_us=%d structures_us=%d pets_us=%d deaths_us=%d wave_time=%.1f players=%d enemies=%d bosses=%d projectiles=%d items=%d consumables=%d neutrals=%d structures=%d pets=%d births=%d" % [
				debug_frame_counter, queue_delay_ms, total_us, modulate_us,
				enemies_update_time, bosses_update_time,
				items_update_time, consumables_update_time,
				proj_update_time, births_update_time,
				neutrals_update_time, structures_update_time, pets_update_time,
				enemy_deaths_update_time, wave_time_left,
				state_dict["PLAYERS"].size(), int(state_dict["ENEMIES"].size() / ENEMY_ROW_BYTES), int(state_dict["BOSSES"].size() / ENEMY_ROW_BYTES),
				state_dict["PLAYER_PROJECTILES"].size() + int(state_dict["ENEMY_PROJECTILES"].size() / EP_ROW_BYTES),
				int(state_dict["ITEMS"].size() / ITEM_ROW_STRIDE), int(state_dict["CONSUMABLES"].size() / CS_ROW_STRIDE),
				state_dict["NEUTRALS"].size(), state_dict["STRUCTURES"].size(),
				state_dict["PETS"].size(), int(state_dict["BIRTHS"].size() / BIRTH_ROW_STRIDE)])


func _apply_ghost_modulate() -> void:
	var ghost_color = Color(0.5, 0.8, 1.0, 0.35)
	for entity in client_enemies.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
			if entity is CollisionObject2D:
				entity.collision_layer = 0
				entity.collision_mask = 0
	for entity in client_enemy_projectiles.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
			if entity is CollisionObject2D:
				entity.collision_layer = 0
				entity.collision_mask = 0
	for entity in client_player_projectiles.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
			if entity is CollisionObject2D:
				entity.collision_layer = 0
				entity.collision_mask = 0
	for entity in client_items.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
			entity.set_physics_process(false)
	for entity in client_consumables.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
			entity.set_physics_process(false)
	for entity in client_neutrals.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
	for entity in client_structures.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
	for entity in _ghost_births.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color
	for entity in client_pets.values():
		if is_instance_valid(entity):
			entity.modulate = ghost_color


func _update_ghost_players(players_array: Array) -> void:
	for player_index in players_array.size():
		var player_dict = players_array[player_index]
		var player = _players[player_index]

		if not is_instance_valid(player) or player.dead:
			if _ghost_players.has(player_index):
				if is_instance_valid(_ghost_players[player_index]):
					_ghost_players[player_index].queue_free()
				_ghost_players.erase(player_index)
			continue

		var ghost
		if _ghost_players.has(player_index) and is_instance_valid(_ghost_players[player_index]):
			ghost = _ghost_players[player_index]
		else:
			ghost = Node2D.new()
			var ghost_sprite = _make_ghost_player_sprite(player)
			ghost_sprite.name = "GhostSprite"
			ghost.add_child(ghost_sprite)
			_entities_container.add_child(ghost)
			_ghost_players[player_index] = ghost

		ghost.position = Vector2(
			player_dict[EntityState.ENTITY_STATE_X_POS],
			player_dict[EntityState.ENTITY_STATE_Y_POS]
		)
		var ghost_sprite = ghost.get_node_or_null("GhostSprite")
		if ghost_sprite:
			ghost_sprite.scale.x = player_dict[EntityState.ENTITY_STATE_SPRITE_SCALE]
		ghost.modulate = Color(0.5, 0.8, 1.0, 0.35)


func _make_ghost_player_sprite(player) -> Node2D:
	var src = player.sprite
	if src is AnimatedSprite:
		var frames = src.frames
		if frames and frames.has_animation(src.animation):
			var texture = frames.get_frame(src.animation, src.frame)
			if texture:
				var s = Sprite.new()
				s.texture = texture
				return s
	elif src is Sprite:
		var s = Sprite.new()
		s.texture = src.texture
		return s
	var fallback = Polygon2D.new()
	var pts = PoolVector2Array()
	for i in 12:
		var a = i * TAU / 12.0
		pts.append(Vector2(cos(a) * 16.0, sin(a) * 16.0))
	fallback.set_polygon(pts)
	return fallback


func _update_ghost_births(rows) -> void:
	var current_births = {}
	if rows == null:
		rows = PoolIntArray()
	for k in int(rows.size() / BIRTH_ROW_STRIDE):
		var base = k * BIRTH_ROW_STRIDE
		var network_id = rows[base]
		current_births[network_id] = true
		if not _ghost_births.has(network_id):
			var birth = ENTITY_BIRTH_SCENE.instance()
			birth.network_id = network_id
			_entities_container.add_child(birth)
			_ghost_births[network_id] = birth
			birth.start(rows[base + 3], ENTITY_BIRTH_SCENE,
				Vector2(rows[base + 1], rows[base + 2]))
			birth._collision_shape.set_deferred("disabled", true)

	var to_remove = []
	for network_id in _ghost_births:
		if not current_births.has(network_id):
			to_remove.push_back(network_id)
	for network_id in to_remove:
		if is_instance_valid(_ghost_births[network_id]):
			_ghost_births[network_id].queue_free()
		_ghost_births.erase(network_id)


func multiplayer_ready():
	_wave_timer.stop()
	waiting_to_start_round = true


func _client_status_received(client_data : Dictionary, player_index : int) -> void:
	if waiting_to_start_round:
		if client_data["CURRENT_SCENE"] == "Main":
			player_in_scene[player_index] = true


func _host_starts_round() -> void:
	waiting_to_start_round = false
	_wave_timer.start()
	_wave_timer.paused = false


func _on_WaveTimer_timeout() -> void:
	if in_multiplayer_game:
		if steam_connection.is_host():
			._on_WaveTimer_timeout()
			# Base wave-end just applied per-player harvest gold and folded leftover materials into
			# bonus_gold (manage_harvesting / clean_up_room) -- both host-authoritative and never
			# recomputed on the client. Gold rides the UNRELIABLE snapshot, so at the wave boundary
			# (few sends before the shop scene loads) a dropped packet can leave the client showing
			# stale pre-harvest gold until the shop's gold sync arrives (the 38/59-vs-30/30 symptom).
			# Push one authoritative snapshot now so the post-harvest totals land promptly.
			# UNVALIDATED (2026-09-04): confirm on two machines before shipping.
			_send_game_state()
			if ENABLE_DEBUG:
				var host_gold := []
				for pi in RunData.get_player_count():
					host_gold.push_back(RunData.players_data[pi].gold)
				print("BTGOLD host wave=%d post-harvest gold=%s bonus=%d" % [RunData.current_wave, str(host_gold), RunData.bonus_gold])
			return
		else:
			_ui_dim_screen.dim()
			_wave_cleared_label.hide()
			_wave_timer_label.hide()
			_hud.hide()

			_coop_upgrades_ui.propagate_call("set_process_input", [true])
			DebugService.log_data("_on_EndWaveTimer_timeout")
			SoundManager.clear_queue()
			SoundManager2D.clear_queue()
			InputService.set_gamepad_echo_processing(true)
			_cleaning_up = true

			for player in _players:
				if is_instance_valid(player):
					player._can_move = false
					player.set_physics_process(false)

			if ENABLE_DEBUG:
				var cli_gold := []
				for pi in RunData.get_player_count():
					cli_gold.push_back(RunData.players_data[pi].gold)
				print("BTGOLD client wave=%d at-wave-end gold=%s bonus=%d seq=%d" % [RunData.current_wave, str(cli_gold), RunData.bonus_gold, _last_state_seq])
	else:
		._on_WaveTimer_timeout()


func _on_EndWaveTimer_timeout()->void :
	if in_multiplayer_game:
		if _run_ended_by_host:
			# Client mirror of the host's run end (see _host_run_ended). The host has
			# left the lobby by now; show the same end-run screen it is showing.
			_end_wave_timer_timedout = true
			_wave_cleared_label.hide()
			_wave_timer_label.hide()
			_hud.hide()
			if _is_run_won:
				RunData.apply_run_won()
			steam_connection.leave_game_lobby()
			var _error = get_tree().change_scene(RunData.get_end_run_scene_path())
		elif steam_connection.is_host():
			if _is_run_lost or RunData.is_last_wave() or _is_run_won:
				# Vanilla offers "Retry wave" once every player died; in multiplayer the
				# lobby is gone by now and clients can't follow a retry, so the run ends
				# for everyone (clients were told by send_run_ended in clean_up_room).
				_is_wave_failed = false
				steam_connection.leave_game_lobby()
			._on_EndWaveTimer_timeout()
	else:
		._on_EndWaveTimer_timeout()


func _on_player_died(p_player : Player, _args : Entity.DieArgs) -> void:
	if not in_multiplayer_game:
		._on_player_died(p_player, _args)
		return
	if steam_connection.is_host():
		# One-shot delta -> reliable events channel (BATCHED_PLAYER_DEATHS).
		_batched_player_deaths.push_back(p_player.player_index)
		._on_player_died(p_player, _args)
		return
	# Client: the host decides the run's outcome (host_run_ended). Mirror only the
	# cosmetic part of the vanilla handler (life bars, highlight, sound); its tail
	# (clean_up_room, ProgressData run-state reset, killed-by stats) is host-only.
	var player_ui = _players_ui[p_player.player_index]
	player_ui.player_life_bar.hide()
	if RunData.is_coop_run:
		player_ui.life_bar.set_value(100)
		player_ui.life_bar.progress_color = Color.white
		player_ui.life_bar.hide_with_flash()
	p_player.highlight.hide()
	SoundManager.play(Utils.get_rand_element(run_lost_sounds), - 5, 0, true)


func clean_up_room() -> void:
	.clean_up_room()
	# _set_run_states just decided the run's fate (every player dead, or the last wave
	# cleared). Tell clients NOW -- the host leaves the lobby when its end-wave timer
	# fires, and a client must hear "run over" before it hears "host left".
	if in_multiplayer_game and steam_connection.is_host() and (_is_run_lost or _is_run_won):
		steam_connection.send_run_ended(_is_run_won, _end_wave_timer.wait_time)


func _host_run_ended(won : bool, delay : float) -> void:
	if steam_connection.is_host() or _run_ended_by_host:
		return
	_run_ended_by_host = true
	_is_run_won = won
	_is_run_lost = not won
	RunData.run_won = won
	_wave_timer.stop()
	_ui_dim_screen.dim()
	for player in _players:
		if is_instance_valid(player):
			player._can_move = false
	_wave_cleared_label.start(false, _is_run_lost, _is_run_won)
	_end_wave_timer.wait_time = max(delay, 0.5)
	_end_wave_timer.start()


func _host_births_array() -> PoolIntArray:
	var rows := PoolIntArray()
	for birth in _births_container.get_children():
		if birth._collision_shape.disabled:
			continue
		rows.push_back(birth.network_id)
		rows.push_back(int(round(birth.global_position.x)))
		rows.push_back(int(round(birth.global_position.y)))
		rows.push_back(birth.type)
	return rows


func _update_births(rows) -> void:
	var current_births : Dictionary = {}
	if rows == null:
		rows = PoolIntArray()

	for k in int(rows.size() / BIRTH_ROW_STRIDE):
		var base = k * BIRTH_ROW_STRIDE
		var network_id = rows[base]
		current_births[network_id] = true

		if not client_births.has(network_id):
			var birth = ENTITY_BIRTH_SCENE.instance()
			birth.network_id = network_id
			_births_container.add_child(birth)
			client_births[network_id] = birth
			birth.start(rows[base + 3], ENTITY_BIRTH_SCENE, Vector2(rows[base + 1], rows[base + 2]))

	for network_id in client_births:
		var old_birth = client_births[network_id]
		if not current_births.has(network_id):
			client_births.erase(network_id)
			old_birth.queue_free()


func _host_player_projectiles_array() -> Array:
	var player_projectiles_array = []

	for child in _player_projectiles.get_children():
		if child is PlayerProjectile and child._hitbox.active:
			var projectile_dict = {}
			var network_id
			if server_player_projectile_ids.has(child):
				network_id = server_player_projectile_ids[child]
			else:
				network_id = brotatogether_options.current_network_id
				brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
				server_player_projectile_ids[child] = network_id

			projectile_dict["NETWORK_ID"] = network_id
			projectile_dict["X_POS"] = child.position.x
			projectile_dict["Y_POS"] = child.position.y
			projectile_dict["ROTATION"] = child.rotation
			projectile_dict["FILENAME"] = child.filename
			player_projectiles_array.push_back(projectile_dict)
	return player_projectiles_array


func _update_player_projectiles(player_projectiles_array : Array) -> void:
	var current_projectiles = {}

	for player_projectile_dict in player_projectiles_array:
		var network_id = player_projectile_dict["NETWORK_ID"]
		current_projectiles[network_id] = true

		if client_player_projectiles.has(network_id):
			var projectile = client_player_projectiles[network_id]

			if is_instance_valid(projectile):
				projectile.position.x = player_projectile_dict["X_POS"]
				projectile.position.y = player_projectile_dict["Y_POS"]
				projectile.rotation = player_projectile_dict["ROTATION"]
		else:
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_player_projectile", player_projectile_dict)

	for network_id in client_player_projectiles:
		if not current_projectiles.has(network_id):
			var proj = client_player_projectiles[network_id]
			if is_instance_valid(proj) and proj.get_parent() != null:
				proj.queue_free()
			client_player_projectiles.erase(network_id)


func _spawn_player_projectile(player_projectile_dict : Dictionary) -> void:
	if not is_instance_valid(_player_projectiles):
		return

	var network_id = player_projectile_dict["NETWORK_ID"]
	var projectile = load(player_projectile_dict["FILENAME"]).instance()

	client_pending_ids.erase(network_id)
	client_player_projectiles[network_id] = projectile

	projectile.position.x = player_projectile_dict["X_POS"]
	projectile.position.y = player_projectile_dict["Y_POS"]
	projectile.spawn_position.x = player_projectile_dict["X_POS"]
	projectile.spawn_position.y = player_projectile_dict["Y_POS"]

	# The projectile will despawn if max_range is too low, the host will
	# erase the projectile at the right time so set max range very high to
	# disable client-side logic in this regard.
	projectile._max_range = 9999

	projectile.rotation = player_projectile_dict["ROTATION"]

	projectile.set_meta("pool_id", Keys.generate_hash(player_projectile_dict["FILENAME"]))
	_player_projectiles.add_child(projectile)

	projectile._hitbox.active = false
	projectile.set_physics_process(false)
	projectile.show()


func _host_items_array() -> PoolIntArray:
	var rows := PoolIntArray()
	for item in _active_golds:
		if not is_instance_valid(item):
			continue
		rows.push_back(item.network_id)
		rows.push_back(int(round(item.global_position.x)))
		rows.push_back(int(round(item.global_position.y)))
		rows.push_back(int(round(item.scale.x * 100.0)))
		rows.push_back(int(round(item.scale.y * 100.0)))
	return rows


func _update_items(rows) -> void:
	var current_items = {}
	if rows == null:
		rows = PoolIntArray()

	for k in int(rows.size() / ITEM_ROW_STRIDE):
		var base = k * ITEM_ROW_STRIDE
		var network_id = rows[base]
		current_items[network_id] = true
		if client_items.has(network_id):
			var item = client_items[network_id]
			item.global_position.x = rows[base + 1]
			item.global_position.y = rows[base + 2]
		else:
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_item", {
					"NETWORK_ID": network_id,
					"X_POS": rows[base + 1], "Y_POS": rows[base + 2],
					"X_SCALE": rows[base + 3] / 100.0, "Y_SCALE": rows[base + 4] / 100.0,
				})

	for network_id in client_items:
		if not current_items.has(network_id):
			client_items[network_id].queue_free()
			client_items.erase(network_id)


func _spawn_item(item_dict : Dictionary) -> void:
	var network_id = item_dict["NETWORK_ID"]
	client_pending_ids.erase(network_id)
	var gold = gold_scene.instance()
	gold.set_texture(gold_sprites[Utils.randi() % 11])
	gold.scale.x = item_dict["X_SCALE"]
	gold.scale.y = item_dict["Y_SCALE"]
	_materials_container.add_child(gold)
	if not brotatogether_options.is_solo_test:
		_active_golds.push_back(gold)
	client_items[network_id] = gold
	gold.call_deferred("show")


func _host_consumables_array() -> PoolIntArray:
	var rows := PoolIntArray()
	var files := []
	var file_index := {}
	for consumable in _consumables_container.get_children():
		if consumable.visible and consumable.consumable_data != null:
			var path = consumable.consumable_data.icon.load_path
			if not file_index.has(path):
				file_index[path] = files.size()
				files.push_back(path)
			rows.push_back(consumable.network_id)
			rows.push_back(int(round(consumable.global_position.x)))
			rows.push_back(int(round(consumable.global_position.y)))
			rows.push_back(file_index[path])
	_cs_files_out = files
	return rows


func _update_consumables(rows, files : Array = []) -> void:
	var current_consumables = {}
	if rows == null:
		rows = PoolIntArray()

	for k in int(rows.size() / CS_ROW_STRIDE):
		var base = k * CS_ROW_STRIDE
		var network_id = rows[base]
		current_consumables[network_id] = true
		if client_consumables.has(network_id):
			var consumable = client_consumables[network_id]
			consumable.global_position.x = rows[base + 1]
			consumable.global_position.y = rows[base + 2]
		else:
			var file_idx = rows[base + 3]
			if file_idx < 0 or file_idx >= files.size():
				continue   # table missing this tick; a later snapshot carries it
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_consumable", {
					"NETWORK_ID": network_id, "X_POS": rows[base + 1], "Y_POS": rows[base + 2],
					"LOAD_PATH": files[file_idx],
				})

	for network_id in client_consumables:
		if not current_consumables.has(network_id):
			client_consumables[network_id].queue_free()
			client_consumables.erase(network_id)


func _spawn_consumable(consumable_dict : Dictionary) -> void:
	client_pending_ids.erase(consumable_dict["NETWORK_ID"])
	var consumable = get_node_from_pool(_consumable_pool_id, _consumables_container)
	if consumable == null:
		consumable = consumable_scene.instance()
		_consumables_container.add_child(consumable)

	var file_path = consumable_dict["LOAD_PATH"]
	consumable.set_texture(load(file_path))
	consumable.global_position.x = consumable_dict["X_POS"]
	consumable.global_position.y = consumable_dict["Y_POS"]
	consumable.call_deferred("show")
	client_consumables[consumable_dict["NETWORK_ID"]] = consumable


func _host_neutrals_array() -> Array:
	var neutrals_array = []

	for neutral in _entity_spawner.neutrals:
		var neutral_dict = {}
		neutral_dict["NETWORK_ID"] = neutral.network_id
		neutral_dict["X_POS"] = neutral.global_position.x
		neutral_dict["Y_POS"] = neutral.global_position.y
		neutrals_array.push_back(neutral_dict)

	return neutrals_array


func _update_neutrals(neutrals_array : Array) -> void:
	var current_neutrals = {}

	for neutral_dict in neutrals_array:
		var network_id = neutral_dict["NETWORK_ID"]
		current_neutrals[network_id] = true
		if client_neutrals.has(network_id):
			pass
		else:
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_neutral", neutral_dict)

	for network_id in client_neutrals:
		if not network_id in current_neutrals:
			client_neutrals[network_id].queue_free()
			client_neutrals.erase(network_id)


func _spawn_neutral(neutral_dict : Dictionary) -> void:
	client_pending_ids.erase(neutral_dict["NETWORK_ID"])
	var neutral = TREE_SCENE.instance()

	neutral.collision_layer = 0
	neutral.collision_mask = 0
	neutral.mode = RigidBody2D.MODE_STATIC
	var hurtbox = neutral.get_node_or_null("Hurtbox")
	if hurtbox:
		hurtbox.collision_layer = 0
		hurtbox.collision_mask = 0

	client_neutrals[neutral_dict["NETWORK_ID"]] = neutral

	Utils.get_scene_node().add_child(neutral)
	neutral.global_position = Vector2(neutral_dict["X_POS"], neutral_dict["Y_POS"])

	if hurtbox:
		hurtbox.monitoring = false
		hurtbox.monitorable = false
		for shape in hurtbox.get_children():
			if shape is CollisionShape2D or shape is CollisionPolygon2D:
				shape.set_deferred("disabled", true)


func _host_structures_array() -> Array:
	var structures_array = []

	for structure in _entity_spawner.structures:
		var structure_dict = {}

		structure_dict["NETWORK_ID"] = structure.network_id
		structure_dict["FILENAME"] = structure.filename
		structure_dict["X_POS"] = structure.position.x
		structure_dict["Y_POS"] = structure.position.y
		structures_array.push_back(structure_dict)

	return structures_array


func _update_structures(structures_array : Array) -> void:
	var current_structures = {}

	for structure_dict in structures_array:
		var network_id = structure_dict["NETWORK_ID"]
		current_structures[network_id] = true
		if client_structures.has(network_id):
			pass
		else:
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_structure", structure_dict)

	for network_id in client_structures:
		if not network_id in current_structures:
			client_structures[network_id].queue_free()
			client_structures.erase(network_id)


func _spawn_structure(structure_dict : Dictionary) -> void:
	client_pending_ids.erase(structure_dict["NETWORK_ID"])
	var filename = structure_dict["FILENAME"]
	var structure = load(filename).instance()

	structure.position.x = structure_dict["X_POS"]
	structure.position.y = structure_dict["Y_POS"]

	structure.stats = CLIENT_TURRET_STATS

	client_structures[structure_dict["NETWORK_ID"]] = structure

	Utils.get_scene_node().add_child(structure)
	structure.set_physics_process(false)
	structure.set_process(false)


func _host_pets_array() -> Array:
	var pets_array = []
	for pet in _entity_spawner.pets:
		if not is_instance_valid(pet) or pet.dead:
			continue
		var pet_dict = {}
		pet_dict["NETWORK_ID"] = pet.network_id
		pet_dict["FILENAME"] = pet.filename
		pet_dict["X_POS"] = pet.position.x
		pet_dict["Y_POS"] = pet.position.y
		pet_dict["MOVE_X"] = pet._current_movement.x
		pet_dict["MOVE_Y"] = pet._current_movement.y
		pet_dict["MODULATE_R"] = pet.sprite.self_modulate.r8
		pet_dict["MODULATE_G"] = pet.sprite.self_modulate.g8
		pet_dict["MODULATE_B"] = pet.sprite.self_modulate.b8
		pet_dict["MODULATE_A"] = pet.sprite.self_modulate.a8
		pets_array.push_back(pet_dict)
	return pets_array


func _update_pets(pets_array: Array) -> void:
	var current_pets = {}
	for pet_dict in pets_array:
		var network_id = pet_dict["NETWORK_ID"]
		current_pets[network_id] = true
		if client_pets.has(network_id):
			var pet = client_pets[network_id]
			if is_instance_valid(pet):
				pet.call_deferred("update_client_enemy", pet_dict)
		else:
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_pet", pet_dict)
	var to_remove = []
	for network_id in client_pets:
		if not current_pets.has(network_id):
			to_remove.push_back(network_id)
	for network_id in to_remove:
		if is_instance_valid(client_pets[network_id]):
			client_pets[network_id].queue_free()
		client_pets.erase(network_id)


func _spawn_pet(pet_dict: Dictionary) -> void:
	if not is_instance_valid(_entities_container):
		return

	var network_id = pet_dict["NETWORK_ID"]
	var pet = load(pet_dict["FILENAME"]).instance()
	pet.position = Vector2(pet_dict["X_POS"], pet_dict["Y_POS"])

	var movement_behavior = pet.get_node_or_null("MovementBehavior")
	if movement_behavior:
		pet.remove_child(movement_behavior)
		var client_mb = ClientMovementBehavior.new()
		client_mb.set_name("MovementBehavior")
		pet.add_child(client_mb, true)
		pet._current_movement_behavior = client_mb

	var target_behavior = pet.get_node_or_null("TargetBehavior")
	if target_behavior:
		pet.remove_child(target_behavior)
		var client_tb = ClientTargetBehavior.new()
		client_tb.set_name("TargetBehavior")
		pet.add_child(client_tb, true)
		pet._current_target_behavior = client_tb

	var attack_behavior = pet.get_node_or_null("AttackBehavior")
	if attack_behavior:
		pet.remove_child(attack_behavior)
		var client_ab = ClientAttackBehavior.new()
		client_ab.set_name("AttackBehavior")
		pet.add_child(client_ab, true)
		pet._current_attack_behavior = client_ab

	for child in pet.get_children():
		if child is CollisionObject2D:
			child.collision_layer = 0
			child.collision_mask = 0

	client_pets[network_id] = pet
	client_pending_ids.erase(network_id)
	_entities_container.add_child(pet)
	pet.set_physics_process(false)
	pet.set_process(false)
	for child in pet.get_children():
		if child is Area2D:
			child.monitoring = false
			child.monitorable = false


func _host_enemy_projectiles_array() -> PoolByteArray:
	var buf := StreamPeerBuffer.new()
	var files := []
	var file_index := {}

	if is_instance_valid(_enemy_projectiles):
		for enemy_projectile in _enemy_projectiles.get_children():
			if enemy_projectile is Projectile and enemy_projectile._hitbox.active:
				var network_id
				if server_enemy_projectile_ids.has(enemy_projectile):
					network_id = server_enemy_projectile_ids[enemy_projectile]
				else:
					network_id = brotatogether_options.current_network_id
					brotatogether_options.current_network_id = brotatogether_options.current_network_id + 1
					server_enemy_projectile_ids[enemy_projectile] = network_id

				var path = enemy_projectile.filename
				if not file_index.has(path):
					file_index[path] = files.size()
					files.push_back(path)
				buf.put_u32(network_id)
				buf.put_16(int(round(enemy_projectile.global_position.x)))
				buf.put_16(int(round(enemy_projectile.global_position.y)))
				buf.put_16(int(round(enemy_projectile.rotation * 1000.0)))
				buf.put_u8(file_index[path])
	_ep_files_out = files
	return buf.data_array


func _update_enemy_projectiles(rows, files : Array = []) -> void:
	var current_enemy_projectiles = {}
	if rows == null:
		rows = PoolByteArray()
	var buf := StreamPeerBuffer.new()
	buf.data_array = rows
	for _k in int(rows.size() / EP_ROW_BYTES):
		var network_id = buf.get_u32()
		var px = buf.get_16()
		var py = buf.get_16()
		var rot = buf.get_16() / 1000.0
		var file_idx = buf.get_u8()
		current_enemy_projectiles[network_id] = true

		if client_enemy_projectiles.has(network_id):
			var enemy_projectile = client_enemy_projectiles[network_id]

			if not is_instance_valid(enemy_projectile):
				continue

			enemy_projectile.position.x = px
			enemy_projectile.position.y = py
			enemy_projectile.rotation = rot
		else:
			if file_idx >= files.size():
				continue   # table missing this tick; a later snapshot carries it
			var enemy_projectile_dict = {
				ProjectileState.PROJECTILE_STATE_NETWORK_ID: network_id,
				ProjectileState.PROJECTILE_STATE_X_POS: px,
				ProjectileState.PROJECTILE_STATE_Y_POS: py,
				ProjectileState.PROJECTILE_STATE_ROTATION: rot,
				ProjectileState.PROJECTILE_STATE_FILENAME: files[file_idx],
			}
			# Register in client_pending_ids BEFORE deferring: multiple snapshots can be
			# applied in ONE frame (backlog drains), and an unguarded defer queued a spawn per
			# apply -- every duplicate node but the last was orphaned from the dict, so the
			# sweep could never free it (the 'projectiles stay on screen' bug).
			if not client_pending_ids.has(network_id):
				client_pending_ids[network_id] = true
				call_deferred("_spawn_enemy_projectile", enemy_projectile_dict)

	for network_id in client_enemy_projectiles:
		if not current_enemy_projectiles.has(network_id):
			var proj = client_enemy_projectiles[network_id]
			if is_instance_valid(proj) and proj.get_parent() != null:
				proj.queue_free()
			client_enemy_projectiles.erase(network_id)


func _spawn_enemy_projectile(enemy_projectile_dict : Dictionary) -> void:
	if not is_instance_valid(_enemy_projectiles):
		return

	var network_id = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_NETWORK_ID]
	client_pending_ids.erase(network_id)
	var enemy_projectile = load(enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_FILENAME]).instance()
	client_enemy_projectiles[network_id] = enemy_projectile

	enemy_projectile.position.x = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_X_POS]
	enemy_projectile.position.y = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_Y_POS]

	enemy_projectile.rotation = enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_ROTATION]

	enemy_projectile.set_meta("pool_id", Keys.generate_hash(enemy_projectile_dict[ProjectileState.PROJECTILE_STATE_FILENAME]))
	_enemy_projectiles.add_child(enemy_projectile)

	enemy_projectile._hitbox.active = false
	enemy_projectile.set_physics_process(false)
	_enemy_projectiles.show()


func _update_batched_hit_particles(batched_hit_effects_array : Array) -> void:
	for hit_effect_dict in batched_hit_effects_array:
		var effect_pos = Vector2(hit_effect_dict["X_POS"], hit_effect_dict["Y_POS"])
		var direction = Vector2(hit_effect_dict["X_DIR"], hit_effect_dict["Y_DIR"])
		var effect_scale = hit_effect_dict["SCALE"]
		_effects_manager.play_hit_effect(effect_pos, direction, effect_scale)


func _update_batched_hit_effects(batched_hit_particles_array : Array) -> void:
	for hit_particles_dict in batched_hit_particles_array:
		var effect_pos = Vector2(hit_particles_dict["X_POS"], hit_particles_dict["Y_POS"])
		var effect_scale = hit_particles_dict["SCALE"]
		_effects_manager.play_hit_particles(effect_pos, Vector2.ZERO, effect_scale)


func _update_batched_floating_text(batched_floating_text_array : Array) -> void:
	for floating_text_dict in batched_floating_text_array:
		var value = floating_text_dict["VALUE"]
		var text_pos = Vector2(floating_text_dict["X_POS"], floating_text_dict["Y_POS"])
		var color = Color8(floating_text_dict["R_COLOR"], floating_text_dict["G_COLOR"], floating_text_dict["B_COLOR"] ,floating_text_dict["A_COLOR"])
		var duration = floating_text_dict["DURATION"]
		var always = floating_text_dict.get("ALWAYS", false)
		_floating_text_manager.call_deferred("display", value, text_pos, color, null, duration, always)


func _host_menu_status() -> Dictionary:
	var menu_dict = {}

	var showing_upgrade_menus : bool = _coop_upgrades_ui.visible
	menu_dict["MENU_VISIBLE"] = showing_upgrade_menus

	if showing_upgrade_menus:
		var player_menus = []
		for player_index in RunData.get_player_count():
			var player_menu_dict = {}
#			_coop_upgrades_ui
			var player_container = _coop_upgrades_ui._get_player_container(player_index)

			var showing_player_items_container = player_container._items_container.visible
			var showing_player_upgrades_container = player_container._upgrades_container.visible
			player_menu_dict["SHOWING_ITEMS"] = showing_player_items_container
			player_menu_dict["SHOWING_UPGRADES"] = showing_player_upgrades_container
			player_menu_dict["PLAYER_FINISHED"] = player_container._checkmark_group.visible

			if showing_player_upgrades_container:
				var upgrade_options = []
				for upgrade in player_container._old_upgrades:
					var upgrade_data = {}
					upgrade_data["UPGRADE_ID"] = upgrade.my_id
					upgrade_options.push_back(upgrade_data)
				player_menu_dict["UPGRADE_OPTIONS"] = upgrade_options
				player_menu_dict["REROLL_PRICE"] = player_container._reroll_price
			elif showing_player_items_container:
				player_menu_dict["ITEM_ID"] = player_container._item_data.my_id

			player_menu_dict["FOCUS"] = _string_for_menu_focus(player_container)
			player_menus.push_back(player_menu_dict)
		menu_dict["PLAYER_MENUS"] = player_menus

	return menu_dict


func _update_menu(menu_dict : Dictionary) -> void:
	var showing_upgrade_menus : bool = menu_dict["MENU_VISIBLE"]

	if showing_upgrade_menus and not _coop_upgrades_ui.visible:
		_coop_upgrades_ui.show()
	elif not showing_upgrade_menus:
		if _coop_upgrades_ui.visible:
			_coop_upgrades_ui.hide()
		return

	var player_menus = menu_dict["PLAYER_MENUS"]
	for player_index in RunData.get_player_count():
		var player_container = _coop_upgrades_ui._get_player_container(player_index)
		var player_menu_dict = player_menus[player_index]

		var showing_player_items_container = player_menu_dict["SHOWING_ITEMS"]
		var showing_player_upgrades_container = player_menu_dict["SHOWING_UPGRADES"]
		var player_finished = player_menu_dict["PLAYER_FINISHED"]
		if showing_player_upgrades_container:
			var upgrade_options : Array = player_menu_dict["UPGRADE_OPTIONS"]
			var should_update_upgrades : bool = false
			for i in upgrade_options.size():
				if i >= player_container._old_upgrades.size():
					should_update_upgrades = true
				else:
					var upgrade_data = upgrade_options[i]
					if upgrade_data["UPGRADE_ID"] != player_container._old_upgrades[i].my_id:
						should_update_upgrades = true
			if should_update_upgrades:
				var upgrades = []
				for i in upgrade_options.size():
					var upgrade_data = upgrade_options[i]
					for dupe_candidate in ItemService.upgrades:
						if dupe_candidate.my_id == upgrade_data["UPGRADE_ID"]:
							upgrades.push_back(dupe_candidate.duplicate())
				player_container._old_upgrades = upgrades
				var upgrade_uis = player_container._get_upgrade_uis()
				for i in upgrade_options.size():
					var upgrade_ui = upgrade_uis[i]
					upgrade_ui.visible = i < upgrades.size()
					if upgrade_ui.visible:
						upgrade_ui.set_upgrade(upgrades[i], player_index)
				var reroll_price = player_menu_dict["REROLL_PRICE"]
				player_container._reroll_button.init(reroll_price, player_index)
				player_container._update_gold_label()

				player_container._items_container.hide()
				player_container._upgrades_container.show()
				player_container.focus()

			player_container._items_container.hide()
			player_container._upgrades_container.show()
		elif showing_player_items_container:
			var item_id = player_menu_dict["ITEM_ID"]

			if player_container._item_data == null or item_id != player_container._item_data.my_id:
				var item_data
				for item_candidate in ItemService.items:
					if item_id == item_candidate.my_id:
						item_data = item_candidate.duplicate()
						break
				for item_candidate in ItemService.weapons:
					if item_id == item_candidate.my_id:
						item_data = item_candidate.duplicate()
						break
				player_container.show_item(item_data)
				player_container.focus()

			player_container._items_container.show()
			player_container._upgrades_container.hide()
		if player_index != my_player_index:
			_focus_for_string(player_container, player_menu_dict["FOCUS"])
		if player_finished:
			player_container._items_container.hide()
			player_container._upgrades_container.hide()
			player_container._checkmark_group.show()


func _update_client_focus(data : Dictionary, player_index : int) -> void:
	if steam_connection.is_host() and player_index != my_player_index:
		var player_container = _coop_upgrades_ui._get_player_container(player_index)
		_focus_for_string(player_container, data["FOCUS"])


func _string_for_menu_focus(player_container : CoopUpgradesUIPlayerContainer) -> String:
	var focus_emulator = player_container.focus_emulator
	if not focus_emulator.focused_control:
		return ""

	var focused_control = focus_emulator.focused_control
	if focused_control == player_container._take_button:
		return "take"
	elif focused_control == player_container._discard_button:
		return "discard"
	elif focused_control == player_container._upgrade_ui_1.button:
		return "upgrade_1"
	elif focused_control == player_container._upgrade_ui_2.button:
		return "upgrade_2"
	elif focused_control == player_container._upgrade_ui_3.button:
		return "upgrade_3"
	elif focused_control == player_container._upgrade_ui_4.button:
		return "upgrade_4"
	elif focused_control == player_container._reroll_button:
		return "reroll"

	return ""


func _focus_for_string(player_container : CoopUpgradesUIPlayerContainer, focus_key: String) -> void:
	var requested_focused_control = null

	if focus_key == "take":
		requested_focused_control = player_container._take_button
	elif focus_key == "discard":
		requested_focused_control = player_container._discard_button
	elif focus_key == "upgrade_1":
		requested_focused_control = player_container._upgrade_ui_1.button
	elif focus_key == "upgrade_2":
		requested_focused_control = player_container._upgrade_ui_2.button
	elif focus_key == "upgrade_3":
		requested_focused_control = player_container._upgrade_ui_3.button
	elif focus_key == "upgrade_4":
		requested_focused_control = player_container._upgrade_ui_4.button
	elif focus_key == "reroll":
		requested_focused_control = player_container._reroll_button

	if requested_focused_control:
		player_container.focus_emulator.focused_control = requested_focused_control


func _client_reroll_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_RerollButton_pressed()


func _client_choose_upgrade_button_pressed(upgrade_dict : Dictionary, player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	for upgrade_candidate in ItemService.upgrades:
		if upgrade_candidate.my_id == upgrade_dict["UPGRADE_ID"]:
			player_container._on_choose_button_pressed(upgrade_candidate.duplicate())


func _client_take_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_TakeButton_pressed()


func _client_discard_button_pressed(player_index : int) -> void:
	var player_container = _coop_upgrades_ui._get_player_container(player_index)
	player_container._on_DiscardButton_pressed()


func _host_entered_shop() -> void:
	_change_scene(RunData.get_shop_scene_path())


func _check_for_pause() -> void:
	if not in_multiplayer_game:
		._check_for_pause()


func connect_visual_effects(unit: Unit)->void :
	.connect_visual_effects(unit)

	# Players are hooked from vanilla _ready (_entity_spawner.init -> players_spawned), which
	# runs BEFORE this extension's _ready sets in_multiplayer_game (Godot calls _ready
	# parent-first), so the cached flag read false for the players and their hits never
	# produced floating text on clients (enemies spawn later and were fine). Read the
	# autoloads directly instead of the cached vars.
	var opts = get_node_or_null("/root/BrotogetherOptions")
	var sc = get_node_or_null("/root/SteamConnection")
	if opts != null and sc != null and opts.in_multiplayer_game and sc.is_host():
		if not unit.is_connected("took_damage", self, "_on_unit_took_damage"):
			var _error_floating_text = unit.connect("took_damage", self, "_on_unit_took_damage")


func _on_unit_took_damage(unit: Unit, value: int, _knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, _args: TakeDamageArgs, _hit_type: int, _is_one_shot: bool)->void :
	var color: Color = Color.white
	var text = str(value)

	if unit is Player:
		if value > 0:
			color = Color.red
			text = "-" + text
		elif is_dodge:
			text = "DODGE"
		elif is_protected:
			text = "NULLIFIED"
	elif is_crit:
		color = Color.yellow
	elif armor_did_something:
		color = Color.gray

	var text_dict = {}
	var text_pos = unit.global_position
	text_dict["X_POS"] = text_pos.x
	text_dict["Y_POS"] = text_pos.y
	text_dict["R_COLOR"] = color.r8
	text_dict["G_COLOR"] = color.g8
	text_dict["B_COLOR"] = color.b8
	text_dict["A_COLOR"] = color.a8
	text_dict["VALUE"] = text
	text_dict["DURATION"] = _floating_text_manager.duration
	text_dict["ALWAYS"] = unit is Player

	brotatogether_options.batched_floating_text.push_back(text_dict)


func spawn_explosion(explosion_dict : Dictionary) -> void:
	var instance = explosion_scene.instance()
	instance.is_ghost_explosion = true
	call_deferred("add_explosion", instance)

	var explosion_scale = Vector2(explosion_dict["SCALE"],explosion_dict["SCALE"])
	instance.set_deferred("global_position", Vector2(explosion_dict["X_POS"], explosion_dict["Y_POS"]))
	instance.set_deferred("scale", explosion_scale)
	instance.call_deferred("start_explosion")


func add_node_to_pool(node: Node, id) -> void:
	if node.has_meta("btg_ghost_enemy"):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
		return
	# id may be null for client-spawned projectiles that have no pool_id meta
	if id != null and _pool.has(id):
		.add_node_to_pool(node, id)
	elif node.get_parent() != null:
		node.get_parent().remove_child(node)


# A member left mid-run. The host treats it as a death (the authoritative path: propagates via
# BATCHED_PLAYER_DEATHS and drives the all-dead run-end check); its slot is never re-awaited.
# Every forced player death passes FRESH DieArgs: a bare die() falls back to the shared
# Utils.default_die_args, whose `from` can still point at a freed killer, and vanilla
# _on_player_died's `_args.from is BulletHell` then raises and skips the rest of the handler.
func _on_player_left_run(player_index : int) -> void:
	if not in_multiplayer_game:
		return
	if player_index >= 0 and player_index < player_in_scene.size():
		player_in_scene[player_index] = true
	if steam_connection.is_host() and player_index < _players.size():
		var p = _players[player_index]
		if is_instance_valid(p) and not p.dead:
			p.die(Entity.DieArgs.new())


# Host: the wave-end chooser waits for EVERY slot to finish its upgrades / item boxes, so a slot
# whose player left mid-run would stall the whole lobby forever (seen: host parked in Main with
# chooser=True after a client drop, run 2026-09-10 T5). Drive that slot's container the way the
# harness drives its own: take items, pick the first upgrade, until its checkmark shows.
func _resolve_left_players_chooser() -> void:
	# Every new wave respawns every slot alive, departed ones included: keep them dead so the
	# all-dead run-end check and the remaining players see a consistent world.
	for idx in steam_connection.left_players.keys():
		if idx >= 0 and idx < _players.size():
			var p = _players[idx]
			if is_instance_valid(p) and not p.dead:
				p.die(Entity.DieArgs.new())
	if not is_instance_valid(_coop_upgrades_ui) or not _coop_upgrades_ui.visible:
		return
	for idx in steam_connection.left_players.keys():
		if idx < 0 or idx >= RunData.get_player_count():
			continue
		var pc = _coop_upgrades_ui._get_player_container(idx)
		if pc == null or not is_instance_valid(pc) or pc._checkmark_group.visible:
			continue
		if pc._items_container.visible:
			pc._on_TakeButton_pressed()
			print("BTLOBBY auto-resolved item box for departed slot %d" % idx)
		elif pc._upgrades_container.visible and pc._old_upgrades.size() > 0:
			pc._on_choose_button_pressed(pc._old_upgrades[0])
			print("BTLOBBY auto-resolved upgrade for departed slot %d" % idx)
