extends Node
class_name SteamConnection


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func _read_P2P_Packet() -> void:
	var packet_size = Steam.getAvailableP2PPacketSize(0)
