extends Node

#TODO, this file should be mostly empty, far too much duping of main.gd

signal consumable_to_process_added(consumable_data)
signal upgrade_to_process_added(consumable_data)

export (PackedScene) var gold_bag_scene:PackedScene
export (PackedScene) var gold_scene:PackedScene
export (PackedScene) var consumable_scene:PackedScene
export (Array) var gold_sprites:Array
export (Array, Resource) var gold_pickup_sounds:Array
export (Array, Resource) var gold_alt_pickup_sounds:Array
export (Resource) var level_up_sound:Resource
export (Array, Resource) var run_won_sounds:Array
export (Array, Resource) var run_lost_sounds:Array
export (Array, Resource) var end_wave_sounds:Array

const EDGE_SIZE = 96
const MAX_GOLDS = 50
const MIN_MAP_SIZE = 12
const PlaceHolderSprite = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/PlaceHolder.tscn")

const MOUSE_DIST_FROM_PLAYER_MANUAL_AIM = 200

var _cleaning_up: = false
var _golds: = []
var _consumables: = []
var _upgrades_to_process: = []
var _consumables_to_process: = []
var _end_wave_timer_timedout: = false

var _player:Player
var _is_run_lost:bool
var _is_run_won:bool
var _gold_bag:Node

var _landmine_timer:Timer = null
var _is_chal_ui_displayed = false

var _last_rjoy_input:Vector2 = Vector2.ZERO

var _proj_on_death_stat_cache:Dictionary = {}
var _items_spawned_this_wave: = 0

var _nb_bosses_killed_this_wave: = 0
var _update_stats_on_gold_changed: = false
var _update_stats_on_enemies_changed: = false
var _update_stats_on_enemies_changed_timer:Timer = null
var _last_gold_amount_used_to_reload_stats: = 0
var _is_horde_wave: = false
var _is_elite_wave: = false
var _elite_killed_bonus: = 0
var _elite_killed: = false

var _convert_stats_half_wave_proced: = false

onready var _entities_container = $Entities
onready var _effects_manager = $EffectsManager
onready var _wave_manager = $WaveManager
onready var _floating_text_manager = $FloatingTextManager
onready var _camera = $Camera
onready var _screenshaker = $Camera / Screenshaker
onready var _items_container = $Items
onready var _consumables_container = $Consumables
onready var _births_container = $Births
onready var _pause_menu = $UI / PauseMenu
onready var _end_wave_timer = $EndWaveTimer
onready var _upgrades_ui = $UI / UpgradesUI as UpgradesUI
onready var _item_box_ui = $UI / ItemBoxUI as ItemBoxUI
onready var _wave_timer = $WaveTimer
onready var _player_life_bar = $"%PlayerLifeBar"
onready var _player_life_bar_container = $PlayerLifeBarContainer

onready var _wave_cleared_label = $UI / WaveClearedLabel
onready var _life_label = $UI / HUD / LifeContainer / UILifeBar / MarginContainer / LifeLabel
onready var _level_label = $UI / HUD / LifeContainer / UIXPBar / MarginContainer / LevelLabel
onready var _hud = $UI / HUD
onready var _life_bar = $UI / HUD / LifeContainer / UILifeBar
onready var _xp_bar = $UI / HUD / LifeContainer / UIXPBar
onready var _ui_gold = $UI / HUD / LifeContainer / UIGold
onready var _ui_bonus_gold = $UI / HUD / LifeContainer / UIBonusGold
onready var _ui_bonus_gold_pos = $UI / HUD / LifeContainer / UIBonusGold / Position2D
onready var _current_wave_label = $UI / HUD / WaveContainer / CurrentWaveLabel
onready var _wave_timer_label = $UI / HUD / WaveContainer / WaveTimerLabel
onready var _ui_wave_container = $UI / HUD / WaveContainer
onready var _ui_upgrades_to_process = $UI / HUD / ThingsToProcessContainer / Upgrades
onready var _ui_consumables_to_process = $UI / HUD / ThingsToProcessContainer / Consumables
onready var _ui_dim_screen = $UI / DimScreen
onready var _tile_map = $TileMap
onready var _tile_map_limits = $TileMapLimits
onready var _background = $CanvasLayer / Background
onready var _harvesting_timer = $HarvestingTimer
onready var _challenge_completed_ui = $UI / ChallengeCompletedUI

onready var _damage_vignette = $UI / DamageVignette
onready var _info_popup = $UI / InfoPopup

onready var networking = $"/root/networking"

const refresh_time = 1.0 / 100.0
var update_timer = refresh_time

func _physics_process(delta:float)->void :
	update_timer -= delta
	if update_timer <= 0:
		send_player_position()
		update_timer = refresh_time

func send_player_position():
	networking.send_client_position()

func _ready()->void :
	_convert_stats_half_wave_proced = false
	
	_background.texture.gradient.colors[1] = RunData.get_background_gradient_color()
	_tile_map.tile_set.tile_set_texture(0, RunData.get_background().tiles_sprite)
	_tile_map.outline.modulate = RunData.get_background().outline_color
	
	TempStats.reset()
	
	var current_zone = ZoneService.get_zone_data(RunData.current_zone).duplicate()
	var current_wave_data = ZoneService.get_wave_data(RunData.current_zone, RunData.current_wave)
	
	var map_size_coef = (1 + (RunData.effects["map_size"] / 100.0))
	
	current_zone.width = max(MIN_MAP_SIZE, (current_zone.width * map_size_coef)) as int
	current_zone.height = max(MIN_MAP_SIZE, (current_zone.height * map_size_coef)) as int
	
	_tile_map.init(current_zone)
	_tile_map_limits.init(current_zone)
	
	ZoneService.current_zone_max_position = Vector2(current_zone.width * Utils.TILE_SIZE, current_zone.height * Utils.TILE_SIZE)
		
	_current_wave_label.text = Text.text("WAVE", [str(RunData.current_wave)]).to_upper()
	
	_wave_timer.wait_time = 1 if RunData.instant_waves else current_wave_data.wave_duration
	_wave_timer.start()
	_wave_timer_label.wave_timer = _wave_timer
	var _error_wave_timer = _wave_timer.connect("tick_started", self, "on_tick_started")
	
	_wave_manager.init(_wave_timer, current_wave_data)
	
	on_bonus_gold_changed(RunData.bonus_gold)
	
	init_camera()
	set_level_label()
	_ui_dim_screen.color.a = 0
	
	var pct_val = RunData.effects["gain_pct_gold_start_wave"]
	var apply_pct_gold_wave = (pct_val > 0 and RunData.current_wave <= RunData.nb_of_waves) or pct_val < 0
	
	
	
	if pct_val < 0 and RunData.current_wave > RunData.nb_of_waves:
		pct_val = - 100.0
	
	if apply_pct_gold_wave:
		var val = RunData.gold * (pct_val / 100.0)
		RunData.add_gold(val)
		
		if RunData.effects["gain_pct_gold_start_wave"] > 0:
			RunData.tracked_item_effects["item_piggy_bank"] += val
	
	for stat_link in RunData.effects["stat_links"]:
		if stat_link[2] == "materials":
			_update_stats_on_gold_changed = true
		elif stat_link[2] == "living_enemy":
			_update_stats_on_enemies_changed = true
			_update_stats_on_enemies_changed_timer = Timer.new()
			_update_stats_on_enemies_changed_timer.wait_time = 1.0
			_update_stats_on_enemies_changed_timer.one_shot = true
			add_child(_update_stats_on_enemies_changed_timer)
	
	if RunData.effects["temp_pct_stats_start_wave"].size() > 0:
		for pct_temp_stat_stacked in RunData.effects["temp_pct_stats_start_wave"]:
			var stat = (RunData.get_stat(pct_temp_stat_stacked[0]) * (pct_temp_stat_stacked[1] / 100.0)) as int
			TempStats.add_stat(pct_temp_stat_stacked[0], stat)
	
	if ProgressData.is_manual_aim():
		ProgressData.update_mouse_cursor()
		InputService.hide_mouse = false
	
	_is_horde_wave = RunData.is_elite_wave(EliteType.HORDE)
	_is_elite_wave = RunData.is_elite_wave(EliteType.ELITE)
	
	DebugService.log_run_info()
	RunData.reset_weapons_dmg_dealt()
	RunData.reset_cache()


func _input(event:InputEvent)->void :
	var is_right_stick_motion = event is InputEventJoypadMotion and (event.axis == JOY_AXIS_2 or event.axis == JOY_AXIS_3) and abs(event.axis_value) > 0.5
	var is_mouse_press = event is InputEventMouseButton
	
	if (is_mouse_press or is_right_stick_motion) and not _cleaning_up:
		if ProgressData.settings.manual_aim_on_mouse_press and not ProgressData.settings.manual_aim:
			ProgressData.update_mouse_cursor()
			
			if is_mouse_press:
				if event.pressed:
					InputService.hide_mouse = false
				else :
					InputService.hide_mouse = true
			else :
				InputService.hide_mouse = false
	
	if InputService.using_gamepad and not InputService.hide_mouse and not ProgressData.is_manual_aim():
		InputService.hide_mouse = true


func add_timer(cooldown:int)->Timer:
	var timer = Timer.new()
	timer.wait_time = cooldown
	add_child(timer)
	timer.start()
	return timer

func on_stat_updated(_stat_name:String, _value:int, _db_mod:float = 0.0)->void :
	reload_stats()

func reload_stats()->void :
	_player.update_player_stats()
	
	LinkedStats.reset()
	
	for weapon in _player.current_weapons:
		if is_instance_valid(weapon):
			weapon.init_stats(false)
	
	_proj_on_death_stat_cache.clear()

func on_tick_started()->void :
	_wave_timer_label.modulate = Color.red


func on_bonus_gold_changed(value:int)->void :
	if value == 0:
		_ui_bonus_gold.hide()


func init_camera()->void :
	var max_pos = ZoneService.current_zone_max_position
	var min_pos = ZoneService.current_zone_min_position
	
	var zone_w = max_pos.x - min_pos.x
	var zone_h = max_pos.y - min_pos.y
	
	_camera.center_horizontal_pos = zone_w / 2
	_camera.center_vertical_pos = zone_h / 2
	
	if zone_w + EDGE_SIZE * 2 <= Utils.project_width:
		_camera.center_horizontal = true
	else :
		_camera.limit_right = max_pos.x + EDGE_SIZE
		_camera.limit_left = min_pos.x - EDGE_SIZE
	
	if zone_h + EDGE_SIZE * 2 <= Utils.project_height:
		_camera.center_vertical = true
	else :
		_camera.limit_bottom = max_pos.y + EDGE_SIZE
		_camera.limit_top = min_pos.y - EDGE_SIZE * 2

func _on_player_died(_p_player:Player)->void :
	_player_life_bar.hide()
	
	if RunData.current_wave <= RunData.nb_of_waves:
		_is_run_lost = true
	else :
		_is_run_won = true
	clean_up_room(false, _is_run_lost, _is_run_won)
	_end_wave_timer.start()
	ProgressData.reset_run_state()
	ChallengeService.complete_challenge("chal_rookie")

func on_consumable_picked_up(consumable:Node)->void :
	RunData.consumables_picked_up_this_run += 1
	_consumables.erase(consumable)
	
	if (consumable.consumable_data.my_id == "consumable_item_box" or consumable.consumable_data.my_id == "consumable_legendary_item_box") and RunData.effects["item_box_gold"] != 0:
		RunData.add_gold(RunData.effects["item_box_gold"])
		RunData.tracked_item_effects["item_bag"] += RunData.effects["item_box_gold"]
	
	if consumable.consumable_data.to_be_processed_at_end_of_wave:
		_consumables_to_process.push_back(consumable.consumable_data)
		emit_signal("consumable_to_process_added", consumable.consumable_data)
	
	if RunData.consumables_picked_up_this_run >= RunData.chal_hungry_value:
		ChallengeService.complete_challenge("chal_hungry")
	
	if RunData.effects["consumable_stats_while_max"].size() > 0 and _player.current_stats.health >= _player.max_stats.health:
		for i in RunData.effects["consumable_stats_while_max"].size():
			var stat = RunData.effects["consumable_stats_while_max"][i]
			var has_max = (stat.size() > 2
				 and RunData.max_consumable_stats_gained_this_wave.size() > i
				 and RunData.max_consumable_stats_gained_this_wave[i].size() > 2)
			
			var reached_max = false
			
			if has_max:
				reached_max = RunData.max_consumable_stats_gained_this_wave[i][2] >= stat[2]
			
			if not has_max or not reached_max:
				RunData.add_stat(stat[0], stat[1])
				
				if stat[0] == "stat_max_hp":
					RunData.tracked_item_effects["item_extra_stomach"] += stat[1]
				
				if has_max:
					RunData.max_consumable_stats_gained_this_wave[i][2] += stat[1]
	
	if not _cleaning_up:
		RunData.handle_explosion("explode_on_consumable", consumable.global_position)
	
	RunData.apply_item_effects(consumable.consumable_data)


func spawn_gold(unit:Unit, entity_type:int)->void :
	var pos = unit.global_position
	var value = unit.stats.value
	
	if entity_type == EntityType.NEUTRAL:
		value += (value * round(RunData.effects["neutral_gold_drops"] / 100.0))
	elif entity_type == EntityType.ENEMY and RunData.effects["enemy_gold_drops"] > 1.0:
		value += (value * round(RunData.effects["enemy_gold_drops"] / 100.0))
	
	for i in value:
		var dist = rand_range(50, 100 + unit.stats.gold_spread)
		var gold = gold_scene.instance()
		
		if RunData.bonus_gold > 0:
			var gold_value = gold.value
			gold.value += min(gold.value, RunData.bonus_gold)
			gold.boosted = 2
			gold.scale.x = 1.25
			gold.scale.y = 1.25
			RunData.remove_bonus_gold(gold_value)
		
		gold.global_position = pos
		gold.rotation = rand_range(0, 2 * PI)
		_items_container.call_deferred("add_child", gold)
		gold.call_deferred("set_texture", gold_sprites[randi() % 11])
		var _error = gold.connect("picked_up", self, "on_gold_picked_up")
		var _error_effects = gold.connect("picked_up", _effects_manager, "on_gold_picked_up")
		var _error_floating_text = gold.connect("picked_up", _floating_text_manager, "on_gold_picked_up")
		gold.push_back_destination = Vector2(rand_range(pos.x - dist, pos.x + dist), rand_range(pos.y - dist, pos.y + dist))
		_golds.push_back(gold)
		
		if randf() < (RunData.effects["instant_gold_attracting"] / 100.0):
			gold.attracted_by = _player

func on_levelled_up()->void :
	SoundManager.play(level_up_sound, 0, 0, true)
	var level = RunData.current_level
	emit_signal("upgrade_to_process_added", ItemService.upgrade_to_process_icon, level)
	_upgrades_to_process.push_back(level)
	set_level_label()
	RunData.add_stat("stat_max_hp", 1)
	RunData.emit_signal("healing_effect", 1)


func set_level_label()->void :
	_level_label.text = "LV." + str(RunData.current_level)


func set_life_label(current_health:int, max_health:int)->void :
	_life_label.text = str(max(current_health, 0.0)) + " / " + str(max_health)


func connect_visual_effects(unit:Unit)->void :
	var _error_effects = unit.connect("took_damage", _effects_manager, "_on_unit_took_damage")
	var _error_floating_text = unit.connect("took_damage", _floating_text_manager, "_on_unit_took_damage")


func clean_up_room(is_last_wave:bool = false, is_run_lost:bool = false, is_run_won:bool = false)->void :
	
	if is_run_lost:
		DebugService.log_data("is_run_lost")
		_wave_timer_label.is_run_lost = true
		_wave_timer.stop()
		_wave_timer.tick_timer.stop()
		_end_wave_timer.wait_time = 2.5
		SoundManager.play(Utils.get_rand_element(run_lost_sounds), - 5, 0, true)
		_ui_dim_screen.dim()
		MusicManager.tween( - 20)
	elif is_run_won:
		DebugService.log_data("is_run_won")
		apply_run_won()
	
	if RunData.is_endless_run:
		
		if RunData.current_wave % 10 == 0 and RunData.current_wave >= 20:
			RunData.init_elites_spawn(RunData.current_wave, 0.0)
		
		DebugService.log_data("is_endless_run")
		
		if RunData.current_wave >= 20:
			var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
			
			character_difficulty.max_endless_wave_beaten.set_info(
				RunData.get_current_difficulty(), 
				RunData.current_wave, 
				RunData.current_run_accessibility_settings.health, 
				RunData.current_run_accessibility_settings.damage, 
				RunData.current_run_accessibility_settings.speed, 
				true
			)
	
	if not RunData.is_testing:
		ProgressData.save()
	
	SoundManager.play(Utils.get_rand_element(end_wave_sounds))
	_cleaning_up = true
	_effects_manager.clean_up_room()
	_floating_text_manager.clean_up_room()
	
	DebugService.log_data("attract bonus_gold and consumables...")
	if _golds.size() > 0:
		var attracted_by = null
		_ui_bonus_gold.show()
		attracted_by = _gold_bag
		_player.disable_gold_pickup()
		
		if ProgressData.settings.optimize_end_waves:
			var bonus_gold_value = 0
			
			for gold in _golds:
				var value = gold.value
				
				if randf() < RunData.effects["chance_double_gold"] / 100.0:
					RunData.tracked_item_effects["item_metal_detector"] += value
					value *= 2
				
				bonus_gold_value += value
				
				gold.visible = false
			
			RunData.add_bonus_gold(bonus_gold_value)
		else :
			for gold in _golds:
				gold.set_collision_layer(256)
				gold.attracted_by = attracted_by
	
	if _consumables.size() > 0:
		for consumable in _consumables:
			consumable.attracted_by = _player
	
	DebugService.log_data("clean_up other objects...")
	_wave_manager.clean_up_room()
	
	if is_instance_valid(_player):
		_player.clean_up()
	
	DebugService.log_data("start wave_cleared_label...")
	_wave_cleared_label.start(is_last_wave, is_run_lost, is_run_won)
	DebugService.log_data("wave_cleared_label started...")

func get_gold_bag_pos()->Vector2:
	return get_viewport().get_canvas_transform().affine_inverse().xform(_ui_bonus_gold_pos.global_position)

func _on_EndWaveTimer_timeout()->void :
	DebugService.log_data("_on_EndWaveTimer_timeout")
	_end_wave_timer_timedout = true
	_ui_dim_screen.dim()
	_ui_consumables_to_process.modulate = Color.white
	_ui_upgrades_to_process.modulate = Color.white
	_wave_cleared_label.hide()
	_wave_timer_label.hide()
	
	if _landmine_timer:
		_landmine_timer.stop()
	
	if _is_run_lost or is_last_wave() or _is_run_won:
		DebugService.log_data("end run...")
		RunData.run_won = not _is_run_lost
		
		if RunData.is_testing:
			var _error = get_tree().change_scene(MenuData.editor_scene)
		else :
			var _error = get_tree().change_scene("res://ui/menus/run/end_run.tscn")
	else :
		DebugService.log_data("process consumables and upgrades...")
		MusicManager.tween( - 8)
		if _consumables_to_process.size() > 0:
			for consumable in _consumables_to_process:
				var fixed_tier = - 1
				
				if consumable.my_id == "consumable_legendary_item_box":
					fixed_tier = Tier.LEGENDARY
				
				var item_data = ItemService.process_item_box(RunData.current_wave, consumable, fixed_tier)
				_item_box_ui.set_item_data(item_data)
				yield (_item_box_ui, "item_box_processed")
				_ui_consumables_to_process.remove_element(consumable)
		
		if _upgrades_to_process.size() > 0:
			for upgrade_to_process in _upgrades_to_process:
				_upgrades_ui.show_upgrade_options(upgrade_to_process)
				yield (_upgrades_ui, "upgrade_selected")
				_ui_upgrades_to_process.remove_element(upgrade_to_process)
		
		DebugService.log_data("display challenge ui...")
		if _is_chal_ui_displayed:
			yield (_challenge_completed_ui, "finished")
		
		var _error = get_tree().change_scene("res://ui/menus/shop/shop.tscn")

func on_focus_lost()->void :
	if _end_wave_timer_timedout:
		if _item_box_ui.visible:
			_item_box_ui.focus()
		elif _upgrades_ui.visible:
			_upgrades_ui.focus()

func on_upgrade_selected(upgrade_data:UpgradeData)->void :
	RunData.apply_item_effects(upgrade_data)

func on_item_box_take_button_pressed(item_data:ItemParentData)->void :
	RunData.add_item(item_data)

func on_item_box_discard_button_pressed(item_data:ItemParentData)->void :
	RunData.add_gold(ItemService.get_recycling_value(RunData.current_wave, item_data.value))

func _on_PauseMenu_paused()->void :
	reload_stats()

func _on_PauseMenu_unpaused()->void :
	on_focus_lost()

func apply_run_won()->void :
	_wave_timer.stop()
	_wave_timer.tick_timer.stop()
	_end_wave_timer.wait_time = 3
	_ui_dim_screen.dim()
	SoundManager.play(Utils.get_rand_element(run_won_sounds), - 5, 0, true)
	
	var character_chal_name = "chal_" + RunData.current_character.name.to_lower().replace("character_", "")
	ChallengeService.complete_challenge(character_chal_name)
	
	var character_difficulty = ProgressData.get_character_difficulty_info(RunData.current_character.my_id, RunData.current_zone)
		
	if character_difficulty.max_selectable_difficulty < RunData.get_current_difficulty() + 1 and RunData.get_current_difficulty() + 1 <= ProgressData.MAX_DIFFICULTY:
		RunData.difficulty_unlocked = RunData.get_current_difficulty() + 1
	
	ChallengeService.complete_challenge("chal_difficulty_" + str(RunData.get_current_difficulty()))
	
	for char_diff in ProgressData.difficulties_unlocked:
		for zone_difficulty_info in char_diff.zones_difficulty_info:
			zone_difficulty_info.max_selectable_difficulty = clamp(RunData.get_current_difficulty() + 1, zone_difficulty_info.max_selectable_difficulty, ProgressData.MAX_DIFFICULTY)
	
	character_difficulty.max_difficulty_beaten.set_info(
		RunData.get_current_difficulty(), 
		RunData.current_wave, 
		RunData.current_run_accessibility_settings.health, 
		RunData.current_run_accessibility_settings.damage, 
		RunData.current_run_accessibility_settings.speed, 
		false
	)
	
	ProgressData.reset_run_state()


func is_last_wave()->bool:
	var is_last_wave = RunData.current_wave == ZoneService.get_zone_data(RunData.current_zone).waves_data.size()
	if RunData.is_endless_run:is_last_wave = false
	return is_last_wave


func manage_harvesting()->void :
	pass

func _on_FiveSecondsTimer_timeout()->void :
	if not _cleaning_up:
		if RunData.effects["temp_stats_stacking"].size() > 0:
			for temp_stat_stacked in RunData.effects["temp_stats_stacking"]:
				TempStats.add_stat(temp_stat_stacked[0], temp_stat_stacked[1])
		
		if RunData.effects["temp_pct_stats_stacking"].size() > 0:
			for pct_temp_stat_stacked in RunData.effects["temp_pct_stats_stacking"]:
				var stat = (RunData.get_stat(pct_temp_stat_stacked[0]) * (pct_temp_stat_stacked[1] / 100.0)) as int
				TempStats.add_stat(pct_temp_stat_stacked[0], stat)


func _on_UIBonusGold_mouse_entered()->void :
	if _cleaning_up:
		_info_popup.display(_ui_bonus_gold, Text.text("INFO_BONUS_GOLD", [str(RunData.bonus_gold)]))


func _on_UIBonusGold_mouse_exited()->void :
	_info_popup.hide()

func _on_HarvestingTimer_timeout()->void :
	if RunData.current_wave > RunData.nb_of_waves:
		var val = ceil(Utils.get_stat("stat_harvesting") * (RunData.ENDLESS_HARVESTING_DECREASE / 100.0))
		RunData.remove_stat("stat_harvesting", val)
	else :
		var val = ceil(Utils.get_stat("stat_harvesting") * (RunData.effects["harvesting_growth"] / 100.0))
		
		var has_crown = false
		var crown_value = 0
		
		for item in RunData.items:
			if item.my_id == "item_crown":
				has_crown = true
				crown_value = item.effects[0].value
				break
		
		if has_crown:
			RunData.tracked_item_effects["item_crown"] += (Utils.get_stat("stat_harvesting") * (crown_value / 100.0)) as int
		
		if val > 0:
			RunData.add_stat("stat_harvesting", val)

func on_gold_changed(gold:int)->void :
	if _update_stats_on_gold_changed:
		if (gold / 30.0) as int != _last_gold_amount_used_to_reload_stats:
			reload_stats()
			_last_gold_amount_used_to_reload_stats = (gold / 30.0) as int
