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

PIXEL_WINDOW_HEIGHT :: 180

LocationId :: i32

Passenger :: struct {
	generation_index : u32,
	origin: LocationId,
	destination: LocationId,
}


TrainMove :: struct {
	origin: LocationId,
	destination: LocationId,
}
TrainTake :: struct {
	origin: LocationId,
	// what we are taking?
	// Like the position of that thing maybe?
	take_which: i32,
}
TrainDeliver :: struct {
	destination: LocationId,
	// what we are delivering?
	// Like the position of that thing maybe?
	deliver_which: i32,
}


TrainActions :: union {
	TrainMove,
	TrainTake,
	TrainDeliver,
}

Train :: struct {
	using rect : rl.Rectangle,
	rotation : f32,
	programmed_actions : [64]TrainActions,
	current_location: LocationId,
	origin: LocationId,
	destination: LocationId,
	passengers: [16]Passenger,
}

// Timeline :: struct {

// }

Location :: struct {
	using rect : rl.Rectangle,
	letter : rune,

	passengers : [32]Passenger,
	last_passenger_index: i32,

	delivered_passengers : [1024]Passenger,
	last_delivered_passenger_index: i32,
}


Game_Memory :: struct {
	player_pos: rl.Vector2,
	player_texture: rl.Texture,
	total_frame_time: int,
	run: bool,
	//Train
	trains: [16]Train,
	frames_since_started_last_actions: i32,

	// Passengers
	passengers: [1024]Passenger,

	locations : [16]Location,
	turn_index : i32,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.player_pos,
		offset = { w/2, h/2 + 20 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
FRAMES_BETWEEN_TURNS :: 600

update :: proc() {
	input: rl.Vector2

	g.frames_since_started_last_actions += 1
	if rl.IsKeyPressed(.SPACE) || g.frames_since_started_last_actions >= FRAMES_BETWEEN_TURNS{
		for &train, train_index in g.trains{
			action := train.programmed_actions[g.turn_index]
			action_switch: switch a in action {
			case TrainMove: {
				train.current_location = a.destination
			}
			case TrainTake: {
				location := g.locations[train.current_location]
				for seat, i in train.passengers{
					if seat == {}{
						passenger, did_take := take_from(&location, a.take_which)
						if did_take{
							train.passengers[i] = passenger
						} else {
							fmt.printfln("Cannot take that passenger index %v for train %v. In location: %#v", i, train_index, location)
						}
						break action_switch
					}
				}
				// If no seat available
				fmt.printfln("No seat available in train %v: %#v", train_index, train)
			}
			case TrainDeliver: {
				delivered_passenger := &train.passengers[a.deliver_which]
				location := g.locations[train.current_location]
				if delivered_passenger.destination == train.current_location{
					deliver_to(&location, delivered_passenger^)
					delivered_passenger = {}
				} else {
					fmt.printfln("Can't deliver passenger from train %v, to location %v", train_index, location)
				}
				// If no seat available

			}
			}
		}

		g.turn_index += 1
		g.frames_since_started_last_actions = 0
	}

	// if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
	// 	input.y -= 1
	// }
	// if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
	// 	input.y += 1
	// }
	// if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
	// 	input.x -= 1
	// }
	// if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
	// 	input.x += 1
	// }



	input = linalg.normalize0(input)
	g.player_pos += input * rl.GetFrameTime() * 100
	g.total_frame_time += 1

	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// rl.BeginMode2D(game_camera())
	// rl.DrawTextureEx(g.player_texture, g.player_pos, 0, 1, rl.WHITE)
	for location, i in g.locations {
		if location != {}{
			rl.DrawRectangleRec(location.rect, rl.GRAY)
			rl.DrawText(fmt.ctprint(location.letter), i32(location.x), i32(location.y), 20, rl.WHITE)
			for j := 0; j < i;j+=1{
				other_location := g.locations[j]
				start_pos := center_pos(location.rect)
				end_pos := center_pos(other_location.rect)
				rl.DrawLineV(start_pos, end_pos, rl.LIGHTGRAY )
			}
		} else {
			break
		}
	}

	for &train, _ in g.trains {
		if train != {}{
			// DrawRectanglePro            :: proc(rec: Rectangle, origin: Vector2, rotation: f32, color: Color) ---                                             // Draw a color-filled rectangle with pro parameters

			action := train.programmed_actions[g.turn_index]
			action_switch: switch a in action {
			case TrainMove: {
				origin := center_pos(g.locations[a.origin])
				destination := center_pos(g.locations[a.destination])
				t := f32(g.frames_since_started_last_actions)/FRAMES_BETWEEN_TURNS
				dx := destination.x - origin.x
				dy := destination.y - origin.y
				train.rotation = math.atan2(dy, dx) * 180 / math.PI
				train.x = origin.x + (destination.x - origin.x) * t
				train.y = origin.y + (destination.y - origin.y) * t
				// rl.DrawRectangleRec(train.rect, rl.RED)
			}
			case TrainTake:
			case TrainDeliver: {
				location := g.locations[train.current_location]
				loc_center_pos := center_pos(location)
				train.x = loc_center_pos.x
				train.y = loc_center_pos.y
			}
			}
			rl.DrawRectanglePro(train.rect, {train.width/2,train.height/2}, train.rotation, rl.RED)

		} else {
			break
		}
	}

	// rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(fmt.ctprintf("total_frame_time: %v\nplayer_pos: %v\ng.frames_since_started_last_actions: %v\ng.trains[0].programmed_actions: %#v", g.total_frame_time, g.player_pos, g.frames_since_started_last_actions, g.trains[0].programmed_actions), 5, 5, 8, rl.WHITE)

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
		total_frame_time = 100,

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

	g.locations[0] = Location {
		rect = {400, 400, 30, 30},
		letter  = 'A',
	}
	g.locations[1] = Location {
		rect = {600, 600, 30, 30},
		letter  = 'B',
	}
	g.locations[2] = Location {
		rect = {400, 600, 30, 30},
		letter  = 'C',
	}
	g.locations[3] = Location {
		rect = {600, 400, 30, 30},
		letter  = 'D',
	}

	center_pos_loc_0 := center_pos(g.locations[0])
	g.trains[0] = Train {
		rect = {center_pos_loc_0.x, center_pos_loc_0.y, 10, 5},
	}
	g.trains[0].programmed_actions[0] = TrainMove{0, 1}
	g.trains[0].programmed_actions[1] = TrainMove{1, 2}


	g.turn_index = 0


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

deliver_to :: proc(loc: ^Location, p: Passenger){
	loc.last_delivered_passenger_index += 1
	loc.delivered_passengers[loc.last_delivered_passenger_index] = p
}

take_from :: proc(loc: ^Location, i: i32) -> (Passenger, bool) {
	if loc.last_passenger_index >= i {
		ret := loc.passengers[i]
		for j := i; j <= loc.last_passenger_index; j += 1{
			loc.passengers[j] = loc.passengers[j+1]
		}
		loc.last_passenger_index -= 1
		return ret, true
	} else{
		fmt.printfln("Cannot take that passenger index %v. In location: %#v", i, loc)
		return Passenger{}, false
	}
}


// UTILS

center_pos :: proc(rect: rl.Rectangle) -> rl.Vector2{
	return {
		rect.x + rect.width/2,
		rect.y + rect.height/2,
	}
}

// player_center_pos :: proc(player_pos: rl.Vector2) -> rl.Vector2{
// 	return {
// 		player_pos.x + f32( g.player_rect.width )/2,
// 		player_pos.y + f32( g.player_rect.height )/2,
// 	}
// }

pos_from_rect :: proc(rect: rl.Rectangle) -> rl.Vector2{
	return {rect.x, rect.y}
}
