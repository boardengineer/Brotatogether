extends Shop

func on_shop_item_bought(shop_item:ShopItem) -> void:
	if  $"/root".has_node("GameController"):
		var game_controller = $"/root/GameController"
		game_controller.send_bought_item_by_id(shop_item.item_data.my_id)
	.on_shop_item_bought(shop_item)
