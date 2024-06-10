extends Node3D

var multiplayer_peer = ENetMultiplayerPeer.new()

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal player_added(id)
# Excluding host
var max_client_connections = 3

var loaded_world = preload("res://scenes/lobby/lobby.tscn")
var loaded_menu = preload("res://scenes/menu/menu.tscn")

var inverted = 1
var other_team_member_id = null
var other_team_member_node = null

#Username van de speler, moet veranderbaar zijn in game
var playername

var player_teams = {}

var players_connected = 0 
var player_names = {}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	#rpc_config("_update_player_info", MultiplayerAPI.RPC_MODE_AUTHORITY)
	#rpc_config("_request_player_infoc", MultiplayerAPI.RPC_MODE_AUTHORITY)

func _on_connection_failed():
	remove_multiplayer_peer()

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	player_names[peer_id] = playername
	player_connected.emit(peer_id, playername)
	rpc_id(1, "_register_player_rpc", peer_id, playername)

# Called when the host button is pressed
func _on_host_pressed(port):
	port = str(port).to_int()
	if multiplayer_peer.create_server(port, max_client_connections) == OK:
		multiplayer.multiplayer_peer = multiplayer_peer
		var world = loaded_world.instantiate()
		get_node("/root/Main/SpawnedItems/Menu").queue_free()
		get_node("/root/Main/SpawnedItems").add_child(world)
		await get_tree().create_timer(0.4).timeout
		player_added.emit(1)
		player_names[1] = playername
		player_connected.emit(1, playername)
		Audiocontroller.play_lobby_music()
	else:
		return false
	return true
	

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null

func _on_player_connected(id):
	if multiplayer.is_server():
		_register_player.rpc(id, playername)
		player_added.emit(id)

@rpc("any_peer","call_local", "reliable")
func _register_player(id, new_player_info):
	rpc_id(id, "_request_player_info_rpc", id)
	player_names[id] = new_player_info
	player_connected.emit(id, new_player_info)

@rpc("any_peer", "reliable")
func _register_player_rpc(id, new_player_info):
	_register_player(id, new_player_info)

func _send_player_info(new_player_info):
	var id = multiplayer.get_unique_id()
	rpc_id(1, "_register_player_rpc", id, new_player_info)	

func _request_player_info_rpc(id):
	if multiplayer.is_server():
		return
	_send_player_info(playername)

func _on_player_disconnected(id):
	player_names.erase(id)
	player_disconnected.emit(id)
	if has_node(str(id)):
		var player_node = get_node(str(id))
		remove_child(player_node)
		player_node.queue_free()
	
func _on_leave_button_pressed():
	var id = multiplayer_peer.get_unique_id()
	_on_player_disconnected(id)
	multiplayer_peer.disconnect_peer(id, true)
	remove_multiplayer_peer()
	get_node("/root/Main/SpawnedItems/World").queue_free()
	get_node("/root/Main/SpawnedItems").add_child(loaded_menu.instantiate())
	
	
func _on_server_disconnected():
	print("Server disconnect")
	var world = get_node_or_null("/root/Main/SpawnedItems/World")
	if world:
		world.queue_free()
	var lobby = get_node_or_null("/root/Main/SpawnedItems/Lobby")
	if lobby:
		lobby.queue_free()
	get_node("/root/Main/SpawnedItems").add_child(loaded_menu.instantiate())
	remove_multiplayer_peer()
	player_names.clear()
	server_disconnected.emit()

# Called when the join button is pressed
func _on_join_pressed(ip, port):
	port = str(port).to_int()
	if multiplayer_peer.create_client(ip, port) == OK:
		multiplayer.multiplayer_peer = multiplayer_peer
		get_node("/root/Main/SpawnedItems/Menu").queue_free()
		Audiocontroller.play_lobby_music()
		return true
	return false
