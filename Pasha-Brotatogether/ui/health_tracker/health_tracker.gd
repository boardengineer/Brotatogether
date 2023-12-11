extends VBoxContainer

var health_bar_map = {}

const HealthBar = preload("res://ui/hud/ui_progress_bar.tscn")

func init(tracked_players:Dictionary) -> void:
	var life_bar = $TemplateLifeBar
	
	for tracked_player_id in tracked_players:
		var health_bar = life_bar.duplicate()
		add_child(health_bar)
		health_bar_map[tracked_player_id] = health_bar
		
	remove_child(life_bar)
	update_health_bars(tracked_players)
	
func update_health_bars(tracked_players:Dictionary) -> void:
	for tracked_player_id in tracked_players:
		var player = tracked_players[tracked_player_id]
		var health_bar = health_bar_map[tracked_player_id]
		
		if player.has("username"):
			var name_label = health_bar.get_node("NameLabel")
			name_label.text = str(player.username)
		
		var current_health = 15
		var max_health = 15
		
		
		if player.has("player") and is_instance_valid(player.player):
			current_health = player.player.current_stats.health
			max_health = player.player.max_stats.health
		
		
		if max_health != 0:
			health_bar.update_value(current_health, max_health)
			
			var life_label = health_bar.get_node("MarginContainer/LifeLabel")
			life_label.text = str(max(current_health, 0.0)) + " / " + str(max_health)
