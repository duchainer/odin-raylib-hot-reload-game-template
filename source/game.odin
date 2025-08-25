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
import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 540

Circle :: struct {
	center: rl.Vector2,
	radius: f32,
	color: rl.Color,
}

StateJumping :: struct {
	jump_start_frame: int,
	jump_height: int,
	jump_duration: f32,
}

StateGrounded :: struct {

}

StateDead :: struct {

}


PlayerStates :: union #no_nil {
	StateGrounded,
	StateJumping,
	StateDead,
}
Player :: struct {
	using circle: Circle,
	state : PlayerStates,
	max_radius: f32,
	default_color: rl.Color,
}

Laser :: struct {
	p1, p2: rl.Vector2,
	p1_velocity, p2_velocity: rl.Vector2,
	velocity: rl.Vector2,
	color: rl.Color,
}

Game_Memory :: struct {
	player : Player,
	rope : struct {
		is_in_front: bool,
		positive_ping_pong_t: f32,
	},
	lasers : [64]Laser,
	lasers_count : int,
	player_texture: rl.Texture,
	frame_count: int,
	run: bool,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.player.center,
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

update :: proc() {
	input: rl.Vector2

	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		input.y -= 1
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		input.y += 1
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	// Rope jumping
	// rope_modulo_frame_count is between 0.0 and SECS_TO_DO_FULL_ROPE_REVOLUTION
	rope_modulo_frame_count := math.mod(f32(g.frame_count) / 60, SECS_TO_DO_FULL_ROPE_REVOLUTION)

	// positive_ping_pont_t is between 0.0 and SECS_TO_DO_FULL_ROPE_REVOLUTION/2
	// because we ping-pong between the min and max values
	if rope_modulo_frame_count > SECS_TO_DO_FULL_ROPE_REVOLUTION/2{
		g.rope.positive_ping_pong_t = SECS_TO_DO_FULL_ROPE_REVOLUTION - rope_modulo_frame_count
	} else{
		g.rope.positive_ping_pong_t = rope_modulo_frame_count
	}

	g.rope.is_in_front = ( rope_modulo_frame_count == g.rope.positive_ping_pong_t )

	switch v in g.player.state {
		case StateJumping : {
			jump_progress : f32=  f32(g.frame_count - v.jump_start_frame)/( f32(60) * v.jump_duration )
			if jump_progress >= 1.0{
				g.player.radius = g.player.max_radius
				g.player.state = StateGrounded{}
				g.player.color = g.player.default_color
			} else {
				ping_pong_jump_progress : f32 = jump_progress
				if jump_progress >= 0.5 {
					ping_pong_jump_progress	= 1.0 - jump_progress
				}
				g.player.radius = g.player.max_radius * (1-2*ping_pong_jump_progress*ping_pong_jump_progress)
				g.player.color.a = u8(f32(g.player.default_color.a) * (1-2*ping_pong_jump_progress*ping_pong_jump_progress))

			}

		}
		case StateGrounded :{
			if (
				SECS_TO_DO_FULL_ROPE_REVOLUTION/2 - 0.1 < rope_modulo_frame_count
					&& rope_modulo_frame_count < SECS_TO_DO_FULL_ROPE_REVOLUTION/2 + 0.1
			) {
				// if we have to jump and haven't yet
				g.player.state = StateJumping{
					jump_start_frame = g.frame_count,
					jump_height = 15,
					jump_duration = 1.0,
				}
			} else {
				for i:= g.lasers_count; i>0; i-=1{
					laser := g.lasers[i]
					if rl.CheckCollisionCircleLine(g.player.center, g.player.radius, laser.p1, laser.p2){
						g.player.state = StateDead{}
						break
					}
				}
			}
		}
	case StateDead : {}
	}

	delta_time := rl.GetFrameTime()

	for i:= g.lasers_count; i>0; i-=1{
		laser := &g.lasers[i]
		laser.p1.x += delta_time * (laser.p1_velocity.x + laser.velocity.x)
		laser.p1.y += delta_time * (laser.p1_velocity.y + laser.velocity.y)
		laser.p2.x += delta_time * (laser.p1_velocity.x + laser.velocity.x)
		laser.p2.y += delta_time * (laser.p1_velocity.y + laser.velocity.y)
	}

	input = linalg.normalize0(input)
	g.player.center += input * delta_time * 100
	// We round the player pos, to have the shadow always centered under the player
	// And it is using integer, so we have to use whole numbers
	g.player.center = {
		math.round(g.player.center.x),
		math.round(g.player.center.y),
	}
	g.frame_count += 1

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	// Test in itch.io window size
	rl.SetWindowSize(WINDOW_WIDTH, WINDOW_HEIGHT)
}

SECS_TO_DO_FULL_ROPE_REVOLUTION :: 2.0

draw :: proc() {
	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())

	rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

	rl.BeginMode2D(game_camera())

	shadow_center := [2]i32{i32(g.player.center.x), i32(math.round(g.player.center.y+g.player.max_radius))}
	rl.DrawEllipse(shadow_center.x, shadow_center.y, g.player.radius, 3, rl.BLACK)

	if _, ok := g.player.state.(StateJumping); ok {
		// We draw the lasers behind the player if the player is jumping

		for i:= g.lasers_count; i>0; i-=1{
			laser := g.lasers[i]
			rl.DrawLineEx(laser.p1, laser.p2, 4, laser.color)
		}

	}

	// Draw Rope
	{
		// ping-pongs between -1.0 and 1.0
		t : f32
		{
			old_value := g.rope.positive_ping_pong_t
			old_min : f32 = 0.0
			old_max : f32 = SECS_TO_DO_FULL_ROPE_REVOLUTION/2
			new_min : f32 = -1.0
			new_max : f32 = +1.0
			t = math.remap(old_value, old_min, old_max, new_min, new_max)
		}
		points: []rl.Vector2 = {
			{g.player.center.x - g.player.radius - 4, g.player.center.y},
			{g.player.center.x - g.player.radius - 4, g.player.center.y},
			{g.player.center.x, g.player.center.y + g.player.radius * t},
			{g.player.center.x + g.player.radius + 4, g.player.center.y},
			{g.player.center.x + g.player.radius + 4, g.player.center.y},
		}
		thick: f32 = 4
		color := rl.PURPLE

		if g.rope.is_in_front{
			// moving rope downward
			// We draw the player on behind the rope

			rl.DrawCircleV(g.player.center, g.player.radius, g.player.color)
			rl.DrawSplineCatmullRom(raw_data(points[:]), i32(len(points)), thick, color)// Draw spline: B-Spline, minimum 4 points
		} else {
			// moving rope upward
			// We draw the player on top of the rope

			rl.DrawSplineCatmullRom(raw_data(points[:]), i32(len(points)), thick, color)// Draw spline: B-Spline, minimum 4 points
			rl.DrawCircleV(g.player.center, g.player.radius, g.player.color)
		}
	}

	if _, ok := g.player.state.(StateJumping); !ok {
		// We draw the lasers over the player if the player is not jumping

		for i:= g.lasers_count; i>0; i-=1{
			laser := g.lasers[i]
			rl.DrawLineEx(laser.p1, laser.p2, 4, laser.color)
		}

	}

	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.

	rl.EndMode2D()
	rl.DrawText(fmt.ctprintf("frame_count: %v\nplayer_pos: %v\nmouse_pos: %v", g.frame_count, g.player.center, rl.GetMousePosition()), 5, 5, 16, rl.GRAY)
	rl.DrawText(fmt.ctprintf("screen_resolution: %v, %v\nplayer: %#v", screen_width, screen_height, g.player), i32(screen_width)-300, 5, 16, rl.GRAY)

	// To test the real resolution
	rl.DrawRectangleLinesEx(
		{0,0, screen_width, screen_height},
		2, rl.BLUE,
	)

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		frame_count = 100,

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
	g = (^Game_Memory)(mem)
	g.player = {
		center = {0,0},
		radius = 15,
		max_radius = 15,
		default_color = rl.GRAY,
		color = rl.GRAY,
	}

	g.lasers_count = 0


	// create a debug laser
	{
		g.lasers_count += 1
		g.lasers[g.lasers_count] = Laser {
			p1 = {-100, -100},
			p2 = {-100, 100},
			velocity = {20, 0},
			color = rl.RED,
		}
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
