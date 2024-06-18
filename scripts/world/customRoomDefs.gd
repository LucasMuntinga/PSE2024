extends Node

static var START = 24
static var END = 23

@onready var customRooms = preload("res://scenes/world/customRooms.tscn").instantiate()

var rooms = ["Room0", "Room1", "Room2"]
var roomNodes = []


func get_room_item(location : Vector3i, room : int, layer : int) -> int:
	return roomNodes[room].get_child(layer).get_cell_item(location)


func get_room_item_orientation(location : Vector3i, room : int, layer : int) -> int: 
	return roomNodes[room].get_child(layer).get_cell_item_orientation(location)


func get_room_size(room : int) -> Array:
	var start = roomNodes[room].get_child(0).get_used_cells_by_item(START)[0]
	var end = roomNodes[room].get_child(0).get_used_cells_by_item(END)[0]
	
	return [end.x - start.x - 1, end.z - start.z + 1, start.x + 1]
	

func total_rooms() -> int:
	return rooms.size()


# Called when the node enters the scene tree for the first time.
func _ready():
	roomNodes = []
	for room in rooms:
		roomNodes.append(customRooms.get_node(room))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass