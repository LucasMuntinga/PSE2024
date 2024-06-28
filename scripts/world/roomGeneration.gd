extends Node3D

@onready var world = get_parent()

enum direction {HORIZONTAL, VERTICAL}

enum items {EMPTY, PATH, WALL, BUTTON, ITEM, LASER, BUFF, ENEMY, BOX}

var parser = preload("res://scripts/world/rms_parser.gd").new()

var absolute_position = Vector3(0, 0, 0)

var wall_scene = preload("res://scenes/world/intern_wall.tscn")


func _ready():
	if not multiplayer.is_server():
		return
	if world.generate_room:
		var start : Vector3i = world.start_pos
		var end : Vector3i = world.end_pos
		var last_room : bool = world.last_room
		absolute_position = Vector3(world.absolute_position)
		var dir = DirAccess.open("res://files/random_map_scripts")
		var filenames = []
		if dir:
			dir.list_dir_begin()
			var file = dir.get_next()
			while file != "":
				if file.ends_with(".rms"):
					filenames.append(file)
				file = dir.get_next()
		var filename = filenames[randi() % filenames.size()]
		var world_dict : Dictionary = parser.parse_file("res://files/random_map_scripts/" +  filename)
		fill_room(world_dict, start, end, last_room)

# This function is a check for a range of 3 tiles on two tiles distance of the given
# (x, z) coordinates.
# A small sketch:
# . c c c .
# c . p . c
# c p x p c
# c . p . c
# . c c c .
# If the given x needs to be checked, if any c is a wall, the function will
# return false. If any of the p locations is the chosen path through the maze,
# the function will also return false.
# The vertical flag checks the upper and lower row, while setting it to false
# means the function will check the two columns.
# Setting the orientation to 1, will mean the function will check the
# positive side of the given direction (lower row if vertical flag, right if
# the flag is not set), while setting the orientation to
# -1 will result in the function checking the negative side (upper with flag,
# left without).
func wall_check(floor_plan: Array, x: int, z: int, max_x: int, max_z: int, orientation: int, is_vertical: bool) -> bool:
	if is_vertical:
		if z + 2 * orientation >= 0 and z + 2 * orientation < max_z:
			if floor_plan[z + orientation][x] == items.PATH:
				return false
			if x - 1 >= 0 and x - 1 < max_x and floor_plan[z + 2 * orientation][x - 1]:
				return false
			if floor_plan[z + 2 * orientation][x]:
				return false
			if x + 1 >= 0 and x + 1 < max_x and floor_plan[z + 2 * orientation][x + 1]:
				return false
	else:
		if x + 2 * orientation >= 0 and x + 2 * orientation < max_x:
			if floor_plan[z][x + orientation] == items.PATH:
				return false
			if z - 1 >= 0 and z - 1 < max_z and floor_plan[z - 1][x + 2 * orientation]:
				return false
			if floor_plan[z][x + 2 * orientation]:
				return false
			if z + 1 >= 0 and z + 1 < max_z and floor_plan[z + 1][x + 2 * orientation]:
				return false

	return true

# This function checks if the wall that gets placed at the given (x, z)
# coordinates can be safely placed. Part of this is the check if it's inside
# the room. Another part is the check if it does not create a corridor that is
# too small for the player to navigate. Only if all the checks are fine, does
# this function return true.
# This function does not check if there exists a route from start to finish.
func check_wall_placement(floor_plan: Array, x: int, z: int) -> bool:
	var max_x: int = floor_plan[0].size() - 1
	var max_z: int = floor_plan.size() - 1


	if x < 0 or x >= max_x or z < 0 or z >= max_z:
		return false

	if floor_plan[z][x]:
		return false

	# If there is a hole next to the coordinates, only place the wall if there
	# is no wall on two tiles distance, since the player can't pass then.
	if x > 1 and (not floor_plan[z][x - 1] or floor_plan[z][x - 1] == items.PATH):
		if not wall_check(floor_plan, x, z, max_x, max_z, -1, false):
			return false
	if z > 1 and (not floor_plan[z - 1][x] or floor_plan[z - 1][x] == items.PATH):
		if not wall_check(floor_plan, x, z, max_x, max_z, -1, true):
			return false
	if z < max_z - 1 and x + 2 < max_x and not floor_plan[z + 1][x]:
		if not wall_check(floor_plan, x, z, max_x, max_z, 1, true):
			return false
	if x < max_x - 1 and z + 2 < max_z and not floor_plan[z][x + 1]:
		if not wall_check(floor_plan, x, z, max_x, max_z, 1, false):
			return false

	return true

# This function is a helper function for the handle_wall function.
# This function actually tries to place the wall at the x(+ i), z( + i)
# coordinates and will update the floor plan if the wall can be placed.
# The exact location depends on the given i and the orientation.
# This check is done by check_wall_placement. If the wall was placed this
# function returns true, and false if the wall could not be placed.
func place_wall(x: int, z: int, i: int, orientation: int, floor_plan: Array) -> bool:
	var wall_block = wall_scene.instantiate()
	var new_x = x
	var new_z = z
	if orientation == HORIZONTAL:
		new_x += i
	else:
		new_z += i
	if not check_wall_placement(floor_plan, new_x - 1, new_z - 1):
		return false
	floor_plan[new_z - 1][new_x - 1] = items.WALL
	# Make sure there is not a complete block of walls along the horizontal axis.
	if floor_plan[new_z - 1].all(func(e): return e == items.WALL):
		floor_plan[new_z - 1][new_x - 1] = items.EMPTY
		return false
	GlobalSpawner.spawn_wall(absolute_position + Vector3(new_x, -1, new_z))
	GlobalSpawner.spawn_wall(absolute_position + Vector3(new_x, -1, -new_z))
	return true

# This function will try to fit a wall on the floor plan given the restrictions
# of the wall dictionary, room size and start position.
# If the operation is successful, the floor plan will be updated, but if not
# a single tile of the wall can be placed, this function will not update the
# floor plan, and will return false.
func handle_wall(floor_plan : Array, wall : Dictionary, width : int, height: int, start : Vector3i) -> bool:
	var placed : bool = false
	var min_dist : int  = wall['set_min_distance']
	var max_dist : int = wall['set_max_distance']
	var length : int = wall['length']
	var variation : int = wall['length_variation']
	length += randi_range(-variation, variation)
	var orientation = randi() % 2
	var x : int = 0
	var z : int = 0
	var xmin : int = 0
	var xmax : int = 0
	var zmin : int = 0
	var zmax : int = 0
	if orientation == HORIZONTAL and width  - 3 > length:
		zmin = max(1, start[2] - max_dist)
		zmax = min(height - 2, start[2] + max_dist)
		z = randi_range(zmin, zmax)

		if abs(start[2] - z) >= min_dist:
			xmin = length / 2
		else:
			xmin = start[0] + min_dist

		xmax = min(width - length / 2 - 2, start[0] + max_dist)
	elif height  - 3 > length:
		zmin = max(length / 2, start[2] - max_dist)
		zmax = min(height - length / 2, start[2] + max_dist)
		z = randi_range(zmin, zmax)

		if abs(start[2] - z) >= min_dist:
			xmin = 1
		else:
			xmin = start[0] + min_dist
		orientation = VERTICAL

		xmax = min(width - 2, start[0] + max_dist)
	else:
		# The length is too large to fit horizontally or vertically, so cancel the operation.
		return false

	# Get a random x coordinate inside the bounds.
	x = randi_range(xmin, xmax)
	for i in range(-length / 2, length / 2):
		if place_wall(x, z, i, orientation, floor_plan):
			placed = true
	# If length / 2 == 0, the upper loop places nothing.
	if length / 2 == 0:
		if place_wall(x, z, 0, orientation, floor_plan):
			placed = true
	return placed

# A custom sorting method to give long walls more priority.
# This sorts the list from longest to smallest wall
func wall_sort(wall_a, wall_b) -> bool:
	return wall_a['length'] > wall_b['length']

# This is a small function that relies on the helper functions to place the walls.
# If the first try of placing a wall fails, it will give a second try,
# but no more than 2.
func add_walls(floor_plan : Array[Array], wall_list : Array, width : int, height : int, start : Vector3i) -> void:
	wall_list.sort_custom(wall_sort)
	for wall in wall_list:
		for i in 10:
			if handle_wall(floor_plan, wall, width, height, start):
				break

# This function will calculate a position (x, z) for the object to spawn. This
# will consider the size of the room and object restrictions, but will not care
# about other things in the room.
func object_placement(object : Dictionary, width : int, height : int, start : Vector3i, wall_avoidance : int = 1) -> Array:
	var min_dist : int = object['set_min_distance']
	var max_dist : int = object['set_max_distance']
	# Calculations to set the object between the minimum and maximum distance.
	# Distances are the Chebyshev distance, where distance between 2 points
	# is equal to the maximum of difference in x and y directions.
	var zmin = min(max(1, start[2] * 2 - max_dist), height - wall_avoidance)
	var zmax = min(height - wall_avoidance, start[2] * 2 + max_dist)
	var z = randi_range(zmin, zmax)
	var xmin = wall_avoidance
	var xmax = min(width - wall_avoidance, start[0] * 2 + max_dist)
	if abs(start[2] * 2 - z) < min_dist:
		xmin = min(width - 1, start[0] * 2 + min_dist)
	var x = randi_range(xmin, xmax)

	return [x, z]

# This function takes the floor plan, an object and some parameters of the room
# and tries to fit the object in the room, while keeping the rules set in the
# object dictionary.
# If the object could be placed successfully, the floor plan will be updated
# and the function returns true. If the placement was unsuccessful, the floor
# plan will be unaltered and the function will return false.
func add_item(floor_plan : Array[Array], object : Dictionary, width: int, height : int, start : Vector3i) -> bool:
	var pos = object_placement(object, width, height, start)
	var x = pos[0]
	var z = pos[1]
	# Check if there is not another object/wall already at that place.
	if floor_plan[z - 1][x - 1]:
		return false
	# Add the item and update the plan.
	floor_plan[z - 1][x - 1] = items.ITEM
	GlobalSpawner.spawn_item(absolute_position + Vector3(x, 0, z))
	GlobalSpawner.spawn_item(absolute_position + Vector3(x, 0, -z))
	return true

# This function will handle the adding of a buff. It expects the floor_plan,
# a dictionary containing the arguments for the placement and typing.
# If the object has a buff_type, it will convert the given string to the
# correct integer that the GlobalSpawner expects.
func add_buff(floor_plan : Array[Array], object : Dictionary, width : int, height : int, start : Vector3i) -> bool:
	var pos = object_placement(object, width, height, start)
	var x = pos[0]
	var z = pos[1]
	var buff = ""
	var buff_id = -1
	if object.has('buff_type'):
		buff = object['buff_type']

	if floor_plan[z - 1][x - 1] > items.PATH:
		return false

	floor_plan[z - 1][x - 1] = items.BUFF
	match buff:
		'bomb':
			buff_id = 5
		'hp':
			buff_id = 0
		'hp_full':
			buff_id = 2
		'strength':
			buff_id = 1
		'speed':
			buff_id = 3
		_:
			buff = -1

	buff = GlobalSpawner.spawn_buff(absolute_position + Vector3(x, 0, z), buff, buff_id == -1)
	if buff != -1:
		GlobalSpawner.spawn_buff(absolute_position + Vector3(x, 0, -z), buff, false)
	return true

# This function will handle the placement of boxes. It expects the floor_plan
# and a dictionary containing the arguments for the placement of the box.
func add_box(floor_plan, object, width, height, start) -> bool:
	var pos = object_placement(object, width, height, start)
	var x = pos[0]
	var z = pos[1]

	if floor_plan[z - 1][x - 1]:
		return false

	floor_plan[z - 1][x - 1] = items.BOX
	GlobalSpawner.spawn_box(absolute_position + Vector3(x, 0, z))
	GlobalSpawner.spawn_box(absolute_position + Vector3(x, 0, -z))
	return true

# This function will attach the given object to a nearby wall. This is used
# for the placements of the buttons and both types of lasers.
func attach_wall(object : Dictionary, pos : Array, width : int, height : int) -> Array:
	const orientations = [0, 90, 180, 270]
	# Convert the given x and z positions to be in the middle of the wall tiles.
	var x : int = pos[0] / 2 * 2 + 1
	var z : int = pos[1] / 2 * 2 + 1
	var orientation = 0

	var min_dist = object['set_min_distance']
	var max_dist = object['set_max_distance']

	if z < min_dist:
		z = 1
		orientation = 270
	elif x < min_dist:
		x = 1
		orientation = 0
	elif width < max_dist:
		x = width - 1
		orientation = 180
	elif height < max_dist:
		z = height - 1
		orientation = 90
	else:
		orientation = orientations[randi() % orientations.size()]
		match orientation:
			0:
				x = 1
			90:
				z = height - 1
			180:
				x = width - 1
			270:
				z = 1

	return [x, z, orientation]

# This function will handle the placement of lasers. It relies on the attach_wall
# function to spawn the lasers attached to the sides of the room. It needs
# the position of the right door to avoid placing it in the door, rendering
# the room uncompletable.
func add_laser(floor_plan : Array[Array], object : Dictionary, width : int, height : int, start : Vector3i, end : Vector3i) -> bool:
	var pos = object_placement(object, width, height, start, 3)
	pos = attach_wall(object, pos, width, height)
	var x = pos[0]
	var z = pos[1]
	var orientation = pos[2]

	if floor_plan[z -  1][x - 1] or (z >= start.z / 2 * 2 + 1 and z <= start.z / 2 * 2 + 3) or (z >= end.z / 2 * 2 + 3 and z <= end.z / 2 * 2 + 5):
		return false

	floor_plan[z - 1][x - 1] = items.LASER
	var angle = deg_to_rad(orientation)
	var basis = Basis().rotated(Vector3(0, 1, 0), angle)
	GlobalSpawner.spawn_laser(absolute_position + Vector3(x, 0, z), basis, false, 1, false, true)
	basis = Basis().rotated(Vector3(0, -1, 0), angle)
	GlobalSpawner.spawn_laser(absolute_position + Vector3(x, 0, -z), basis, false, 1, false, true)
	return true

# This function places the enemy lasers. Firstly, it places the laser based on the
# given arguments. Then it tries to place as many buttons as specified by the
# set_activation. If it fails to place the button, it will reduce the activation
# count of the laser. This might result in lasers that cannot be turned on.
func add_enemy_laser(floor_plan : Array[Array], object : Dictionary, width : int, height : int, start : Vector3i, end : Vector3i) -> bool:
	var pos : Array = object_placement(object, width, height, start, 3)
	pos = attach_wall(object, pos, width, height)
	var x = pos[0]
	var z = pos[1]
	var orientation = pos[2]

	if floor_plan[z - 1][x - 1] or (z >= start.z / 2 * 2 + 1 and z <= start.z / 2 * 2 + 3) or (z >= end.z / 2 * 2 + 3 and z <= end.z / 2 * 2 + 5):
		return false

	# Spawn the laser
	floor_plan[z - 1][x - 1] = items.LASER
	var angle = deg_to_rad(orientation)
	var basis = Basis().rotated(Vector3(0, 1, 0), -angle)
	var laser = GlobalSpawner.spawn_laser(absolute_position + Vector3(x, 0, -z), basis, false, object['set_activation'], true, true)
	basis = Basis().rotated(Vector3(0, -1, 0), -angle)
	var laser2 = GlobalSpawner.spawn_laser(absolute_position + Vector3(x, 0, z), basis, false, object['set_activation'], true, true)

	var button_object = {'set_min_distance' : object['set_button_min'], 'set_max_distance' : object['set_button_min']}
	for i in object['set_activation']:
		pos = object_placement(button_object, width, height, start)
		pos = attach_wall(button_object, pos, width, height)
		x = pos[0]
		z = pos[1]
		orientation = pos[2]

		if floor_plan[z - 1][x - 1] or (z >= start.z / 2 * 2 + 1 and z <= start.z / 2 * 2 + 3) or (z >= end.z / 2 * 2 + 1 and z <= end.z / 2 * 2 + 5):
			laser.activation_count -= 1
			laser2.activation_count -= 1
			continue

		floor_plan[z - 1][x - 1] = items.BUTTON
		angle = deg_to_rad(orientation)
		var rotated_basis = Basis().rotated(Vector3(0, 1, 0), deg_to_rad(90))
		GlobalSpawner.spawn_button(absolute_position + Vector3(x, -1, z), rotated_basis.rotated(Vector3(0, 1, 0), angle), laser, false)
		GlobalSpawner.spawn_button(absolute_position + Vector3(x, -1, -z), rotated_basis.rotated(Vector3(0, 1, 0), -angle), laser2, false)

	return true

# This function will handle the placement and linking of buttons. By default,
# this function will link the button to the door. This function relies on the
# attach_wall function to place the button on the nearest wall. It also needs
# the position of the final door to stay away from it.
func add_button(floor_plan : Array[Array], object : Dictionary, doors : Array, width : int, height : int, start : Vector3i, end : Vector3i) -> bool:
	var pos = object_placement(object, width, height, start, 3)
	pos = attach_wall(object, pos, width, height)
	var x = pos[0]
	var z = pos[1]
	var orientation = pos[2]

	if floor_plan[z - 1][x - 1] or (z >= start.z / 2 * 2 + 1 and z <= start.z / 2 * 2 + 3) or (z >= end.z / 2 * 2 + 1 and z <= end.z / 2 * 2 + 5):
		return false

	floor_plan[z - 1][x - 1] = items.BUTTON
	doors[0].deactivated()
	doors[1].deactivated()
	var angle = deg_to_rad(orientation)
	var rotated_basis = Basis().rotated(Vector3(0, 1, 0), deg_to_rad(90))
	GlobalSpawner.spawn_button(absolute_position + Vector3(x, -1, z), rotated_basis.rotated(Vector3(0, 1, 0), angle), doors[0], false)
	GlobalSpawner.spawn_button(absolute_position + Vector3(x, -1, -z), rotated_basis.rotated(Vector3(0, 1, 0), -angle), doors[1], false)
	return true


# This function will handle the object placements. This will call the correct
# add function to handle the actual placement of the given item. If the item
# type is not known, it will return an error, but this should not happen if
# the RMS file follows the template.
func object_matcher(object : Dictionary, floor_plan : Array[Array], doors : Array, width : int, height : int, start: Vector3i, end : Vector3i) -> bool:
	match object['type']:
		'ITEM':
			return add_item(floor_plan, object, width, height, start)
		'BUFF':
			return add_buff(floor_plan, object, width, height, start)
		'BOX':
			return add_box(floor_plan, object, width, height, start)
		'LASER':
			return add_laser(floor_plan, object, width, height, start, end)
		'ENEMY_LASER':
			return add_enemy_laser(floor_plan, object, width, height, start, end)
		'BUTTON':
			return add_button(floor_plan, object, doors, width, height, start, end)
		_:
			print('The object ', object['type'], ' is not a supported object')
			return true

# This function will eventually handle all the object placements.
# It will handle objects that failed to place by trying again. If it fails too
# often, it will give up on trying and place another object.
func add_objects(floor_plan : Array[Array], objects_list : Array, doors : Array, width : int, height: int, start: Vector3i, end : Vector3i) -> void:
	for object in objects_list:
		for i in 5:
			if object_matcher(object, floor_plan, doors, width, height, start, end):
				break

# This function will handle the placements of a single enemy. It returns
# the x and z coordinate of the placed enemy.
func enemy_placement(floor_plan : Array[Array], object : Dictionary, radius : int, width : int, height : int, start : Vector3i) -> Array:
	var min_dist : int = object['set_min_distance']
	var max_dist : int = object['set_max_distance']
	var buffer = radius + 1

	var zmin = min(max(buffer, start[2] * 2 - max_dist), height - buffer)
	var zmax = min(height - buffer, start[2] * 2 + max_dist)
	var z = randi_range(zmin, zmax)
	var xmin = radius + 1
	var xmax = min(width - buffer, start[0] * 2 + max_dist)
	if abs(start[2] * 2 - z) < min_dist:
		xmin = min(width - buffer, start[0] * 2 + min_dist)
	var x = randi_range(xmin, xmax)

	assert(z < height)

	return [x, z]

# This function will tightly place the enemies.
func place_enemy_in_radius_tight(floor_plan : Array[Array], radius : int, x : int, z : int) -> Array:
	for i in radius + 1:
		for j in radius + 1:
			if not floor_plan[z - 1 + j][x - 1 + i]:
				return [x + i, z + j]
	return []

# this function will loosely place the enemies inside the given radius.
func place_enemy_in_radius_loose(floor_plan : Array[Array], radius : int, x : int, z : int) -> Array:
	var xs = range(-radius, radius + 1)
	var ys = range(-radius, radius + 1)
	xs.shuffle()
	ys.shuffle()
	for i in xs:
		for j in ys:
			if not floor_plan[z - 1 + j][x - 1 + i]:
				return [x + i, z + j]
	return []

# This function will handle the placement of a group of enemies, if a single
# enemy failed, it will return an empty array. Otherwise, it will return
# the positions where enemies can be spawned.
func generate_enemy_placement(floor_plan : Array[Array], object : Dictionary, radius : int, x : int, z: int) -> Array:
	var number_enemies = object['set_group_size']
	var positions = []
	positions.resize(number_enemies)
	for i in number_enemies:
		var pos = []
		if object['loose_grouping']:
			pos = place_enemy_in_radius_loose(floor_plan, radius, x, z)
		else:
			pos = place_enemy_in_radius_tight(floor_plan, radius, x, z)
		if not pos:
			for j in i:
				pos = positions[j]
				var new_x = pos[0]
				var new_z = pos[1]
				assert(floor_plan[new_z - 1][new_x - 1] == items.ENEMY)
				floor_plan[new_z - 1][new_x - 1] = items.EMPTY
			return []
		positions[i] = pos
		var new_x = pos[0]
		var new_z = pos[1]
		floor_plan[new_z - 1][new_x - 1] = items.ENEMY
	return positions

# This function handles the placement of a group of enemies. It will return true
# if the placement went correctly, otherwise false.
func add_mob(floor_plan : Array[Array], object : Dictionary, width : int, height : int, start : Vector3i) -> bool:
	var radius = object['radius'] if object.has('radius') else 2
	var pos = enemy_placement(floor_plan, object, radius, width, height, start)
	var x = pos[0]
	var z = pos[1]
	assert(z < height)
	var type = object['type']
	var positions = generate_enemy_placement(floor_plan, object, radius, x, z)
	for position in positions:
		x = position[0]
		z = position[1]
		if type == 'MELEE':
			GlobalSpawner.spawn_melee_enemy(Vector3(x, 0, z) + absolute_position)
			GlobalSpawner.spawn_melee_enemy(Vector3(x, 0, -z) + absolute_position)
		elif type == 'RANGED':
			# Pass for now, since the bullets of the ranged enemies are bugged.
			continue
			GlobalSpawner.spawn_ranged_enemy(Vector3(x, 0, z) + absolute_position)
			GlobalSpawner.spawn_ranged_enemy(Vector3(x, 0, -z) + absolute_position)

	return positions != []

# This function will handle the placements of all the enemies. If the placement
# of a group of enemies failed, it will try up to 5 times, otherwise it gives
# up on the group.
func add_mobs(floor_plan : Array[Array], objects_list : Array, width : int, height : int, start : Vector3i) -> void:
	for object in objects_list:
		for i in 5:
			if add_mob(floor_plan, object, width, height, start):
				break


# This function will trace a shortest path from the start of the room to the
# finish to assure the player not getting stuck. The path will be traced
# inside the floor plan matrix where the path cells will have the value
# PATH.
func generate_path(floor_plan : Array[Array], width : int, height : int, start : Vector3i, end : Vector3i) -> void:
	var position : Vector3i = start
	floor_plan[position.z - 2][position.x] = items.PATH
	floor_plan[position.z - 1][position.x] = items.PATH
	floor_plan[position.z][position.x] = items.PATH
	floor_plan[position.z + 1][position.x] = items.PATH
	floor_plan[position.z + 2][position.x] = items.PATH
	var up_down : int = 1 if start.z < end.z else -1
	while position != end:
		var new_direction = randi() % 2
		match new_direction:
			HORIZONTAL:
				if position.x == width - 1:
					continue
				position.x += 1
			VERTICAL:
				if position.z == end.z:
					continue
				if position.z + up_down < 0:
					continue
				if position.z + up_down > height - 1:
					continue
				position.z += up_down
		floor_plan[position.z][position.x] = items.PATH

	floor_plan[position.z - 2][position.x - 1] = items.PATH
	floor_plan[position.z - 1][position.x - 1] = items.PATH
	floor_plan[position.z + 1][position.x - 1] = items.PATH
	floor_plan[position.z + 2][position.x - 1] = items.PATH


# Generates a matrix of the size (width, height)
func generate_floor_plan(width : int, height : int) -> Array[Array]:
	var floor_plan : Array[Array] = []
	floor_plan.resize(height)
	for i in height:
		floor_plan[i].resize(width)
		floor_plan[i].fill(0)
	return floor_plan

# This function will spawn the doors dynamically, so buttons can be linked.
func spawn_dynamic_doors(end : Vector3i) -> Array:
	var door_pos_1 = Vector3(end.x, -1, end.z + 3)
	var door_pos_2 = Vector3(door_pos_1)
	door_pos_2.z = -door_pos_2.z
	var rotation = deg_to_rad(-90)
	var door_1 = GlobalSpawner.spawn_door(absolute_position + door_pos_1, Basis().rotated(Vector3(0, 1, 0), rotation), 1)
	door_1.activated()
	var door_2 = GlobalSpawner.spawn_door(absolute_position + door_pos_2, Basis().rotated(Vector3(0, 1, 0), rotation), 1)
	door_2.activated()
	return [door_1, door_2]

# The main function of the script that will generate a room and duplicates
# it for the enemy, so the entire room is just a single scene.
func fill_room(world_dict: Dictionary, start : Vector3i, end : Vector3i, last_floor : bool) -> void:
	var room = world.room
	var width : int = room[0] * 2
	var height : int = room[1] * 2
	var floor_plan : Array[Array] = generate_floor_plan(width, height)

	if not last_floor:
		generate_path(floor_plan, width, height, start, end)
	if world_dict.has('walls'):
		add_walls(floor_plan, world_dict['walls'], width, height, start)
	var doors = spawn_dynamic_doors(end)
	if world_dict.has('objects'):
		add_objects(floor_plan, world_dict['objects'], doors, width, height, start, end)
	if world_dict.has('enemies'):
		add_mobs(floor_plan, world_dict['enemies'], width, height, start)
