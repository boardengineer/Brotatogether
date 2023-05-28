extends WaveManager

var test_group = preload("res://mods-unpacked/Pasha-Brotatogether/enemy_data/group_1.tres")

func init(p_wave_timer:Timer, wave_data:Resource)->void :
	.init(p_wave_timer, wave_data)
	
	var altered_group = test_group.duplicate()
	
	current_wave_data.groups_data.push_back(altered_group)
