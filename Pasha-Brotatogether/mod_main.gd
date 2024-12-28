extends Node

const SteamConnection = preload("res://mods-unpacked/Pasha-Brotatogether/steam_connection.gd")
const BrotogetherOptions = preload("res://mods-unpacked/Pasha-Brotatogether/brotatogether_options.gd")

const MOD_DIR = "Pasha-Brotatogether/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init():
	Steam.steamInit()
	
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/movement_behaviors/player_movement_behavior.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/pages/main_menu.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "singletons/coop_service.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/utils.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/weapon_selection.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/base_shop.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/coop_shop.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/global/focus_emulator.gd")
	


func _ready():
	var steam_connection = SteamConnection.new()
	steam_connection.set_name("SteamConnection")
	$"/root".call_deferred("add_child",steam_connection)
	
	var options_node = BrotogetherOptions.new()
	options_node.set_name("BrotogetherOptions")
	$"/root".call_deferred("add_child",options_node)
