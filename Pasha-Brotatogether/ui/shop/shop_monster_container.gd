extends VBoxContainer
class_name ShopMonsterContainer

var _shop_option
var game_controller

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
			
	get_node("ShopItem/VBoxContainer/BuyButton").text = str(price)
	
func _on_buyButton_pressed(shop_option: Resource) -> void:
	var price = shop_option.price
	if RunData.gold >= price:
		RunData.remove_gold(price)
		game_controller.send_bought_item(shop_option)
		
		$"/root/Shop"._shop_items_container.update_buttons_color()
		
func add_player_count(username:String, count: int) -> void:
	var label = Label.new()
	label.text = str(username, "-", count)
	
	get_node("PurchaseTracker").add_child(label)
	
func clear_player_counts() -> void:
	var purchase_tracker = get_node("PurchaseTracker")
	for child in purchase_tracker.get_children():
		purchase_tracker.remove_child(child)
