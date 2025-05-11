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
import "core:strings"
import "core:c/libc"

PIXEL_WINDOW_HEIGHT :: 180

Game_Memory :: struct {
	player_pos: rl.Vector2,
	player_texture: rl.Texture,
	some_number: int,
	run: bool,
	file_content : [dynamic]byte,
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
	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	if rl.IsKeyPressed(.SPACE) {
		file, err_open := os2.open("./source/game.odin", os2.File_Flags{.Read, .Write, .Sync})
		fmt.assertf(err_open == nil, "Bad os2.open %v", err_open)

		// g.file_content[40] = u8('0')
		new_chars := [?]u8{u8('F'), u8('F')}
		switch{
		case rl.IsKeyDown(.ZERO): new_chars = [?]u8{u8('0'), u8('0')}
		case rl.IsKeyDown(.ONE): new_chars = [?]u8{u8('1'), u8('1')}
		case rl.IsKeyDown(.NINE): new_chars = [?]u8{u8('9'), u8('9')}
		// case rl.IsKeyDown(.F): new_chars = u8('FFF')
		}

		n_write_at, err_write_at := os2.write_at(file, new_chars[:], 38)
		fmt.assertf(err_write_at == nil, "Bad os2.write_at %v", err_write_at)
		fmt.println("Wrote %v byte(s)", n_write_at)

		// Hot-reload
		command : cstring = "bash ./build_hot_reload.sh" // The terminal command you want to execute

		// Execute the command
		exit_code := libc.system(command)

		if exit_code == 0 {
			fmt.println("Command executed successfully.")
		} else {
			fmt.println("Command failed with exit code:", exit_code)
		}
	}
}

draw :: proc() {
	file_as_cstring := strings.clone_to_cstring(string(g.file_content[:5141]), context.temp_allocator)

	rl.BeginDrawing()
	rl.ClearBackground(transmute(rl.Color)(BACKGROUND_COLOR))

	// rl.DrawTextureEx(g.player_texture, g.player_pos, 0, 1, rl.WHITE)
	// rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
	// rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)
	textSize :: 32
	is_editable :: true
	// rl.GuiSetStyle(control: GuiControl, property: c.int, value: c.int)
	// rl.GuiSetStyle(.TEXTBOX, i32(rl.GuiDefaultProperty.BACKGROUND_COLOR), 0x000000)
	// rl.GuiTextBox({0, 250, 500, 1000}, file_as_cstring, textSize, is_editable)
	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	font_spacing :: 0
	rl.DrawTextEx(mono_font, file_as_cstring, {5, 5}, textSize, font_spacing, rl.WHITE)
	// rl.DrawText("HELLO", 5, 5, 8, rl.WHITE)



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

		file_content = make([dynamic]byte, file_size*2),
	}



	n, err_read := os2.read(file, g.file_content[:file_size])
	fmt.assertf(err_read == nil, "Bad os2.read %v", err_read)
	fmt.println(n, string(g.file_content[:file_size]))

	os2.close(file)

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
	delete(g.file_content)
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
