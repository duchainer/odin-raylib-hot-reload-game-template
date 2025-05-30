package game
BACKGROUND_COLOR :i32: 0x000000//Last char is 43 so [38:43] if you want to replace them
//                       ^ 38th character, let's replace it and rebuild
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



import "core:fmt"
// import "core:math/linalg"
import rl "vendor:raylib"
import "core:os/os2"
// import "core:strings"
import "core:c/libc"

PIXEL_WINDOW_HEIGHT :: 180

Game_Memory :: struct {
	player_pos: rl.Vector2,
	player_texture: rl.Texture,
	some_number: int,
	run: bool,
}

g: ^Game_Memory

file_size : i64

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
	if rl.IsKeyPressed(.ESCAPE) && rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyDown(.LEFT_SHIFT) {
		g.run = false
	}
	// for char := rl.GetCharPressed(); true; {

	// 		fmt.println("Character pressed: %c (Unicode: %d)\n", rune(char), char)
	// 		// Here you would trigger your xdotool command for this character
	// 		break
	// }

	if rl.IsKeyPressed(.SPACE) {
		// Hot-reload
		command : cstring = "xdotool type --window 69206051 'IHelloWorld' " // The terminal command you want to execute

		// Execute the command
		exit_code := libc.system(command)

		if exit_code == 0 {
			fmt.println("Command executed successfully.")
		} else {
			fmt.println("Command failed with exit code:", exit_code)
		}
	}
}

file_content_indexes : struct{
	start: i64,
	end: i64,
}

draw :: proc() {

	rl.BeginDrawing()
	rl.ClearBackground(transmute(rl.Color)(BACKGROUND_COLOR))

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
	g = new(Game_Memory)

	file, err_open := os2.open("./source/game.odin", os2.File_Flags{.Read, .Write, .Sync})
	fmt.assertf(err_open == nil, "Bad os2.open %v", err_open)

	err_file_size : os2.Error
	file_size, err_file_size = os2.file_size(file)
	fmt.assertf(err_file_size == nil, "Bad os2.file_size %v", err_file_size)
	fmt.println("File size : %v", file_size)

	g^ = Game_Memory {
		run = true,
		some_number = 100,

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

mono_font: rl.Font

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	file, err_open := os2.open("./source/game.odin", os2.File_Flags{.Read, .Write, .Sync})
	fmt.assertf(err_open == nil, "Bad os2.open %v", err_open)

	err_file_size : os2.Error
	file_size, err_file_size = os2.file_size(file)
	fmt.assertf(err_file_size == nil, "Bad os2.file_size %v", err_file_size)
	fmt.println("File size : %v", file_size)

	monospaced_font_path :: "./assets/fonts/JuliaMono/JuliaMono-Black.ttf"
	mono_font = rl.LoadFont(monospaced_font_path)

	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.

	// TODO Refetch the file_content from disk
	//  But maybe we don't even need to have g.file_content if we always refetch it?
	//  How should we deal with unsaved changes? Should we always save right BEFORE hot-reloading?
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
