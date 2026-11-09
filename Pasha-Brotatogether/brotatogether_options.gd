extends Node

# TODO rename options to globals

var joining_multiplayer_lobby : bool = false
var is_solo_test : bool = false

var in_multiplayer_game : bool = false

var current_network_id : int = 0
# Set by the gpe_spawner extension when it seeds the map roll; Main's _ready re-randomizes.
var map_rng_seeded : bool = false

var batched_enemy_deaths = {}
var batched_unit_flashes = {}
var batched_floating_text = []
var batched_hit_particles = []
var batched_explosions = []
var batched_hit_effects = []
var batched_sounds = []
var batched_2d_sounds = []
var batched_holes = []   # 1.2 brachiosaurus stomp holes, [x, y] each (gpe_spawner extension)
