extends HBoxContainer

onready var selected_character_element := get_node("%SelectedCharacter")
onready var selected_weapon_element := get_node("%SelectedWeapon")
onready var selected_danger_element := get_node("%SelectedDanger")
onready var username_label := get_node("%Username")
onready var ready_toggle := get_node("%ReadyToggle")


func _ready():
	pass
#	selected_character_element.set_element(load("res://items/characters/arms_dealer/arms_dealer_data.tres"))


func set_player_name(name:String) -> void:
	username_label.text = name


func disable_selections() -> void:
	selected_character_element.disabled = true
	selected_weapon_element.disabled = true


func hide_ready_toggle() -> void:
	ready_toggle.hide()


func disable_ready_toggle() -> void:
	ready_toggle.disabled = true


func _on_SelectedCharacter_element_pressed(element):
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.character_selection_scene)


func _on_SelectedWeapon_element_pressed(element):
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.weapon_selection_scene)


func set_player_selections(selections_dict : Dictionary, is_me:bool = false) -> void:
	if selections_dict.has("character"):
		var character_id = selections_dict["character"]
		for character in ItemService.characters:
			if character.my_id == character_id:
				selected_character_element.set_element(character)
				break
			if is_me:
				selected_weapon_element.disabled = false
	else:
		selected_weapon_element.disabled = true
		selected_danger_element.disabled = true
	
	if selections_dict.has("weapon"):
		var weapon_id = selections_dict["weapon"]
		for weapon in ItemService.weapons:
			if weapon.my_id == weapon_id:
				selected_weapon_element.set_element(weapon)
				break
	else:
		selected_danger_element.disabled = true
	
	if selections_dict.has("danger"):
		var danger_id = selections_dict["danger"]
		for difficulty in ItemService.difficulties:
			if difficulty.my_id == danger_id:
				selected_danger_element.set_element(difficulty)
				break


func _on_select_danger_element_pressed(element):
	$"/root/GameController".back_to_lobby = true
	var _error = get_tree().change_scene(MenuData.difficulty_selection_scene)
