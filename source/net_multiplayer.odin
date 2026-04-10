package game

import "core:net"
import "core:fmt"

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

// Send a message with type header
net_send_msg :: proc(state: ^Network_State, msg_type: u8, data: []u8) -> bool {
	if !state.connected {
		return false
	}
	buf := make([]u8, 1 + len(data))
	buf[0] = msg_type
	copy(buf[1:], data)
	_, err := net.send_tcp(state.tcp_socket, buf)
	return err == nil
}

net_recv_msg :: proc(state: ^Network_State, max_size: int) -> (header: u8, payload: []u8, count: int) {
	if !state.connected {
		return 0, nil, 0
	}
	buf := make([]u8, max_size)
	num_read, recv_err := net.recv_tcp(state.tcp_socket, buf)
	if recv_err != nil || num_read == 0 {
		state.connected = false
		return 0, nil, 0
	}
	header_val := buf[0]
	return header_val, buf[1:num_read], num_read-1
}