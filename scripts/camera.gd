extends Camera3D

# Reference to the player nodes
var player: Node = null
var player2: Node = null

var other_player_id = null

#camera interpolation speed
var move_speed = 2

# calculate how many players are in the team
func get_player_count():
	var playercount: int = 0
	if player:
		playercount += 1
	else:
		player = get_node("/root/Main/SpawnedItems/World/PlayerSpawner").get_node_or_null(str(multiplayer.get_unique_id()))
	if player2:
		playercount += 1
	else:
		player2 = get_node("/root/Main/SpawnedItems/World/PlayerSpawner").get_node_or_null(str(Network.other_team_member_id))
		Network.other_team_member_node = player2

	if not multiplayer.get_peers().size() == 0 and Network.inverted == 1 and Network.player_teams.has(str(multiplayer.get_unique_id())) and Network.player_teams[str(multiplayer.get_unique_id())] == 2:
		var light = $"../../world/DirectionalLight3D"
		if not light:
			return 0
		light.rotate_y(PI)
		global_transform.origin = Vector3(0, 20, 0)
		rotate_y(PI)
		Network.inverted = -1
		var transform = global_transform
		transform.basis.x = -transform.basis.x
		global_transform = transform
	return playercount

# calculate the total x-values of the players in a team
func calc_total_x(player_count):
	var total_x: float = 0.0
	if  is_instance_valid(player) and player.get_parent() != null:
		total_x += player.global_transform.origin.x
	if  is_instance_valid(player2) and player2.get_parent() != null:
		total_x += player2.global_transform.origin.x
	return total_x

# calculate the total z-values of the players in a team
func calc_total_z(player_count):
	var total_z: float = 0.0
	if  is_instance_valid(player) and player.get_parent() != null:
		total_z += player.global_transform.origin.z + 20 * Network.inverted
	if  is_instance_valid(player2) and player2.get_parent() != null:
		total_z += player2.global_transform.origin.z + 20 * Network.inverted
	return total_z

# modify the current camera position
func modify_camera_pos(average_x, average_z, delta):
	# Get the camera position
	var camera_position = global_transform.origin

	# Update only the x-axis of the camera position
	camera_position.x = average_x
	camera_position.z = average_z

	# Set the new position back to the camera
	global_transform.origin = lerp(global_transform.origin, camera_position, move_speed * delta)


# Make sure the camera only moves in the X-axis
func _physics_process(delta):
	var player_count: int = get_player_count()

	# Calculate the average x position if there are players in the team
	if player_count > 0:
		var total_x: float = calc_total_x(player_count)
		var average_x: float = total_x / player_count

		var total_z: float = calc_total_z(player_count)
		var average_z: float = total_z / player_count

		modify_camera_pos(average_x, average_z, delta)
