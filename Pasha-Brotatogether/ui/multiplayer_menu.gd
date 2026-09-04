extends Control

# must be greater than 1024
var SERVER_PORT = 11111
var MAX_PLAYERS = 5

const ChatMessage = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat/chat_message.tscn")
const LobbyEntry = preload("res://mods-unpacked/Pasha-Brotatogether/ui/lobby_entry.tscn")

const DirectConnection = preload("res://mods-unpacked/Pasha-Brotatogether/networking/direct_connection.gd")

var GameController = load("res://mods-unpacked/Pasha-Brotatogether/networking/game_controller.gd")

var direct_connection
var game_controller

var DEBUG = false

onready var chat_messages = $"%ChatMessages"
onready var lobbies_list = $"%Lobbies"
onready var chat_input : LineEdit = $"%ChatInput"
onready var create_lobby_button : Button = $"%CreateLobbyButton"

# Manual on ready vars
var steam_connection
var brotatogether_options

# "Friends only" toggle for the lobby we create; added next to the Create Lobby button in _ready.
var friends_only_checkbox : CheckBox

# Called when the node enters the scene tree for the first time.
func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("global_chat_received", self, "_received_global_chat")
	steam_connection.connect("game_lobby_found", self, "_game_lobby_found")
	steam_connection.connect("join_blocked", self, "_on_join_blocked")

	brotatogether_options = $"/root/BrotogetherOptions"

	for message in steam_connection.pending_system_messages:
		var new_message_node = ChatMessage.instance()
		new_message_node.message = message
		new_message_node.username = "SYSTEM"
		chat_messages.add_child(new_message_node)
	steam_connection.pending_system_messages.clear()

	# Add a "Friends only" checkbox next to Create Lobby (built in code so the decompiled .tscn
	# doesn't need editing). When ticked, the created lobby is only listed to the host's friends.
	friends_only_checkbox = CheckBox.new()
	friends_only_checkbox.text = "Friends only"
	create_lobby_button.get_parent().add_child(friends_only_checkbox)
	create_lobby_button.get_parent().move_child(friends_only_checkbox, create_lobby_button.get_index())

	create_lobby_button.grab_focus()
	CoopService.clear_coop_players()

	# var solo_test_btn = Button.new()
	# solo_test_btn.text = "Solo Test"
	# create_lobby_button.get_parent().add_child(solo_test_btn)
	# solo_test_btn.connect("pressed", self, "_on_solo_test_button_pressed")


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


func _on_join_blocked(reason) -> void:
	var new_message_node = ChatMessage.instance()
	new_message_node.message = "Cannot join that game:\n" + reason
	new_message_node.username = "SYSTEM"
	chat_messages.add_child(new_message_node)


func _on_solo_test_button_pressed() -> void:
	steam_connection.game_lobby_id = 1
	steam_connection.game_lobby_owner_id = steam_connection.steam_id
	steam_connection.lobby_members = [steam_connection.steam_id]
	steam_connection.lobby_member_names = [Steam.getFriendPersonaName(steam_connection.steam_id)]
	brotatogether_options.is_solo_test = true
	brotatogether_options.joining_multiplayer_lobby = true
	var _error = get_tree().change_scene(MenuData.character_selection_scene)


func _on_create_lobby_button_pressed():
	var friends_only = friends_only_checkbox != null and friends_only_checkbox.pressed
	steam_connection.create_new_game_lobby(friends_only)


func _on_refresh_lobbies_button_pressed():
	for child in lobbies_list.get_children():
		lobbies_list.remove_child(child)
	steam_connection.request_lobby_search()


func _game_lobby_found(lobby_id, lobby_name) -> void:
	var new_lobby_entry = LobbyEntry.instance()
	new_lobby_entry.lobby_id = lobby_id
	new_lobby_entry.lobby_name = lobby_name
	lobbies_list.add_child(new_lobby_entry)
