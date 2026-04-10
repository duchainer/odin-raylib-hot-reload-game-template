package game

import "core:net"
import "core:fmt"
import "core:mem"
import "core:hash/xxhash"
import rl "vendor:raylib"

NET_PORT :: 7890

Multiplayer_Mode :: enum {
	None,
	Host,
	Client,
}

Network_State :: struct {
	mode: Multiplayer_Mode,
	tcp_socket: net.TCP_Socket,
	listener: net.TCP_Socket,
	connected: bool,
	synced: bool,  // Initial sync done
	remote_checksum: u64,  // Last received checksum from remote
}

net_init_as_host :: proc(state: ^Network_State) -> bool {
	fmt.println("Starting as host on port", NET_PORT)
	listener, err := net.listen_tcp(net.Endpoint{address = net.IP4_Any, port = NET_PORT})
	if err != nil {
		fmt.eprintln("Failed to listen:", err)
		return false
	}
	net.set_blocking(listener, false)
	state.listener = listener
	state.mode = .Host
	fmt.println("Host listening for connections (non-blocking)...")
	return true
}

net_init_as_client :: proc(state: ^Network_State, host: string) -> bool {
	fmt.println("Connecting to host:", host, "port", NET_PORT)
	tcp_socket, err := net.dial_tcp(net.Endpoint{address = net.IP4_Loopback, port = NET_PORT})
	if err != nil {
		fmt.eprintln("Failed to connect:", err)
		return false
	}
	state.tcp_socket = tcp_socket
	state.mode = .Client
	state.connected = true
	fmt.println("Connected to host!")
	return true
}

net_accept_client :: proc(state: ^Network_State) -> bool {
	tcp_socket, _, err := net.accept_tcp(state.listener)
	if err != nil {
		#partial switch err {
		case .Would_Block:
			return false
		}
		fmt.eprintln("ACCEPT FAILED:", err)
		return false
	}
	state.tcp_socket = tcp_socket
	state.connected = true
	fmt.println("*** CLIENT ACCEPTED! ***")
	return true
}

net_send :: proc(state: ^Network_State, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	_, err := net.send_tcp(state.tcp_socket, data)
	return err == nil
}

net_recv :: proc(state: ^Network_State, data: []u8) -> int {
	if !state.connected {
		return 0
	}
	n, err := net.recv_tcp(state.tcp_socket, data)
	if err != nil {
		fmt.eprintln("Recv error:", err)
		state.connected = false
		return 0
	}
	return n
}

net_close :: proc(state: ^Network_State) {
	if state.tcp_socket != 0 {
		net.close(state.tcp_socket)
	}
	if state.listener != 0 {
		net.close(state.listener)
	}
	state.connected = false
}

// Message types for sync protocol
MULTIPLAYER_MSG_INIT_STATE :: 1
MULTIPLAYER_MSG_INPUT :: 2
MULTIPLAYER_MSG_FRAME :: 3
MULTIPLAYER_MSG_SYNC :: 4

// Send a message with type header
net_send_msg :: proc(state: ^Network_State, msg_type: u8, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	buf := make([]u8, 1 + len(data))
	buf[0] = msg_type
	copy(buf[1:], data)
	_, err := net.send_tcp(state.tcp_socket, buf)
	if err != nil {
		fmt.eprintln("Send error:", err)
	}
	return err == nil
}

net_recv_msg :: proc(state: ^Network_State, max_size: int) -> (header: u8, payload: []u8, count: int) {
	if !state.connected {
		return 0, nil, 0
	}
	buf := make([]u8, max_size)
	num_read, recv_err := net.recv_tcp(state.tcp_socket, buf)
	if recv_err != nil || num_read == 0 {
		if recv_err != nil {
			fmt.eprintln("Recv error:", recv_err)
		}
		state.connected = false
		return 0, nil, 0
	}
	header_val := buf[0]
	return header_val, buf[1:num_read], num_read-1
}

// Initial state sync - Host sends to client
Init_Sync_Data :: struct {
	player_index: u8,
	frame_count: i64,
	seed: u64,
}

send_init_sync :: proc(state: ^Network_State, player_index: u8, frame_count: i64, seed: u64) {
	data := mem.slice_to_bytes([]Init_Sync_Data{{player_index, frame_count, seed}})
	net_send_msg(state, MULTIPLAYER_MSG_INIT_STATE, data)
	fmt.println("Sent init sync: player=", player_index, " frame=", frame_count, " seed=", seed)
}

recv_init_sync :: proc(data: []u8) -> Init_Sync_Data {
	result: Init_Sync_Data
	if len(data) >= size_of(Init_Sync_Data) {
		mem.copy(&result, raw_data(data), size_of(Init_Sync_Data))
	}
	return result
}

// Input + checksum sync - Client sends inputs + local checksum to host
Input_Sync_Data :: struct {
	keys: u32,
	checksum: u64,
	frame_count: i64,
}

send_input_sync :: proc(state: ^Network_State, keys: u32, checksum: u64, frame_count: i64) {
	data := mem.slice_to_bytes([]Input_Sync_Data{{keys, checksum, frame_count}})
	net_send_msg(state, MULTIPLAYER_MSG_INPUT, data)
}

recv_input_sync :: proc(data: []u8) -> (keys: u32, checksum: u64, frame_count: i64) {
	if len(data) >= size_of(Input_Sync_Data) {
		sync: Input_Sync_Data
		mem.copy(&sync, raw_data(data), size_of(Input_Sync_Data))
		return sync.keys, sync.checksum, sync.frame_count
	}
	return 0, 0, 0
}

// Frame sync with checksum - Host broadcasts to client for verification
Frame_Sync_Data :: struct {
	frame_count: i64,
	checksum: u64,
}

send_frame_sync :: proc(state: ^Network_State, frame_count: i64, checksum: u64) {
	data := mem.slice_to_bytes([]Frame_Sync_Data{{frame_count, checksum}})
	net_send_msg(state, MULTIPLAYER_MSG_SYNC, data)
}

recv_frame_sync :: proc(data: []u8) -> (frame_count: i64, checksum: u64) {
	if len(data) >= size_of(Frame_Sync_Data) {
		sync: Frame_Sync_Data
		mem.copy(&sync, raw_data(data), size_of(Frame_Sync_Data))
		return sync.frame_count, sync.checksum
	}
	return 0, 0
}

// Compute checksum of current game state for deterministic verification
compute_game_checksum :: proc(frame_count: int, player_rect: rl.Rectangle, last_sheep_index: u32, lava_height: f32, lava_speed: f32, last_sheep_spawn: f32, count_sheep_sacrificed: u32, sheep_time_seed: u64, sheep_dir_seed: u64, sheeps: [^]Sheep, sheeps_count: u32) -> u64 {
	// Use xxhash like the existing checksum code
	checksum := xxhash.XXH3_64_default(mem.byte_slice(&frame_count, size_of(int)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&player_rect, size_of(rl.Rectangle)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&last_sheep_index, size_of(u32)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&lava_height, size_of(f32)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&lava_speed, size_of(f32)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&last_sheep_spawn, size_of(f32)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&count_sheep_sacrificed, size_of(u32)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&sheep_time_seed, size_of(u64)))
	checksum += xxhash.XXH3_64_default(mem.byte_slice(&sheep_dir_seed, size_of(u64)))
	if sheeps != nil && sheeps_count > 0 {
		checksum += xxhash.XXH3_64_default(mem.byte_slice(sheeps, int(size_of(Sheep) * int(sheeps_count))))
	}
	return checksum
}

Network_State :: struct {
	mode: Multiplayer_Mode,
	tcp_socket: net.TCP_Socket,
	listener: net.TCP_Socket,
	connected: bool,
	synced: bool,  // Initial sync done
}

net_init_as_host :: proc(state: ^Network_State) -> bool {
	fmt.println("Starting as host on port", NET_PORT)
	listener, err := net.listen_tcp(net.Endpoint{address = net.IP4_Any, port = NET_PORT})
	if err != nil {
		fmt.eprintln("Failed to listen:", err)
		return false
	}
	net.set_blocking(listener, false)
	state.listener = listener
	state.mode = .Host
	fmt.println("Host listening for connections (non-blocking)...")
	return true
}

net_init_as_client :: proc(state: ^Network_State, host: string) -> bool {
	fmt.println("Connecting to host:", host, "port", NET_PORT)
	tcp_socket, err := net.dial_tcp(net.Endpoint{address = net.IP4_Loopback, port = NET_PORT})
	if err != nil {
		fmt.eprintln("Failed to connect:", err)
		return false
	}
	state.tcp_socket = tcp_socket
	state.mode = .Client
	state.connected = true
	fmt.println("Connected to host!")
	return true
}

net_accept_client :: proc(state: ^Network_State) -> bool {
	tcp_socket, _, err := net.accept_tcp(state.listener)
	if err != nil {
		#partial switch err {
		case .Would_Block:
			return false
		}
		fmt.eprintln("ACCEPT FAILED:", err)
		return false
	}
	state.tcp_socket = tcp_socket
	state.connected = true
	fmt.println("*** CLIENT ACCEPTED! ***")
	return true
}

net_send :: proc(state: ^Network_State, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	_, err := net.send_tcp(state.tcp_socket, data)
	return err == nil
}

net_recv :: proc(state: ^Network_State, data: []u8) -> int {
	if !state.connected {
		return 0
	}
	n, err := net.recv_tcp(state.tcp_socket, data)
	if err != nil {
		fmt.eprintln("Recv error:", err)
		state.connected = false
		return 0
	}
	return n
}

net_close :: proc(state: ^Network_State) {
	if state.tcp_socket != 0 {
		net.close(state.tcp_socket)
	}
	if state.listener != 0 {
		net.close(state.listener)
	}
	state.connected = false
}

// Message types for sync protocol
MULTIPLAYER_MSG_INIT_STATE :: 1
MULTIPLAYER_MSG_INPUT :: 2
MULTIPLAYER_MSG_FRAME :: 3
MULTIPLAYER_MSG_SYNC :: 4

// Send a message with type header
net_send_msg :: proc(state: ^Network_State, msg_type: u8, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	buf := make([]u8, 1 + len(data))
	buf[0] = msg_type
	copy(buf[1:], data)
	_, err := net.send_tcp(state.tcp_socket, buf)
	if err != nil {
		fmt.eprintln("Send error:", err)
	}
	return err == nil
}

net_recv_msg :: proc(state: ^Network_State, max_size: int) -> (header: u8, payload: []u8, count: int) {
	if !state.connected {
		return 0, nil, 0
	}
	buf := make([]u8, max_size)
	num_read, recv_err := net.recv_tcp(state.tcp_socket, buf)
	if recv_err != nil || num_read == 0 {
		if recv_err != nil {
			fmt.eprintln("Recv error:", recv_err)
		}
		state.connected = false
		return 0, nil, 0
	}
	header_val := buf[0]
	return header_val, buf[1:num_read], num_read-1
}

// Initial state sync - Host sends to client
Init_Sync_Data :: struct {
	player_index: u8,
	frame_count: i64,
	seed: u64,
}

send_init_sync :: proc(state: ^Network_State, player_index: u8, frame_count: i64, seed: u64) {
	data := mem.slice_to_bytes([]Init_Sync_Data{{player_index, frame_count, seed}})
	net_send_msg(state, MULTIPLAYER_MSG_INIT_STATE, data)
	fmt.println("Sent init sync: player=", player_index, " frame=", frame_count, " seed=", seed)
}

recv_init_sync :: proc(data: []u8) -> Init_Sync_Data {
	result: Init_Sync_Data
	if len(data) >= size_of(Init_Sync_Data) {
		mem.copy(&result, raw_data(data), size_of(Init_Sync_Data))
	}
	return result
}

// Input sync - Client sends inputs to host
Input_Sync_Data :: struct {
	keys: u32,
}

send_input_sync :: proc(state: ^Network_State, keys: u32) {
	data := mem.slice_to_bytes([]Input_Sync_Data{{keys}})
	net_send_msg(state, MULTIPLAYER_MSG_INPUT, data)
}

recv_input_sync :: proc(data: []u8) -> u32 {
	if len(data) >= size_of(Input_Sync_Data) {
		keys: u32
		mem.copy(&keys, raw_data(data), size_of(u32))
		return keys
	}
	return 0
}

// Frame sync - Host broadcasts to client
Frame_Sync_Data :: struct {
	frame_count: i64,
	player_x: f32,
	player_y: f32,
}

send_frame_sync :: proc(state: ^Network_State, frame_count: i64, player_x: f32, player_y: f32) {
	data := mem.slice_to_bytes([]Frame_Sync_Data{{frame_count, player_x, player_y}})
	net_send_msg(state, MULTIPLAYER_MSG_SYNC, data)
}

recv_frame_sync :: proc(data: []u8) -> (frame_count: i64, player_x: f32, player_y: f32) {
	if len(data) >= size_of(Frame_Sync_Data) {
		sync: Frame_Sync_Data
		mem.copy(&sync, raw_data(data), size_of(Frame_Sync_Data))
		return sync.frame_count, sync.player_x, sync.player_y
	}
	return 0, 0, 0
}