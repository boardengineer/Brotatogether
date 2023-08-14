extends Node

const MOD_DIR = "Pasha-Brotatogether/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init(_modLoader = ModLoader):
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
#	modLoader.install_script_extension(ext_dir + "global/entity_spawner.gd")
	ModLoaderMod.install_script_extension(ext_dir + "main.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "effects/items/burn_chance_effect.gd")
	ModLoaderMod.install_script_extension(ext_dir + "effects/items/chance_stat_damage_effect.gd")
	ModLoaderMod.install_script_extension(ext_dir + "effects/items/stat_gains_modification_effect.gd")
	ModLoaderMod.install_script_extension(ext_dir + "effects/items/structure_effect.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "effects/weapons/null_effect.gd")
	ModLoaderMod.install_script_extension(ext_dir + "effects/weapons/class_bonus_effect.gd")

	ModLoaderMod.install_script_extension(ext_dir + "entities/birth/birth.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/neutral/neutral.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/enemies/enemy.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/structures/structure.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/movement_behaviors/follow_player_movement_behavior.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "global/effects_manager.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "items/consumables/consumable.gd")
	ModLoaderMod.install_script_extension(ext_dir + "items/global/effect.gd")
	ModLoaderMod.install_script_extension(ext_dir + "items/materials/gold.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/run_data.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/weapon_service.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "projectiles/player_projectile.gd")
	ModLoaderMod.install_script_extension(ext_dir + "projectiles/bullet_enemy/enemy_projectile.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/pages/main_menu.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/weapon_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/ingame/pause_menu.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/item_popup.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/stat_container.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/shop_item.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/shop_items_container.gd")
		
	ModLoaderMod.install_script_extension(ext_dir + "zones/wave_manager.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "weapons/shooting_behaviors/ranged_weapon_shooting_behavior.gd")
	ModLoaderMod.install_script_extension(ext_dir + "weapons/shooting_behaviors/melee_weapon_shooting_behavior.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "visual_effects/floating_text/floating_text_manager.gd")
	
	
func _ready():
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/player/player.gd")
	ModLoaderMod.install_script_extension(ext_dir + "global/entity_spawner.gd")
		
	var run_data = load("res://mods-unpacked/Pasha-Brotatogether/run_data.gd")
	var run_data_node = run_data.new()
	run_data_node.set_name("MultiplayerRunData")
	$"/root".call_deferred("add_child", run_data_node)
	
	var utils = load("res://mods-unpacked/Pasha-Brotatogether/utils.gd")
	var utils_node = utils.new()
	utils_node.set_name("MultiplayerUtils")
	$"/root".call_deferred("add_child", utils_node)
	
	var weapon_service = load("res://mods-unpacked/Pasha-Brotatogether/weapon_service.gd")
	var weapon_service_node = weapon_service.new()
	weapon_service_node.set_name("MultiplayerWeaponService")
	$"/root".call_deferred("add_child", weapon_service_node)
