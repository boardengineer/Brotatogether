extends StatsContainer

func update_tab(tab:int)->void :
	if get_tree().get_current_scene().get_name() != "Shop":
		.update_tab(tab)
		return
	
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
	
