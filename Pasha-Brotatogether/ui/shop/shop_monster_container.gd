extends HBoxContainer

#onready var _label = $Label
var game_controller

# TODO rename to work for all types
func init(shop_option: Resource, parent_game_controller) -> void:
	game_controller = parent_game_controller
	var price: int = shop_option.price
	var effect: Resource = shop_option.effect
	var display_text: String = shop_option.display_text
	
	get_node("Title").text = display_text
	get_node("BuyButton") .connect("pressed", self, "_on_buyButton_pressed", [shop_option])
	
	print_debug("we set the text ", display_text)
	
	if effect is WaveGroupData:
		for wave_unit_data in effect.wave_units_data:
			var enemy = wave_unit_data.unit_scene.instance()
			get_node("Icon").texture = enemy.get_node("Animation/Sprite").texture
			
	get_node("BuyButton").text = str(shop_option.price)
	
func _on_buyButton_pressed(shop_option: Resource) -> void:
	var price = shop_option.price
	if RunData.gold >= price:
		RunData.remove_gold(price)
		game_controller.send_bought_item(shop_option)
		
		$"/root/Shop"._shop_items_container.update_buttons_color()
