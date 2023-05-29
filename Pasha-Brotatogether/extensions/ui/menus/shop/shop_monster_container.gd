extends HBoxContainer

#onready var _label = $Label
var game_controller

# TODO rename to work for all types
func init(shop_option: Resource, parent_game_controller) -> void:
	game_controller = parent_game_controller
	var price: int = shop_option.price
	var effect: Resource = shop_option.effect
	var display_text: String = shop_option.display_text
	
	var buy_button = get_node("Label") 
	buy_button.text = display_text
	
	buy_button.connect("pressed", self, "_on_buyButton_pressed", [shop_option])
	
	print_debug("we set the text ", display_text)
	
	if effect is WaveGroupData:
		for wave_unit_data in effect.wave_units_data:
			var enemy = wave_unit_data.unit_scene.instance()
			get_node("Icon").texture = enemy.get_node("Animation/Sprite").texture
			
	get_node("Value").text = str(shop_option.price)
	
func _on_buyButton_pressed(shop_option: Resource) -> void:
	game_controller.send_bought_item(shop_option)
	print_debug("pressed buy button ", shop_option.effect.get_path())
