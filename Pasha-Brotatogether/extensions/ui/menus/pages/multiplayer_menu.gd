extends VBoxContainer

# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

onready var text_box = $"HBoxContainer/InfoBox/Label"
onready var ip_box = $"HBoxContainer/InfoBox/ServerIp"

var lobby_id = 0

const SteamConnection = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/steam_connection.gd")
const DirectConnection = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/direct_connection.gd")

var GameController = load("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/game_controller.gd")

var steam_connection
var direct_connection
var game_controller

var DEBUG = false

onready var debug_server_button = $HBoxContainer/ControlBox/Buttons/ServerButton
onready var debug_client_button = $HBoxContainer/ControlBox/Buttons/ClientButton
onready var debug_start_button = $HBoxContainer/ControlBox/Buttons/StartButton
onready var debug_start2_button = $HBoxContainer/ControlBox/Buttons/StartButton2
onready var debug_info_box = $HBoxContainer/InfoBox

# Called when the node enters the scene tree for the first time.
func _ready():
	if not DEBUG:
		debug_info_box.hide()
		debug_server_button.hide()
		debug_client_button.hide()
		debug_start_button.hide()
		debug_start2_button.hide()
	
	var rooted_steam_connection = null
	var rooted_direct_connection = null
	var rooted_game_controller = null
	
	for root_child in $"/root".get_children():
		if root_child is SteamConnection:
			rooted_steam_connection = root_child
		if root_child is GameController:
			rooted_game_controller = root_child
		if root_child is DirectConnection:
			rooted_direct_connection = root_child

	if not rooted_steam_connection:
		rooted_steam_connection = SteamConnection.new()
		rooted_steam_connection.set_name("SteamConnection")
		$"/root".add_child(rooted_steam_connection)
	if not rooted_game_controller:
		rooted_game_controller = GameController.new()
		rooted_game_controller.set_name("GameController")
		$"/root".add_child(rooted_game_controller)
	if not rooted_direct_connection:
		rooted_direct_connection = DirectConnection.new()
		rooted_direct_connection.set_name("DirectConnection")
		$"/root".add_child(rooted_direct_connection)

	game_controller = rooted_game_controller
	steam_connection = rooted_steam_connection
	direct_connection = rooted_direct_connection


func _on_ServerButton_pressed():
	game_controller.connection = direct_connection
	direct_connection.parent = game_controller
	
#	var connection = 
	var peer = NetworkedMultiplayerENet.new()
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	
	game_controller.self_peer_id = 1
	game_controller.is_host = true
	game_controller.tracked_players[1] = {}
	
	get_tree().network_peer = peer
	
	direct_connection.rpc_id(1, "register_player")
	text_box.text = str(error)

func _on_ClientButton_pressed():
	var peer = NetworkedMultiplayerENet.new()
	var _error = peer.create_client(ip_box.text, SERVER_PORT)
	
	game_controller.connection = direct_connection
	direct_connection.parent = game_controller
	
	get_tree().network_peer = peer
	text_box.text = str(get_tree().get_current_scene().get_name())

func _on_StartButton_pressed():
	if game_controller.is_host:
		game_controller.is_source_of_truth = true
	var game_mode = "shared"
	game_controller.send_start_game({"current_wave":1, "mode":game_mode})
	game_controller.game_mode = game_mode
	RunData.add_character(preload("res://items/characters/well_rounded/well_rounded_data.tres"))
	var _weapon_error = RunData.add_weapon(preload("res://weapons/ranged/minigun/4/minigun_4_data.tres"), true)
	
	var _change_scene_error = get_tree().change_scene(MenuData.game_scene)

func _on_StartButton2_pressed():
	var weapon_path = "res://weapons/melee/hatchet/1/hatchet_data.tres"
	var character_path = "res://items/characters/well_rounded/well_rounded_data.tres"
	
	RunData.add_character(load(character_path))
	var _unused_weapon = RunData.add_weapon(load(weapon_path), true)
	
	if game_controller.is_host:
		game_controller.is_source_of_truth = false
		
	var game_mode = "async"
	
	var lobby_info = {}
	
	lobby_info["character"] = character_path
	lobby_info["weapon"] = weapon_path
	lobby_info["danger"] = 5
		
	game_controller.send_start_game({"current_wave":1, "mode":game_mode, "lobby_info":lobby_info})
	game_controller.game_mode = game_mode
	
	var _change_scene_error = get_tree().change_scene(MenuData.game_scene)

func _on_SteamLobbies_pressed():
	for old_child in $"/root/MultiplayerMenu/HBoxContainer/LobbiesBox".get_children():
		$"/root/MultiplayerMenu/HBoxContainer/LobbiesBox".remove_child(old_child)
	
	Steam.addRequestLobbyListDistanceFilter(3)
	Steam.addRequestLobbyListStringFilter("game", "Brotatogether", 0)
	Steam.requestLobbyList()
	
	#TODO move this elsewhere
	game_controller.connection = steam_connection
	steam_connection.parent = game_controller
	
func _on_CreateSteamLobby_pressed():
	if lobby_id == 0:
		# first param is visibility, 2 for public
		Steam.createLobby(2, 5)
		
		# TODO move this elsewhere
		game_controller.is_host = true
		game_controller.is_source_of_truth = true
		game_controller.connection = steam_connection
		
		steam_connection.parent = game_controller
	else:
		steam_connection.send_handshakes()
		
func update_lobbies(lobbies: Array) -> void:
	for found_lobby_id in lobbies:
		var join_button = Button.new()
		var host_name = Steam.getLobbyData(found_lobby_id, "host")
		join_button.text = str(host_name)
		$"/root/MultiplayerMenu/HBoxContainer/LobbiesBox".add_child(join_button)
		join_button.connect("pressed", self, "join_button_pressed", [found_lobby_id])
		# Steam.joinLobby(lobbies[0])
		
func join_button_pressed(joining_lobby_id: int) :
	Steam.joinLobby(joining_lobby_id)

func _input(event:InputEvent)->void :
	manage_back(event)

func manage_back(event:InputEvent)->void :
	if event.is_action_pressed("ui_cancel"):
		RunData.current_zone = 0
		RunData.reload_music = false
		var _error = get_tree().change_scene(MenuData.title_screen_scene)
