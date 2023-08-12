extends "res://items/global/effect.gd"

func multiplayer_apply(run_data):
	print_debug("applied effect ", key)
	
#	print_debug("applied effect before ", run_data.effects[key])
	
	if custom_key != "" or storage_method == StorageMethod.KEY_VALUE:
		run_data.effects[custom_key].push_back([key, value])
	elif storage_method == StorageMethod.REPLACE:
		base_value = run_data.effects[key]
		run_data.effects[key] = value
	else :
		run_data.effects[key] += value
		
#	print_debug("applied effect after ", run_data.effects[key])
	
func multiplayer_unapply(player_id):
	pass
