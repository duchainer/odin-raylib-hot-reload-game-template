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
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

Tile :: union {
	PlantType,
	LevelTile,
}

LevelTile :: enum {
	SHIP,
	EXIT,
}


Game_Memory :: struct {
	some_number: u16,
	run : bool,
	next_player_pos: [2]u8,
	current_level: u8,
	level : struct{
		tiles : [8][8]Tile,
	},
	plant_bay :[4][4]Plant,
	captain : struct{
		air_need : int,
		thirst : int,
		hunger : int,
	},
}

g: ^Game_Memory

watered_plants :  map[int]bool

time: f64

space_texture, seed_texture, ship_texture,
plant_stage1_texture, plant_stage2_texture, plant_stage3_texture  : rl.Texture

update :: proc() {
	time = rl.GetTime()

	if rl.IsMouseButtonPressed(.LEFT){
		mouse_x := f32(rl.GetMouseX())
		mouse_y := f32(rl.GetMouseY())

		for plant_row, i in g.plant_bay {
			for plant, j in plant_row {
				plant_rect := offset_rect_from_index(i,j, {100, 100})
				if plant != {} && !watered_plants[i+j*4] {
					if rl.CheckCollisionPointRec({mouse_x, mouse_y}, plant_rect){
						watered_plants[i+j*4] = true
						previous_player_pos := g.next_player_pos

						switch plant.type{
						case .NONE:  {}
						case .UP:    {g.next_player_pos.y -= 1}
						case .DOWN:  {g.next_player_pos.y += 1}
						case .LEFT:  {g.next_player_pos.x -= 1}
						case .RIGHT: {g.next_player_pos.x += 1}
						case .O2:    {g.captain.air_need -= 1}
						case .WATERMELON: {g.captain.thirst -= 1}
						case .NUT: {g.captain.hunger -= 1}
						}

						if  g.next_player_pos.x > 7 {
							g.next_player_pos.x = 0
						}
						if  g.next_player_pos.x < 0 {
							g.next_player_pos.x = 7
						}

						if  g.next_player_pos.y > 7 {
							g.next_player_pos.y = 0
						}
						if  g.next_player_pos.y < 0 {
							g.next_player_pos.y = 7
						}

						g.next_player_pos.x = clamp(g.next_player_pos.x , 0, 7)
						g.next_player_pos.y = clamp(g.next_player_pos.y , 0, 7)
						if previous_player_pos != g.next_player_pos{
							prev_tile := &g.level.tiles[previous_player_pos.x][previous_player_pos.y]
							next_tile := &g.level.tiles[g.next_player_pos.x][g.next_player_pos.y]
							next_tile^ = prev_tile^
							prev_tile^ = {}
						}

					} // else{
					// 	watered_plants[i+j*4] = false
					// }
				}
			}
		}
	}

	if  math.mod(time, 2) < 0.05 {
		// All watered plants get reset, and reusable
		clear_map(&watered_plants)
	}



	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

offset_rect_from_index :: proc(i, j : int, offset: [2]f32) -> rl.Rectangle{
	width  : f32 = 100
	height : f32 = 100
	pos := [2]f32{f32(i), f32(j)} * {width, height} + offset
	return rl.Rectangle{
		x = pos.x,
		y = pos.y,
		width = width,
		height = height,
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	for level_row, i in g.level.tiles {
		for tile, j in level_row {
			tile_rect := offset_rect_from_index(i,j, {600, 100})

			rl.DrawTextureV(space_texture, {tile_rect.x, tile_rect.y}, rl.WHITE)

			if tile != {}{
				switch t in tile{
				case PlantType:
				case LevelTile:{
					switch t {
					case .SHIP: rl.DrawTextureV(ship_texture, {tile_rect.x, tile_rect.y}, rl.WHITE)
					case .EXIT:
					}
				}

				}
				// tile_color := rl.GREEN //tile_color_from_index(i,j)
				// rl.DrawRectangleRec(tile_rect, tile_color)
			}
			rl.DrawText(fmt.ctprintf("(%v, %v)", i, j), i32(tile_rect.x), i32(tile_rect.y), 16, rl.BLUE)
			rl.DrawText(fmt.ctprintf("%v", tile), i32(tile_rect.x), i32(tile_rect.y)+20, 16, rl.BLUE)
		}

	}

	// rl.BeginMode2D(game_camera())
	// rl.DrawTextureEx(g.player_texture, g.player_pos, 0, 1, rl.WHITE)
	for plant_row, i in g.plant_bay {
		for plant, j in plant_row {
			plant_rect := offset_rect_from_index(i,j, {100, 100})
			if plant != {}{
				plant_color := rl.BLUE if watered_plants[i+j*4] else rl.GREEN //plant_color_from_index(i,j)
				rl.DrawRectangleRec(plant_rect, plant_color)
			}
			rl.DrawText(fmt.ctprintf("(%v, %v)", i, j), i32(plant_rect.x), i32(plant_rect.y), 16, rl.BLUE)
			rl.DrawText(fmt.ctprintf("%v", plant.type), i32(plant_rect.x), i32(plant_rect.y)+20, 25, rl.BLUE)
		}

	}
	// rl.EndMode2D()

	// rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	mouse_x := f32(rl.GetMouseX())
	mouse_y := f32(rl.GetMouseY())

	rl.DrawText(fmt.ctprintf("time:%v\nmouse_pos:%v, %v\nsome_number: %v\nnext_player_pos: %v", math.mod(time, 2), mouse_x, mouse_y, g.some_number, g.next_player_pos), 5, 5, 8, rl.WHITE)
	rl.DrawText(fmt.ctprintf("captain:%#v", g.captain), 5, 550, 25, rl.WHITE)

	// rl.EndMode2D()

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
	rl.SetTargetFPS(30)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		some_number = 100,
		next_player_pos = {0, 0},
		current_level = 0,
		// level = {}

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		// player_texture = rl.LoadTexture("assets/round_cat.png"),
	}
	for i in 0..=3{
		g.plant_bay[0][i] = Plant{PlantType(i+1), .MATURE}
		g.plant_bay[1][i] = Plant{PlantType(i+4), .MATURE}
	}


	g.plant_bay[3][2] = Plant{.RIGHT, .MATURE}
	g.plant_bay[3][3] = Plant{.RIGHT, .MATURE}

	g.level.tiles[0][0] = LevelTile.SHIP

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
	rl.UnloadTexture(space_texture)
	rl.UnloadTexture(seed_texture)
	rl.UnloadTexture(ship_texture)
	rl.UnloadTexture(plant_stage1_texture)
	rl.UnloadTexture(plant_stage2_texture)
	rl.UnloadTexture(plant_stage3_texture)

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

	space_texture        = rl.LoadTexture("./assets/sprites/basicTile.png")
	seed_texture         = rl.LoadTexture("./assets/sprites/Plant1Seed.png")
	ship_texture         = rl.LoadTexture("./assets/sprites/Ship.png")
	plant_stage1_texture = rl.LoadTexture("./assets/sprites/Plant1Stage1.png")
	plant_stage2_texture = rl.LoadTexture("./assets/sprites/Plant1Stage2.png")
	plant_stage3_texture = rl.LoadTexture("./assets/sprites/Plant1Stage3.png")




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
