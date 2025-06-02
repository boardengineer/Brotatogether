extends "res://visual_effects/floating_text/floating_text_manager.gd"

var steam_connection
var brotatogether_options
var in_multiplayer_game = false
var is_host = false


func _ready():
	steam_connection = $"/root/SteamConnection"
	brotatogether_options = $"/root/BrotogetherOptions"
	in_multiplayer_game = brotatogether_options.in_multiplayer_game
	
	if in_multiplayer_game:
		is_host = steam_connection.is_host()


func display(value: String, text_pos: Vector2, color: Color = Color.white, icon: Resource = null, p_duration: float = duration, always_display: bool = false, p_direction: Vector2 = direction, need_translate: bool = true, icon_scale: Vector2 = Vector2(0.5, 0.5))->void :
	.display(value, text_pos, color, icon, p_duration, always_display, p_direction, need_translate, icon_scale)
	
	if in_multiplayer_game and self.is_host:
		var text_dict = {}
		
		text_dict["X_POS"] = text_pos.x
		text_dict["Y_POS"] = text_pos.y
		text_dict["R_COLOR"] = color.r8
		text_dict["G_COLOR"] = color.g8
		text_dict["B_COLOR"] = color.b8
		text_dict["A_COLOR"] = color.a8
		text_dict["VALUE"] = value
		text_dict["DURATION"] = p_duration
		
#		brotatogether_options.batched_floating_text.push_back(text_dict)
