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
import "core:math/rand"
import real_raylib "vendor:raylib"
import rl "./wrapped_raylib"
import commodino "./commodino/"


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

CountedPanelsArrayRect :: struct {
	panels : [64]rl.Rectangle,
	// int, because we want to match the type from `for x, i in arr` loops
	panel_count: int,
}

CountedHandlesArrayRect :: struct {
	handles : [64]rl.Rectangle,
	handle_count: int,
}

CachedInput :: struct {
    mouse: struct{
        pos : real_raylib.Vector2,
        buttons: [real_raylib.MouseButton]struct{
            down: bool,
            pressed: bool,
        },
    },
    key: struct{
		// enumerated array length: 349
		// enum field count: 110
		// Suggestion: prepend #sparse to the enumerated array to allow for non-contiguous elements
		// Warning: the number of named elements is much smaller than the length of the array, are you sure this is what you want?
		//          this warning will be removed if #sparse is applied
        buttons: #sparse [real_raylib.KeyboardKey]struct{
            down: bool,
            pressed: bool,
        },
    },
}


WINDOW_COUNT :: 2
Game_Memory :: struct {
	commodino: struct {
		break_only_game: bool,
	},
	input : CachedInput,
	// TODO remove player_pos and player_texture
	player_pos: rl.Vector2,
	player_texture: rl.Texture,

	total_frame_count: int,
	run: bool,
	windows: [WINDOW_COUNT+1]rl.Rectangle,

	using panels_counted_arr : CountedPanelsArrayRect,
	grabbed_panel: struct{
		window_index: int,
		index: int,
		offset_mouse_x: f32,
		handle_indexes: [64]int,
		handle_indexes_count: int,
		leftmost_handle_index: int,
		rightmost_handle_index: int,
	},

	using handles_counted_arr : CountedHandlesArrayRect,
	grabbed_handle_index: int,
	grabbed_handle_offset_mouse_x: f32,

	wolves : [WINDOW_COUNT*3][2]f32,
	slammed_wolves_timer : [WINDOW_COUNT*3]int,
}

g: ^Game_Memory

is_this_small_aligned_rect_inside_big_rect :: proc(small_rect, big_rect : rl.Rectangle) -> bool {
	small_rect_x_max := small_rect.x + small_rect.width
	big_rect_x_max := big_rect.x + big_rect.width
	return (
		small_rect.x >= big_rect.x &&
		small_rect_x_max <= big_rect_x_max
	)
}

input :: proc(){
	g.input.mouse.pos = real_raylib.GetMousePosition()
	g.input.mouse.buttons[.LEFT].pressed = real_raylib.IsMouseButtonPressed(.LEFT)
	g.input.mouse.buttons[.LEFT].down = real_raylib.IsMouseButtonDown(.LEFT)


	g.input.key.buttons[.LEFT_CONTROL].pressed = real_raylib.IsKeyPressed(.LEFT_CONTROL)
	g.input.key.buttons[.LEFT_SHIFT].pressed   = real_raylib.IsKeyPressed(.LEFT_SHIFT)
	g.input.key.buttons[.ESCAPE].pressed       = real_raylib.IsKeyPressed(.ESCAPE)
}

update :: proc() {

	mouse_pos := g.input.mouse.pos
	if g.input.mouse.buttons[.LEFT].pressed{
		// reverse for loop, starting with the last existing element, and skipping the last "zero/null" element
		for i:=g.handle_count; i>0; i-=1{
			handle_rect:= g.handles[i]
			if rl.CheckCollisionPointRec(mouse_pos, handle_rect){
				g.grabbed_handle_index = i
				g.grabbed_handle_offset_mouse_x = mouse_pos.x - handle_rect.x
				// reverse for loop, starting with the last existing element, and skipping the last "zero/null" element
				for j:=g.panel_count; j>0; j-=1{
					panel_rect := g.panels[j]
					if rl.CheckCollisionPointRec(mouse_pos, panel_rect){
						g.grabbed_panel.index = j
						g.grabbed_panel.offset_mouse_x = mouse_pos.x - panel_rect.x
						g.grabbed_panel.handle_indexes[0] = i
						g.grabbed_panel.handle_indexes_count = 1
						g.grabbed_panel.leftmost_handle_index = i
						g.grabbed_panel.rightmost_handle_index = i


						g.grabbed_panel.window_index = 0
						for candidate, window_index in g.windows{
							if is_this_small_aligned_rect_inside_big_rect(handle_rect, candidate){
								g.grabbed_panel.window_index = window_index
							}
						}
						if !commodino.assert(&g.commodino.break_only_game, g.grabbed_panel.window_index != 0, "Handles should always be inside windows, if they are on a panel, code loc: %v"){
						// FIXME We need to better take care of the non-input stuff
						//  g should not be constantly updated in-place,
						//  but we should rather have a double buffer of Game_Memory
						//  swapping only when no commodino_assert failed
							rl.SetTargetFPS(1)
							return
						} else{
							rl.SetTargetFPS(TARGET_FPS)
						}



						for handle, k in g.handles{
							if k == i {
								continue
							}
							// ASSUMPTION
							// No need to check for full handle rect, we always have the handle fully inside the panel
							// So let's avoid checking 2 points, when 1 is enough
							if rl.CheckCollisionPointRec({handle.x, handle.y}, panel_rect){
								if handle.x < g.handles[g.grabbed_panel.leftmost_handle_index].x {
									g.grabbed_panel.leftmost_handle_index = k
								}
								if handle.x > g.handles[g.grabbed_panel.rightmost_handle_index].x {
									g.grabbed_panel.rightmost_handle_index = k
								}
								g.grabbed_panel.handle_indexes[g.grabbed_panel.handle_indexes_count] = k
								g.grabbed_panel.handle_indexes_count += 1
							}
						}

					}
				}
				// No need to search, we found it
				break
			}
		}
	} else if g.input.mouse.buttons[.LEFT].down{
		handle := &g.handles[g.grabbed_handle_index]
		panel := &g.panels[g.grabbed_panel.index]
		window := g.windows[g.grabbed_panel.window_index]

		old_handle_x := handle.x
		new_handle_x := mouse_pos.x - g.grabbed_handle_offset_mouse_x

		leftmost_handle := g.handles[g.grabbed_panel.leftmost_handle_index]
		leftmost_handle_delta_x := leftmost_handle.x - old_handle_x

		rightmost_handle := g.handles[g.grabbed_panel.rightmost_handle_index]
		rightmost_handle_delta_x := rightmost_handle.x - old_handle_x



		if window.x > new_handle_x + leftmost_handle_delta_x {
			// Too far left
			clamped_x := window.x - leftmost_handle_delta_x
			panel.x = clamped_x - g.grabbed_panel.offset_mouse_x + g.grabbed_handle_offset_mouse_x
			// We set new_handle_x, because we still need it to update other handles x pos
			new_handle_x = clamped_x
			handle.x = new_handle_x
		} else if new_handle_x + rightmost_handle_delta_x + rightmost_handle.width > window.x + window.width{
			// Too far right
			clamped_x := window.x + window.width - rightmost_handle_delta_x
			panel.x = clamped_x - handle.width - g.grabbed_panel.offset_mouse_x + g.grabbed_handle_offset_mouse_x
			// We set new_handle_x, because we still need it to update other handles x pos
			new_handle_x =  clamped_x - handle.width
			handle.x = new_handle_x
		} else{
			// handle is still inside the frame
			panel.x = mouse_pos.x - g.grabbed_panel.offset_mouse_x
			handle.x = new_handle_x
		}
		// reverse for loop, starting with the last existing element,
		// and skipping the 0th element, as we already handled it, above
		for i:=g.grabbed_panel.handle_indexes_count-1; i>0; i-=1{
			other_handle := &g.handles[g.grabbed_panel.handle_indexes[i]]
			delta_x := other_handle.x - old_handle_x
			other_handle.x = new_handle_x + delta_x
		}


	} else{
		// Nothing grabbed no longer
		g.grabbed_handle_index = 0
		g.grabbed_panel.index = 0
		g.grabbed_panel.handle_indexes_count = 0
	}

	wolf_flee :: proc(wolf:^[2]f32, wolf_index: int){
		g.slammed_wolves_timer[wolf_index] = 120
		wolf^ = {}
	}

	g.total_frame_count += 1

	frames_to_kill :: 20
	current_sprite_frame := ( g.total_frame_count/ 5 ) % frames_to_kill
	frameRec.x      = f32(current_sprite_frame) * f32(wolf_texture.width/WOLF_SPRITE_COUNT)
	frameRec.height = (1+f32(current_sprite_frame)) * f32(wolf_texture.height)/frames_to_kill
	// frameRec.height = f32(wolf_texture.height)

	spawn_points := WOLVES_SPAWNS

	next_wolf: for &wolf, i in g.wolves{
		g.slammed_wolves_timer[i] -= 1
		if wolf != {} {
			for j:=g.panel_count; j>0; j-=1{
				rect := g.panels[j]
				wolf_rect := rl.Rectangle{
					wolf.x,
					wolf.y,
					f32( wolf_texture.width/WOLF_SPRITE_COUNT ),
					frameRec.height,
				}
				if is_this_small_aligned_rect_inside_big_rect(wolf_rect, rect){
					wolf_flee(&wolf, i)
					continue next_wolf
				}
			}
			wolf.y = spawn_points[i].y - (1+f32(current_sprite_frame)) * f32(wolf_texture.height)/frames_to_kill
		}
	}
	if g.total_frame_count %60 == 0{
		// TODO have unsynced wolf animations
		rand_num := rand.int_max(WINDOW_COUNT*3)
		for i in 0..=5 {
			rand_i := (rand_num+i) % (WINDOW_COUNT*3)
			if g.wolves[rand_i] == {} {
				g.wolves[rand_i] = spawn_points[rand_i]
				g.wolves[rand_i].y = 300
				break
			}
		}
	}

	if (
		g.input.key.buttons[.LEFT_CONTROL].pressed &&
		g.input.key.buttons[.LEFT_SHIFT].pressed &&
		g.input.key.buttons[.ESCAPE].pressed
	   ) {
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

		for rect in g.windows {
			// window outside
			rl.DrawRectangleRec(rect, rl.DARKBLUE)
		}

		for wolf_pos, i in g.wolves{
			if g.slammed_wolves_timer[i] > 0{
				rl.DrawText("GO AWAY!", i32(WOLVES_SPAWNS[i].x), i32(WOLVES_SPAWNS[i].y), 32, rl.WHITE)
			}

			if wolf_pos != {} {
				rl.DrawTextureRec(wolf_texture, frameRec, wolf_pos, rl.WHITE)
			}
		}

		for i:=g.panel_count; i>0; i-=1{
			rect := g.panels[i]
			rl.DrawRectangleRec(rect, rl.BROWN)
		}

		// reverse for loop, starting with the last existing element, and skipping the last "zero/null" element
		for i:=g.handle_count; i>0; i-=1{
			rect := g.handles[i]
			rl.DrawRectangleRec(rect, rl.BEIGE)
		}

		for rect in g.windows {
			// window frame
			rl.DrawRectangleLinesEx(rect, WINDOW_THICKNESS, rl.WHITE)
		}

		// rl.EndMode2D()
	}

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	when ODIN_DEBUG {
		rl.DrawText(fmt.ctprintf("total_frame_count: %v\ng.grabbed_handle_index: %v\ng.wolves: %#v", g.total_frame_count, g.grabbed_handle_index, g.wolves,), 5, 5, 8, rl.WHITE)
		rl.DrawText(fmt.ctprintf("mouse_pos: %v\ng.grabbed_panel.handle_indexes: %#v", g.input.mouse.pos, g.grabbed_panel.handle_indexes[:g.grabbed_panel.handle_indexes_count]), 250, 5, 8, rl.WHITE)

		rl.DrawText(fmt.ctprintf("g.commodino.break_only_game: %v", g.commodino.break_only_game), 250, 250, 8, rl.WHITE)
	}

	rl.EndMode2D()

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	if ! g.commodino.break_only_game{
		// We don't want to grab more input for the game, if we have hit a commodino.assert
		// Instead, we want to keep running the update, with the last input state
		input()
	}
	// context.user_ptr = &g.input
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

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		// player_texture = rl.LoadTexture("assets/round_cat.png"),
	}


	// section previously in the hot_reloaded stuff
	wolf_texture = rl.LoadTexture("assets/wolf/wolf-head.png")
	frameRec = { 0, 0, f32(wolf_texture.width/WOLF_SPRITE_COUNT), f32(wolf_texture.height) }


	g.windows = {}

	g.windows[1] = rl.Rectangle{
		100-WINDOW_THICKNESS, 200-WINDOW_THICKNESS,
		500+2*WINDOW_THICKNESS, 100+2*WINDOW_THICKNESS,
	}
	g.windows[2] = rl.Rectangle{
		800-WINDOW_THICKNESS, 200-WINDOW_THICKNESS,
		500+2*WINDOW_THICKNESS, 100+2*WINDOW_THICKNESS,
	}

	WOLVES_SPAWNS = {
		{g.windows[1].x + 0*g.windows[1].width/3, g.windows[1].y+g.windows[1].height},
		{g.windows[1].x + 1*g.windows[1].width/3, g.windows[1].y+g.windows[1].height},
		{g.windows[1].x + 2*g.windows[1].width/3, g.windows[1].y+g.windows[1].height},

		{g.windows[2].x + 0*g.windows[2].width/3, g.windows[2].y+g.windows[2].height},
		{g.windows[2].x + 1*g.windows[2].width/3, g.windows[2].y+g.windows[2].height},
		{g.windows[2].x + 2*g.windows[2].width/3, g.windows[2].y+g.windows[1].height},
	}



	g.panels = {}
	g.panel_count = 0
	create_panel:: proc(rect: rl.Rectangle){
		g.panels[g.panel_count+1] = rect
 		g.panel_count += 1
	}

	create_panel(rl.Rectangle{
		100, 200,
		300, 100,
	})
	create_panel(rl.Rectangle{
		1100, 200,
		300, 100,
	})


	g.handles = {}
	g.handle_count = 0
	create_handle:: proc(rect: rl.Rectangle){
		g.handles[g.handle_count+1] = rect
 		g.handle_count += 1
	}

	create_handle(rl.Rectangle{
		150, 250,
		25, 50,
	})
	create_handle(rl.Rectangle{
		150+100, 250,
		25, 50,
	})
	create_handle(rl.Rectangle{
		150+200, 250,
		25, 50,
	})
	create_handle(rl.Rectangle{
		1100+150, 250,
		25, 50,
	})

	// endsection previously in the hot_reloaded stuff

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

WOLVES_SPAWNS : [WINDOW_COUNT*3][2]f32
WINDOW_THICKNESS :: 3

WOLF_SPRITE_COUNT :: 4
wolf_texture : rl.Texture2D
frameRec : rl.Rectangle
@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return real_raylib.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return real_raylib.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
