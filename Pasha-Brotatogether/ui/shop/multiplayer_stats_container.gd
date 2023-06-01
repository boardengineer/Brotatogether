extends StatsContainer

onready var game_controller = $"/root/GameController"

const shop_options_resource = preload("res://mods-unpacked/Pasha-Brotatogether/opponents_shop/data/opponents_shop_options.tres")
const shop_monster_container_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/shop/shop_monster_container.tscn")

func _ready():
	var opponents_shop = $MarginContainer/VBoxContainer2/OpponentsShop
	for opponents_shop_option in shop_options_resource.shop_options:
		var shop_option = shop_monster_container_scene.instance()
		shop_option.init(opponents_shop_option, game_controller)
		opponents_shop.add_child(shop_option)

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
	update_tab(3)

func update_bought_items(tracked_players:Dictionary) -> void:
	var opponents_shop = $MarginContainer/VBoxContainer2/OpponentsShop
	for shop_item_container in opponents_shop.get_children():
		shop_item_container.clear_player_counts()
		for tracked_player_id in tracked_players:
			for effect_path in tracked_players[tracked_player_id]["extra_enemies_next_wave"]:
				if effect_path == shop_item_container._shop_option.effect.get_path():
					var tracked_player = tracked_players[tracked_player_id]
					var count = tracked_player["extra_enemies_next_wave"][effect_path]
					var display_name = str(tracked_player_id)
					if tracked_player.has("username"):
						display_name = tracked_player["username"]
					
					shop_item_container.add_player_count(display_name, count)
