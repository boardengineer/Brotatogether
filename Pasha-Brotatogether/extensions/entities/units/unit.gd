extends Unit


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func take_damage(value:int, hitbox:Hitbox = null, dodgeable:bool = true, armor_applied:bool = true, custom_sound:Resource = null, base_effect_scale:float = 1.0)->Array:
	if dead:
		return [0, 0, 0]
	return .take_damage(value, hitbox, dodgeable, armor_applied, custom_sound, base_effect_scale)


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
