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
NeedsLimits :: struct{
	// "X is becoming hungry, and might start doing worse/different decisions"
	soft : Needs,
	// "X is really hungry, and wants to take over the train"
	hard : Needs,
	// "X died from lack of Y. Train morale dropped significantly"
	death : Needs,
}


People :: struct {
	name: [128]u8,
	needs: struct {
		// Every normal day, consumes these from its current.
		daily: Needs,
		// The accumulated needs met at this point, will go down daily until reaching some limits
		current: Needs,
		limits: NeedsLimits,
	},
}

Event :: struct {
	summary_text : [128]u8,
	description : [2092]u8,
	resources_template : [2092]u8,
	left_choice : [2092]u8,
	left_choice_modifier: i32,
	right_choice : [2092]u8,
	people: []People,
	food: i32,
	water: i32,
	medecine: i32,
	fuel: i32,
	morale: i32,
}

Game_Memory :: struct {
	total_frame_count: int,
	run: bool,
	// passive_background_music: rl.Music,
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
	people: [1024]People,
	people_count: int,
	selected_event : i32,
	available_events: [2]Event,
	current_event_text: [256]u8,
}

g: ^Game_Memory

BASE_LINE_CURRENT_NEED := Needs{
	food = 100,
	water = 100,
	medecine = 100,
	morale = 100,
}

BASE_LINE_SOFT_LIMIT := Needs{
	food = 30,
	water = 30,
	medecine = 30,
	morale = 30,
}

BASE_LINE_HARD_LIMIT := Needs{
	food = 15,
	water = 15,
	medecine = 15,
	morale = 15,
}

BASE_LINE_DEATH_LIMIT := Needs{
	food = 0,
	water = 0,
	medecine = 0,
	morale = 0,
}


ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

get_random_events :: proc() -> [2]Event{
	return {
		events[0],
		events[0], // For now, just use the same event twice
	}
}


mute_music_button : rl.Rectangle
pause_music : bool

THREE_BUTTONS :: enum {
	LEFT,
	RIGHT,
	SKIP,
}
three_buttons : [THREE_BUTTONS]rl.Rectangle

update :: proc() {
	if rl.IsMouseButtonPressed(.LEFT){
		mouse_pos := rl.GetMousePosition()
		// mark MUSIC pause
		if rl.CheckCollisionPointRec(mouse_pos, mute_music_button){
			pause_music = !pause_music
            if (pause_music) do rl.PauseMusicStream(g.active_background_music)
            else do rl.ResumeMusicStream(g.active_background_music)
		}
		// mark next_event
		if g.selected_event == -1 {
			if rl.CheckCollisionPointRec(mouse_pos, three_buttons[.SKIP]){
				g.available_events = get_random_events()
				g.selected_event = 0
			}
		} else {
			current_event := g.available_events[g.selected_event]
			if rl.CheckCollisionPointRec(mouse_pos, three_buttons[.LEFT]){
				g.resources.food += current_event.food/2
				g.resources.water += current_event.water/2
				g.resources.medecine += current_event.medecine/2
				g.resources.fuel += current_event.fuel/2
				g.resources.morale += current_event.morale
			}
			if rl.CheckCollisionPointRec(mouse_pos, three_buttons[.RIGHT]){
				for new_people in current_event.people{
					g.people_count += 1
					g.people[g.people_count] = new_people
				}
				g.resources.food += current_event.food
				g.resources.water += current_event.water
				g.resources.medecine += current_event.medecine
				g.resources.fuel += current_event.fuel
				g.resources.morale += current_event.morale
			}
			if rl.CheckCollisionPointRec(mouse_pos, three_buttons[.SKIP]){
				g.available_events = get_random_events()
				g.selected_event = -1
			}
		}
	}

	// mark MUSIC run
	{
		// rl.UpdateMusicStream(g.passive_background_music)
		rl.UpdateMusicStream(g.active_background_music)
	}

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

	real_screen_width := rl.GetScreenWidth()
	real_screen_height := rl.GetScreenHeight()
	// mark MUSIC
	{
		// Actual screen width can be different in full screen
		mute_button_font_size :i32 = 16
		if pause_music {
			mute_text : cstring = "Unmute Music"
			mute_music_button = rl.Rectangle{
				f32(real_screen_width - 10 - 100),
				10,
				f32(rl.MeasureText(mute_text, mute_button_font_size)),
				10,
			}
			rl.DrawText(mute_text, i32(mute_music_button.x), i32(mute_music_button.y), mute_button_font_size, rl.WHITE)

		} else{
			mute_text : cstring = "Mute Music"
			mute_music_button = rl.Rectangle{
				f32(real_screen_width - 10 - 100),
				10,
				f32(rl.MeasureText(mute_text, mute_button_font_size)),
				10,
			}
			rl.DrawText(mute_text, i32(mute_music_button.x), i32(mute_music_button.y), mute_button_font_size, rl.WHITE)
		}
	}

	// mark EVENT
	{
		if g.selected_event >= 0 {
			current_event := g.available_events[g.selected_event]
			event_text := fmt.ctprintf("Event: %s", current_event.summary_text)
			rl.DrawText(event_text, real_screen_width/2, real_screen_height/2, 16, rl.WHITE)
		} else {
			rl.DrawText("Press SKIP to get an event", real_screen_width/2, real_screen_height/2, 16, rl.WHITE)
		}
	}


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
		selected_event = -1,
		people_count = 0,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		// passive_background_music = rl.LoadMusicStream("assets/music/thevoid.mp3"),
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
    // rl.UnloadMusicStream(g.passive_background_music)   // Unload music stream buffers from RAM
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
