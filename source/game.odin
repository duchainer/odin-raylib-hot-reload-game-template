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

Needs :: struct {
	food: i32,
	water: i32,
	medecine: i32,
	morale: i32,
	// fuel maybe? for warmth?
	// TODO next iteration, maybe?
}

People :: struct {
	name: [128]u8,
	needs: struct {
		// Every normal day, consumes these from its current.
		daily: Needs,
		// The accumulated needs met at this point, will go down daily until reaching some limits
		current: Needs,
		limits: struct{
			// "X is becoming hungry, and might start doing worse/different decisions"
			soft : Needs,
			// "X is really hungry, and wants to take over the train"
			hard : Needs,
			// "X died from lack of Y. Train morale dropped significantly"
			death : Needs,
		},
	},
}

Game_Memory :: struct {
	player_texture: rl.Texture,
	total_frame_count: int,
	run: bool,
	passive_background_music: rl.Music,
	active_background_music: rl.Music,
	resources: struct {
		// For people
		food: i32,
		water: i32,
		medecine: i32,
		// For the train
		fuel: i32,
		// For the group
		morale: i32,
	},
	people: []People,
}

g: ^Game_Memory

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

update :: proc() {
	// rl.UpdateMusicStream(g.passive_background_music)
	rl.UpdateMusicStream(g.active_background_music)
	g.total_frame_count += 1

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("total_frame_count: %v\n", g.total_frame_count), 5, 5, 8, rl.WHITE)

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
	rl.InitAudioDevice()

	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		player_texture = rl.LoadTexture("assets/round_cat.png"),

		passive_background_music = rl.LoadMusicStream("assets/music/thevoid.mp3"),
		active_background_music = rl.LoadMusicStream("assets/music/in-the-night.mp3"),
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
    rl.UnloadMusicStream(g.passive_background_music)   // Unload music stream buffers from RAM
    rl.UnloadMusicStream(g.active_background_music)    // Unload music stream buffers from RAM
    rl.CloseAudioDevice()         // Close audio device (music streaming is automatically stopped)
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

    // rl.PlayMusicStream(g.passive_background_music)
    rl.PlayMusicStream(g.active_background_music)

	fmt.printfln("Playing?: %v", rl.IsMusicStreamPlaying(g.active_background_music))
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
