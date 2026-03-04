extends Node

const PLAYER = preload("uid://k6mcorwk6nxq") 
var enet_peer := ENetMultiplayerPeer.new()

var PORT = 9999
var IP_ADDRESS = '127.0.0.1'
var local_player_name := ""

var assigned_indices: Dictionary = {}
var destroyed_objects: Array[NodePath] = []

# Función para encontrar el primer índice libre
func _get_first_free_index() -> int:
	var i = 0
	while i in assigned_indices.values():
		i += 1
	return i

func start_server():
	assigned_indices.clear()
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	print("Servidor iniciado en puerto: ", PORT)

func join_server():
	assigned_indices.clear()
	enet_peer.create_client(IP_ADDRESS, PORT)
	multiplayer.peer_connected.connect(add_player) 
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.multiplayer_peer = enet_peer	
	print("Intentando unirse a: ", IP_ADDRESS)

func on_connected_to_server():
	print("Conexión al servidor exitosa. Mi ID es: ", multiplayer.get_unique_id())
	add_player(multiplayer.get_unique_id())

func add_player(peer_id: int):
	if peer_id == 1: return
	
	# Solo el servidor decide el índice
	if multiplayer.is_server():
		var idx = _get_first_free_index()
		assigned_indices[peer_id] = idx
		print("Servidor asigna Índice ", idx, " al Peer ", peer_id)
		rpc_id(peer_id, "sync_late_join_objects", destroyed_objects) #actualizamos estado de objetos
	
	var new_player = PLAYER.instantiate()
	new_player.name = str(peer_id)

	var rand_x = randf_range(-5.0, 5.0)
	var rand_z = randf_range(-5.0, 5.0)
	new_player.position = Vector3(rand_x, 1.0, rand_z)
	
	get_tree().current_scene.add_child(new_player, true)

func remove_player(peer_id):
	if (peer_id as int == 1): leave_server()
	
	if assigned_indices.has(peer_id):
		print("Jugador ", peer_id, " (Índice ", assigned_indices[peer_id], ") desconectado.")
		assigned_indices.erase(peer_id)
	
	var players: Array[Node] = get_tree().get_nodes_in_group('Players')
	var player_to_remove = players.find_custom(func(item): return item.name == str(peer_id))
	if player_to_remove != -1:
		players[player_to_remove].queue_free()
		
func leave_server():
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	assigned_indices.clear()
	get_tree().reload_current_scene()

@rpc("any_peer", "reliable")
func request_late_join_objects() -> void:
	# El cliente que acaba de cargar el mapa pide la lista.
	# Solo el servidor responde.
	if multiplayer.is_server():
		var sender = multiplayer.get_remote_sender_id()
		rpc_id(sender, "sync_late_join_objects", destroyed_objects)

@rpc("reliable")
func sync_late_join_objects(paths: Array[NodePath]) -> void:
	# El cliente recibe la lista y destruye los objetos que ya no deberían existir
	for path in paths:
		var obj = get_node_or_null(path)
		if obj:
			obj.queue_free()
