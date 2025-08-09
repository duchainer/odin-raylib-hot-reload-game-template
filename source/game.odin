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
// import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 360


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


Game_Memory :: struct {
	player_pos: rl.Vector2,
	player_texture: rl.Texture,
	total_frame_count: int,
	run: bool,
	windows: [2]rl.Rectangle,
	panels : [64]rl.Rectangle,
	panel_count: u32,
	grabbed_panel_index: u32,
	grabbed_panel_offset_mouse_x: f32,
	handles : [64]rl.Rectangle,
	handle_count: u32,
	grabbed_handle_index: u32,
	grabbed_handle_offset_mouse_x: f32,
	// leftover_panels : [64]rl.Rectangle,
}

g: ^Game_Memory

update :: proc() {

	mouse_pos := rl.GetMousePosition()
	if rl.IsMouseButtonPressed(.LEFT){
		// reverse for loop, starting with the last existing element, and skipping the last "zero/null" element
		for i:=g.handle_count; i>0; i-=1{
			rect := g.handles[i]
			if rl.CheckCollisionPointRec(mouse_pos, rect){
				g.grabbed_handle_index = i
				g.grabbed_handle_offset_mouse_x = mouse_pos.x - rect.x
				// reverse for loop, starting with the last existing element, and skipping the last "zero/null" element
				for j:=g.panel_count; j>0; j-=1{
					panel_rect := g.panels[j]
					if rl.CheckCollisionPointRec(mouse_pos, panel_rect){
						g.grabbed_panel_index = j
						g.grabbed_panel_offset_mouse_x = mouse_pos.x - panel_rect.x
					}
				}
				// No need to search, we found it
				break
			}
		}
	} else if rl.IsMouseButtonDown(.LEFT){
		handle := &g.handles[g.grabbed_handle_index]
		// panel := &g.panels[g.grabbed_panel_index]
		window_index: u32
		for candidate, i in g.windows{
			if candidate.x < handle.x && handle.x + handle.width < candidate.x + candidate.width{
				window_index = u32(i)
			}
		}
		window := g.windows[window_index]
		new_handle_x := mouse_pos.x - g.grabbed_handle_offset_mouse_x
		if window.x > new_handle_x{
			// Too far left
			g.panels[g.grabbed_panel_index].x = window.x - g.grabbed_panel_offset_mouse_x + g.grabbed_handle_offset_mouse_x
			g.handles[g.grabbed_handle_index].x = window.x

		} else if new_handle_x + handle.width < window.x + window.width{
			// Too far right
			g.panels[g.grabbed_panel_index].x = mouse_pos.x - g.grabbed_panel_offset_mouse_x
			g.handles[g.grabbed_handle_index].x = new_handle_x
		} else{
			// handle is still inside the frame
			g.panels[g.grabbed_panel_index].x = mouse_pos.x - g.grabbed_panel_offset_mouse_x
			g.handles[g.grabbed_handle_index].x = new_handle_x
		}
	} else{
		// Nothing grabbed no longer
		g.grabbed_handle_index = 0
		g.grabbed_panel_index = 0
	}



	// g.player_pos += input * rl.GetFrameTime() * 100
	g.total_frame_count += 1

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

LEFTOVER_SMALLNESS_IN_UI_FACTOR :: 4
draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	{
		// rl.BeginMode2D(game_camera())
		// BEIGE      :: Color{ 211, 176, 131, 255 }   // Beige
		// BROWN      :: Color{ 127, 106, 79, 255 }    // Brown
		// DARKBROWN  :: Color{ 76, 63, 47, 255 }      // Dark Brown


		for rect in g.panels {
			rl.DrawRectangleRec(rect, rl.BROWN)
		}
		for rect in g.handles {
			rl.DrawRectangleRec(rect, rl.BEIGE)
		}

		for rect in g.windows {
			rl.DrawRectangleLinesEx(rect, WINDOW_THICKNESS, rl.WHITE)
		}

		// rl.EndMode2D()
	}
	//

	// for rect in g.leftover_panels {
	// 	smaller_rect := rl.Rectangle{
	// 		rect.x,
	// 		rect.y,
	// 		rect.width / LEFTOVER_SMALLNESS_IN_UI_FACTOR,
	// 		rect.height / LEFTOVER_SMALLNESS_IN_UI_FACTOR,
	// 	}
	// 	rl.DrawRectangleRec(smaller_rect, rl.BROWN)
	// }

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("total_frame_count: %v\ng.grabbed_handle_index: %v", g.total_frame_count, g.grabbed_handle_index), 5, 5, 8, rl.WHITE)

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

WINDOW_THICKNESS :: 3
@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	g.windows[0] = rl.Rectangle{
		100-WINDOW_THICKNESS, 200-WINDOW_THICKNESS,
		500+2*WINDOW_THICKNESS, 100+2*WINDOW_THICKNESS,
	}
	g.windows[1] = rl.Rectangle{
		1100-WINDOW_THICKNESS, 200-WINDOW_THICKNESS,
		500+2*WINDOW_THICKNESS, 100+2*WINDOW_THICKNESS,
	}



	g.panels[1] = rl.Rectangle{
		100, 200,
		300, 100,
	}
	g.panel_count += 1

	g.handles[1] = rl.Rectangle{
		150, 250,
		25, 50,
	}
	g.handle_count += 1

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
