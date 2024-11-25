extends HBoxContainer

var username := "Test Username"
var message := "Test Message"

onready var username_label = $"%Username"
onready var message_label = $"%Message"


func _ready():
	username_label.text = username
	message_label.text = message
