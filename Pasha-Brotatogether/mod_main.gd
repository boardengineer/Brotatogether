extends Node

const SteamConnection = preload("res://mods-unpacked/Pasha-Brotatogether/steam_connection.gd")
const BrotogetherOptions = preload("res://mods-unpacked/Pasha-Brotatogether/brotatogether_options.gd")
# bt_harness.gd is loaded at runtime, not preloaded: a const preload compiles it with this
# script, before _init() installs the extensions, so any vanilla class it names gets loaded
# too early (1.6.9: naming ShopItem broke retail 1.2's boot with 209 parse errors).
const BT_HARNESS_PATH = "res://mods-unpacked/Pasha-Brotatogether/bt_harness.gd"
const MpMouse = preload("res://mods-unpacked/Pasha-Brotatogether/ui/mouse/mp_mouse.gd")

const MOD_DIR = "Pasha-Brotatogether/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init():
	# Retail 1.2 has already initialised Steam (SteamPlatform) by the time mods load; a
	# second steamInit() re-connects Steam.run_callbacks to idle_frame (boot-time "already
	# connected" error). Test trees on LocalPlatform still need it.
	if not Steam.loggedOn():
		Steam.steamInit()
	
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/unit/unit.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/structures/turret/turret.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/entity.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/birth/entity_birth.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/movement_behaviors/player_movement_behavior.gd")
	
	# TODO replace this
#	ModLoaderMod.install_script_extension(ext_dir + "global/effects_manager.gd")
	ModLoaderMod.install_script_extension(ext_dir + "global/entity_spawner.gd")
	ModLoaderMod.install_script_extension(ext_dir + "global/gpe_spawner.gd")
	
	# No items/global/item.gd extension: see main.gd _bt_item_network_id.
	ModLoaderMod.install_script_extension(ext_dir + "main.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "projectiles/player_explosion.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "singletons/coop_service.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/run_data.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/sound_manager.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/sound_manager_2d.gd")
	ModLoaderMod.install_script_extension(ext_dir + "singletons/utils.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/ingame/coop_upgrades_ui_player_container.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/ingame/pause_menu.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/ingame/upgrades_ui.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/pages/main_menu.gd")
	
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/character_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/run/weapon_selection.gd")
	# coop_shop and shop are installed late (see _install_late_extensions).
	# No shop_item.gd extension on 1.2: script-extending it gives the ShopItem class two
	# scripts, and the 1.2 hint scripts typed `shop_item: ShopItem` (coop_ban_shop_hint,
	# coop_dismantle_shop_hint) then fail to parse against their parent -- no co-op item popup.
	# Its old client-only deactivate() is unnecessary now that the base one is purely cosmetic.
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/player_gear_container.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/global/focus_emulator.gd")
	call_deferred("_install_late_extensions")


# Brotato 1.2.0.1 base_shop.gd has `var next_wave := RunData.get_next_wave()`. Compiled during
# ModLoader init, before the RunData autoload exists, that inference fails ("The assigned value
# doesn't have a set type"), base_shop fails to load and every extension of a shop script is
# dropped (no co-op shop sync at all). Installed after init, every autoload is in the tree.
func _install_late_extensions():
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/coop_shop.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/shop/shop.gd")


func _ready():
	var steam_connection = SteamConnection.new()
	steam_connection.set_name("SteamConnection")
	$"/root".call_deferred("add_child",steam_connection)
	
	var options_node = BrotogetherOptions.new()
	options_node.set_name("BrotogetherOptions")
	$"/root".call_deferred("add_child",options_node)

	var bt_harness = load(BT_HARNESS_PATH).new()
	bt_harness.set_name("BTHarness")
	$"/root".call_deferred("add_child",bt_harness)

	# Mouse control for the local player in multiplayer menus (ui/mouse/mp_mouse.gd).
	var mp_mouse = MpMouse.new()
	mp_mouse.set_name("BtMpMouse")
	$"/root".call_deferred("add_child", mp_mouse)
