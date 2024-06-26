extends CharacterBody3D

# Combat params
@export var health = Global.player_max_health
@export var alive = false
var respawn_immunity: bool = false
var getHitCooldown = true

# Speed params
@export var walk_speed = 8
var walk_acceleration = 40
var walk_deceleration = 50
var rotation_speed = 10
@export var fall_acceleration = 30
@export var jump_impulse = 8.5

# Multipliers (for potions)
var walkspeed_multiplier: float = 1
var strength: float = 1.0
var speed_boost: float = 1.0

# Push and pull params
var push_pull_factor = 2.0 / 3.0
var min_pull_dist = 1.5

# Params for interpolations
var speed = 0
var direction = Vector2.ZERO

# Max distance between players
var max_dist: float = 25.0

var AnimDeath: bool = false
var AnimJump: bool = false
var AnimPunching: bool = false

@onready var HpBar = $PlayerCombat/SubViewport/HpBar

var lobby_spawn = Vector3( - 20, 11, 20)
var game_spawn = {1: [Vector3(3, 3, 5), Vector3(3, 3, 11)],2: [Vector3(3, 3, -5), Vector3(3, 3, -11)]}

# this functions gets called only once when the node gets added to the scene tree
func _enter_tree():
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())
	alive = get_node_or_null("../../HUD") == null

# this functions sets the paramaters for the player on all peers connected to the host
@rpc("authority", "call_local", "reliable")
func set_params_for_player(id, new_scale, new_walk_speed, new_accel, margin):
	if str(id) != str(multiplayer.get_unique_id()):
		return
	$Pivot.scale = new_scale
	$PlayerHitbox.scale = new_scale
	$CollisionShape3D.scale = new_scale
	$FloatingName.scale = new_scale
	$FloatingName.position.y += 5.1
	walk_speed = new_walk_speed
	walk_acceleration = new_accel
	walk_deceleration = new_accel * 1.2
	position = lobby_spawn + Vector3(margin, 0, 0)

# this function only gets called once when the node enters the scene tree
func _ready():
	# Load the HUD
	var hud = get_node_or_null("../../HUD")
	if hud and name == str(multiplayer.get_unique_id()):
		await get_tree().create_timer(3.0).timeout
		hud.loaded.rpc()

	# spawn the player in the right location depending on the team sizes and players.
	$FloatingName.text = Network.playername
	if Network.player_teams.size() == 0:
		return
	elif multiplayer.get_peers().size() > 0 and Network.other_team_member_id != null:
		var is_lower = 0 if multiplayer.get_unique_id() < int(Network.other_team_member_id) else 1
		position = game_spawn[Network.player_teams[str(multiplayer.get_unique_id())]][is_lower]
	else:
		position = game_spawn[1][0]

# Calculates the new horizontal velocity and returns Vector3.
func _horizontal_movement(delta):
	# If the player is dead, they shouldn't be able to move.
	if !alive:
		return Vector3.ZERO

	# movement
	var vel = Vector3.ZERO
	var current_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Accelerate if moving
	if current_direction != Vector2.ZERO:
		# Calc the new speed according to the current speed, acceleration, speed boost and max speed.
		speed = min(walk_speed * walkspeed_multiplier * speed_boost, speed + walk_acceleration * delta)
		# Calculate the new direction, with a set amount of smoothing.
		direction = lerp(direction, current_direction, rotation_speed * delta)
		# Set the new direction, which is inverted for the mirrored team.
		basis = $Pivot.basis.looking_at(Vector3(direction.x, 0, direction.y * Network.inverted))

		# Push moveable objects
		_push_objects()

	# Decelerate if not moving
	else:
		# Decelerate
		speed = max(0, speed - walk_deceleration * delta)

	vel.x = direction.x * speed
	# Invert the velocity for the mirrored team
	vel.z = direction.y * speed * Network.inverted
	return vel

# Calculates the new vertical velocity and returns a Vector3.
func _vertical_movement(delta):
	# If the player is dead, they shouldn't be able to move.
	if !alive:
		return Vector3.ZERO

	var vel = Vector3.ZERO

	# Players can jump when on ground and alive
	if is_on_floor() and Input.is_action_just_pressed("jump") and not AnimDeath:
		Audiocontroller.play_jump_sfx()
		vel.y = jump_impulse
	# dont allow the player to move in the air.
	if not is_on_floor():
		Global.on_floor = false
		vel.y = velocity.y - (fall_acceleration * delta)

	return vel

# Calculates the new combined horizontal and vertical veclocity and returns a
# Vector3.
func _player_movement(delta):
	var h = _horizontal_movement(delta)
	var v = _vertical_movement(delta)

	# Make sure the player never falls below the map.
	if alive and global_position.y < - 1:
		global_position.y = 2

	return h + v

func check_distance(target_velocity):
	if Network.other_team_member_node != null: # null check
		# acquire team's positions
		var player_pos = global_transform.origin
		var player2_pos = Network.other_team_member_node.global_transform.origin

		var x_distance = abs(player_pos.x - player2_pos.x)
		if x_distance > max_dist: # check distance
			if player_pos.x > player2_pos.x and target_velocity.x > 0: # if player trying to walk further
				target_velocity.x = 0
			elif player_pos.x < player2_pos.x and target_velocity.x < 0: # if player trying to walk further
				target_velocity.x = 0

	return target_velocity.x

func play_animation(anim_player, animation):
	if anim_player == 1: # anim speed 1
		$Pivot/AnimationPlayer.play(animation)
	elif anim_player == 2: # anim speed 1.15 (default for walk speed 7)
		$Pivot/AnimationPlayer2.play(animation)
	elif anim_player == 3: # anim speed 1.25 (default for jump)
		$Pivot/AnimationPlayer3.play(animation)
	else: # anim speed  1.285 (default for walk speed 9)
		$Pivot/AnimationPlayer4.play(animation)

func stop_animations(): # stop all animation players
	$Pivot/AnimationPlayer.stop()
	$Pivot/AnimationPlayer2.stop()
	$Pivot/AnimationPlayer3.stop()
	$Pivot/AnimationPlayer4.stop()

# request other clients to play animation
func request_play_animation(anim_player, animation):
	rpc_id(0, "sync_play_animation", anim_player, animation)

# send animation update to other clients
@rpc("any_peer", "call_local", "reliable")
func sync_play_animation(anim_player, animation):
	if anim_player == 0: # to stop animations
		stop_animations()
	else: # to play animations
		play_animation(anim_player, animation)

func anim_handler():
	if Global.AttackAnim and not AnimDeath: # prioritise death anim
		if not AnimPunching: # if not already in a punching animation
			AnimPunching = true
			request_play_animation(0, "stop")
			request_play_animation(1, "punch")
			await get_tree().create_timer(1.1).timeout # wait for anim
			Global.AttackAnim = false
			AnimPunching = false
	else: # if not attacking
		if is_on_floor() and Input.is_action_just_pressed("jump") and not AnimDeath:
			request_play_animation(0, "stop")
			request_play_animation(3, "jump")
			AnimJump = true
		else:
			if velocity != Vector3.ZERO&&velocity.y == 0:
				if not ($Pivot/AnimationPlayer.is_playing() or $Pivot/AnimationPlayer2.is_playing()
				or $Pivot/AnimationPlayer3.is_playing() or $Pivot/AnimationPlayer4.is_playing()):
					request_play_animation(4, "walk")
			if velocity == Vector3.ZERO and not AnimJump and not AnimDeath:
				request_play_animation(0, "stop")
			if velocity.y == 0:
				AnimJump = false

# Applies velocity to moveable objects when the player collides with them.
func _push_objects():
	# only allow the peers to push objects on their own controlled player node
	if name != str(multiplayer.get_unique_id()):
		return

	# Loop over all colliders until a moveable object is found.
	# Then apply the new velocity.
	for i in get_slide_collision_count():

		var c = get_slide_collision(i)
		var collider = c.get_collider()
		if not collider is RigidBody3D or not collider.get_parent().is_in_group("Moveables"):
			continue

		# Set new velocity on the server
		_set_velocity_on_object. rpc (collider.get_path(), \
		 - c.get_normal() * walk_speed * speed_boost * push_pull_factor)
		break

@rpc("any_peer", "call_local", "reliable")
func _set_velocity_on_object(path, velo):
	if not multiplayer.is_server():
		return
	get_node(path).set_axis_velocity(velo)

# Applies velocity to moveable objects when the player presses the pull key.
# This moves the object towards the player.
func _pull_objects():
	if name != str(multiplayer.get_unique_id()):
		return

	# Loops over all candidates in the area, and apply velocity if applicable.
	var bodies = $PullArea.get_overlapping_bodies()
	for body in bodies:
		# Move the object only if movable and not too close to the player.
		if not body.get_parent().is_in_group("Moveables") \
		or global_transform.origin.distance_to(body.global_transform.origin) < min_pull_dist:
			continue

		# Calc the direction the object should move in.
		var pull_direction = (global_position - body.global_position).normalized()
		var v = Vector3.ZERO
		v.x = pull_direction.x * walk_speed * speed_boost * push_pull_factor
		v.z = pull_direction.z * walk_speed * speed_boost * push_pull_factor

		_set_velocity_on_object.rpc(body.get_path(), v)

# this function only gets called when a body enters the area connected to the player
# Displays an interaction indicator text
func _on_pull_area_body_entered(body):
	if name != str(multiplayer.get_unique_id()):
		return
	if not body.get_parent().is_in_group("Moveables") \
		or global_transform.origin.distance_to(body.global_transform.origin) < min_pull_dist:
			return
	body.get_node("PullText").visible = true

# this function only gets called when a body leaves the area connected to the player
# Removes an interaction indicator text
func _on_pull_area_body_exited(body):
	if name != str(multiplayer.get_unique_id()):
		return
	if not body.get_parent().is_in_group("Moveables"):
			return
	body.get_node("PullText").visible = false

func _physics_process(delta):
	if is_on_floor():
		Global.on_floor = true
	if Global.in_pause or Global.in_chat:
		if not is_on_floor():
			velocity.y -= fall_acceleration * delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	if $MultiplayerSynchronizer.is_multiplayer_authority() and not Global.in_chat:
		var target_velocity = _player_movement(delta)
		target_velocity.x = check_distance(target_velocity)
		velocity = target_velocity
		anim_handler()

		# only allow all velocity and physics changes if the player is actually alive.
		if alive:
			move_and_slide()

		if Input.is_action_pressed("pull"):
			_pull_objects()

func _input(event):
	if not alive:
		return
	var hudNode = get_node_or_null("../../HUD")
	if alive and str(multiplayer.get_unique_id()) == name and hudNode != null:
		if not hudNode.abilitiesAvailable:
			return

		#ability1
		if event.is_action_pressed("ability_1") and not Global.in_pause and not Global.in_chat:
			$Class.ability1()
			hudNode.useAbility(1)
			Audiocontroller.play_health_pickup_regen_sfx()

		#ability2
		if event.is_action_pressed("ability_2") and not Global.in_pause and not Global.in_chat:
			$Class.ability2()
			hudNode.useAbility(2)
			Audiocontroller.play_sabotaging_sfx()

# Lowers health by certain amount, cant go lower then 0. Starts hit cooldawn timer
@rpc("any_peer", "call_local", "reliable")
func take_damage(id, damage):
	if str(id) != str(multiplayer.get_unique_id()):
		return
	if !respawn_immunity and alive and getHitCooldown:
		health = max(0, health - damage)
		getHitCooldown = false
		$PlayerCombat/GetHitCooldown.start()
	HpBar.value = float(health) / Global.player_max_health * 100

	if health <= 0 and alive and not AnimDeath:
		die()

# Increases health/HP of the player with a certain amount, can't go higher
# than Global.player_max_health
@rpc("any_peer", "call_local", "reliable")
func increase_health(value):
	health = min(Global.player_max_health, health + value)
	HpBar.value = float(health) / Global.player_max_health * 100

# Sets the player's health to full HP of player
@rpc("any_peer", "call_local", "reliable")
func full_health():
	health = Global.player_max_health
	HpBar.value = Global.player_max_health

func die():
	# assign globals
	AnimDeath = true
	var temp = walk_speed
	walk_speed = 0
	alive = false

	request_play_animation(1, "death") # play anim
	Audiocontroller.play_player_death_sfx()
	await get_tree().create_timer(2).timeout # wait for anim
	get_parent().player_died(self) # die

	# reset globals
	AnimDeath = false
	request_play_animation(0, "stop")
	await get_tree().create_timer(0.8).timeout # wait to respawn
	walk_speed = temp

	$PlayerItem._drop_item()

# this function only gets called when the respawn immunity timer reaches it end.
func _on_respawn_immunity_timeout():
	respawn_immunity = false

# Resets the player's speed to its normal speed
func _on_speed_timer_timeout():
	speed_boost = 1.0 # Reset the player's speed
	$PlayerEffects/SpeedTimer.stop()

# Resets the boost value to its standard value after the timer ended
func _on_strength_timer_timeout():
	strength = 1.0 # Reset the player's strength
	$PlayerEffects/StrengthTimer.stop()
