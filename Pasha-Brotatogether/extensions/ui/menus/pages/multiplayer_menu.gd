extends VBoxContainer


# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

onready var text_box = $"HBoxContainer/InfoBox/Label"
onready var ip_box = $"HBoxContainer/InfoBox/ServerIp"

var lobby_id = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	Steam.connect("lobby_created", self, "_on_Lobby_Created")
	Steam.connect("lobby_match_list", self, "_on_Lobby_Match_List")
	Steam.connect("lobby_joined", self, "_on_Lobby_Joined")
	Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	pass # Replace with function body.

func _on_ServerButton_pressed():
	var peer = NetworkedMultiplayerENet.new()
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	
	$"/root/networking".self_peer_id = 1
	
	get_tree().network_peer = peer
	
	$"/root/networking".rpc_id(1, "register_player")
	text_box.text = str(error)

func _on_ClientButton_pressed():
	var peer = NetworkedMultiplayerENet.new()
	var error = peer.create_client(ip_box.text, SERVER_PORT)
	
	get_tree().network_peer = peer
	text_box.text = str(get_tree().get_current_scene().get_name())

func _on_StartButton_pressed():
	
	$"/root/networking".rpc("start_game", {"current_wave":1})
	RunData.add_character(preload("res://items/characters/well_rounded/well_rounded_data.tres"))
	RunData.add_weapon(preload("res://weapons/melee/dagger/1/dagger_data.tres"), true)
#	RunData.add_weapon(preload("res://weapons/ranged/pistol/1/pistol_data.tres"), true)
	get_tree().change_scene(MenuData.game_scene)

func _on_SteamLobbies_pressed():
	Steam.addRequestLobbyListDistanceFilter(3)
	Steam.addRequestLobbyListStringFilter("game", "Brotatogether", 0)
	Steam.requestLobbyList()
	print_debug("pressed steam lobbies button")
	
func _on_Lobby_Match_List(lobbies: Array):
	print_debug("lobbies ", lobbies)
	if lobbies.size() == 1:
		Steam.joinLobby(lobbies[0])
	pass

func _on_CreateSteamLobby_pressed():
	if lobby_id == 0:
		# first param is visibility, 2 for public
		Steam.createLobby(2, 5)
		
func _on_Lobby_Created(connect: int, connected_lobby_id: int) -> void:
	if connect == 1:
		print_debug("Lobby Created: ", connected_lobby_id)
		lobby_id = connected_lobby_id
		
		Steam.setLobbyData(lobby_id, "game", "Brotatogether")
		Steam.allowP2PPacketRelay(true)
	pass

func _on_Lobby_Joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	print_debug("joined lobby ", lobby_id, " with permissions ", _permissions)
	
func _on_Lobby_Chat_Update(lobby_id: int, change_id: int, making_change_id: int, chat_state: int) -> void:
	var changer = Steam.getFriendPersonaName(change_id)
	print_debug("something changed with ", changer)
