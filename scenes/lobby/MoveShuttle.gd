extends Node3D

# Initial speed
var speed = 0.0

# Acceleration rate (units per second squared)
const ACCELERATION = 5.0

@onready var mesh = $SpaceshuttleV2

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# Increase the speed by the acceleration multiplied by the delta time
	speed += ACCELERATION * delta
	
	# Move the shuttle to the left
	position += transform.basis * Vector3(-speed, speed/5, 0) * delta
