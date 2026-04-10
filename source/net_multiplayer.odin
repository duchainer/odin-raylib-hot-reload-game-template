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
	state.listener = listener
	state.mode = .Host
	fmt.println("Host listening for connections...")
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
		return false
	}
	state.tcp_socket = tcp_socket
	state.connected = true
	fmt.println("Client connected!")
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