package game

import "core:net"
import "core:fmt"
import "core:mem"

import "./types"

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
	synced: bool,
	client_input_keys: u32,  // Last received input from client (host side)
	host_input_keys: u32,  // Last received input from host (client side)

	debug_is_paused: bool,
	debug_frame_target: int,
	debug_send_count: int,
	debug_recv_count: int,
	debug_last_send: string,
	debug_last_recv: string,
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
	net.set_blocking(state.tcp_socket, false)
	fmt.println("*** CLIENT ACCEPTED! ***")
	return true
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

MULTIPLAYER_MSG_INIT_STATE :: 1
MULTIPLAYER_MSG_INPUT :: 2
MULTIPLAYER_MSG_SYNC :: 4
MULTIPLAYER_MSG_SNAPSHOT :: 5  // Full game state snapshot from host to client
MULTIPLAYER_MSG_STEP :: 6   // Frame step command for debugging

debug_msg_name :: proc(msg_type: u8) -> string {
	switch msg_type {
	case MULTIPLAYER_MSG_INIT_STATE: return "INIT"
	case MULTIPLAYER_MSG_INPUT:     return "INPUT"
	case MULTIPLAYER_MSG_SYNC:      return "SYNC"
	case MULTIPLAYER_MSG_SNAPSHOT: return "SNAP"
	case MULTIPLAYER_MSG_STEP:    return "STEP"
	}
	return "UNK"
}

net_send_msg :: proc(state: ^Network_State, msg_type: u8, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	buf := make([]u8, 1 + len(data))
    defer delete(buf)
	buf[0] = msg_type
	copy(buf[1:], data)
	_, err := net.send_tcp(state.tcp_socket, buf)
	if err != nil {
		fmt.eprintln("Send error:", err)
	}

	state.debug_send_count += 1
	debug_str: string
	if msg_type == MULTIPLAYER_MSG_SNAPSHOT {
		debug_str = fmt.tprintf("%s #%d snapshot", debug_msg_name(msg_type), state.debug_send_count)
	} else if msg_type == MULTIPLAYER_MSG_STEP {
		debug_str = fmt.tprintf("%s #%d step_cmd", debug_msg_name(msg_type), state.debug_send_count)
	} else if msg_type == MULTIPLAYER_MSG_SYNC && len(data) >= 12 {
		keys_val: u32
		mem.copy(&keys_val, &data[8], 4)
		debug_str = fmt.tprintf("%s #%d keys=%d", debug_msg_name(msg_type), state.debug_send_count, keys_val)
	} else {
		debug_str = fmt.tprintf("%s #%d", debug_msg_name(msg_type), state.debug_send_count)
	}
	state.debug_last_send = debug_str

	return err == nil
}

net_recv_msg :: proc(state: ^Network_State, max_size: int) -> (header: u8, payload: []u8, count: int) {
	if !state.connected {
		return 0, nil, 0
	}
	buf := make([]u8, max_size)
    defer delete(buf)
	num_read, recv_err := net.recv_tcp(state.tcp_socket, buf)
	if recv_err != nil {
		#partial switch recv_err {
		case .Would_Block:
			return 0, nil, 0  // No data available yet, not an error
		}
		fmt.eprintln("Recv error:", recv_err)
		fmt.eprintln("Recv error:", recv_err)
		state.connected = false
		return 0, nil, 0
	}
	if num_read == 0 {
		state.connected = false  // Connection closed
		return 0, nil, 0
	}
	header_val := buf[0]
	state.debug_recv_count += 1
	recv_debug: string
	if header_val == MULTIPLAYER_MSG_STEP {
		recv_debug = fmt.tprintf("%s #%d step_cmd", debug_msg_name(header_val), state.debug_recv_count)
	} else if num_read > 1 && len(buf) > 3 {
		recv_debug = fmt.tprintf("%s #%d keys=%d", debug_msg_name(header_val), state.debug_recv_count, buf[4])
	} else {
		recv_debug = fmt.tprintf("%s #%d", debug_msg_name(header_val), state.debug_recv_count)
	}
	state.debug_last_recv = recv_debug

	return header_val, buf[1:num_read], num_read-1
}

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

compute_game_checksum :: proc(session: ^Session_Memory) -> types.Session_Memory_Checksums {
	return compute_session_checksum(session)
}

checksums_equal :: proc(a: types.Session_Memory_Checksums, b: types.Session_Memory_Checksums) -> bool {
	return a.player_rect == b.player_rect &&
	       a.player2_rect == b.player2_rect &&
	       a.sheeps == b.sheeps &&
	       a.lava_height == b.lava_height &&
	       a.lava_speed == b.lava_speed &&
	       a.last_sheep_spawn == b.last_sheep_spawn &&
	       a.count_sheep_sacrificed == b.count_sheep_sacrificed &&
	       a.sheep_time_rand_gen_state == b.sheep_time_rand_gen_state &&
	       a.sheep_dir_rand_gen_state == b.sheep_dir_rand_gen_state
}

Frame_Sync_Data :: struct {
	frame_count: i64,
	input_keys: u32,  // Host's input for client to use
	checksum: types.Session_Memory_Checksums, // TODO MAke sure it checksums are from the previous frame
}

send_frame_sync :: proc(state: ^Network_State, frame_count: i64, input_keys: u32, checksum: types.Session_Memory_Checksums) {
	data := mem.slice_to_bytes([]Frame_Sync_Data{{frame_count, input_keys, checksum}})
	net_send_msg(state, MULTIPLAYER_MSG_SYNC, data)
}

recv_frame_sync :: proc(data: []u8) -> (frame_count: i64, input_keys: u32, checksum: types.Session_Memory_Checksums) {
	result: Frame_Sync_Data
	if len(data) >= size_of(Frame_Sync_Data) {
		mem.copy(&result, raw_data(data), size_of(Frame_Sync_Data))
		return result.frame_count, result.input_keys, result.checksum
	}
	return 0, 0, {}
}

// Full game state snapshot for initial sync
Snapshot_Data :: struct {
    using current_session : Session_Memory,
	commodino_instance_id: i64,
	commodino_game_session_id: i64,
}

send_snapshot :: proc(state: ^Network_State, snapshot: Snapshot_Data) {
	data := mem.slice_to_bytes([]Snapshot_Data{snapshot})
	net_send_msg(state, MULTIPLAYER_MSG_SNAPSHOT, data)
	fmt.println("Sent snapshot: frame=", snapshot.frame_count, " player_rect=", snapshot.player_rect.x)
}

recv_snapshot :: proc(data: []u8) -> (snapshot: Snapshot_Data, ok: bool) {
	if len(data) >= size_of(Snapshot_Data) {
		mem.copy(&snapshot, raw_data(data), size_of(Snapshot_Data))
		return snapshot, true
	}
	return {}, false
}

Step_Cmd :: struct {
	target_frame: i64,
}

send_step_cmd :: proc(state: ^Network_State, target_frame: i64) {
	data := mem.slice_to_bytes([]Step_Cmd{{target_frame}})
	net_send_msg(state, MULTIPLAYER_MSG_STEP, data)
	fmt.println("Sent STEP cmd: target=", target_frame)
}

recv_step_cmd :: proc(data: []u8) -> (cmd: Step_Cmd) {
	if len(data) >= size_of(Step_Cmd) {
		mem.copy(&cmd, raw_data(data), size_of(Step_Cmd))
	}
	return
}
