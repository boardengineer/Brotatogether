extends "res://items/global/effect.gd"

func multiplayer_apply(run_data) -> void:
	if custom_key != "" or storage_method == StorageMethod.KEY_VALUE:
		run_data.effects[custom_key].push_back([key, value])
	elif storage_method == StorageMethod.REPLACE:
		base_value = run_data.effects[key]
		run_data.effects[key] = value
	else :
		run_data.effects[key] += value
	
func multiplayer_unapply(run_data) -> void:
	if custom_key != "" or storage_method == StorageMethod.KEY_VALUE:
		run_data.effects[custom_key].erase([key, value])
	elif storage_method == StorageMethod.REPLACE:
		run_data.effects[key] = base_value
	else :
		run_data.effects[key] -= value
