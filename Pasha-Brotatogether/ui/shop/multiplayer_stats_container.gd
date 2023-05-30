extends StatsContainer

onready var opponents_shop = $MarginContainer/VBoxContainer2/OpponentsShop
onready var game_controller = $"/root/GameController"

const shop_options_resource = preload("res://mods-unpacked/Pasha-Brotatogether/opponents_shop/data/opponents_shop_options.tres")
const shop_monster_container_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/shop/shop_monster_container.tscn")

func _ready():
	for opponents_shop_option in shop_options_resource.shop_options:
		var shop_option = shop_monster_container_scene.instance()
		shop_option.init(opponents_shop_option, game_controller)
		opponents_shop.add_child(shop_option)
		print_debug("opponents_shop_option ", opponents_shop_option.display_text)

func update_tab(tab:int)->void :
	var has_opponents_tab = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer/MarginContainer/VBoxContainer2".has_node("OpponentsButton")
	
	if tab == 3:
		if has_opponents_tab:
			var opponents_button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer/MarginContainer/VBoxContainer2/OpponentsButton"
			var opponents_shop = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer/MarginContainer/VBoxContainer2/OpponentsShop"
			opponents_button.flat = true
			opponents_shop.show()
		_primary_tab.flat = false
		_secondary_tab.flat = false
		_general_stats.hide()
		_primary_stats.hide()
		_secondary_stats.hide()
		pass
	else:
		if has_opponents_tab:
			var opponents_button = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer/MarginContainer/VBoxContainer2/OpponentsButton"
			var opponents_shop = $"/root/Shop/Content/MarginContainer/HBoxContainer/VBoxContainer2/StatsContainer/MarginContainer/VBoxContainer2/OpponentsShop"	
			opponents_button.flat = false
			opponents_shop.hide()
		.update_tab(tab)


func _on_OpponentsButton_pressed():
	print_debug("here 1")
	update_tab(3)
