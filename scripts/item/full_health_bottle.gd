extends "res://scripts/item/item.gd"


# Called when the player actually uses the item by pressing KEY 'Q'
# Sets the health of the player back to full health
func use():
	var player = Network.get_player_node_by_id(owned_id)
	if player:
		player.rpc("full_health")
	super.consume_item()

