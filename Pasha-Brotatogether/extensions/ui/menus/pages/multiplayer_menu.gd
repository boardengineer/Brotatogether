extends VBoxContainer


# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

onready var text_box = $"HBoxContainer/InfoBox/Label"
onready var ip_box = $"HBoxContainer/InfoBox/ServerIp"

var lobby_id = 0

const SteamConnection = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/steam_connection.gd")
const DirectConnection = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/direct_connection.gd")

const GameController = preload("res://mods-unpacked/Pasha-Brotatogether/extensions/networking/game_controller.gd")

var steam_connection
var direct_connection
var game_controller

# Called when the node enters the scene tree for the first time.
func _ready():
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
		$"/root".add_child(rooted_steam_connection)
	if not rooted_game_controller:
		rooted_game_controller = GameController.new()
		rooted_game_controller.set_name("GameController")
		$"/root".add_child(rooted_game_controller)
	if not rooted_direct_connection:
		rooted_direct_connection = DirectConnection.new()
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
	
	get_tree().network_peer = peer
	
	direct_connection.rpc_id(1, "register_player")
	text_box.text = str(error)

func _on_ClientButton_pressed():
	var peer = NetworkedMultiplayerENet.new()
	var error = peer.create_client(ip_box.text, SERVER_PORT)
	
	game_controller.connection = direct_connection
	direct_connection.parent = game_controller
	
	get_tree().network_peer = peer
	text_box.text = str(get_tree().get_current_scene().get_name())

func _on_StartButton_pressed():
	game_controller.send_start_game({"current_wave":1})
	RunData.add_character(preload("res://items/characters/well_rounded/well_rounded_data.tres"))
	RunData.add_weapon(preload("res://weapons/melee/dagger/1/dagger_data.tres"), true)
#	RunData.add_weapon(preload("res://weapons/ranged/pistol/1/pistol_data.tres"), true)
	get_tree().change_scene(MenuData.game_scene)

func _on_SteamLobbies_pressed():
	Steam.addRequestLobbyListDistanceFilter(3)
	Steam.addRequestLobbyListStringFilter("game", "Brotatogether", 0)
	Steam.requestLobbyList()
	
	#TODO move this elsewhere
	game_controller.connection = steam_connection
	steam_connection.parent = game_controller
	
	print_debug("pressed steam lobbies button")
	
func _on_CreateSteamLobby_pressed():
	if lobby_id == 0:
		# first param is visibility, 2 for public
		Steam.createLobby(2, 5)
		
		# TODO move this elsewhere
		game_controller.is_host = true
		game_controller.connection = steam_connection
		
		steam_connection.parent = game_controller
	else:
		steam_connection.send_handshakes()
