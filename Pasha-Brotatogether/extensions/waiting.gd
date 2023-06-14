extends Node2D

onready var message_label = $Message

# Called when the node enters the scene tree for the first time.
func _ready():
	var messages = []
	
	messages.push_back("THESE PRETZELS ARE MAKING ME THIRSTY")
	messages.push_back("support the dev -> get a better screen here")
	messages.push_back("SERENITY NOW")
	messages.push_back("(1/3) We must go forward not backward")
	messages.push_back("(2/3) Upward not forward")
	messages.push_back("(3/3) And always twirling, twirling, twirling towards freedom")
	messages.push_back("So you're telling me there's a chance")
	messages.push_back("Great Success!")
	messages.push_back("Bueller ... Bueller ... Bueller")
	messages.push_back("The dude abides")

	
	message_label.text = Utils.get_rand_element(messages)
