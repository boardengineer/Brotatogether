extends Node

# Keyboard paging for the co-op shop's per-player carousels (shop <-> stats <-> secondary
# stats): 9 pages every panel left, 0 pages right.
#
# Why a separate node instead of the shop's own _input: on co-op screens every player's
# FocusEmulator receives input BEFORE the shop root (Godot 3 dispatches _input from the
# bottom of the tree upward) and marks any non-UI key as handled while
# CoopService.listening_for_inputs is false, so a handler on the shop root never saw 9/0.
# This node is added as the shop's LAST child, which puts it first in line.

const PAGE_LEFT_SCANCODE = KEY_9
const PAGE_RIGHT_SCANCODE = KEY_0

var shop = null
var debug_log := false   # set by the test harness (--bt-key-test)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.scancode != PAGE_LEFT_SCANCODE and event.scancode != PAGE_RIGHT_SCANCODE:
		return
	# Godot 3 exposes the GUI focus owner on Control, not Viewport (calling it on the
	# viewport raised and aborted this handler before any paging -- B, 2026-09-14).
	var focus = null
	if shop != null and is_instance_valid(shop) and shop.has_method("get_focus_owner"):
		focus = shop.get_focus_owner()
	if debug_log:
		print("BTKEY recv scancode=%d carousels=%d frame=%d focus=%s" % [event.scancode, carousels().size(), Engine.get_idle_frames(), str(focus)])
	if focus != null and focus is LineEdit:
		if debug_log:
			print("BTKEY skipped: a LineEdit has focus")
		return   # typing digits into a chat box
	var paged = 0
	for car in carousels():
		var was = car.index
		if event.scancode == PAGE_LEFT_SCANCODE:
			car._on_ArrowLeft_pressed()
		else:
			car._on_ArrowRight_pressed()
		paged += 1
		if debug_log:
			print("BTKEY paged %s %d -> %d" % [str(car.get_path()).get_file(), was, car.index])
	if paged > 0:
		get_tree().set_input_as_handled()


func carousels() -> Array:
	var out = []
	if shop == null or not is_instance_valid(shop) or not shop.has_method("_get_coop_player_container"):
		return out
	for pi in RunData.get_player_count():
		var cont = shop._get_coop_player_container(pi)
		if cont == null or not is_instance_valid(cont) or not ("carousel" in cont):
			continue
		var car = cont.carousel
		if car != null and is_instance_valid(car) and car.active:
			out.push_back(car)
	return out
