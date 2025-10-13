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

import "core:c"
// import "core:fmt"
// _ :: fmt
import "core:math"
import linalg "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 360
UI_PIXEL_WINDOW_HEIGHT :: 500

MAX_PATH_POINTS_COUNT :: 1024 // arbitrary
Broom :: struct {
	using rect : rl.Rectangle,
	color : rl.Color,
	rotation: f32,
	speed: f32,
	// For now, DrawSplineLinear, TODO later will be a bit smoother spline
	target_path_index: int,
	path_points_count: int,
	path_points: [MAX_PATH_POINTS_COUNT]rl.Vector2,
}

Game_Memory :: struct {
	lighthouse_pos: rl.Vector2,
	player_texture: rl.Texture,
	frame_time: int,
	run: bool,
	brooms : [64]Broom,
	brooms_count : int,
	hovered_broom: ^Broom,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.lighthouse_pos,
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/UI_PIXEL_WINDOW_HEIGHT,
	}
}

Poly :: struct {
	points: [^]rl.Vector2,
	pointCount: c.int,
	center: rl.Vector2,
}

// TODO obb_to_poly instead, as we want that in our duchlib for other game jams
broom_to_poly :: proc(broom: Broom, allocator := context.temp_allocator) -> Poly{
	// TODO handle if the origin is not the center of broom / obb
	origin := rl.Vector2{broom.width/2, broom.height/2}
	// We put it on the heap, because we use a pointer to it in C
	points := make([]rl.Vector2, 4, allocator)

	center : rl.Vector2

	// Use the DrawRectanglePro formula for getting the 4 corners global pos, with the rotation around the origin
	{
		sin_rotation := linalg.sin(broom.rotation * rl.DEG2RAD)
		cos_rotation := linalg.cos(broom.rotation * rl.DEG2RAD)
		x := broom.x
		y := broom.y
		dx := -origin.x
		dy := -origin.y

		// Top-left
		points[0].x = x + dx*cos_rotation - dy*sin_rotation
		points[0].y = y + dx*sin_rotation + dy*cos_rotation

		// Top-right
		points[1].x = x + (dx + broom.width)*cos_rotation - dy*sin_rotation
		points[1].y = y + (dx + broom.width)*sin_rotation + dy*cos_rotation

		// Bottom-right
		points[2].x = x + (dx + broom.width)*cos_rotation - (dy + broom.height)*sin_rotation
		points[2].y = y + (dx + broom.width)*sin_rotation + (dy + broom.height)*cos_rotation

		// Bottom-left
		points[3].x = x + dx*cos_rotation - (dy + broom.height)*sin_rotation
		points[3].y = y + dx*sin_rotation + (dy + broom.height)*cos_rotation


		// Bottom-right
		center = {
			x + (dx + broom.width/2)*cos_rotation - (dy + broom.height/2)*sin_rotation,
			y + (dx + broom.width/2)*sin_rotation + (dy + broom.height/2)*cos_rotation,
		}
	}

	return Poly{
		points = raw_data(points),
		pointCount = (c.int)(len(points)),
		center = center,
	}
}

angle_to_target :: proc(from, to: rl.Vector2) -> f32{
	diff := to - from
	return linalg.atan2(diff.x, -diff.y) * rl.RAD2DEG
}

lerp_angle :: proc(from, to: f32, t : f32) -> f32{
	diff := to - from
	// Normalize angles to -180 to 180
	diff = diff - math.floor((diff + 180) / 360) * 360
	return from + diff * t
}

POINTS_COUNT_MIN_FOR_CURVE_DRAWING :: 4
POINTS_MIN_DISTANCE :: 1.0
GOOD_ENOUGH_DISTANCE_TO_TARGET_PATH_POINT :: 2.0*4

// DARKBEIGE := rl.BEIGE/2 + rl.BROWN/2
darkbeige :: proc() -> rl.Color {
	return rl.BEIGE/2 + rl.BROWN/2
}

mouse_pos : rl.Vector2
update :: proc() {
	delta_time := 1.0 / f32(TARGET_FPS)
	window_mouse_pos := rl.GetMousePosition()
	{
		camera := game_camera()

		// Convert screen coordinates to world coordinates
		// Formula: world_pos = (screen_pos - offset) / zoom + target
		mouse_pos = (window_mouse_pos - camera.offset) / camera.zoom + camera.target
	}

	// Mouse-only game
	#reverse for &broom, _ in g.brooms[1:g.brooms_count+1]{
		broom_poly := broom_to_poly(broom)

		sin_rotation := linalg.sin(broom.rotation * rl.DEG2RAD)
		cos_rotation := linalg.cos(broom.rotation * rl.DEG2RAD)
		forward_x := rl.Vector2{
			sin_rotation,
			-cos_rotation,
		}

		broom.x += forward_x.x * broom.speed * delta_time
		broom.y += forward_x.y * broom.speed * delta_time
		if broom.target_path_index <= broom.path_points_count {
			target_point := broom.path_points[broom.target_path_index]
			target_angle := angle_to_target(broom_poly.center, target_point)

			BROOM_SPEED :: 360.0  // degrees per seconds
			rotation_lerp_speed := BROOM_SPEED * delta_time / 360.0
			broom.rotation = lerp_angle(broom.rotation, target_angle, rotation_lerp_speed)

			distance_to_target := linalg.vector_length(target_point - broom_poly.center)
			if distance_to_target < GOOD_ENOUGH_DISTANCE_TO_TARGET_PATH_POINT {
				broom.target_path_index += 1
			}
		}

		if rl.CheckCollisionPointPoly(mouse_pos, broom_poly.points, broom_poly.pointCount){
			if rl.IsMouseButtonPressed(.LEFT){
				// reset path
				broom.path_points = {}
				broom.path_points_count = 0
				broom.target_path_index = 0
				broom.path_points[broom.path_points_count] = broom_poly.center
				g.hovered_broom = &broom
			}
			broom.color = darkbeige()
		} else {
			broom.color = rl.BROWN
		}

	}
	broom := g.hovered_broom

	if broom != nil && rl.IsMouseButtonDown(.LEFT) {
			last_point := broom.path_points[broom.path_points_count]
			diff_points := mouse_pos - last_point
			diff := linalg.vector_length(diff_points)

			// Only put points if we have a minimum distance between them.
			if broom != nil &&
			broom.path_points_count	 < POINTS_COUNT_MIN_FOR_CURVE_DRAWING ||
			diff > POINTS_MIN_DISTANCE {
				broom.path_points_count += 1
				broom.path_points[broom.path_points_count] = mouse_pos
			}
	} else {
		g.hovered_broom = nil
	}


	g.frame_time += 1

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode2D(game_camera())
	// rl.DrawTextureEx(g.player_texture, g.lighthouse_pos, 0, 1, rl.WHITE)
	// NOTE, remember that [low:high] syntax always exclude the `high`, so [1:1] is an empty slice
	#reverse for &broom, _ in g.brooms[1:g.brooms_count+1]{

		if broom.path_points_count >= POINTS_COUNT_MIN_FOR_CURVE_DRAWING{
			thick : f32 = 1
			path_color := rl.PURPLE
			rl.DrawSplineCatmullRom(&broom.path_points[0], c.int(broom.path_points_count), thick, path_color)
		}
	}

	#reverse for &broom, _ in g.brooms[1:g.brooms_count+1]{
		{
			// Draw broom stick
			sin_rotation := linalg.sin(broom.rotation * rl.DEG2RAD)
			cos_rotation := linalg.cos(broom.rotation * rl.DEG2RAD)
			forward_x := rl.Vector2{
				sin_rotation,
				-cos_rotation,
			} *25

			// I wish I could just do broom.pos, instead of that, but maybe later I'll do pos(broom)
			global_rect_center := rl.Vector2{broom.x, broom.y}
			rl.DrawLineEx(global_rect_center, global_rect_center+forward_x, 1, rl.BEIGE)
		}

		origin := rl.Vector2{broom.width/2, broom.height/2}
		rect := broom.rect
		// rect.height *= 2
		rl.DrawRectanglePro(rect, origin, broom.rotation, broom.color)
	}
	when ODIN_DEBUG {
		rl.DrawPixelV(mouse_pos, rl.BROWN)
	}
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	// when ODIN_DEBUG {
	// 	rl.DrawText(fmt.ctprintf("frame_time: %v\nplayer_pos: %v\ng.hovered_broom:%#v", g.frame_time, g.lighthouse_pos, g.hovered_broom), 5, 5, 10, rl.WHITE)
	// }

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

TARGET_FPS :: 30
@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1920, 1080, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(TARGET_FPS)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		frame_time = 100,

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

broom_create :: proc(
	rect := rl.Rectangle{},
	color := rl.BROWN,
	rotation : f32 = 0,
	speed : f32 = 0,
){
	g.brooms_count += 1
	g.brooms[g.brooms_count] = {
		rect = rect,
		color = color,
		rotation = rotation,
		speed = speed,
	}
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	g.brooms_count = 0
	broom_create(
		rect = {5, 5, 5, 10},
		color = rl.GREEN,
		rotation = 0,
		speed = 5,
	)

	broom_create(
		rect = {25, 25, 5, 10},
		color = rl.RED,
		rotation = 15,
		speed = 5,
	)

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
