extends Node

var ClientMovementBehavior = load("res://mods-unpacked/Pasha-Brotatogether/client/client_movement_behavior.gd")

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
var _elite_killed_bonus: = 0
var _elite_killed: = false

var _convert_stats_half_wave_proced: = false

onready var _entities_container = $Entities
onready var _effects_manager = $EffectsManager
onready var _wave_manager = $WaveManager
onready var _floating_text_manager = $FloatingTextManager
onready var _camera = $Camera
onready var _ui_gold = $UI/HUD/GoldContainer/UIGold
onready var _ui_bonus_gold = $UI/HUD/LifeContainer/UIBonusGold
onready var _ui_upgrades_to_process = $UI/HUD/UpgradesToProcess
onready var _ui_consumables_to_process = $UI/HUD/ConsumablesToProcess
onready var _item_box_ui = $UI/ItemBoxUI

func _ready():
	game_controller = $"/root/GameController"
	game_controller.connect("complete_player_update", self, "_on_complete_player_update")
	game_controller.connect("item_box_undo", self, "_on_item_box_undo")

func on_gold_changed(gold:int)->void :
	if _update_stats_on_gold_changed:
		if (gold / 30.0) as int != _last_gold_amount_used_to_reload_stats:
			reload_stats()
			_last_gold_amount_used_to_reload_stats = (gold / 30.0) as int

func _on_WaveTimer_timeout() -> void:
	clean_up_room(false, false, false)

func _on_EndWaveTimer_timeout() -> void:
	_end_wave_timer_timedout = true
	game_controller.send_complete_player_request()
	yield(game_controller, "complete_player_update")
	
	if _is_run_won:
		apply_run_won()
		RunData.run_won = true
		var _error = get_tree().change_scene("res://ui/menus/run/end_run.tscn")
		return
	
	InputService.hide_mouse = true

	var consumables = game_controller.tracked_players[game_controller.self_peer_id].consumables_to_process
	if consumables.size() > 0:
		for consumable in consumables:
			var fixed_tier = -1
			if consumable.my_id == "consumable_legendary_item_box":
				fixed_tier = Tier.LEGENDARY
			var item_data = ItemService.process_item_box(RunData.current_wave, consumable, fixed_tier)
			_item_box_ui.set_item_data(item_data)
			yield(_item_box_ui, "item_box_processed")
			game_controller.send_complete_player_request()
			yield(game_controller, "complete_player_update")
			_ui_consumables_to_process.remove_element(consumable)
	game_controller.tracked_players[game_controller.self_peer_id].consumables_to_process = []

	if _upgrades_to_process.size() > 0:
		for upgrade_to_process in _upgrades_to_process:
			_upgrades_ui.show_upgrade_options(upgrade_to_process)
			yield(_upgrades_ui, "upgrade_selected")
			game_controller.send_complete_player_request()
			yield(game_controller, "complete_player_update")
			_ui_upgrades_to_process.remove_element(upgrade_to_process)

	var _error = get_tree().change_scene("res://mods-unpacked/Pasha-Brotatogether/ui/shop/multiplayer_shop.tscn")

func _on_complete_player_update():
	pass

func _on_item_box_undo(item_data: Resource):
	_ui_consumables_to_process.add_element(item_data)

func clean_up_room(is_lost: bool, is_won: bool, immediate: bool):
	_cleaning_up = true
	_is_run_lost = is_lost
	_is_run_won = is_won
	for consumable in _consumables:
		if is_instance_valid(consumable):
			consumable.queue_free()
	_consumables.clear()
	for gold in _golds:
		if is_instance_valid(gold):
			gold.queue_free()
	_golds.clear()
	_entities_container.queue_free()
	_effects_manager.queue_free()
	_wave_manager.queue_free()
	_floating_text_manager.queue_free()
