extends Node

# TODO rename options to globals

var joining_multiplayer_lobby : bool = false

var in_multiplayer_game : bool = false

var current_network_id : int = 0

var batched_enemy_deaths = {}
var batched_unit_flashes = {}
var batched_floating_text = []
var batched_hit_particles = []
var batched_explosions = []
var batched_hit_effects = []
var batched_sounds = []
var batched_2d_sounds = []
