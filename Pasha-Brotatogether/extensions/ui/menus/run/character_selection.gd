extends "res://ui/menus/run/character_selection.gd"

const ChatPanel = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat_panel.tscn")
const ChatMessage = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat/chat_message.tscn")

var steam_connection
var brotatogether_options

var is_multiplayer_lobby = false

var global_chat_panel
var global_chat_messsages
var global_chat_input

var lobby_chat_panel
var lobby_chat_messsages
var lobby_chat_input

var panel_parent_container

var panels_array
var visible_panel_index : int = 0

func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("global_chat_received", self, "_received_global_chat")
	steam_connection.connect("game_lobby_chat_received", self, "_received_lobby_chat")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	brotatogether_options.joining_multiplayer_lobby = false
	
	if is_multiplayer_lobby:
		ProgressData.settings.coop_mode_toggled = true
		_coop_button.init()
		var run_options_top_panel = _run_options_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer")
		run_options_top_panel.remove_child(run_options_top_panel.get_node("Icon"))
		
		# Add left and right buttons to the heading
		var run_options_left_arrow : TextureButton = TextureButton.new()
		run_options_left_arrow.texture_normal = load("res://ui/menus/global/arrow_left.png")
		run_options_top_panel.add_child(run_options_left_arrow)
		run_options_top_panel.move_child(run_options_left_arrow, 0)
		var _err = run_options_left_arrow.connect("pressed", self, "_on_pressed_left_menu_arrow")
		
		var run_options_right_arrow : TextureButton = TextureButton.new()
		run_options_right_arrow.texture_normal = load("res://ui/menus/global/arrow_right.png")
		run_options_top_panel.add_child(run_options_right_arrow)
		_err =  run_options_right_arrow.connect("pressed", self, "_on_pressed_right_menu_arrow")
		
		panel_parent_container = _run_options_panel.get_parent()
		
		global_chat_panel = ChatPanel.instance()
		global_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/ChatTitle").text = "Global Chat"
		var global_chat_left_arrow = global_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/LeftArrow")
		_err = global_chat_left_arrow.connect("pressed", self, "_on_pressed_left_menu_arrow")
		var global_chat_right_arrow = global_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/RightArrow")
		_err = global_chat_right_arrow.connect("pressed", self, "_on_pressed_right_menu_arrow")
		panel_parent_container.add_child_below_node(_run_options_panel, global_chat_panel)
		
		global_chat_messsages = global_chat_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/ChatMessages")
		global_chat_input = global_chat_panel.get_node("MarginContainer/VBoxContainer/ChatInput")
		global_chat_input.connect("text_entered", self, "_on_global_chat_text_entered")
		
		lobby_chat_panel = ChatPanel.instance()
		lobby_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/ChatTitle").text = "Lobby Chat"
		var lobby_chat_left_arrow = lobby_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/LeftArrow")
		_err = lobby_chat_left_arrow.connect("pressed", self, "_on_pressed_left_menu_arrow")
		var lobby_chat_right_arrow = lobby_chat_panel.get_node("MarginContainer/VBoxContainer/HBoxContainer/RightArrow")
		_err = lobby_chat_right_arrow.connect("pressed", self, "_on_pressed_right_menu_arrow")
		panel_parent_container.add_child_below_node(_run_options_panel, lobby_chat_panel)
		
		lobby_chat_messsages = lobby_chat_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/ChatMessages")
		lobby_chat_input = lobby_chat_panel.get_node("MarginContainer/VBoxContainer/ChatInput")
		lobby_chat_input.connect("text_entered", self, "_on_lobby_chat_text_entered")
		
		panels_array = [_run_options_panel, global_chat_panel, lobby_chat_panel]
		update_panel_visiblility()


func _on_pressed_left_menu_arrow() -> void:
	visible_panel_index = (visible_panel_index - 1 + panels_array.size()) % panels_array.size()
	update_panel_visiblility()
 

func _on_pressed_right_menu_arrow() -> void:
	visible_panel_index = (visible_panel_index + 1) % panels_array.size()
	update_panel_visiblility()


func update_panel_visiblility() -> void:
	for index in panels_array.size():
		if index == visible_panel_index:
			panels_array[index].visible = true
		else:
			panels_array[index].visible = false


func _received_global_chat(user, message) -> void:
	print_debug("received global chat")
	var new_message_node = ChatMessage.instance()
	new_message_node.message = message
	new_message_node.username = user
	global_chat_messsages.add_child(new_message_node)


func _received_lobby_chat(user, message) -> void:
	print_debug("received lobby chat")
	var new_message_node = ChatMessage.instance()
	new_message_node.message = message
	new_message_node.username = user
	lobby_chat_messsages.add_child(new_message_node)


func _on_global_chat_text_entered(message):
	steam_connection.send_global_chat_message(message)
	global_chat_input.clear()


func _on_lobby_chat_text_entered(message):
	steam_connection.send_lobby_chat_message(message)
	lobby_chat_input.clear()
