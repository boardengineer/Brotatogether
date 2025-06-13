extends "res://ui/menus/run/character_selection.gd"

const ChatPanel = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat_panel.tscn")
const ChatMessage = preload("res://mods-unpacked/Pasha-Brotatogether/ui/chat/chat_message.tscn")
const UsernameLabel = preload("res://mods-unpacked/Pasha-Brotatogether/ui/username_label.tscn")

const MULTIPLAYER_CLIENT_PLAYER_TYPE = 10

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

var inventory_by_string_key : Dictionary

var username_labels = []

func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("global_chat_received", self, "_received_global_chat")
	steam_connection.connect("game_lobby_chat_received", self, "_received_lobby_chat")
	steam_connection.connect("player_focused_character", self, "_player_focused_character")
	steam_connection.connect("player_selected_character", self, "_player_selected_character")
	steam_connection.connect("character_lobby_update", self, "_lobby_characters_updated")
	steam_connection.connect("request_character_lobby_update", self, "_character_lobby_update_requested")
	steam_connection.connect("character_selection_complete", self, "_host_character_selection_complete")
	
	# TODO gracefully add new players
	steam_connection.connect("lobby_players_updated", self, "reload_scene")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	
	if is_multiplayer_lobby:
		ProgressData.settings.coop_mode_toggled = true
		_coop_button.init()
		_coop_button.hide()
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
		
		var username_label_player_1 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel1".add_child(username_label_player_1)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel1".move_child(username_label_player_1, 0)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel1/MarginContainer".set("custom_constants/margin_top", 50)
		username_labels.push_back(username_label_player_1)
		
		var username_label_player_2 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel2".add_child(username_label_player_2)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel2".move_child(username_label_player_2, 0)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel2/MarginContainer".set("custom_constants/margin_top", 50)
		username_labels.push_back(username_label_player_2)
		
		var username_label_player_3 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel3".add_child(username_label_player_3)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel3".move_child(username_label_player_3, 0)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel3/MarginContainer".set("custom_constants/margin_top", 50)
		username_labels.push_back(username_label_player_3)
		
		var username_label_player_4 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel4".add_child(username_label_player_4)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel4".move_child(username_label_player_4, 0)
		$"MarginContainer/VBoxContainer/DescriptionContainer/Panel4/MarginContainer".set("custom_constants/margin_top", 50)
		username_labels.push_back(username_label_player_4)
		
		for index in steam_connection.lobby_member_names.size():
			username_labels[index].text = steam_connection.lobby_member_names[index]
		
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
		
		for member_index in steam_connection.lobby_members.size():
			var member_id = steam_connection.lobby_members[member_index]
			if member_id == steam_connection.steam_id:
				CoopService._add_player(0, MULTIPLAYER_CLIENT_PLAYER_TYPE)
			else:
				CoopService._add_player(100 + member_index, MULTIPLAYER_CLIENT_PLAYER_TYPE)
			
		for character_data in _get_all_possible_elements(0):
			inventory_by_string_key[character_item_to_string(character_data)] = character_data
		
		# Find the random element in the inventory
		for character_data in _get_inventories()[0].get_children():
			if character_data.is_random:
				inventory_by_string_key[character_item_to_string(character_data)] = character_data


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
	var new_message_node = ChatMessage.instance()
	new_message_node.message = message
	new_message_node.username = user
	global_chat_messsages.add_child(new_message_node)


func _received_lobby_chat(user, message) -> void:
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


func _on_element_focused(element:InventoryElement, inventory_player_index:int) -> void:
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		var element_string = ""
		if element.item != null:
			element_string = element.item.name
		elif element.is_random:
			element_string = "RANDOM"
		steam_connection.character_focused(element_string)


func character_item_to_string(item : Resource) -> String:
	if item == null:
		return "RANDOM"
	return item.name


func _player_focused_character(player_index : int , character : String) -> void:
	var selected_item = null
	if inventory_by_string_key.has(character):
		selected_item = inventory_by_string_key[character]
	_clear_selected_element(player_index)
	_player_characters[player_index] = selected_item
	
	var panel = _get_panels()[player_index]
	
	if panel.visible:
		if selected_item != null:
			if character == "RANDOM":
				panel.set_custom_data("RANDOM", selected_item.get_inventory_icon())
			else:
				panel.set_data(selected_item, player_index)


func _player_selected_character(player_index : int) -> void:
	_set_selected_element(player_index)


func reload_scene() -> void:
	$"/root/BrotogetherOptions".joining_multiplayer_lobby = true
	var _error = get_tree().change_scene(MenuData.character_selection_scene)


func _lobby_characters_updated(player_characters : Array, has_player_selected : Array) -> void:
	for player_index in player_characters.size():
		if player_characters[player_index] != null:
			_player_focused_character(player_index, player_characters[player_index])
	
	var all_selected = true
	for player_index in RunData.get_player_count():
		if has_player_selected[player_index]:
			_set_selected_element(player_index)
		else:
			all_selected = false
			_clear_selected_element(player_index)
	
	if all_selected and steam_connection.is_host():
		_selections_completed_timer.start()


func _set_selected_element(player_index:int) -> void:
	if _has_player_selected[player_index]:
		return
	
	._set_selected_element(player_index)
	
	if steam_connection.get_lobby_index_for_player(steam_connection.steam_id) == player_index:
		steam_connection.character_selected()


func _character_lobby_update_requested() -> void:
	var currently_focused_characters = []
	for panel in _get_panels():
		var selected_item = panel.item_data
		if selected_item == null:
			currently_focused_characters.push_back("RANDOM")
		else:
			currently_focused_characters.push_back(character_item_to_string(selected_item))
	
	steam_connection.send_character_lobby_update(currently_focused_characters, _has_player_selected)


func _on_selections_completed() -> void:
	if is_multiplayer_lobby:
		if not steam_connection.is_host():
			return
	else:
		._on_selections_completed()
		return
	
	var currently_focused_characters = []
	# Sad dupe of inner logic to make things simpler
	for player_index in RunData.get_player_count():
		var chosen_item = _get_panels()[player_index]
		
		var character = _player_characters[player_index]
		if chosen_item.item_data == null:
			var available_elements: = []
			for element in ItemService.characters:
				if not element.is_locked:
					available_elements.push_back(element)
			character = Utils.get_rand_element(available_elements)
			_player_characters[player_index] = character
		
		RunData.add_character(character, player_index)
		currently_focused_characters.push_back(character_item_to_string(character))
	
	steam_connection.send_character_selection_completed(RunData.some_player_has_weapon_slots(), currently_focused_characters)
	if RunData.some_player_has_weapon_slots():
		_change_scene(MenuData.weapon_selection_scene)
	else:
		_change_scene(MenuData.difficulty_selection_scene)
	

func _host_character_selection_complete(some_player_has_weapon_slots : bool, selected_characters : Array) -> void:
	# Sad dupe of inner logic to make things simpler
	for player_index in selected_characters.size():
		if selected_characters[player_index] != null:
			_player_focused_character(player_index, selected_characters[player_index])
	
	for player_index in RunData.get_player_count():
		var character = _player_characters[player_index]
		RunData.add_character(character, player_index)
	
	if some_player_has_weapon_slots:
		_change_scene(MenuData.weapon_selection_scene)
	else:
		_change_scene(MenuData.difficulty_selection_scene)
