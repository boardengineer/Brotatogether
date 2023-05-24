extends VBoxContainer


# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

onready var text_box = $"HBoxContainer/InfoBox/Label"
onready var ip_box = $"HBoxContainer/InfoBox/ServerIp"

# Called when the node enters the scene tree for the first time.
func _ready():
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
