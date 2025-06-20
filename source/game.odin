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
// import "core:math"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180


Tile :: enum {
	None,
	Pawn,
	Rook,
	Knight,
	Bishop,
	King,
	Queen,
}


Game_Memory :: struct {
	some_number: int,
	camera_center_pos: rl.Vector2,
	run: bool,
	board: [4][4]Tile,
	previous_moves: [9999][2]int,
	previous_moves_latest_index: uint,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.camera_center_pos,
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}


BOARD_TILE_SIZE :: 64
BOARD_POSITION :: rl.Vector2{ 200, 200}

BOARD_SIZE :: 4

ColoredRect :: struct {
	rect : rl.Rectangle,
	color, base_color: rl.Color,
}

tile_rects : [BOARD_SIZE][BOARD_SIZE]ColoredRect

get_hovered_tile :: proc(mousePos: rl.Vector2) -> (hovered_tile: [2]int, has_hovered_tile: bool){
	mousePosRelativeToBoard := mousePos - BOARD_POSITION
	f64_hovered_tile := mousePosRelativeToBoard / BOARD_TILE_SIZE
	hovered_tile = {
		int(f64_hovered_tile.x),
		int(f64_hovered_tile.y),
	}
	has_hovered_tile = (
		hovered_tile.x >= 0 &&
		hovered_tile.x < BOARD_SIZE &&
		hovered_tile.y >= 0 &&
		hovered_tile.y < BOARD_SIZE
	)

	return hovered_tile, has_hovered_tile
}

hovered_tile, old_hovered_tile, selected_tile : [2]int
old_has_hovered_tile, has_hovered_tile, has_selected_tile := false, false, false

update :: proc() {
	g.some_number += 1
	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
	hovered_tile, has_hovered_tile = get_hovered_tile(rl.GetMousePosition())

	if old_has_hovered_tile && old_hovered_tile != hovered_tile {
		old_colored_rect := &tile_rects[old_hovered_tile.x][old_hovered_tile.y]
		if has_selected_tile && old_hovered_tile == selected_tile {
			// keep the selected_tile color there
		} else {
			old_colored_rect.color = old_colored_rect.base_color
		}
	}
	old_hovered_tile = hovered_tile
	old_has_hovered_tile = has_hovered_tile

	if has_hovered_tile{
		if rl.IsMouseButtonReleased(.LEFT){
			if has_selected_tile {
				tile := &tile_rects[selected_tile.x][selected_tile.y]
				tile.color = tile.base_color
			}
			selected_tile = hovered_tile
			has_selected_tile = true
			tile_rects[hovered_tile.x][hovered_tile.y].color = rl.BLUE
		} else if selected_tile == hovered_tile{
			// keep the blue color
		} else{
			tile_rects[hovered_tile.x][hovered_tile.y].color = rl.YELLOW
		}
	}

}

@(rodata)
PIECE_TO_CHAR := [Tile]rune {
	Tile.None     = ' ',
	Tile.Pawn     = 'p',
	Tile.Knight   = 'n',
	Tile.Bishop   = 'b',
	Tile.Rook     = 'r',
	Tile.Queen    = 'q',
	Tile.King     = 'k',
}
draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	//rl.BeginMode2D(game_camera())
	for i:=0; i < BOARD_SIZE; i+=1{
		for j:=0; j < BOARD_SIZE; j+=1{
			colored_rect := tile_rects[i][j]
			rl.DrawRectangleRec(colored_rect.rect, colored_rect.color)

			// if ([2]int{i, j} == [2]int{ 0, 3 })
			{
				rect := tile_rects[i][j].rect
				char := PIECE_TO_CHAR[(Tile)( ( i+j ) % len(Tile) )]
				rl.DrawTextCodepoint(chess_font, char, // piece_chars[i][j]
									 {rect.x, rect.y}, 64, rl.BLACK)
			}
		}
	}
	
	
	//rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("some_number: %v,\nplayer_pos: %v,\nhas_selected_tile: %v,\nselected_tile: %v,\n", g.some_number, g.camera_center_pos, has_selected_tile, selected_tile), 5, 5, 2, rl.WHITE)

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
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		some_number = 100,
		camera_center_pos = { w/2, h/2 },

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		// player_texture = rl.LoadTexture("assets/round_cat.png"),
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

chess_font : rl.Font

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
		
	// monospaced_font_path :: "./assets/fonts/JuliaMono/JuliaMono-Black.ttf"
	chess_font_path :: "./assets/fonts/chess/CASEFONT.TTF"
	chess_font = rl.LoadFont(chess_font_path)


	for i:=0; i < BOARD_SIZE; i+=1{
		for j:=0; j < BOARD_SIZE; j+=1{
			base_color := ( rl.WHITE if (i+j)%2==0 else rl.GRAY )
			tile_rects[i][j] = {
				rect = rl.Rectangle{
					x      = f32(i*BOARD_TILE_SIZE) + BOARD_POSITION.x,
					y      = f32(j*BOARD_TILE_SIZE)+ BOARD_POSITION.y,
					width  = BOARD_TILE_SIZE,
					height = BOARD_TILE_SIZE,
				},
				color = base_color,
				base_color = base_color,
			}
		}
	}

	g = (^Game_Memory)(mem)

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
