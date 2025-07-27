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

RabbitState :: enum {
	DEFAULT,
	JUMPING,
}

Rabbit :: struct {
	using rect: rl.Rectangle,
	input: rl.Vector2,
	last_dir_decision: i32,
	detection: f32,
	state: RabbitState,
}


Game_Memory :: struct {
	player_pos: rl.Vector2,
	rabbits : [1024]Rabbit,
	player_texture: rl.Texture,
	frame_time: int,
	run: bool,
}

g: ^Game_Memory
// previous_g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.player_pos,
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

update :: proc() {
	delta_time := rl.GetFrameTime()

	input: rl.Vector2

	// if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
	// 	input.y -= 1
	// }
	// if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
	// 	input.y += 1
	// }
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	player_speed :: 60.0
	g.player_pos += input * delta_time * player_speed
	g.frame_time += 1


	rabbit_speed :: 30.0
	rabbit_jump_initial_speed :: 30.0
	for &rabbit, i in g.rabbits {
		if rabbit != {}{
			switch rabbit.state{
			case .JUMPING :{
				if rabbit.y + rabbit.height <= 0{
					rabbit.state = .DEFAULT
					rabbit.input.y = 0
				}
				rabbit.input.y -= 5
			}
			case .DEFAULT :{
				rabbit_center_pos := center_pos(rabbit)
				delta_pos_to_player := player_center_pos(g.player_pos).x - rabbit_center_pos.x
				distance_to_player := math.abs(delta_pos_to_player)
				if distance_to_player < rabbit.detection {
					// We jump above the player
					rabbit.input.x = delta_pos_to_player/distance_to_player
					rabbit.input.y = rabbit_jump_initial_speed
				}
				is_rabbit_on_ground := rabbit.x - rabbit.height == 0
				if is_rabbit_on_ground && rabbit.last_dir_decision > 120{
					rand_time := rand.uint32() % 90
					rand_num := rand.uint32() % 3
					// We have an input between of -1, 0, or  1
					rabbit.input.x = f32(rand_num) - 1
					rabbit.input.y = 0
					rabbit.last_dir_decision = i32(rand_time)
				}
				rabbit.last_dir_decision += 1
				}
			}
			rabbit.x += rabbit.input.x * rabbit_speed * delta_time
			rabbit.y += rabbit.input.y * rabbit_speed * delta_time

		} else if i != 0 {
			break
		}
	}

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode2D(game_camera())
	rl.DrawTextureEx(g.player_texture, g.player_pos, 0, 1, rl.WHITE)
	rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
	rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)

	for rabbit, i in g.rabbits {
		if rabbit != {}{
			rl.DrawRectangleRec(rabbit, rl.WHITE)

			// DEBUG:  center of rabbit
			rabbit_center_pos := center_pos(rabbit)

			left_detection := rabbit_center_pos
			left_detection.x -= rabbit.detection

			right_detection := rabbit_center_pos
			right_detection.x += rabbit.detection

			rl.DrawRectangleV(left_detection, {2,2}, rl.RED)
			rl.DrawRectangleV(right_detection, {2,2}, rl.RED)
		} else if i != 0 {
			break
		}
	}

	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("frame_time: %v\nplayer_pos: %v", g.frame_time, g.player_pos), 5, 5, 8, rl.WHITE)

	rl.EndMode2D()

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1250, 900, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(30)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		player_texture = rl.LoadTexture("assets/round_cat.png"),
	}

	game_hot_reloaded(g)
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
game_hot_reloaded :: proc(mem: rawptr) {
	breakpoint()
	g = (^Game_Memory)(mem)

	g.rabbits[1] = {
		rect = {100, 10, 10, 10,},
		input = {1, 0},
		last_dir_decision = 0,
		detection = 20,
		state = .DEFAULT,
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

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}


center_pos :: proc(rect: rl.Rectangle) -> rl.Vector2 {
	return rl.Vector2{
		rect.x + rect.width/2,
		rect.y + rect.height/2,
	}
}

player_center_pos :: proc(player_pos: rl.Vector2) -> rl.Vector2{
	return rl.Vector2{
		player_pos.x + f32(g.player_texture.width)/2,
		player_pos.y + f32(g.player_texture.height)/2,
	}
}
