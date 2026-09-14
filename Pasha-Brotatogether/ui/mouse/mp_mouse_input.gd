extends Node

# Per-scene mouse handler for the local player in a multiplayer run (attached by
# ui/mouse/mp_mouse.gd as the scene's last child, so it sees mouse events before the
# FocusEmulators swallow them).
#
# Hover moves the local player's emulator focus onto the control under the cursor; a left click
# focuses it and presses it exactly the way the keyboard / gamepad accept does
# (FocusEmulator._press_button: FocusEmulatorSignal.emit(button, "pressed", player)). Every
# action therefore goes through the same handlers, player lookup and multiplayer sync as the
# local player's keyboard.
#
# Mouse events over ANOTHER player's panel are consumed and ignored. Events outside every
# player's panel pass through untouched (lobby chat, lobby slot buttons, ...). Modelled on the
# AutoBattler's lone-human mouse control, keyed on SteamConnection.get_my_index() instead of 0.

var _pending = null   # control a deferred hover focus was already queued for this frame
var debug_log := false   # set by the test harness (--bt-mouse-test)


func _process(_delta: float) -> void:
	_pending = null


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return
	var sc = get_node_or_null("/root/SteamConnection")
	if sc == null:
		return
	var me = sc.get_my_index()
	if me < 0 or me >= RunData.get_player_count():
		return
	var scene = get_parent()
	if scene == null:
		return
	match scene.name:
		"CharacterSelection":
			_character_selection(scene, me, event)
		"WeaponSelection":
			_weapon_selection(scene, me, event)
		"DifficultySelection":
			if sc.is_host():   # the danger level is the host's call
				_difficulty_selection(scene, me, event)
		"CoopShop":
			_shop(scene, me, event)
		"Main":
			_level_up(scene, me, event)


# ------------------------------------------------------------------------------ helpers --

static func _is_left_press(event) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT


static func _hit(control, pos: Vector2) -> bool:
	return control != null and is_instance_valid(control) and control is Control \
			and control.is_visible_in_tree() and control.get_global_rect().has_point(pos)


static func _first_hit(controls: Array, pos: Vector2):
	for control in controls:
		if _hit(control, pos):
			return control
	return null


func _consume() -> void:
	get_tree().set_input_as_handled()


static func _emulator(player_index: int, emulator):
	if emulator != null and is_instance_valid(emulator):
		return emulator
	return Utils.get_focus_emulator(player_index)


# Hover: move the player's focus (deferred, like Utils.focus_player_control everywhere else).
func _focus(control, player_index: int, emulator = null) -> void:
	var em = _emulator(player_index, emulator)
	if em == null or control == _pending or em.focused_control == control:
		return
	_pending = control
	Utils.focus_player_control(control, player_index, em)


# Click: focus now, then press the way the emulator's accept action does.
func _press(control, player_index: int, emulator = null) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	if control is BaseButton and control.disabled:
		return
	var em = _emulator(player_index, emulator)
	if em != null and em.focused_control != control:
		em.focused_control = control
	FocusEmulatorSignal.emit(control, "pressed", player_index)


func _hover_or_press(control, player_index: int, event, emulator = null) -> void:
	if event is InputEventMouseMotion:
		_focus(control, player_index, emulator)
	elif _is_left_press(event):
		_press(control, player_index, emulator)


static func _element_at(inventory, pos: Vector2):
	if inventory == null or not is_instance_valid(inventory) or not inventory.is_visible_in_tree():
		return null
	return _first_hit(inventory.get_children(), pos)


# Carousel arrows are disabled for multiplayer players (vanilla treats them as gamepads and
# pages with the triggers) and faded out at either end, so they are paged directly.
static func _page_carousel(carousel, pos: Vector2) -> bool:
	if carousel == null or not is_instance_valid(carousel) or not carousel.active:
		return false
	if _hit(carousel.arrow_left, pos) and carousel.arrow_left.modulate.a > 0.01:
		carousel._on_ArrowLeft_pressed()
		return true
	if _hit(carousel.arrow_right, pos) and carousel.arrow_right.modulate.a > 0.01:
		carousel._on_ArrowRight_pressed()
		return true
	return false


# --------------------------------------------------------------------------- selections --

# One shared grid; hovering shows the character in the local player's panel.
func _character_selection(scene, me: int, event) -> void:
	var inventories = scene._get_inventories()
	if inventories.empty():
		return
	var element = _element_at(inventories[0], event.position)
	if element == null:
		return
	_consume()
	if not scene._has_player_selected[me]:
		_hover_or_press(element, me, event)


# One grid per player; only the local player's grid responds.
func _weapon_selection(scene, me: int, event) -> void:
	var inventories = scene._get_inventories()
	for pi in inventories.size():
		var element = _element_at(inventories[pi], event.position)
		if element == null:
			continue
		_consume()
		if pi == me and not scene._has_player_selected[me]:
			_hover_or_press(element, me, event)
		return


func _difficulty_selection(scene, me: int, event) -> void:
	var inventories = scene._get_inventories()
	if inventories.empty() or scene.difficulty_selected:
		return
	var element = _element_at(inventories[0], event.position)
	if element == null:
		return
	_consume()
	_hover_or_press(element, me, event)


# ---------------------------------------------------------------------------------- shop --

static func _panel_owner(containers: Array, pos: Vector2) -> int:
	for pi in containers.size():
		if _hit(containers[pi], pos):
			return pi
	return -1


func _shop(scene, me: int, event) -> void:
	var pos: Vector2 = event.position
	var mine = scene._get_coop_player_container(me)
	if mine == null or not is_instance_valid(mine):
		return

	# A pressed owned weapon / item opens a focused popup (combine / discard / cancel) that can
	# overlap a neighbouring panel; while it is open only its buttons respond, as with a pad.
	var popup = mine.item_popup
	var popup_open = popup != null and is_instance_valid(popup) and popup.visible and popup._focused
	if popup_open:
		var button = _first_hit([popup._combine_button, popup._discard_button, popup._cancel_button], pos)
		if button != null:
			_consume()
			_hover_or_press(button, me, event)
			return

	var containers = []
	for pi in RunData.get_player_count():
		containers.push_back(scene._get_coop_player_container(pi))
	var panel_owner = _panel_owner(containers, pos)
	if debug_log and event is InputEventMouseButton and event.pressed:
		var car = mine.carousel
		print("BTMOUSE shop press pos=%s owner=%d me=%d popup_open=%s go_pressed=%s car_active=%s idx=%d arrowR=%s visR=%s aR=%.2f" % [str(pos), panel_owner, me, str(popup_open), str(scene._player_pressed_go_button[me]), str(car.active), car.index, str(car.arrow_right.get_global_rect()), str(car.arrow_right.is_visible_in_tree()), car.arrow_right.modulate.a])
	if panel_owner < 0:
		return
	_consume()
	if panel_owner != me or popup_open:
		return

	if _is_left_press(event) and _page_carousel(mine.carousel, pos):
		return

	var go_button = scene._get_go_button(me)
	if scene._player_pressed_go_button[me]:
		# Ready: only GO itself responds (un-ready); hovering away would clear the ready state.
		if _is_left_press(event) and _hit(go_button, pos):
			_press(go_button, me)
		return

	var target = null
	var items_container = scene._get_shop_items_container(me)
	if items_container != null:
		for item in items_container._shop_items:
			if is_instance_valid(item) and item.active and _hit(item, pos):
				target = item._button
				break
	if target == null:
		target = _first_hit([scene._get_reroll_button(me), go_button], pos)
	if target == null:
		var gear = scene._get_gear_container(me)
		if gear != null:
			for source in [gear.weapons_container, gear.items_container]:
				if source != null and is_instance_valid(source) and source._elements != null:
					target = _element_at(source._elements, pos)
					if target != null:
						break
	if target != null:
		_hover_or_press(target, me, event)


# --------------------------------------------------------------------- level-up chooser --

func _level_up(scene, me: int, event) -> void:
	if not ("_coop_upgrades_ui" in scene):
		return
	var ui = scene._coop_upgrades_ui
	if ui == null or not is_instance_valid(ui) or not ui.visible:
		return
	var pos: Vector2 = event.position
	var containers = []
	for pi in RunData.get_player_count():
		containers.push_back(ui._get_player_container(pi))
	var panel_owner = _panel_owner(containers, pos)
	if panel_owner < 0:
		return
	_consume()
	if panel_owner != me:
		return
	var container = containers[me]
	if container._checkmark_group.visible:
		return
	if _is_left_press(event) and _page_carousel(container.carousel, pos):
		return

	var candidates = []
	if container._upgrades_container.is_visible_in_tree():
		for card in [container._upgrade_ui_1, container._upgrade_ui_2, container._upgrade_ui_3, container._upgrade_ui_4]:
			if is_instance_valid(card) and card.upgrade_data != null:
				candidates.push_back(card.button)
		candidates.push_back(container._reroll_button)
	elif container._items_container.is_visible_in_tree():
		candidates = [container._take_button, container._discard_button]
	var target = _first_hit(candidates, pos)
	if target != null:
		_hover_or_press(target, me, event, container.focus_emulator)
