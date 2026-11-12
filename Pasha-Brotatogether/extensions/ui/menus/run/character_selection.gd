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

# Mapped inventory item by item keys.  Used to reset focus based on external
# calls.
var inventory_by_string_key : Dictionary

# Mapped Selections by item keys.  Kept independent of itnentory items to
# avoid complications around randoms, locked items, etc.
var selections_by_string_key : Dictionary

var username_labels = []
var external_focus = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	steam_connection.connect("global_chat_received", self, "_received_global_chat")
	steam_connection.connect("game_lobby_chat_received", self, "_received_lobby_chat")
	steam_connection.connect("player_focused_character", self, "_player_focused_character")
	steam_connection.connect("player_selected_character", self, "_player_selected_character")
	steam_connection.connect("character_lobby_update", self, "_lobby_characters_updated")
	steam_connection.connect("request_character_lobby_update", self, "_character_lobby_update_requested")
	steam_connection.connect("character_selection_complete", self, "_host_character_selection_complete")
	
	# A join still reloads the scene (the simplest way to grow the vanilla panel set); a leave
	# is handled in place so the remaining players keep their picks.
	steam_connection.connect("lobby_players_updated", self, "reload_scene")
	steam_connection.connect("lobby_roster_changed", self, "_on_lobby_roster_changed")
	steam_connection.connect("lobby_slots_updated", self, "_refresh_slot_controls")
	
	brotatogether_options = $"/root/BrotogetherOptions"
	is_multiplayer_lobby = brotatogether_options.joining_multiplayer_lobby
	
	if is_multiplayer_lobby:
		RunData.is_coop_run = true
		# Vanilla _ready already ran init(), which connects "toggled"; a second init()
		# double-connects it (the CoopButton "already connected" error). Only re-read pressed.
		if _coop_button.is_connected("toggled", _coop_button, "_on_toggled"):
			_coop_button.pressed = RunData.play_mode != RunData.PlayMode.SOLO
		else:
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
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel1/vboxContainer".add_child(username_label_player_1)
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel1/vboxContainer".move_child(username_label_player_1, 0)
		username_labels.push_back(username_label_player_1)
		
		var username_label_player_2 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel2/vboxContainer".add_child(username_label_player_2)
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel2/vboxContainer".move_child(username_label_player_2, 0)
		username_labels.push_back(username_label_player_2)
		
		var username_label_player_3 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel3/vboxContainer".add_child(username_label_player_3)
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel3/vboxContainer".move_child(username_label_player_3, 0)
		username_labels.push_back(username_label_player_3)
		
		var username_label_player_4 : Label = UsernameLabel.instance()
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel4/vboxContainer".add_child(username_label_player_4)
		$"MarginContainer/VBoxContainer/DescriptionContainer/HBoxContainer/Panel4/vboxContainer".move_child(username_label_player_4, 0)
		username_labels.push_back(username_label_player_4)
		
		for index in steam_connection.lobby_member_names.size():
			username_labels[index].text = steam_connection.lobby_member_names[index]
		_build_slot_controls()
		
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
		
		panels_array = [_run_options_panel,  global_chat_panel, lobby_chat_panel]
		update_panel_visiblility()
		
		for member_index in steam_connection.lobby_members.size():
			var member_id = steam_connection.lobby_members[member_index]
			if member_id == steam_connection.steam_id:
				CoopService._add_player(0, MULTIPLAYER_CLIENT_PLAYER_TYPE)
			else:
				CoopService._add_player(100 + member_index, MULTIPLAYER_CLIENT_PLAYER_TYPE)
			
		for character_data in _get_all_possible_elements(0):
			selections_by_string_key[character_item_to_string(character_data)] = character_data
		
		# Find the random element in the inventory
		for character_data in _get_inventories()[0].get_children():
			if character_data.is_random:
				inventory_by_string_key[character_item_to_string(character_data)] = character_data
				selections_by_string_key[character_item_to_string(character_data)] = character_data
			else:
				inventory_by_string_key[character_item_to_string(character_data.item)] = character_data

		for panel in _get_panels():
			panel._small(true)


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


func _on_element_focused(element:InventoryElement, inventory_player_index:int, _displayPanelData: bool = true) -> void:
	._on_element_focused(element, inventory_player_index)
	
	if is_multiplayer_lobby:
		var element_string = ""
		if element.item != null:
			element_string = element.item.name
		elif element.is_random:
			element_string = "RANDOM"
		if not external_focus:
			steam_connection.character_focused(element_string)
		else:
			external_focus = false


func character_item_to_string(item : Resource) -> String:
	if item == null:
		return "RANDOM"
	return item.name


func _player_focused_character(player_index : int , character : String) -> void:
	var selected_item = null
	var focused_element = null
	
	if selections_by_string_key.has(character):
		selected_item = selections_by_string_key[character]
		
	if inventory_by_string_key.has(character):
		focused_element = inventory_by_string_key[character]
		
	_clear_selected_element(player_index)
	_player_characters[player_index] = selected_item
	if player_index < RunData.get_player_count() and player_index != steam_connection.get_my_index():
		if focused_element != null:
			if Utils.get_focus_emulator(player_index).focused_control != focused_element:
				external_focus = true
				Utils.get_focus_emulator(player_index).focused_control = focused_element
	
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
	for player_index in RunData.get_player_count():
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

	if brotatogether_options.is_solo_test:
		var all_selected = true
		for i in RunData.get_player_count():
			if not _has_player_selected[i]:
				all_selected = false
				break
		if all_selected:
			CoopService.listening_for_inputs = false
			_selections_completed_timer.start()

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
				# 1.2: a character can need an item set the host has switched off.
				if not element.is_locked and _get_item_disabled_update(element) == null:
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


# --- Lobby slot controls ------------------------------------------------------------------
# Per slot (index = player index): Kick under an occupied name (host), a "Waiting for a
# player..." box on the vanilla CoopJoinPanel of an empty slot (+ Lock for the host), and the
# vanilla LockedPanel re-labelled "Slot locked" for a closed slot (+ Unlock for the host). Lock
# state lives in SteamConnection.locked_slots (host publishes it; Steam's member limit follows).
var _slot_kick_buttons := []
var _slot_lock_buttons := []
var _slot_unlock_buttons := []
var _slot_wait_boxes := []      # our CenterContainer inside each CoopJoinPanel
var _slot_controls_built := false
const EMPTY_SLOT_WIDTH := 160   # px; player panel 370 + run options 320 + gaps must fit 1920


func _build_slot_controls() -> void:
	if not is_multiplayer_lobby or _slot_controls_built:
		return
	_slot_controls_built = true
	var host = steam_connection.is_host()
	var join_panels = _get_coop_join_panels()
	var locked_panels = _get_locked_panels()
	for i in username_labels.size():
		var kick : Button = null
		if host:
			kick = Button.new()
			kick.text = "Kick"
			kick.connect("pressed", self, "_on_kick_pressed", [i])
			var holder = username_labels[i].get_parent()
			holder.add_child(kick)
			holder.move_child(kick, username_labels[i].get_index() + 1)
		if host and i == 0:
			var invite := Button.new()
			invite.text = "Invite friends"
			invite.connect("pressed", self, "_on_invite_pressed")
			var holder0 = username_labels[0].get_parent()
			holder0.add_child(invite)
			holder0.move_child(invite, username_labels[0].get_index() + 1)
		_slot_kick_buttons.push_back(kick)

		var wait_box : CenterContainer = null
		var lock : Button = null
		if i < join_panels.size() and join_panels[i] != null:
			var jp = join_panels[i]
			# Vanilla parks all four CoopJoinPanels at the END of the row, so an open slot always
			# rendered at the far right whichever slot was unlocked. Seat it right after its own
			# LockedPanel so open / locked / occupied all draw in the slot's position.
			if i < locked_panels.size() and locked_panels[i] != null and jp.get_parent() == locked_panels[i].get_parent():
				jp.get_parent().move_child(jp, locked_panels[i].get_index() + 1)
			# Vanilla sizes these for the local-coop join instructions (370 px); three of them next
			# to a player panel and the run-options panel overflow 1920 px, so keep empty slots narrow.
			jp.rect_min_size = Vector2(EMPTY_SLOT_WIDTH, 0)
			wait_box = CenterContainer.new()
			wait_box.size_flags_horizontal = SIZE_EXPAND_FILL
			wait_box.size_flags_vertical = SIZE_EXPAND_FILL
			var box = VBoxContainer.new()
			box.alignment = BoxContainer.ALIGN_CENTER
			var wait_label = Label.new()
			wait_label.text = "Open slot"
			wait_label.align = Label.ALIGN_CENTER
			box.add_child(wait_label)
			if host and i > 0:
				lock = Button.new()
				lock.text = "Lock"
				lock.connect("pressed", self, "_on_lock_pressed", [i, true])
				box.add_child(lock)
			wait_box.add_child(box)
			jp.add_child(wait_box)
		_slot_wait_boxes.push_back(wait_box)
		_slot_lock_buttons.push_back(lock)

		var unlock : Button = null
		if i < locked_panels.size() and locked_panels[i] != null:
			var lp = locked_panels[i]
			lp.rect_min_size = Vector2(EMPTY_SLOT_WIDTH, 0)
			var desc = lp.get_node_or_null("MarginContainer/VBoxContainer/Description")
			if desc != null:
				desc.text = "Locked"
			if host and i > 0:
				unlock = Button.new()
				unlock.text = "Unlock"
				unlock.connect("pressed", self, "_on_lock_pressed", [i, false])
				var vbox = lp.get_node_or_null("MarginContainer/VBoxContainer")
				if vbox != null:
					vbox.add_child(unlock)
		_slot_unlock_buttons.push_back(unlock)
	_refresh_slot_controls()


func _refresh_slot_controls() -> void:
	if not is_multiplayer_lobby or not _slot_controls_built:
		return
	var occupied = steam_connection.lobby_members.size()
	var join_panels = _get_coop_join_panels()
	var locked_panels = _get_locked_panels()
	for i in username_labels.size():
		username_labels[i].text = steam_connection.lobby_member_names[i] if i < steam_connection.lobby_member_names.size() else ""
		var is_occupied = i < occupied
		var is_locked = (not is_occupied) and i < steam_connection.locked_slots.size() and steam_connection.locked_slots[i]
		if _slot_kick_buttons[i] != null:
			_slot_kick_buttons[i].visible = is_occupied and i > 0
		if i < join_panels.size() and join_panels[i] != null:
			var jp = join_panels[i]
			jp.visible = not is_occupied and not is_locked
			# Only our waiting box shows; vanilla's "press to join" content is for local co-op.
			for child in jp.get_children():
				child.visible = child == _slot_wait_boxes[i]
		if i < locked_panels.size() and locked_panels[i] != null:
			locked_panels[i].visible = is_locked
		if _slot_lock_buttons[i] != null:
			_slot_lock_buttons[i].visible = not is_occupied and not is_locked
		if _slot_unlock_buttons[i] != null:
			_slot_unlock_buttons[i].visible = is_locked


func _on_lock_pressed(slot : int, locked : bool) -> void:
	steam_connection.set_slot_locked(slot, locked)


# Vanilla re-shows join panels / hides locked panels whenever the player count changes;
# re-apply the lobby's slot state on top.
func _update_character_selection_player_count_ui() -> void:
	._update_character_selection_player_count_ui()
	_refresh_slot_controls()


func _on_kick_pressed(slot : int) -> void:
	steam_connection.kick_player(slot)


# A member left during character selection: drop its slot in place. Slots above it shift down,
# so the per-slot selection arrays shift with them; the host then resyncs everyone.
func _on_lobby_roster_changed(removed_indices : Array) -> void:
	if not is_multiplayer_lobby:
		return
	var idxs = removed_indices.duplicate()
	idxs.sort()
	idxs.invert()
	for idx in idxs:
		if idx <= 0 or idx >= RunData.get_player_count():
			continue
		# Raw device from connected_players: get_remapped_player_device is overridden by the
		# AutoBattler to hand bot slots a debug device, which is not what _remove_player keys on.
		var device = CoopService.connected_players[idx][0] if idx < CoopService.connected_players.size() else -1
		if idx < _player_characters.size():
			_player_characters.remove(idx)
			_player_characters.push_back(null)
		if idx < _has_player_selected.size():
			_has_player_selected.remove(idx)
			_has_player_selected.push_back(false)
		if device != -1:
			CoopService._remove_player(device)   # vanilla shrinks RunData + the panels via connected_players_updated
	var was_selected := []
	for i in RunData.get_player_count():
		was_selected.push_back(i < _has_player_selected.size() and _has_player_selected[i])
	for i in RunData.get_player_count():
		var character = _player_characters[i] if i < _player_characters.size() else null
		_player_focused_character(i, character_item_to_string(character))   # clears + refocuses the slot
		if was_selected[i]:
			._set_selected_element(i)
	_refresh_slot_controls()
	if steam_connection.is_host():
		_character_lobby_update_requested()


func _on_invite_pressed() -> void:
	steam_connection.invite_friends()
