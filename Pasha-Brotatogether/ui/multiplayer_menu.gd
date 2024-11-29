extends Control

# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

var lobby_id = 0

const ChatMessage = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat/chat_message.tscn")

const DirectConnection = preload("res://mods-unpacked/Pasha-Brotatogether/networking/direct_connection.gd")

var GameController = load("res://mods-unpacked/Pasha-Brotatogether/networking/game_controller.gd")

var direct_connection
var game_controller

var DEBUG = false

onready var chat_messages = $"%ChatMessages"
onready var chat_input : LineEdit = $"%ChatInput"

# Manual on ready vars
var steam_connection
var brotatogether_options

# Called when the node enters the scene tree for the first time.
func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("global_chat_received", self, "_received_global_chat")
	
	brotatogether_options = $"/root/BrotogetherOptions"


func _input(event:InputEvent)->void :
	manage_back(event)


func manage_back(event:InputEvent)->void :
	if event.is_action_pressed("ui_cancel"):
		RunData.current_zone = 0
		RunData.reload_music = false
		var _error = get_tree().change_scene(MenuData.title_screen_scene)


func _on_back_button_pressed():
	RunData.reload_music = false
	var _error = get_tree().change_scene(MenuData.title_screen_scene)


func _on_chat_input_text_entered(message):
	steam_connection.send_global_chat_message(message)
	chat_input.clear()


func _received_global_chat(user, message) -> void:
	var new_message_node = ChatMessage.instance()
	new_message_node.message = message
	new_message_node.username = user
	chat_messages.add_child(new_message_node)


func _on_create_lobby_button_pressed():
	steam_connection.create_new_game_lobby()
#	brotatogether_options.joining_multiplayer_lobby = true
#	var _error = get_tree().change_scene(MenuData.character_selection_scene)
