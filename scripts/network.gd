extends Node

const PLAYER = preload("uid://k6mcorwk6nxq")
var enet_peer := ENetMultiplayerPeer.new()

var PORT = 9999
var IP_ADRESS = '127.0.0.1'

func start_server():
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	

func join_server():
	enet_peer.create_client(IP_ADRESS, PORT)
	multiplayer.peer_connected.connect(add_player) #only listens to other players
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.multiplayer_peer = enet_peer
	

func add_player(peer_id: int):
	if peer_id == 1: #this means I am the server
		return
	var new_player = PLAYER.instantiate()
	new_player.name = str(peer_id)
	get_tree().current_scene.add_child(new_player,true)
	
func on_connected_to_server():
	add_player(multiplayer.get_unique_id()) #this is how we add ourselves
	
func remove_player(peer_id):
	if peer_id == 1:
		leave_server()
		
		var players: Array[Node] = get_tree().get_nodes_in_group('Players')
		var player_to_remove = players.find_custom(func(item): return item.name == str(peer_id))
		if player_to_remove != -1:
			players[player_to_remove].queue_free()
		
func leave_server():
	multiplayer.multiplayer_peer.close() #we are gone
	multiplayer.multiplayer_peer = null #we clean so we can rewrite
	clean_up_signals()
	get_tree().reload_current_scene()
	
func clean_up_signals():
	multiplayer.peer_connected.disconnect(add_player) 
	multiplayer.peer_disconnected.disconnect(remove_player)
	multiplayer.connected_to_server.disconnect(on_connected_to_server)
	
