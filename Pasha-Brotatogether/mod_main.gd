extends Node

const MOD_DIR = "Pasha-Brotatogether/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init(modLoader = ModLoader):
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
#	modLoader.install_script_extension(ext_dir + "global/entity_spawner.gd")
	ModLoaderMod.install_script_extension(ext_dir + "main.gd")
#	ModLoaderMod.install_script_extension(ext_dir + "weapons/weapon.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/player/player.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/birth/birth.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/neutral/neutral.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/enemies/enemy.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/structures/structure.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/movement_behaviors/follow_player_movement_behavior.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "items/consumables/consumable.gd")
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
	
	
	ModLoaderMod.install_script_extension(ext_dir + "zones/wave_manager.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "weapons/shooting_behaviors/ranged_weapon_shooting_behavior.gd")
	ModLoaderMod.install_script_extension(ext_dir + "weapons/shooting_behaviors/melee_weapon_shooting_behavior.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "visual_effects/floating_text/floating_text_manager.gd")
	ModLoaderMod.install_script_extension(ext_dir + "global/effects_manager.gd")
	
