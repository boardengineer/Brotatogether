extends "res://singletons/utils.gd"

# Host-authoritative effective stats for REMOTE players, propagated via the reliable
# co-op shop packet (coop_shop.gd STATS key). Keyed [player_index][stat_hash] -> float.
# On a client, get_stat serves these for any index the packet covered, so every stats
# panel (shop stat containers, popups) shows the HOST's computed truth instead of the
# client's locally-drifted RunData/LinkedStats view. Never populated for the local
# player's own index, and always empty on the host. Cleared on leave_game_lobby.
var remote_player_stats := {}


func get_stat(stat_hsh: int, player_index: int) -> float:
	if remote_player_stats.has(player_index):
		var stats = remote_player_stats[player_index]
		if stats.has(stat_hsh):
			return stats[stat_hsh]
	return .get_stat(stat_hsh, player_index)


func is_player_action_released(event: InputEvent, player_index: int, action: String)->bool:
	if CoopService.get_remapped_player_device(player_index) >= 50:
		return false
	
	return .is_player_action_released(event, player_index, action)
