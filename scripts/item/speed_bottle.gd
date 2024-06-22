extends "res://scripts/item/item.gd"


var speed_boost = 1.5
var duration = 10


# Called when the player actually uses the item by pressing KEY 'Q'
func use():
	var player = owned_node
	var timer = player.get_node("SpeedTimer")
	timer.start(duration) # Start timer for potion effect
	if player:
		player.speed_boost = speed_boost
	print("SPEED ", player.speed)
	super.consume_item()
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	super._process(delta)
