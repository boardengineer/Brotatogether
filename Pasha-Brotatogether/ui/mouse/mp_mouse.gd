extends Node

# Mouse support for the LOCAL player in a Brotatogether multiplayer run (the AutoBattler's
# lone-human mouse control, generalised: every machine has exactly one local human, at
# SteamConnection.get_my_index()).
#
# Vanilla co-op is gamepad-first and blocks the mouse in several ways: InputService hides the
# cursor on every input event in a co-op run, the FocusEmulators swallow mouse events whenever
# CoopService.listening_for_inputs is false, selection grids ignore the mouse, and raw GUI
# clicks carry no player (they fall back to player 0). This persistent node re-shows the
# cursor on multiplayer menu screens and attaches ui/mouse/mp_mouse_input.gd as the LAST child
# of each supported scene, so it receives mouse events before the FocusEmulators do (Godot 3
# dispatches _input from the bottom of the tree up) and routes them to the local player only.

const MouseInput = preload("res://mods-unpacked/Pasha-Brotatogether/ui/mouse/mp_mouse_input.gd")
const HANDLED_SCENES = ["CharacterSelection", "WeaponSelection", "DifficultySelection", "CoopShop", "Main"]
const HANDLER_NAME = "BtMouseInput"

var _scene_id := 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS


func _process(_delta: float) -> void:
	var scene = get_tree().current_scene
	if scene == null or not in_multiplayer():
		return
	var sid = scene.get_instance_id()
	if sid != _scene_id:
		_scene_id = sid
		if scene.name in HANDLED_SCENES and not scene.has_node(HANDLER_NAME):
			var handler = MouseInput.new()
			handler.name = HANDLER_NAME
			scene.add_child(handler)
	# InputService hides the cursor again on every input event in a co-op run; input is
	# dispatched before _process, so restoring it here happens before the frame is drawn.
	if _cursor_wanted(scene) and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


static func in_multiplayer() -> bool:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return false
	var options = tree.root.get_node_or_null("BrotogetherOptions")
	var sc = tree.root.get_node_or_null("SteamConnection")
	if options == null or sc == null or not RunData.is_coop_run:
		return false
	if not (options.in_multiplayer_game or options.joining_multiplayer_lobby):
		return false
	return sc.game_lobby_id > 0


# Menus always; in the arena only while the post-wave level-up chooser is up.
func _cursor_wanted(scene) -> bool:
	if not (scene.name in HANDLED_SCENES):
		return false
	if scene.name == "Main":
		return ("_coop_upgrades_ui" in scene) and is_instance_valid(scene._coop_upgrades_ui) \
				and scene._coop_upgrades_ui.visible
	return true
