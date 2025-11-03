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
_ :: fmt
import "core:math"
import "core:math/rand"
import "base:runtime"
import "core:math/linalg"
import rl "vendor:raylib"

// For debugging traps
import "core:sys/posix"

// To allow debugging tests:
//  1. add a call to breakpoint()
//  2. call the test or tests from main()
//  3. `odin run tests/ -debug -o:none`
//  4. `gdb tests.bin`
//  5. `run`
//  6. `next` a few times until you are out of th breakpoint() proc
//  7. profit
//
//  Bonus:
//  you can use gdb's:
//   - `display` to see the state of expression on every break,
//   - `watch` break on any write
//   - `rwatch` break on any read
//   - `awatch` break on any read or write
breakpoint :: proc () {
	posix.kill(posix.getpid(), .SIGTRAP)
}



PIXEL_WINDOW_HEIGHT :: 180

SheepState :: enum{
	DEFAULT,
	JUMPING,
	FALLING,
}

Sheep :: struct {
	using rect: rl.Rectangle,
	input: f32,
	speed: rl.Vector2,
	last_dir_decision: i32,
	state: SheepState,
}

Carrot :: struct {
	using rect: rl.Rectangle,
}

MAX_FRAME_COUNT :: TARGET_FPS * 60 /*secs in minute*/ * 10 /* minutes */ // 60 /*minutes in hour*/ * 1


UsedKeysEnum :: enum{
	LEFT,
	RIGHT,
	ENTER,
}

KeyState :: struct{
	pressed : bool,
}
CachedInput :: struct {
	keys : [UsedKeysEnum]KeyState,
}


Game_Memory :: struct {
	run: bool,
	commodino : CommodinoStruct,
	using current_session : Session_Memory,
	// recording_session: Session_Memory,
	// +1, because we don't do anything to the 0th element, it is a null element

	sheep_time_rand_gen_state, sheep_dir_rand_gen_state : rand.Default_Random_State,
	sheep_time_rand_gen, sheep_dir_rand_gen : runtime.Random_Generator,
}
Session_Memory :: struct {
	frame_time: int,
	player_rect : rl.Rectangle,
	sheeps : [1024]Sheep,
	last_sheep_index: u32,
	carrots : [1024]Carrot,
	last_carrot_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_sheep_spawn: f32,
	count_sheep_sacrificed: u32,
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

// TODO unify the player_input_*_down, giving the UsedKeysEnum.* instead, cuts down on plain repetition.
player_input_left_down :: proc() -> bool {
	if g.commodino.is_replaying{
		return g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index+1].keys[UsedKeysEnum.LEFT].pressed
	} else {
		return rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A)
	}
}

player_input_right_down:: proc() -> bool{
	if g.commodino.is_replaying{
		return g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index+1].keys[UsedKeysEnum.RIGHT].pressed
	} else {
		return rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D)
	}
}

// TODO unify the player_input_*_just_pressed, giving the UsedKeysEnum.* instead, cuts down on plain repetition.
player_input_enter_just_pressed:: proc() -> bool {
	if g.commodino.is_replaying{
		if g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index+1].keys[UsedKeysEnum.ENTER].pressed{
			// just_pressed means : previous frame was not pressed
			return !g.commodino.recorded_input_events[g.commodino.replaying_prev_frame_index].keys[UsedKeysEnum.ENTER].pressed
		}
		return false
	} else {
		return rl.IsKeyPressed(.ENTER)
	}
}

input :: proc() -> (input: rl.Vector2){

        mouse_pos := rl.GetMousePosition()
    // commodino_input :: proc() {
        if rl.IsMouseButtonPressed(.LEFT){
            if mouse_pos.y > 0 && mouse_pos.y < SCRUBBER_HEIGHT - SCRUBBER_PADDING {
                // If we are clicking inside the playback/recording scrubber
                g.commodino.is_dragging_playback_scrubber = true
                g.commodino.target_frame_index = int(mouse_pos.x / f32(rl.GetScreenWidth())) * g.commodino.recorded_input_events_count
                return
            }
        }
        if g.commodino.is_dragging_playback_scrubber{
            if !rl.IsMouseButtonDown(.LEFT){
                g.commodino.is_dragging_playback_scrubber = false
            }
            g.commodino.target_frame_index = int(mouse_pos.x / f32(rl.GetScreenWidth())) * g.commodino.recorded_input_events_count
        }
    // }
    // commodino_input()

    if g.commodino.is_replaying {
        g.commodino.replaying_prev_frame_index += 1
        // We read from g.commodino.recorded_input_events in player_input_* procs

        // g.commodino.recorded_input_events[g.commodino.].keys = {
        //     .LEFT =  { pressed = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) },
        //     .RIGHT = { pressed = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) },
        //     .ENTER = { pressed = rl.IsKeyPressed(.ENTER) },
        // }
    } else {
       // We are either replaying OR Recording 

        g.commodino.recorded_input_events_count += 1
        g.commodino.recorded_input_events[g.commodino.recorded_input_events_count].keys = {
            .LEFT =  { pressed = rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) },
            .RIGHT = { pressed = rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) },
            .ENTER = { pressed = rl.IsKeyPressed(.ENTER) },
        }
    }


	if player_input_enter_just_pressed(){
		game_init()
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

	if player_input_left_down() {
		input.x -= 1
	}
	if player_input_right_down() {
		input.x += 1
	}
	// if rl.IsKeyPressed(.SPACE){
	// 	g.carrots[g.last_carrot_index+1] = Carrot{
	// 		x = g.player_rect.x + f32( g.player_rect.width ) /2 - CARROT_WIDTH/2,
	// 		y = 0 - CARROT_WIDTH,
	// 		width = CARROT_WIDTH,
	// 		height = CARROT_WIDTH,
	// 	}
	// 	g.last_carrot_index += 1
	// }

	input = linalg.normalize0(input)
	return input
}

SHEEP_LAVA_WORTH :: 75
CARROT_WIDTH :: 5.0
update :: proc(input: rl.Vector2) -> (ok:bool) {
	commodino_assert_message = "" // reset assert_message

	delta_time := rl.GetFrameTime()

	player_speed :: 60.0
	g.player_rect.x += input.x * delta_time * player_speed
	g.player_rect.y += input.y * delta_time * player_speed
	g.player_rect.x = max(g.player_rect.x, LEFT_HOLE_START_X)
	g.player_rect.x = min(g.player_rect.x, RIGHT_HOLE_START_X-g.player_rect.width)
	g.frame_time += 1


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
	commodino_assert_message = fmt.tprintf("test?")

	if g.last_sheep_spawn > 10{
		commodino_assert_message = fmt.tprintf("Too much sheeps, expected less than 10, instead got %v", g.last_sheep_spawn)
		return false // assert failed in update
	}

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
					sheep.input =  f32(rand_num) - 1
					if ( sheep.input == -1 && is_sheep_near_left_hole ) || ( sheep.input == 1 && is_sheep_near_right_hole ) {
						sheep.input = -sheep.input
					}
					sheep.last_dir_decision = i32(rand_time)
				}

				if distance_player_sheep <= SHEEP_DETECTION {
					sheep.state = .JUMPING
					sheep.speed.y = SHEEP_INITIAL_JUMP_SPEED
					sheep.input = delta_x_player_sheep / distance_player_sheep
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
			sheep.speed.x = sheep.input * SHEEP_SPEED
			sheep.x += sheep.speed.x * delta_time
			sheep.y += sheep.speed.y * delta_time
			sheep.last_dir_decision += 1
		}
	}

	carrot_loop: for &carrot, i in g.carrots{
		if carrot != {}{

		} else if i != 0 {
			break
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

	carrot_loop: for &carrot, i in g.carrots{
		if carrot != {}{
			rl.DrawRectangleRec(carrot, rl.ORANGE)
		} else if i != 0 {
			break
		}
	}

	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	if g.lava_height >= VOLCANO_HEIGHT{
		rl.DrawRectangle(30-5, 100-5, 270, 75, {100, 100, 100, 230})
		rl.DrawText(fmt.ctprintf(
"               GAME OVER\nSurvived %v seconds and %v frames\n  Sacrificed %v sheeps to the void\n      Press ENTER to restart",
			g.frame_time/60, g.frame_time%60, g.count_sheep_sacrificed,
		), 30, 100, 15, rl.WHITE)

	}

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	// when ODIN_DEBUG {
	if commodino_assert_message != ""{
		rl.DrawText(fmt.ctprintf("assert_message:\"%v\", \nreplaying_prev_frame_index: %v,\ng.commodino.is_replaying: %#v,\ng.commodino.is_dragging_playback_scrubber:%v,\n", commodino_assert_message, g.commodino.replaying_prev_frame_index, g.commodino.is_replaying, g.commodino.is_dragging_playback_scrubber), 5, 5, 8, rl.WHITE)
	}
		// rl.DrawText(fmt.ctprintf("frame_time: %v\nplayer_rect: %v\nlast_carrot_index: %v\nplayer_texture.width, height: %v, %v", g.frame_time, g.player_rect, g.last_carrot_index, g.player_rect.width, g.player_rect.height), 5, 5, 8, rl.WHITE)
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

Update_State :: enum {
    PLAYING,
    SCRUBBING,
    REPLAYING,
    REPLAY_UNTIL_ASSERT_FIXED,
}
update_state : Update_State

@(export)
game_update :: proc() {
	// Prevent calling the context.random_generator,
	// instead we want our system-specifig rng
	context.random_generator = runtime.Random_Generator{
		procedure = prevent_rng_call,
		data = nil,
	}

    switch update_state {
    case .PLAYING:
            if g.commodino.is_dragging_playback_scrubber{
                update_state = .SCRUBBING
                g.commodino.replaying_prev_frame_index = 0
                break
            } 
            if update_ok {
                input_vec = input()
            }
            _ = update(input_vec)
    case .SCRUBBING:
        // If still scrubbing, don't generate more frames than needed, and draw at the end of this frame
        for i:=g.commodino.replaying_prev_frame_index; i <= g.commodino.target_frame_index; i+=1 {
            input_vec = input()
            _ = update(input_vec)
        }

        draw()
        
        // TODO Have the simulation pause to draw if we are near the FPS limit or something, maybe just draw every Xth frame?
        // If no longer scrubbing, go to replaying for next frame, as we now want to continue looking at the game
    case .REPLAYING:
    case .REPLAY_UNTIL_ASSERT_FIXED:
    }

	// fmt.println(commodino_assert_message)
	draw()

    // if !update_ok do update_state = .REPLAY_UNTIL_ASSERT_FIXED

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

TARGET_FPS :: 30
@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1500, 900, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(TARGET_FPS)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	update_ok = true // Allow getting the input right after init, as we can't have errors yet
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
	}


	restart_current_session_memory()
	game_hot_reloaded(g)
}

restart_current_session_memory :: proc(){
	g.current_session = {}

    sheep_time_rand_gen_state_seed := rand.uint64()
    // g.commodino.sheep_time_rand_gen_state_seed = sheep_time_rand_gen_state_seed

	g.sheep_time_rand_gen_state = rand.create(seed)
	g.sheep_time_rand_gen = rand.default_random_generator(&g.sheep_time_rand_gen_state)

    sheep_dir_rand_gen_state_seed = rand.uint64()
    // g.commodino.sheep_dir_rand_gen_state_seed = sheep_dir_rand_gen_state_seed

	g.sheep_dir_rand_gen_state = rand.create(sheep_dir_rand_gen_state_seed)
	g.sheep_dir_rand_gen = rand.default_random_generator(&g.sheep_dir_rand_gen_state)

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

	g.last_carrot_index = 0
	g.carrots = {}

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

		// We start counting from 0, check always this and next frame_index
		g.commodino.replaying_prev_frame_index = 0
	}



	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

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


CommodinoStruct ::struct {
	recorded_input_events : [MAX_FRAME_COUNT+1]CachedInput,
    recorded_input_events_count : int,
    replaying_prev_frame_index: int,
    target_frame_index: int,

    is_replaying: bool,
    is_dragging_playback_scrubber: bool,
}

SCRUBBER_HEIGHT :: 30.0
SCRUBBER_PADDING :: 5.0
