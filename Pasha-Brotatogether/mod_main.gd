extends Node

const MOD_DIR = "Pasha-Brotatogether/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init(modLoader = ModLoader):
	dir = modLoader.UNPACKED_DIR + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
#	modLoader.install_script_extension(ext_dir + "global/entity_spawner.gd")
	modLoader.install_script_extension(ext_dir + "main.gd")
	modLoader.call_deferred("install_script_extension", ext_dir + "weapons/weapon.gd")
	
	modLoader.install_script_extension(ext_dir + "entities/units/player/player.gd")
	modLoader.install_script_extension(ext_dir + "entities/birth/birth.gd")
	modLoader.install_script_extension(ext_dir + "entities/units/neutral/neutral.gd")

	
	modLoader.install_script_extension(ext_dir + "items/consumables/consumable.gd")
	modLoader.install_script_extension(ext_dir + "items/materials/gold.gd")
	modLoader.install_script_extension(ext_dir + "singletons/run_data.gd")
	modLoader.install_script_extension(ext_dir + "projectiles/player_projectile.gd")
	modLoader.install_script_extension(ext_dir + "ui/menus/pages/main_menu.gd")
	modLoader.install_script_extension(ext_dir + "entities/units/enemies/enemy.gd")
	modLoader.install_script_extension(ext_dir + "weapons/shooting_behaviors/ranged_weapon_shooting_behavior.gd")
	modLoader.install_script_extension(ext_dir + "visual_effects/floating_text/floating_text_manager.gd")
	modLoader.install_script_extension(ext_dir + "global/effects_manager.gd")
