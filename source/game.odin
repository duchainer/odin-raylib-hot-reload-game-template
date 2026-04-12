// -*- compile-command: "../build_hot_reload.sh" -*-
// -*- compile-command: "EMSDK_QUIET=1 source ~/Documents/repos/emsdk/emsdk_env.sh; ../build_zip_web.sh" -*-
//  The first definition seems to win, so just swap them, save and kill the buffer, than reopen it to set the variable
//  Makes it quicker to run the wanted compile command as needed, in emacs

/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import "core:fmt"
import "core:log"
_ :: log

import "core:math"
import "core:math/rand"
import "base:runtime"
import "core:math/linalg"
import rl "vendor:raylib"
import "core:time"
import "core:os"

import "core:hash/xxhash"
import "core:mem"
import sqlite "../vendor/odin-sqlite3/"

import "./types"

REPLAY_TIMING :: true
_ :: time



PIXEL_WINDOW_HEIGHT :: 180

SheepState :: enum{
	DEFAULT,
	JUMPING,
	FALLING,
}

Sheep :: struct {
	using rect: rl.Rectangle,
	input: i8,
	speed: rl.Vector2,
	last_dir_decision: i32,
	state: SheepState,
}

Game_Memory :: struct {
	run: bool,
	commodino : types.CommodinoStruct,
	using current_session : Session_Memory,
	sheep_time_rand_gen, sheep_dir_rand_gen : runtime.Random_Generator,
	db_conn: ^sqlite.Connection,
	replay_stmt: ^sqlite.Statement,
	replay_batch_stmt: ^sqlite.Statement,
	replay_batch: types.Replay_Frame_Batch,
	replay_batch_idx: int,
	player_index: int, // 0 = player 1 (host), 1 = player 2 (client)
	
	// Multiplayer networking
	net_state: Network_State,
	connected_to_host: bool,
	received_initial_state: bool,
}

// TODO Use some fixed point math like fixedptc or libfixmath
// TODO Replace f32 with fixed point values

MAX_PLAYERS :: 2

Session_Memory :: struct {
	frame_count: int,
	player_rect : rl.Rectangle,
	player2_rect : rl.Rectangle, // Second player (host at right, client at left)
	sheeps : [1024]Sheep,
	last_sheep_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_sheep_spawn: f32,
	count_sheep_sacrificed: u32,
	sheep_time_rand_gen_state, sheep_dir_rand_gen_state : rand.Default_Random_State,
}


g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT/2.5,
		offset = { w/2 , h/2 +200 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
USED_KEY_TO_RL_KEY : [types.UsedKeysEnum][2]rl.KeyboardKey= {
        .LEFT =  { .LEFT, .A },
        .RIGHT = { .RIGHT, .D },
        .ENTER = { .ENTER, .KEY_NULL },
}

replay_frame : types.Replay_Frame

player_input_down :: proc(my_key: types.UsedKeysEnum) -> bool {
	if g.commodino.is_replaying{
		return replay_frame.input_keys[my_key]
	} else {
        for key in USED_KEY_TO_RL_KEY[my_key] {
            if rl.IsKeyDown(key){
                return true
            }
        }
        return false
	}
}

player_input_just_pressed :: proc(my_key: types.UsedKeysEnum) -> bool {
	if g.commodino.is_replaying{
		if replay_frame.input_keys[my_key]{
            return !replay_frame_prev_input_keys[my_key]
        }
        return false
	} else {
        for key in USED_KEY_TO_RL_KEY[my_key] {
            if rl.IsKeyPressed(key){
                return true
            }
        }
        return false
	}
}

replay_frame_prev_input_keys : [types.UsedKeysEnum]bool
when REPLAY_TIMING {
    replay_timing : struct {
        db_load_ns : i64,
        input_ns   : i64,
        update_ns  : i64,
        frames     : int,
    }
    batch_recorded_delta_ns : i64
    batch_start_time : time.Time
    batch_frame_count : int
    total_recorded_delta_ns : i64
    total_wall_clock_ns : i64
    replay_start_time : time.Time
}

input :: proc() -> (input: rl.Vector2){

    if g.commodino.is_replaying{
        replay_frame_prev_input_keys = replay_frame.input_keys
    } else if g.lava_height < VOLCANO_HEIGHT {
        g.commodino.recorded_input_events_count += 1

        for rl_keys, used_key in USED_KEY_TO_RL_KEY {
            pressed: bool
            for key in rl_keys{
                pressed = rl.IsKeyDown(key) || pressed
            }
            recorded_input_keys[used_key] = pressed
        }
    }


	if player_input_just_pressed(.ENTER){
		should_restart_game = true
	}

	if g.lava_height >= VOLCANO_HEIGHT{
		return
	}


	if player_input_down(.LEFT) {
		input.x -= 1
	}
	if player_input_down(.RIGHT) {
		input.x += 1
	}

    // We do that in update() currently, like host does it for client input
    // TODO Move the input stuff, even remote, to the input() proc
    // TODO rollback, by checking the frame_{count,index} of the received input, and re-simulating
	// // Client: use input received from host instead of keyboard
	// if g.player_index == 1 && g.net_state.connected && g.net_state.host_input_keys != 0 {
	// 	input = {}  // Clear keyboard input
	// 	if (g.net_state.host_input_keys & 1) != 0 {  // LEFT
	// 		input.x -= 1
	// 	}
	// 	if (g.net_state.host_input_keys & 2) != 0 {  // RIGHT
	// 		input.x += 1
	// 	}
	// }

	input = linalg.normalize0(input)
	return input
}

latest_delta_time: f32
recorded_input_keys : [types.UsedKeysEnum]bool

SHEEP_LAVA_WORTH :: 75
update :: proc(input: rl.Vector2) -> (ok:bool) {
	commodino_assert_message = "" // reset assert_message


    delta_time : f32 = rl.GetFrameTime()
    if g.commodino.is_replaying{
        latest_delta_time = delta_time
        delta_time = replay_frame.delta_time
        if delta_time <= 0 {
            delta_time = 1.0 / f32(types.TARGET_FPS)
        }
    }else{
        if delta_time <= 0 {
            delta_time = 1.0 / f32(types.TARGET_FPS)
        }
        recorded_delta_time = delta_time
    }

	player_speed :: 60.0
	if g.player_index == 0 {
    // No need to be connected if Host, we can start playing while the client will join later
    // connected is true for host when we net_accept_client
    // && g.net_state.connected
    // 
        g.player_rect.x += input.x * delta_time * player_speed
        g.player_rect.y += input.y * delta_time * player_speed
        g.player_rect.x = max(g.player_rect.x, LEFT_HOLE_START_X)
        g.player_rect.x = min(g.player_rect.x, RIGHT_HOLE_START_X-g.player_rect.width)
    }

    // Client control his player
	if g.player_index == 1 && g.net_state.connected {
        g.player2_rect.x += input.x * delta_time * player_speed
        g.player2_rect.y += input.y * delta_time * player_speed
        g.player2_rect.x = max(g.player2_rect.x, LEFT_HOLE_START_X)
        g.player2_rect.x = min(g.player2_rect.x, RIGHT_HOLE_START_X-g.player_rect.width)

	// Client: apply Host input to player 1
        {
            host_keys := g.net_state.host_input_keys
            host_input: rl.Vector2
            if (host_keys & 1) != 0 {  // LEFT
                host_input.x -= 1
            }
            if (host_keys & 2) != 0 {  // RIGHT
                host_input.x += 1
            }
            host_input = linalg.normalize0(host_input)
            g.player_rect.x += host_input.x * delta_time * player_speed
            g.player_rect.y += host_input.y * delta_time * player_speed
            g.player_rect.x = max(g.player_rect.x, LEFT_HOLE_START_X)
            g.player_rect.x = min(g.player_rect.x, RIGHT_HOLE_START_X-g.player2_rect.width)
        }

    }

	// Host: apply client input to player 2
	if g.player_index == 0 && g.net_state.connected {
		client_keys := g.net_state.client_input_keys
		client_input: rl.Vector2
		if (client_keys & 1) != 0 {  // LEFT
			client_input.x -= 1
		}
		if (client_keys & 2) != 0 {  // RIGHT
			client_input.x += 1
		}
		client_input = linalg.normalize0(client_input)
		g.player2_rect.x += client_input.x * delta_time * player_speed
		g.player2_rect.y += client_input.y * delta_time * player_speed
		g.player2_rect.x = max(g.player2_rect.x, LEFT_HOLE_START_X)
		g.player2_rect.x = min(g.player2_rect.x, RIGHT_HOLE_START_X-g.player2_rect.width)
	}


	percent_lava_on_max := g.lava_height / VOLCANO_HEIGHT
	g.lava_height += g.lava_speed * (1.1 - percent_lava_on_max)
	g.lava_speed *= 1.001

	if g.last_sheep_spawn > 120 {
		g.sheeps[g.last_sheep_index+1] = Sheep{
			rect= rl.Rectangle{
				-5, -20, 10, 10,
			},
			state=.JUMPING,
		}
		g.last_sheep_index += 1
		g.last_sheep_spawn = 0
	}
	g.last_sheep_spawn += 1

	SHEEP_SPEED :: 35.0
	SHEEP_INITIAL_JUMP_SPEED :: -60.0
	GRAVITY_ON_SHEEP :: 60.0
	SHEEP_DETECTION :: 20.0
	NEAR_HOLE_DISTANCE :: SHEEP_DETECTION * 1.5

	// Reverse loop, to allow for unordered remove of sheeps that fell in the hole
	sheep_loop: for i := g.last_sheep_index;  i>0; i-=1 {
		sheep := &g.sheeps[i]
		if sheep != {}{
			is_sheep_over_ground := sheep.x + sheep.width > LEFT_HOLE_START_X && sheep.x < RIGHT_HOLE_START_X
			is_sheep_near_left_hole := sheep.x < LEFT_HOLE_START_X + NEAR_HOLE_DISTANCE
			is_sheep_near_right_hole := sheep.x > RIGHT_HOLE_START_X - NEAR_HOLE_DISTANCE
			switch sheep.state{
			case .DEFAULT:{
				if !is_sheep_over_ground{
					sheep.state = .FALLING
					continue
				}
				player_center_pos := player_center_pos(pos_from_rect(g.player_rect))
				sheep_center_pos := center_pos(sheep.rect)

				delta_x_player_sheep := player_center_pos.x - sheep_center_pos.x
				distance_player_sheep := math.abs(delta_x_player_sheep)


				if sheep.last_dir_decision > 120 || is_sheep_near_left_hole || is_sheep_near_right_hole{
					rand_time := rand.uint32(g.sheep_time_rand_gen) % 90
					rand_num := rand.uint32(g.sheep_dir_rand_gen) % 3
					// We have an input between of -1, 0, or  1
					sheep.input =  i8(rand_num) - 1
					if ( sheep.input == -1 && is_sheep_near_left_hole ) || ( sheep.input == 1 && is_sheep_near_right_hole ) {
						sheep.input = -sheep.input
					}
					sheep.last_dir_decision = i32(rand_time)
				}

				if distance_player_sheep <= SHEEP_DETECTION {
					sheep.state = .JUMPING
					sheep.speed.y = SHEEP_INITIAL_JUMP_SPEED
					sheep.input = i8(delta_x_player_sheep / distance_player_sheep)
					// continue sheep_loop
				} else{
					sheep.y = -sheep.height
				}

			}
			case .JUMPING:{
				sheep.speed.y += GRAVITY_ON_SHEEP * delta_time
				is_sheep_at_ground_level := sheep.y + sheep.height >= 0
				if is_sheep_at_ground_level{
					if is_sheep_over_ground && is_sheep_at_ground_level{
						sheep.speed.y = 0
						sheep.state = .DEFAULT
					} else {
						sheep.state = .FALLING
					}
				}
			}
			case .FALLING: {
				sheep.speed.y += GRAVITY_ON_SHEEP * delta_time
				is_sheep_deep_in_hole := sheep.y + sheep.height >= 100
				if is_sheep_deep_in_hole {
					g.lava_height -= SHEEP_LAVA_WORTH
					if g.lava_height < 0{
						g.lava_height = 1
					}

					// Unordered remove of sheep, by replacing by last sheep of g.sheeps
					// Yes, if it is already the last sheep, this line does nothing, but that's alright
					g.sheeps[i] = g.sheeps[g.last_sheep_index]
					// No need to clear the previous last sheep, because we will write over it when we use that slot
					// g.sheeps[g.last_sheep_index] = {}
					g.last_sheep_index -= 1
					g.count_sheep_sacrificed += 1
					continue
				}
			}
			}
			sheep.speed.x = f32(sheep.input * SHEEP_SPEED)
			sheep.x += sheep.speed.x * delta_time
			sheep.y += sheep.speed.y * delta_time
			sheep.last_dir_decision += 1
		}
	}

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
	return true
}

volcano_center_x : f32
VOLCANO_HEIGHT :: 300

VOLCANO_TOP_Y :: 50
VOLCANO_BASE_Y :: VOLCANO_TOP_Y + VOLCANO_HEIGHT
VOLCANO_SIDE_WIDTH :: 500
VOLCANO_INNER_WIDTH :: 50

LEFT_HOLE_START_X :: -250
RIGHT_HOLE_START_X :: 250

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	volcano_center_x = f32(rl.GetScreenWidth())/2
	// volcano_center_x -= g.player_rect.x /10

	rl.DrawTriangle({volcano_center_x-30, VOLCANO_BASE_Y},{volcano_center_x, 0},{volcano_center_x+30,VOLCANO_BASE_Y}, rl.BROWN)

	// rl.DrawTriangle({volcano_center_x,0},{volcano_center_x-30, VOLCANO_BASE_Y},{volcano_center_x+30, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawTriangle({volcano_center_x-VOLCANO_INNER_WIDTH,VOLCANO_TOP_Y},{volcano_center_x-VOLCANO_INNER_WIDTH-VOLCANO_SIDE_WIDTH, VOLCANO_BASE_Y},{volcano_center_x-VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawTriangle({volcano_center_x+VOLCANO_INNER_WIDTH,VOLCANO_TOP_Y},{volcano_center_x+VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y},{volcano_center_x+VOLCANO_INNER_WIDTH+VOLCANO_SIDE_WIDTH, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawRectangleRec({volcano_center_x-VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y-g.lava_height, VOLCANO_INNER_WIDTH*2, g.lava_height}, ( rl.RED/2+rl.ORANGE/2 ) )

	rl.BeginMode2D(game_camera())

	rl.DrawRectangleGradientV(LEFT_HOLE_START_X, 0, RIGHT_HOLE_START_X-LEFT_HOLE_START_X, 100, rl.BROWN, rl.DARKBROWN)
	// rl.DrawTextureEx(g.player_rect, pos_from_rect(g.player_rect), 0, 1, rl.WHITE)
	// rl.DrawTextureEx(g.player_rect, pos_from_rect(g.player_rect), 0, 1, rl.WHITE)
	rl.DrawRectangleRec(g.player_rect, rl.DARKPURPLE)
	rl.DrawRectangleRec(g.player2_rect, rl.PURPLE)
	// rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)

	for i in 0..=g.last_sheep_index {
		sheep := g.sheeps[i]
		if sheep != {}{
			rl.DrawRectangleRec(sheep, rl.WHITE)
			rl.DrawRectangleLinesEx(sheep, 1, {210,210,210,255})
		} else if i != 0 {
			// We ignore the NULL Sheep
			break
		}
	}

	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	if g.lava_height >= VOLCANO_HEIGHT{
		rl.DrawRectangle(30-5, 100-5, 270, 75, {100, 100, 100, 230})
		rl.DrawText(fmt.ctprintf(
"               GAME OVER\nSurvived %v seconds and %v frames\n  Sacrificed %v sheeps to the void\n      Press ENTER to restart",
			g.frame_count/60, g.frame_count%60, g.count_sheep_sacrificed,
		), 30, 100, 15, rl.WHITE)

	}

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	// when ODIN_DEBUG {
	if commodino_assert_message != ""{
		rl.DrawText(fmt.ctprintf("assert_message:\"%v\", \nreplaying_prev_frame_index: %v,\ng.commodino.is_replaying: %#v,\ng.commodino.is_dragging_playback_scrubber:%v,\n", commodino_assert_message, g.commodino.replaying_prev_frame_index, g.commodino.is_replaying, g.commodino.is_dragging_playback_scrubber), 5, 5, 8, rl.WHITE)
	}
		// if g.sheeps[1] != {} {
		// 	rl.DrawText(fmt.ctprintf("g.sheeps[1]: %#v", g.sheeps[1]), 200, 5, 8, rl.WHITE)
		// }
	// }

	rl.EndMode2D()

	rl.EndDrawing()
}

prevent_rng_call :: proc(data: rawptr, mode: runtime.Random_Generator_Mode, p: []byte){
	fmt.eprintln("ERROR: context.random_generator should not be used! Pass generator explicitly.")
	breakpoint()
}

update_ok : bool
input_vec : rl.Vector2
recorded_delta_time : f32

compute_session_checksum :: proc(session: ^Session_Memory) -> types.Session_Memory_Checksums {
    sheeps_count := int(session.last_sheep_index + 1)
    return types.Session_Memory_Checksums{
        frame_count = session.frame_count,
        player_rect = session.player_rect,
        player2_rect = session.player2_rect,
        last_sheep_index = session.last_sheep_index,
        lava_height = session.lava_height,
        lava_speed = session.lava_speed,
        last_sheep_spawn = session.last_sheep_spawn,
        count_sheep_sacrificed = session.count_sheep_sacrificed,
        sheep_time_rand_gen_state = xxhash.XXH3_64_default(mem.byte_slice(&session.sheep_time_rand_gen_state, size_of(session.sheep_time_rand_gen_state))),
        sheep_dir_rand_gen_state = xxhash.XXH3_64_default(mem.byte_slice(&session.sheep_dir_rand_gen_state, size_of(session.sheep_dir_rand_gen_state))),
        sheeps = sheeps_count > 0 ? xxhash.XXH3_64_default(mem.byte_slice(&session.sheeps[0], size_of(Sheep) * sheeps_count)) : 0,
    }
}

save_new_frame_checksum :: proc(frame_checksum: ^types.Session_Memory_Checksums, current_session: ^Session_Memory){
    frame_checksum^ = compute_session_checksum(current_session)
}

restart_game :: proc(mode: types.Hot_Reload_Mode) {
	old_g := g

	g = new(Game_Memory)
	g^ = Game_Memory {
		run = true,
		db_conn = old_g.db_conn,
		commodino = old_g.commodino,
		frame_count = old_g.frame_count,
	}

	update_ok = true

	free(old_g)

	game_hot_reloaded(g, mode)
}

@(export)
game_update :: proc() {
    // Host: try to accept client connections each frame
    if g.player_index == 0 && g.net_state.listener != 0 && !g.net_state.connected {
        if net_accept_client(&g.net_state) {
            fmt.println("*** CLIENT ACCEPTED! ***")
            // Send full game snapshot to client for initial sync
            snapshot := Snapshot_Data{
                frame_count = g.current_session.frame_count,
                player_rect = g.current_session.player_rect,
                player2_rect = g.current_session.player2_rect,
                sheeps = g.current_session.sheeps,
                last_sheep_index = g.current_session.last_sheep_index,
                lava_height = g.current_session.lava_height,
                lava_speed = g.current_session.lava_speed,
                last_sheep_spawn = g.current_session.last_sheep_spawn,
                count_sheep_sacrificed = g.current_session.count_sheep_sacrificed,
                sheep_time_rand_gen_state = g.current_session.sheep_time_rand_gen_state,
                sheep_dir_rand_gen_state = g.current_session.sheep_dir_rand_gen_state,
                commodino_instance_id = g.commodino.instance_id,
                commodino_game_session_id = g.commodino.game_session_id,
            }
            send_snapshot(&g.net_state, snapshot)
            fmt.println("Sent full snapshot to client")
            g.net_state.synced = true
        }
    }

    // Network sync - input-based with checksum verification for deterministic rollback
    if g.net_state.connected {
        // Host: receive client inputs + checksum, send frame sync with checksum
        if g.player_index == 0 {
            // Receive inputs + checksum from client
            header, payload, _ := net_recv_msg(&g.net_state, 256)
            if header == MULTIPLAYER_MSG_INPUT {
                client_keys, client_checksum, client_frame := recv_input_sync(payload)
                fmt.println("Host: client input keys=", client_keys, " frame=", client_frame)
                // Store client input for use in game update
                g.net_state.client_input_keys = client_keys
                _ = client_checksum
            }
            // Compute local checksum for verification
            local_checksum := compute_game_checksum(&g.current_session)
            // Encode host's input keys to send to client
            // TODO use a bitfield instead, and use it in recorded_input_keys too
            host_keys: u32 = 0
            if recorded_input_keys[types.UsedKeysEnum.LEFT] { host_keys |= 1 }
            if recorded_input_keys[types.UsedKeysEnum.RIGHT] { host_keys |= 2 }
            if recorded_input_keys[types.UsedKeysEnum.ENTER] { host_keys |= 4 }
            // Send frame sync with host's input keys for client verification
            send_frame_sync(&g.net_state, i64(g.current_session.frame_count), host_keys, local_checksum)
        }
        // Client: send inputs + checksum to host, receive frame sync with checksum
        if g.player_index == 1 {
            // If not synced yet (no snapshot received), wait and skip rest of update
            if !g.net_state.synced {
                // Try to receive snapshot - may need multiple reads for large data
                header, payload, _ := net_recv_msg(&g.net_state, size_of(Snapshot_Data) + 1)
                if header == MULTIPLAYER_MSG_SNAPSHOT && len(payload) >= size_of(Snapshot_Data) {
                    snapshot, ok := recv_snapshot(payload)
                    if ok {
                        fmt.println("Received snapshot: frame=", snapshot.frame_count)
                        g.frame_count = int(snapshot.frame_count)
                        g.current_session.frame_count = int(snapshot.frame_count)
                        g.current_session.player_rect = snapshot.player_rect
                        g.current_session.player2_rect = snapshot.player2_rect
                        g.current_session.sheeps = snapshot.sheeps
                        g.current_session.last_sheep_index = snapshot.last_sheep_index
                        g.current_session.lava_height = snapshot.lava_height
                        g.current_session.lava_speed = snapshot.lava_speed
                        g.current_session.last_sheep_spawn = snapshot.last_sheep_spawn
                        g.current_session.count_sheep_sacrificed = snapshot.count_sheep_sacrificed
                        g.current_session.sheep_time_rand_gen_state = snapshot.sheep_time_rand_gen_state
                        g.current_session.sheep_dir_rand_gen_state = snapshot.sheep_dir_rand_gen_state
                        g.sheep_time_rand_gen_state = snapshot.sheep_time_rand_gen_state
                        g.sheep_dir_rand_gen_state = snapshot.sheep_dir_rand_gen_state
                        g.sheep_time_rand_gen = rand.default_random_generator(&g.sheep_time_rand_gen_state)
                        g.sheep_dir_rand_gen = rand.default_random_generator(&g.sheep_dir_rand_gen_state)
                        g.net_state.synced = true
                        fmt.println("Applied snapshot - now synced!")
                    }
                }
                return  // Wait for snapshot before continuing
            }

            // Compute local checksum before applying any remote updates
            local_checksum := compute_game_checksum(&g.current_session)
            // Encode input keys as bitfield (LEFT=bit0, RIGHT=bit1, ENTER=bit2)
            keys: u32 = 0
            if recorded_input_keys[types.UsedKeysEnum.LEFT] { keys |= 1 }
            if recorded_input_keys[types.UsedKeysEnum.RIGHT] { keys |= 2 }
            if recorded_input_keys[types.UsedKeysEnum.ENTER] { keys |= 4 }
            // Send input + local checksum + frame_count
            send_input_sync(&g.net_state, keys, local_checksum, i64(g.current_session.frame_count))
            
            // Receive frame sync from host
            header, payload, _ := net_recv_msg(&g.net_state, 256)
            if header == MULTIPLAYER_MSG_SYNC && g.net_state.synced {
                frame_count, host_input_keys, remote_checksum := recv_frame_sync(payload)
                g.net_state.host_input_keys = host_input_keys
                // Verify each checksum component - if different, we've desynced!
                if !checksums_equal(local_checksum, remote_checksum) {
                    desync_player_rect := local_checksum.player_rect != remote_checksum.player_rect
                    desync_player2_rect := local_checksum.player2_rect != remote_checksum.player2_rect
                    desync_sheep := local_checksum.sheeps != remote_checksum.sheeps
                    
                    if desync_player_rect || desync_player2_rect {
                        fmt.println("!!! CRITICAL DESYNC - PLAYERS NOT SYNCED !!!")
                    }
                    fmt.println("!!! DESYNC DETECTED !!!")
                    fmt.println("  player_rect match:", !desync_player_rect, "  player2_rect match:", !desync_player2_rect, "  sheep match:", !desync_sheep)
                    fmt.println("  local:  player_rect=", local_checksum.player_rect, " player2_rect=", local_checksum.player2_rect, " sheep=", local_checksum.sheeps)
                    fmt.println("  remote: player_rect=", remote_checksum.player_rect, " player2_rect=", remote_checksum.player2_rect, " sheep=", remote_checksum.sheeps)
                    fmt.println("  frame=", frame_count)
                    // Request snapshot from host to resync
                    // For now, just mark as needing resync
                }
            }
        }
    }

    // log.logf(.Debug, "frame update player_index=%v", g.player_index)

    if should_restart_game{
        restart_game(.HOT_RELOAD)
        should_restart_game = false
    }

	// Prevent calling the context.random_generator,
	// instead we want our system-specifig rng
	context.random_generator = runtime.Random_Generator{
		procedure = prevent_rng_call,
		data = nil,
	}

    if g.commodino.is_replaying{
        if g.commodino.replaying_prev_frame_index >= g.commodino.recorded_input_events_count{
            if commodino_assert_message == ""{
                commodino_assert_message = "End of replay"
            }
            draw()
            return
        }
    }

	if update_ok {
        when REPLAY_TIMING {
            t_input := time.now()
        }
		input_vec = input()
        when REPLAY_TIMING {
            replay_timing.input_ns += time.duration_nanoseconds(time.since(t_input))
        }
	    g.frame_count += 1
	}
    when REPLAY_TIMING {
        t_update := time.now()
    }
	update_ok = update(input_vec)
    when REPLAY_TIMING {
        replay_timing.update_ns += time.duration_nanoseconds(time.since(t_update))
        replay_timing.frames += 1
    }

    DRAW_EVERY_NTH_FRAME :: 5000
	// fmt.println(commodino_assert_message)
    if g.commodino.is_replaying{
        if g.commodino.replaying_prev_frame_index % DRAW_EVERY_NTH_FRAME == 0{
            draw()
        }
    } else {
        draw()
    }


    // Everything on tracking allocator is valid until end-of-frame.
    if !g.commodino.is_replaying {
        free_all(context.temp_allocator)
    }

    _ :: mem
    _ :: xxhash
    frame_checksum : types.Session_Memory_Checksums
    if !g.commodino.is_replaying {
        save_new_frame_checksum(&frame_checksum, &g.current_session)
    }


    if g.commodino.is_replaying{
        i := g.commodino.replaying_prev_frame_index+1

        batch_idx := i - g.replay_batch.offset
        if batch_idx < 0 || batch_idx >= g.replay_batch.count {
            db_load_replay_frame_batch(g.replay_batch_stmt, &g.replay_batch, g.commodino.instance_id, i)
            g.replay_batch_idx = 0
            batch_idx = 0
        }
        next_frame := g.replay_batch.frames[batch_idx]
        g.replay_batch_idx = batch_idx + 1

        if next_frame != {} {
            replay_frame_prev_input_keys = replay_frame.input_keys
            replay_frame = next_frame
            when REPLAY_TIMING {
                batch_recorded_delta_ns += i64(replay_frame.delta_time * 1e9)
                batch_frame_count += 1
            }
        }

        REPLAY_TIMING_EVERY_NTH_FRAME :: 5000
        when REPLAY_TIMING {
            if g.commodino.replaying_prev_frame_index % REPLAY_TIMING_EVERY_NTH_FRAME == 0 || g.commodino.replaying_prev_frame_index >= g.commodino.recorded_input_events_count-1 {
                wall_clock_ns := time.duration_nanoseconds(time.since(batch_start_time))
                total_wall_clock_ns += wall_clock_ns
                total_recorded_delta_ns += batch_recorded_delta_ns
                game_speed := f64(batch_recorded_delta_ns) / f64(wall_clock_ns)
                total_game_speed := f64(total_recorded_delta_ns) / f64(total_wall_clock_ns)
                fmt.printfln(
                    "replaying frame[%d] (batch of %d frames), batch_speed=%.3fx | total_speed=%.3fx | wall_time=%.3fs game_time=%.3fs | db_load=%.3fms input=%.3fms update=%.3fms total=%.3fms",
                    i, batch_frame_count,
                    game_speed, total_game_speed,
                    f64(total_wall_clock_ns) / 1e9,
                    f64(total_recorded_delta_ns) / 1e9,
                    f64(replay_timing.db_load_ns) / 1e6,
                    f64(replay_timing.input_ns) / 1e6,
                    f64(replay_timing.update_ns) / 1e6,
                    f64(replay_timing.db_load_ns + replay_timing.input_ns + replay_timing.update_ns) / 1e6)
                replay_timing = {}
                batch_recorded_delta_ns = 0
                batch_start_time = time.now()
                batch_frame_count = 0
            }
        }                
        
        CHECK_EVERY_NTH_FRAME :: 500
        VERIFY_CHECKSUMS :: false
        when VERIFY_CHECKSUMS {
            if g.commodino.replaying_prev_frame_index % CHECK_EVERY_NTH_FRAME == 0 {
                save_new_frame_checksum(&frame_checksum, &g.current_session)
                recorded_frame, _ := db_load_replay_frame(g.db_conn, g.commodino.instance_id, i)
                config_diffs := diff_struct(types.Session_Memory_Checksums, recorded_frame.checksum, frame_checksum)
                defer delete(config_diffs)
                print_on_no_diff :: false
                print_diffs(config_diffs, print_on_no_diff)

                if len(config_diffs) > 0{
                    commodino_assert_message = fmt.tprintf("Replay desync at frame %v, bisecting from frame 1...", i)
                    fmt.eprintln(commodino_assert_message)

                    saved_session := g.current_session
                    saved_rng_time := g.sheep_time_rand_gen_state
                    saved_rng_dir := g.sheep_dir_rand_gen_state
                    saved_frame_count := g.frame_count

                    restart_current_session_memory()
                    restore_recorded_session_rand_gen()

                    bisect_replay_frame : types.Replay_Frame
                    bisect_replay_frame, _ = db_load_replay_frame(g.db_conn, g.commodino.instance_id, 1)
                    bisect_prev_input_keys : [types.UsedKeysEnum]bool

                    bisect_found := false
                    for bf := 1; bf <= g.commodino.replaying_prev_frame_index + 1; bf += 1 {
                        if bf > 1 {
                            next_bf, bisect_loaded := db_load_replay_frame(g.db_conn, g.commodino.instance_id, bf)
                            if bisect_loaded {
                                bisect_prev_input_keys = bisect_replay_frame.input_keys
                                bisect_replay_frame = next_bf
                            }
                        }

                        replay_frame = bisect_replay_frame
                        replay_frame_prev_input_keys = bisect_prev_input_keys

                        latest_delta_time = rl.GetFrameTime()
                        dt := replay_frame.delta_time
                        if dt <= 0 { dt = 1.0 / f32(types.TARGET_FPS) }

                        g.frame_count += 1
                        input_vec = input()
                        _ = update(input_vec)

                        bisect_checksum : types.Session_Memory_Checksums
                        save_new_frame_checksum(&bisect_checksum, &g.current_session)
                        bisect_recorded, _ := db_load_replay_frame(g.db_conn, g.commodino.instance_id, bf)
                        bisect_diffs := diff_struct(types.Session_Memory_Checksums, bisect_recorded.checksum, bisect_checksum)
                        defer delete(bisect_diffs)
                        if len(bisect_diffs) > 0{
                            fmt.eprintfln("First desync at frame %d", bf)
                            print_diffs(bisect_diffs, true)
                            bisect_found = true
                            break
                        }
                    }

                    g.current_session = saved_session
                    g.sheep_time_rand_gen_state = saved_rng_time
                    g.sheep_dir_rand_gen_state = saved_rng_dir
                    g.frame_count = saved_frame_count
                    g.sheep_time_rand_gen = rand.default_random_generator(&g.sheep_time_rand_gen_state)
                    g.sheep_dir_rand_gen = rand.default_random_generator(&g.sheep_dir_rand_gen_state)

                    if !bisect_found {
                        fmt.eprintln("Bisect: no divergence found")
                    }

                    draw()
                }
            }
        }
        g.commodino.replaying_prev_frame_index += 1
    } else {
        assert(g.current_session.frame_count > 0, `
    Because we increment inside
    """
        if update_ok {
            input_vec = input()
            g.frame_count += 1
        }
    """
    the 0-th index is free for game_init initial state
`)

        i := g.current_session.frame_count
        db_save_frame(g.db_conn, g.commodino.instance_id, i, recorded_delta_time, recorded_input_keys, 0, frame_checksum)
    }
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1500, 900, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(types.TARGET_FPS)
	rl.SetExitKey(nil)
}

should_restart_game: bool

get_mode_from_args :: proc() -> int {
    // Check environment variable or use default
    // 0 = none, 1 = host, 2 = client
    env_mode := os.get_env_alloc("MULTIPLAYER_MODE", context.temp_allocator)
    if env_mode == "host" {
        return 1
    }
    if env_mode == "client" {
        return 2
    }
    return 0
}

get_host_arg :: proc() -> string {
    host := os.get_env_alloc("MULTIPLAYER_HOST", context.temp_allocator)
    if host == "" {
        return "127.0.0.1"  // default to localhost
    }
    return host
}

// TODO Make that be a string of inputs, and use it for the LLM checks
get_test_input :: proc() -> int {
    // For testing: read MULTIPLAYER_TEST_INPUT env var (0 or 1)
    input_str := os.get_env_alloc("MULTIPLAYER_TEST_INPUT", context.temp_allocator)
    if input_str == "1" {
        return 1
    }
    if input_str == "-1" {
        return -1
    }
    return 0
}

get_db_path :: proc(player_index: int) -> string {
    if player_index == 0 {
        return "host_game_state.db"
    } else if player_index == 1 {
        return "client_game_state.db"
    }
    return "host_game_state.db"
}

@(export)
game_init :: proc() {
    ok: bool
    g = new(Game_Memory)
    g^ = Game_Memory {
        run = true,
    }

    // Set up player index based on mode
    game_mode := get_mode_from_args()
    // TODO use the enum key instead of plain numbers
    if game_mode == 1 {
        fmt.println("=== Starting as HOST ===")
        g.player_index = 0
    } else if game_mode == 2 {
        host_addr := get_host_arg()
        fmt.println("=== Starting as CLIENT, connecting to:", host_addr, "===")
        g.player_index = 1
    } else {
        fmt.println("=== Single player mode ===")
    }

    db_path := get_db_path(g.player_index)
    fmt.println("Using database:", db_path)
    g.db_conn, ok = db_init(db_path)
    if !ok {
        fmt.eprintln("Failed to initialize database")
        free(g)
        g = nil
        return
    }

    // Initialize networking
    if g.player_index == 0 {
        // Host: start listening
        ok = net_init_as_host(&g.net_state)
        if !ok {
            fmt.eprintln("Failed to init as host")
        } else {
            fmt.println("Host initialized, will accept in update loop")
        }
        g.connected_to_host = true  // Host is "active" even without client
    } else if g.player_index == 1 {
        // Client: connect to host
        host_addr := get_host_arg()
        fmt.println("Connecting to host:", host_addr)
        ok = net_init_as_client(&g.net_state, host_addr)
        if ok {
            fmt.println("Connected to host!")
            g.connected_to_host = true
        } else {
            fmt.eprintln("Failed to connect to host")
        }
    }

    update_ok = true
    // TEMP: Disable replay for multiplayer testing
    // loaded := db_load_commodino_struct(g.db_conn, &g.commodino)
    // if loaded {
    //     fmt.println("Successfully loaded commodino_struct from database")
    //     restart_current_session_memory()
    //     restore_recorded_session_rand_gen()
    //     g.commodino.is_replaying = true
    //
    //     g.replay_stmt = db_prepare_replay_stmt(g.db_conn)
    //     g.replay_batch_stmt = db_prepare_replay_batch_stmt(g.db_conn)
    //     replay_frame, ok = db_load_replay_frame_stmt(g.replay_stmt, g.commodino.instance_id, 1)
    //     if !ok {
    //         fmt.eprintln("Failed to load first replay frame")
    //     }
    //     replay_frame_prev_input_keys = {}
    //     when REPLAY_TIMING {
    //         batch_start_time = time.now()
    //         batch_recorded_delta_ns = 0
    //         batch_frame_count = 0
    //         total_recorded_delta_ns = 0
    //         total_wall_clock_ns = 0
    //         replay_start_time = time.now()
    //     }
    // } else {
    //     fmt.println("No saved commodino_struct found, starting fresh")
        restart_current_session_memory()
        reset_current_session_rand_gen()
        db_insert_initial_values(g.db_conn, &g.commodino, types.COMMODINO_STRUCT_VERSION)
    // }
    game_hot_reloaded(g, .HOT_RELOAD)
}

reset_current_session_rand_gen :: proc() {
    // This uses 60+ bits of timestamp ensuring uniqueness
    // across machines and instances without coordination
    // TODO on collision, have the joining player regenerate its id and update it in the record db.
    g.commodino.instance_id = time.time_to_unix_nano(time.now())
    // LATER, the game_session_id will be changed when we join a hosted multiplayer game
    // TODO How do we want to record when we quit a game and join a new one? A new recording?
    //      If so, should we have main menu recordings? or have it be stored before and after the game?
    //      We would be recording the game menu UI at the very least, I guess
    g.commodino.game_session_id = g.commodino.instance_id  // Host: game_session_id = instance_id

    sheep_time_rand_gen_state_seed := rand.uint64()
    g.commodino.sheep_time_rand_gen_state_seed = sheep_time_rand_gen_state_seed

	g.sheep_time_rand_gen_state = rand.create(sheep_time_rand_gen_state_seed)
	g.sheep_time_rand_gen = rand.default_random_generator(&g.sheep_time_rand_gen_state)

    sheep_dir_rand_gen_state_seed := rand.uint64()
    g.commodino.sheep_dir_rand_gen_state_seed = sheep_dir_rand_gen_state_seed

	g.sheep_dir_rand_gen_state = rand.create(sheep_dir_rand_gen_state_seed)
	g.sheep_dir_rand_gen = rand.default_random_generator(&g.sheep_dir_rand_gen_state)
}

restore_recorded_session_rand_gen :: proc() {
    sheep_time_rand_gen_state_seed := g.commodino.sheep_time_rand_gen_state_seed

	g.sheep_time_rand_gen_state = rand.create(sheep_time_rand_gen_state_seed)
	g.sheep_time_rand_gen = rand.default_random_generator(&g.sheep_time_rand_gen_state)

    sheep_dir_rand_gen_state_seed := g.commodino.sheep_dir_rand_gen_state_seed

	g.sheep_dir_rand_gen_state = rand.create(sheep_dir_rand_gen_state_seed)
	g.sheep_dir_rand_gen = rand.default_random_generator(&g.sheep_dir_rand_gen_state)
}

restart_current_session_memory :: proc(){
	g.current_session = {}

	g.sheeps[1] = {
		rect = {200, -10, 10, 10,},
		input = 1,
		speed = {0, 0},
		last_dir_decision = 0,
	}
	g.last_sheep_index += 1

	g.sheeps[2] = {
		rect = {-200, -10, 10, 10,},
		input = -1,
		speed = {0, 0},
		last_dir_decision = 0,
	}
	g.last_sheep_index += 1

	g.sheeps[3] = {
		rect = {-150, -10, 10, 10,},
		input = -1,
		speed = {0, 0},
		last_dir_decision = 0,
	}
	g.last_sheep_index += 1

	g.player_rect = {230, 0, 10, 15}
	g.player_rect.y = -f32(g.player_rect.height)
	g.player2_rect = {-230, 0, 10, 15}
	g.player2_rect.y = -f32(g.player2_rect.height)

	g.lava_height = VOLCANO_HEIGHT/3.5
	g.lava_speed = 0.25
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.run
}

@(export)
game_shutdown :: proc() {
    if g != nil {
        if g.replay_stmt != nil {
            sqlite.finalize(g.replay_stmt)
        }
        if g.db_conn != nil {
            db_close(g.db_conn)
        }
    }
    fmt.println("size_of(g^): ", size_of(g^))
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr, mode: types.Hot_Reload_Mode) {
	g = (^Game_Memory)(mem)

	switch mode {
	case .HOT_RELOAD:
		// Normal hot-reload: preserve everything, just restore the pointer
		// is_replaying stays as it was in the loaded commodino
        // Nothing, no restart or replay to setup

	case .FORCE_RESTART:
		// Full restart: load recording and replay it, fast (skip draws)
		g.commodino.is_replaying = true
		restart_current_session_memory()
		restore_recorded_session_rand_gen()
		g.commodino.replaying_prev_frame_index = 0

		g.replay_stmt = db_prepare_replay_stmt(g.db_conn)
		replay_frame, _ = db_load_replay_frame_stmt(g.replay_stmt, g.commodino.instance_id, 1)
		replay_frame_prev_input_keys = {}
		when REPLAY_TIMING {
			batch_start_time = time.now()
			batch_recorded_delta_ns = 0
			batch_frame_count = 0
			total_recorded_delta_ns = 0
			total_wall_clock_ns = 0
			replay_start_time = time.now()
		}

	case .FORCE_REPLAY:
		// Full restart: load recording and replay it at normal speed
		g.commodino.is_replaying = true
		restart_current_session_memory()
		restore_recorded_session_rand_gen()
		g.commodino.replaying_prev_frame_index = 0

		g.replay_stmt = db_prepare_replay_stmt(g.db_conn)
		replay_frame, _ = db_load_replay_frame_stmt(g.replay_stmt, g.commodino.instance_id, 1)
		replay_frame_prev_input_keys = {}
		when REPLAY_TIMING {
			batch_start_time = time.now()
			batch_recorded_delta_ns = 0
			batch_frame_count = 0
			total_recorded_delta_ns = 0
			total_wall_clock_ns = 0
			replay_start_time = time.now()
		}
	}
}

// TODO CHECK IF WE CAN GET RID OF THOSE TODOS for game_force_*() procedures
// Currently, that continue playing, without replaying
// TODO Make it also continue to record, but on a copy of the game_state.db
// TODO LATER, have it on the same game_state.db, but allow storing a tree of states, instead of sequentially
@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

// Currently, will restart the game fully:
// - Will fetch recording and replay it
// - Will replay (faster) at (DRAW_EVERY_NTH_FRAME times) speed, VS force_replay
// TODO : Fix hot-reloading with record-and-replay,
//   Seems game_force_reload and hot_reloading in general, fails to write
//   to sqlite db: 
//      Failed to begin transaction: out of memory
@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// Currently, will restart the game fully:
// - Will fetch recording and replay it
// - Will replay at (slower) normal speed VS force_restart
// TODO fix this for force_replay:
    // Found 1 difference(s) (recorded -> replayed):
    //   frame_count: 83 -> 82
@(export)
game_force_replay :: proc() -> bool {
	return rl.IsKeyPressed(.F10)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

center_pos :: proc(rect: rl.Rectangle) -> rl.Vector2{
	return {
		rect.x + rect.width/2,
		rect.y + rect.height/2,
	}
}

player_center_pos :: proc(player_pos: rl.Vector2) -> rl.Vector2{
	return {
		player_pos.x + f32( g.player_rect.width )/2,
		player_pos.y + f32( g.player_rect.height )/2,
	}
}

pos_from_rect :: proc(rect: rl.Rectangle) -> rl.Vector2{
	return {rect.x, rect.y}
}

//
// COMMODINO (Record-and-replay, etc)
//

commodino_assert_message : string
