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

RabbitState :: enum{
	DEFAULT,
	JUMPING,
	FALLING,
}

Rabbit :: struct {
	using rect: rl.Rectangle,
	input: f32,
	speed: rl.Vector2,
	last_dir_decision: i32,
	state: RabbitState,
}

Carrot :: struct {
	using rect: rl.Rectangle,
}

Game_Memory :: struct {
	frame_time: int,
	run: bool,
	player_rect : rl.Rectangle,
	rabbits : [1024]Rabbit,
	last_rabbit_index: u32,
	carrots : [1024]Carrot,
	last_carrot_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_rabbit_spawn: f32,
}

g: ^Game_Memory
// previous_g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = pos_from_rect(g.player_rect),
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
RABBIT_LAVA_WORTH :: 150
CARROT_WIDTH :: 5.0
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
	if rl.IsKeyPressed(.SPACE){
		g.carrots[g.last_carrot_index+1] = Carrot{
			x = g.player_rect.x + f32( g.player_rect.width ) /2 - CARROT_WIDTH/2,
			y = 0 - CARROT_WIDTH,
			width = CARROT_WIDTH,
			height = CARROT_WIDTH,
		}
		g.last_carrot_index += 1
	}

	input = linalg.normalize0(input)
	player_speed :: 60.0
	g.player_rect.x += input.x * delta_time * player_speed
	g.player_rect.y += input.y * delta_time * player_speed
	g.frame_time += 1


	g.lava_height += g.lava_speed
	g.lava_speed *= 1.0001

	if g.last_rabbit_spawn > 120 {
		g.rabbits[g.last_rabbit_index+1] = Rabbit{
			rect= rl.Rectangle{
				-5, -20, 10, 10,
			},
			state=.JUMPING,
		}
		g.last_rabbit_index += 1
		g.last_rabbit_spawn = 0
	}
	g.last_rabbit_spawn += 1

	RABBIT_SPEED :: 30.0
	RABBIT_INITIAL_JUMP_SPEED :: -60.0
	GRAVITY_ON_RABBIT :: 60.0
	RABBIT_DETECTION :: 20.0
	// Reverse loop, to allow for unordered remove of rabbits that fell in the hole
	rabbit_loop: for i := g.last_rabbit_index;  i>0; i-=1 {
		rabbit := &g.rabbits[i]
		if rabbit != {}{
			is_rabbit_over_ground := rabbit.x > LEFT_HOLE_START_X && rabbit.x < RIGHT_HOLE_START_X
			switch rabbit.state{
			case .DEFAULT:{
				if !is_rabbit_over_ground{
					rabbit.state = .FALLING
					continue
				}
				player_center_pos := player_center_pos(pos_from_rect(g.player_rect))
				rabbit_center_pos := center_pos(rabbit.rect)

				delta_x_player_rabbit := player_center_pos.x - rabbit_center_pos.x
				distance_player_rabbit := math.abs(delta_x_player_rabbit)

				if distance_player_rabbit <= RABBIT_DETECTION {
					rabbit.state = .JUMPING
					rabbit.speed.y = RABBIT_INITIAL_JUMP_SPEED
					rabbit.input = delta_x_player_rabbit / distance_player_rabbit
					// continue rabbit_loop
				}

				if rabbit.last_dir_decision > 120{
					rand_time := rand.uint32() % 90
					rand_num := rand.uint32() % 3
					// We have an input between of -1, 0, or  1
					rabbit.input =  f32(rand_num) - 1
					rabbit.last_dir_decision = i32(rand_time)
				}
			}
			case .JUMPING:{
				rabbit.speed.y += GRAVITY_ON_RABBIT * delta_time
				is_rabbit_at_ground_level := rabbit.y + rabbit.height >= 0
				if is_rabbit_at_ground_level{
					if is_rabbit_over_ground && is_rabbit_at_ground_level{
						rabbit.speed.y = 0
						rabbit.state = .DEFAULT
					} else {
						rabbit.state = .FALLING
					}
				}
			}
			case .FALLING: {
				rabbit.speed.y += GRAVITY_ON_RABBIT * delta_time
				is_rabbit_deep_in_hole := rabbit.y + rabbit.height >= 100
				if is_rabbit_deep_in_hole {
					g.lava_height -= RABBIT_LAVA_WORTH
					if g.lava_height < 0{
						g.lava_height = 1
					}

					// Unordered remove of rabbit, by replacing by last rabbit of g.rabbits
					// Yes, if it is already the last rabbit, this line does nothing, but that's alright
					g.rabbits[i] = g.rabbits[g.last_rabbit_index]
					// No need to clear the previous last rabbit, because we will write over it when we use that slot
					// g.rabbits[g.last_rabbit_index] = {}
					g.last_rabbit_index -= 1
					continue
				}
			}
			}
			rabbit.speed.x = rabbit.input * RABBIT_SPEED
			rabbit.x += rabbit.speed.x * delta_time
			rabbit.y += rabbit.speed.y * delta_time
			rabbit.last_dir_decision += 1
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
}

VOLCANO_CENTER_X: f32
VOLCANO_HEIGHT :: 300

VOLCANO_TOP_Y :: 100
VOLCANO_BASE_Y :: VOLCANO_TOP_Y + VOLCANO_HEIGHT
VOLCANO_SIDE_WIDTH :: 500
VOLCANO_INNER_WIDTH :: 50

LEFT_HOLE_START_X :: -500
RIGHT_HOLE_START_X :: 200

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	VOLCANO_CENTER_X = 1000.0


	rl.DrawTriangle({VOLCANO_CENTER_X-30, VOLCANO_BASE_Y},{VOLCANO_CENTER_X, 0},{VOLCANO_CENTER_X+30,VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawTriangle({0,0},{0, 30},{30,0}, rl.BROWN)

	VOLCANO_CENTER_X -= g.player_rect.x /10
	// rl.DrawTriangle({VOLCANO_CENTER_X,0},{VOLCANO_CENTER_X-30, VOLCANO_BASE_Y},{VOLCANO_CENTER_X+30, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawTriangle({VOLCANO_CENTER_X-VOLCANO_INNER_WIDTH,VOLCANO_TOP_Y},{VOLCANO_CENTER_X-VOLCANO_INNER_WIDTH-VOLCANO_SIDE_WIDTH, VOLCANO_BASE_Y},{VOLCANO_CENTER_X-VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawTriangle({VOLCANO_CENTER_X+VOLCANO_INNER_WIDTH,VOLCANO_TOP_Y},{VOLCANO_CENTER_X+VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y},{VOLCANO_CENTER_X+VOLCANO_INNER_WIDTH+VOLCANO_SIDE_WIDTH, VOLCANO_BASE_Y}, rl.BROWN)
	rl.DrawRectangleRec({VOLCANO_CENTER_X-VOLCANO_INNER_WIDTH, VOLCANO_BASE_Y-g.lava_height, VOLCANO_INNER_WIDTH*2, g.lava_height}, ( rl.RED/2+rl.ORANGE/2 ) )

	rl.BeginMode2D(game_camera())

	rl.DrawRectangleGradientV(LEFT_HOLE_START_X, 0, RIGHT_HOLE_START_X-LEFT_HOLE_START_X, 100, rl.BROWN, rl.DARKBROWN)
	// rl.DrawTextureEx(g.player_rect, pos_from_rect(g.player_rect), 0, 1, rl.WHITE)
	// rl.DrawTextureEx(g.player_rect, pos_from_rect(g.player_rect), 0, 1, rl.WHITE)
	rl.DrawRectangleRec(g.player_rect, rl.DARKPURPLE)
	rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)

	for i in 0..=g.last_rabbit_index {
		rabbit := g.rabbits[i]
		if rabbit != {}{
			rl.DrawRectangleRec(rabbit, rl.WHITE)
		} else if i != 0 {
			// We ignore the NULL Rabbit
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

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("frame_time: %v\nplayer_rect: %v\nlast_carrot_index: %v\nplayer_texture.width, height: %v, %v", g.frame_time, g.player_rect, g.last_carrot_index, g.player_rect.width, g.player_rect.height), 5, 5, 8, rl.WHITE)
	if g.rabbits[1] != {} {
		rl.DrawText(fmt.ctprintf("g.rabbits[1]: %#v", g.rabbits[1]), 200, 5, 8, rl.WHITE)
	}

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
	g = (^Game_Memory)(mem)

	g.rabbits[1] = {
		rect = {100, -10, 10, 10,},
		input = 1,
		speed = {0, 0},
		last_dir_decision = 0,
	}
	g.last_rabbit_index += 1

	g.last_carrot_index = 0
	g.carrots = {}

	g.player_rect = {0, 0, 20, 24}
	g.player_rect.y = -f32(g.player_rect.height)


	g.lava_height = VOLCANO_HEIGHT/4
	g.lava_speed = 0.5

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
