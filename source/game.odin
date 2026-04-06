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
import "core:math"
import "core:math/rand"
import "base:runtime"
import "core:math/linalg"
import rl "vendor:raylib"

import "core:hash/xxhash"
import "core:mem"
import sqlite "../vendor/odin-sqlite3/"
// import sa "../vendor/odin-sqlite3/addons/"

import "./types"



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
	// recording_session: Session_Memory,

}

// TODO Use some fixed point math like fixedptc or libfixmath
// TODO Replace f32 with fixed point values

Session_Memory :: struct {
	frame_count: int,
	player_rect : rl.Rectangle,
	sheeps : [1024]Sheep,
	last_sheep_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_sheep_spawn: f32,
	count_sheep_sacrificed: u32,
	sheep_time_rand_gen_state, sheep_dir_rand_gen_state : rand.Default_Random_State,
}


g: ^Game_Memory
// previous_g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT/2.5,
		// target = pos_from_rect(g.player_rect),
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

player_input_down :: proc(my_key: types.UsedKeysEnum) -> bool {
	if g.commodino.is_replaying{
		return g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index+1].keys[my_key].pressed
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
		if g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index+1].keys[my_key].pressed{
            return !g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index].keys[my_key].pressed
        }
        return false
	} else {
        for key in USED_KEY_TO_RL_KEY[my_key] {
            //  NOTE There is one single effect of that for when we have 2 raylib keys to the same used_key
            //  If you were to frame perfect alternate keys being just pressed, you could have multiple frames of that key being "just_pressed"
            //  But It shouldn't be an issue, I think.
            //  Worse case, it will become some speedrun trick or something
            if rl.IsKeyPressed(key){
                return true
            }
        }
        return false
	}
}


input :: proc() -> (input: rl.Vector2){

    if g.commodino.is_replaying{
        
    } else {
        g.commodino.recorded_input_events_count += 1

        // NOTE That for loop, it is equivalent to this:
        // g.commodino.recorded_input_events[g.commodino.recorded_input_events_count].keys = {
        //     .LEFT =  { pressed = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) },
        //     .RIGHT = { pressed = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) },
        //     .ENTER = { pressed = rl.IsKeyDown(.ENTER) },
        // }
        // if we have : 
        // USED_KEY_TO_RL_KEY : [types.UsedKeysEnum][2]rl.KeyboardKey= {
        //         .LEFT =  { .LEFT, .A },
        //         .RIGHT = { .RIGHT, .D },
        //         .ENTER = { .ENTER, .KEY_NULL },
        // }
        // 
        for rl_keys, used_key in USED_KEY_TO_RL_KEY {
			// fmt.println(used_key, rl_keys)
            // m : [2]rl.KeyboardKey = rl_keys
            pressed: bool
            for key in rl_keys{
                pressed = rl.IsKeyDown(key) || pressed
            }
            g.commodino.recorded_input_events_count = min(types.MAX_FRAME_COUNT, g.commodino.recorded_input_events_count)
            g.commodino.recorded_input_events[g.commodino.recorded_input_events_count].keys[used_key] = {
                pressed = pressed,
            }
        }
    }


	if player_input_just_pressed(.ENTER){
		should_restart_game = true
	}

	if g.lava_height >= VOLCANO_HEIGHT{
		return
	}


	// if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
	// 	input.y -= 1
	// }
	// if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
	// 	input.y += 1
	// }

	if player_input_down(.LEFT) {
		input.x -= 1
	}
	if player_input_down(.RIGHT) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	return input
}

latest_delta_time: f32

SHEEP_LAVA_WORTH :: 75
update :: proc(input: rl.Vector2) -> (ok:bool) {
	commodino_assert_message = "" // reset assert_message


    delta_time : f32 = rl.GetFrameTime()
    if g.commodino.is_replaying{
        latest_delta_time = delta_time
        frame_index := g.commodino.replaying_prev_frame_index+1
        delta_time = g.commodino.delta_times[frame_index]
        assert(frame_index == 1 || delta_time > 0, fmt.tprintf("Unless we just started (1st frame), delta_time should be around 1/FPS, not zero"))
    }else{
        frame_index := g.frame_count
        assert(frame_index == 1 || delta_time > 0, fmt.tprintf("Unless we just started (1st frame), delta_time should be around 1/FPS, not zero"))
        g.commodino.delta_times[g.frame_count] = delta_time
    }

	player_speed :: 60.0
	g.player_rect.x += input.x * delta_time * player_speed
	g.player_rect.y += input.y * delta_time * player_speed
	g.player_rect.x = max(g.player_rect.x, LEFT_HOLE_START_X)
	g.player_rect.x = min(g.player_rect.x, RIGHT_HOLE_START_X-g.player_rect.width)


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
	// commodino_assert_message = fmt.tprintf("test?")

	// if g.last_sheep_spawn > 10{
	// 	commodino_assert_message = fmt.tprintf("Too much sheeps, expected less than 10, instead got %v", g.last_sheep_spawn)
	// 	return false // assert failed in update
	// }

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

save_new_frame_checksum :: proc(frame_checksum: ^types.Session_Memory_Checksums, current_session: ^Session_Memory){
    frame_checksum.frame_count = current_session.frame_count
    frame_checksum.player_rect.x  = current_session.player_rect.x 
    frame_checksum.player_rect.y  = current_session.player_rect.y 
    // Hash only the active slice of sheeps
    frame_checksum.sheeps = xxhash.XXH3_64_default(mem.byte_slice(&current_session.sheeps[0], size_of(Sheep) * (current_session.last_sheep_index + 1)))
    frame_checksum.last_sheep_index = current_session.last_sheep_index
    frame_checksum.lava_height = current_session.lava_height
    frame_checksum.lava_speed = current_session.lava_speed
    frame_checksum.last_sheep_spawn = current_session.last_sheep_spawn
    frame_checksum.count_sheep_sacrificed = current_session.count_sheep_sacrificed
    frame_checksum.sheep_time_rand_gen_state = xxhash.XXH3_64_default(mem.byte_slice(&current_session.sheep_time_rand_gen_state, size_of(current_session.sheep_time_rand_gen_state))) 
    frame_checksum.sheep_dir_rand_gen_state = xxhash.XXH3_64_default(mem.byte_slice(&current_session.sheep_dir_rand_gen_state, size_of(current_session.sheep_dir_rand_gen_state))) 
}

@(export)
game_update :: proc() {
    // TODO Check if it is actually useful to record the restart on the same game_state.db
    // It is an implicit branch-off, but I'm not yet sure of the utility of it, unless we also did do a code change
    //  Since we reset all the game data from the game start
    if should_restart_game{
        // We keep appending to the recording

        // Copy pointer to Game_Memory
        old_g := g

        // re create a new Game_Memory, set to g
        game_init()

        // We restore the commodino stuff
        g.commodino = old_g.commodino
        // We allow continuing to append to the commodino lists
        g.frame_count = old_g.frame_count

        // game_init does not free the old_g
        free(old_g)

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
		input_vec = input()
	    g.frame_count += 1
	}
	update_ok = update(input_vec)

    DRAW_EVERY_NTH_FRAME :: 500
	// fmt.println(commodino_assert_message)
    if g.commodino.is_replaying{
        if g.commodino.replaying_prev_frame_index % DRAW_EVERY_NTH_FRAME == 0{
            draw()
        }
    } else {
        draw()
    }


	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)

    _ :: mem
    _ :: xxhash
    frame_checksum : types.Session_Memory_Checksums
    save_new_frame_checksum(&frame_checksum, &g.current_session)


    // // HACK figure out why we have an off-by-one recording vs replaying
    // //    Might be that we have frame_count be 0, but store on 1.. or something
    // frame_checksum.frame_count = 0

    if g.commodino.is_replaying{
        i := g.commodino.replaying_prev_frame_index+1

        recorded_frame_checksum := g.commodino.frame_checksums[i]

        // FOR FUN/PERF, to see how quickly we run our replays,
        // NOTE, rl.GetFrameTime() actually "Returns time in seconds for last frame drawn (delta time)", not from the last call to it
        //      So we multiply by the amount of skipped draw frames, to approximate the actual delta_time, of those updates and that one draw
        // TODO: Use rl.GetTime() and compare, instead, to have something closer to the delta_time
        PRINT_REPLAY_SPEED :: true
        when PRINT_REPLAY_SPEED {
            fmt.printfln(
                "replaying frame[%d], delta_time: recorded(%.9f)/replaying(%.9f) = %.9f times faster",
                i,
                g.commodino.delta_times[i], latest_delta_time/DRAW_EVERY_NTH_FRAME,
                g.commodino.delta_times[i] / latest_delta_time * DRAW_EVERY_NTH_FRAME)
        }
        
        config_diffs := diff_struct(types.Session_Memory_Checksums, recorded_frame_checksum, frame_checksum)
        defer delete(config_diffs)
        print_on_no_diff :: false
        print_diffs(config_diffs, print_on_no_diff)

        // if (current_frame_checksum != frame_checksum){
        if len(config_diffs) > 0{
            commodino_assert_message = fmt.tprintf("Replay desync, check stdout: '%v', '%v'", g.commodino.frame_checksums[i], frame_checksum) 
            // breakpoint()
            // fmt.eprintln(commodino_assert_message)
            draw()
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
        g.commodino.frame_checksums[i] = frame_checksum
        db_update_commodino_struct(db_conn, g.commodino)
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

db_conn: ^sqlite.Connection
@(export)
game_init :: proc() {
    ok: bool
    db_conn, ok = db_init("game_state.db")
    if !ok {
        fmt.eprintln("Failed to initialize database")
        return
    }
    // breakpoint()
    
    update_ok = true // Allow getting the input right after init, as we can't have errors yet
    g = new(Game_Memory)

    g^ = Game_Memory {
        run = true,
        // You can put textures, sounds and music in the `assets` folder. Those
        // files will be part any release or web build.
    }

    // Try to load commodino_struct from database
    loaded := db_load_commodino_struct(db_conn, &g.commodino)
    if loaded {
        fmt.println("Successfully loaded commodino_struct from database")
        
        // After loading, you may want to restore the random number generators
        // from the loaded seeds
        restore_recorded_session_rand_gen()
        g.commodino.is_replaying = true
    } else {
        fmt.println("No saved commodino_struct found, starting fresh")
        
        // Initialize new session since we didn't load anything
        restart_current_session_memory()
        reset_current_session_rand_gen()
        db_insert_initial_values(db_conn, &g.commodino, types.COMMODINO_STRUCT_VERSION)

    // TODO MAYBE, reset most of Commodino
        g.commodino.frame_checksums = {}

        frame_checksum: types.Session_Memory_Checksums
        save_new_frame_checksum(&frame_checksum, &g.current_session)
        g.commodino.frame_checksums[0] = frame_checksum
    }

    game_hot_reloaded(g, g.commodino.is_replaying)
}

reset_current_session_rand_gen :: proc() {
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
    db_close(db_conn)
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
game_hot_reloaded :: proc(mem: rawptr, is_replaying: bool = false) {
	g = (^Game_Memory)(mem)
	g.commodino.is_replaying = is_replaying
	if g.commodino.is_replaying{
		// Restart the game
		restart_current_session_memory()

        // To set the recorded seeds into new random generators
        restore_recorded_session_rand_gen()

		// We start counting from 0, check always this and next frame_index
		g.commodino.replaying_prev_frame_index = 0
	}



	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

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
    // ret := g.current_session.frame_count > 10
    // g.current_session.frame_count = 0
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
