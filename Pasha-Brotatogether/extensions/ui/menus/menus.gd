extends "res://ui/menus/menus.gd"

var _menu_multiplayer = preload("res://mods-unpacked/Pasha-Brotatogether/ui/multiplayer_menu.tscn").instance()

func _ready():
	._ready()
	var _error_multiplayer = _main_menu.connect("multiplayer_button_pressed", self, "on_multiplayer_button_pressed")


func on_multiplayer_button_pressed():
	add_child(_menu_multiplayer)
	switch(_main_menu, _menu_multiplayer)
