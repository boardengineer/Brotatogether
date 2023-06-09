extends VBoxContainer
class_name ShopMonsterContainer

var _shop_option
var game_controller

const count_label_scene = preload("res://mods-unpacked/Pasha-Brotatogether/ui/shop/count_label.tscn")

# TODO rename to work for all types
func init(shop_option: Resource, parent_game_controller) -> void:
	game_controller = parent_game_controller
	_shop_option = shop_option
	var price: int = shop_option.price
	var effect: Resource = shop_option.effect
	var display_text: String = shop_option.display_text
	
	get_node("ShopItem/Title").text = display_text
	var _connection_error = get_node("ShopItem/VBoxContainer/BuyButton").connect("pressed", self, "_on_buyButton_pressed", [shop_option])
	
	if effect is WaveGroupData:
		for wave_unit_data in effect.wave_units_data:
			var enemy = wave_unit_data.unit_scene.instance()
			get_node("ShopItem/Icon").texture = enemy.get_node("Animation/Sprite").texture
	elif effect is Effect:
		if effect.key.begins_with("stat_"):
			get_node("ShopItem/Icon").texture = ItemService.get_stat_icon(effect.key)
		
	var adjusted_price = ItemService.get_value(RunData.current_wave, price, true, true)
	get_node("ShopItem/VBoxContainer/BuyButton").text = str(adjusted_price)
	
func _on_buyButton_pressed(shop_option: Resource) -> void:
	var adjusted_price = ItemService.get_value(RunData.current_wave, shop_option.price, true, true)
	if RunData.gold >= adjusted_price:
		RunData.remove_gold(adjusted_price)
		game_controller.send_bought_item(shop_option)
		
		$"/root/Shop"._shop_items_container.update_buttons_color()
		
func add_player_count(username:String, count: int) -> void:
	var label = count_label_scene.instance()
	label.text = str(username, "-", count)
	
	get_node("PurchaseTracker").add_child(label)
	
func clear_player_counts() -> void:
	var purchase_tracker = get_node("PurchaseTracker")
	for child in purchase_tracker.get_children():
		purchase_tracker.remove_child(child)
