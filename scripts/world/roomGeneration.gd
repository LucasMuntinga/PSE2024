extends Node3D

@onready var world = get_parent()

enum {HORIZONTAL, VERTICAL}

var parser = preload("res://scripts/world/rms_parser.gd").new()

var enemy_scene = preload("res://scenes/enemy/enemy.tscn")
var laser_scene = preload("res://scenes/interactables/laser_beam.tscn")
var item_scene = preload("res://scenes/item/item.tscn")
var box_scene = preload("res://scenes/interactables/moveable_object.tscn")
var wall_scene = preload("res://scenes/world/intern_wall.tscn")

func _ready():
	if world.generate_room:
		var start : Vector3i = world.start_pos
		var filename = "res://files/random_map_scripts/test.rms"
		var world_dict : Dictionary = parser.parse_file(filename)
		fill_room(world_dict, start)
		
func place_wall(x: int, z: int, i: int, orientation: int):
	var wall_block = wall_scene.instantiate()
	if orientation == HORIZONTAL:
		wall_block.position = Vector3i(x + i, 3, z)
	else:
		wall_block.position = Vector3i(x, 3, z + i)
	add_child(wall_block, true)

func add_walls(wall_list : Array, width : int, height : int, start : Vector3i):
	for wall in wall_list:
		var min_dist : int  = wall['set_min_distance']
		var max_dist : int = wall['set_max_distance']
		var length : int = wall['length']
		var variation : int = wall['length_variation']
		length += randi_range(-variation, variation)
		var orientation = randi() % 2
		var x : int = 0
		var z : int = 0
		if orientation == HORIZONTAL and width > length:
			x = randi_range(max(length / 2, start[0] + min_dist), min(width * 2 - length / 2, start[0] + max_dist))
			z = randi_range(max(2, start[2] + min_dist), min(height * 2 - 2, start[2] + max_dist))
		else:
			var xmin = max(2, start[0] - min_dist)
			var xmax = min(width * 2 - 2, start[0] + max_dist)
			var ymin = max(length / 2, start[2] - min_dist)
			var ymax = min(height * 2 - length / 2, start[2] + max_dist)
			x = randi_range(xmin, xmax)
			z = randi_range(ymin, ymax)
			orientation = VERTICAL
		for i in range(-length / 2, length / 2):
			place_wall(x, z, i, orientation)
		if length / 2 == 0:
			place_wall(x, z, 0, orientation)


func add_objects(objects_list):
	pass
	

func fill_room(world_dict: Dictionary, start : Vector3i):
	var room = world.room
	var width : int = room[0]
	var height : int = room[1]
	add_walls(world_dict['walls'], width, height, start)
	
	#var enemy = enemy_scene.instantiate()
	#enemy.position = Vector3i(randi_range(1, room[0] * 2 - 1), randi_range(5, 30), randi_range(1, room[1] * 2 - 1))
	#add_child(enemy, true)
	#
	#var laser = laser_scene.instantiate()
	#laser.position = Vector3i(2, 3, 5)
	#add_child(laser, true)
	#
	#var item = item_scene.instantiate()
	#item.position = Vector3i(randi_range(1, room[0] * 2 - 1), randi_range(3, 10), randi_range(1, room[1] * 2 - 1))
	#add_child(item, true)
	#
	#var box = box_scene.instantiate()
	#box.position = Vector3i(randi_range(1, room[0] * 2 - 1), randi_range(3, 10), randi_range(1, room[1] * 2 - 1))
	#add_child(box, true)

#func _process(delta):
	#pass
