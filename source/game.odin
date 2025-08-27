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
// import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

RagdollSegmentId :: int

RagdollSegment :: struct {
	using rect: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
	color: rl.Color,
}

Circle :: struct {
	using center: rl.Vector2,
	radius: f32,
	color: rl.Color,
}

RagdollJoint :: struct {
	using circle: Circle,
	parent_id: RagdollSegmentId,
	child_id: RagdollSegmentId,
	rel_rotation: f32,
}

Game_Memory :: struct {
	player_pos: rl.Vector2,
	total_frame_count: int,
	run: bool,
	ragdoll : struct {
		segments: [3]RagdollSegment,
		joints : [2]RagdollJoint,
		segments_count, joints_count: int,
	},
	last_right_clicked_pos: rl.Vector2,
}

g: ^Game_Memory

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
	g.total_frame_count += 1

	g.ragdoll.segments_count = 0
	g.ragdoll.joints_count = 0
	BODY_SIZE :: rl.Vector2{40, 50}
	ARM_SIZE1 :: rl.Vector2{25, 10}

	g.ragdoll.segments[g.ragdoll.segments_count] = RagdollSegment{
		rl.Rectangle{0, 0, BODY_SIZE.x, BODY_SIZE.y},
		{BODY_SIZE.x/2, BODY_SIZE.y/2},
		f32(g.total_frame_count%360),
		rl.DARKGRAY,
	}
	g.ragdoll.segments_count += 1

	// Adapted from rl.DrawRectanglePro
	// https://github.com/raysan5/raylib/blob/71037033137e692f1a39003e06f570fa2744dce3/src/rshapes.c#L714
	segment_percent_offset_point :: proc(body: RagdollSegment, percent_offset := rl.Vector2{0,0}) -> rl.Vector2{
		sinRotation := math.sin(body.rotation*rl.DEG2RAD)
		cosRotation := math.cos(body.rotation*rl.DEG2RAD)
		dx := -body.origin.x
		dy := -body.origin.y

		segment_percent_offset_point := rl.Vector2{
			body.x + (dx + body.width*percent_offset.x)*cosRotation - (dy + body.height*percent_offset.y)*sinRotation,
			body.y + (dx + body.width*percent_offset.x)*sinRotation + (dy + body.height*percent_offset.y)*cosRotation,
		}
		return segment_percent_offset_point
	}


	g.ragdoll.joints[g.ragdoll.joints_count] = {
		circle = Circle{
			segment_percent_offset_point(g.ragdoll.segments[0], {1.0, 0.3}),
			5,
			rl.GREEN,
		},
		parent_id= 0,
		child_id= 1,
		rel_rotation = 45,
	}
	g.ragdoll.joints_count += 1


	joint : RagdollJoint = g.ragdoll.joints[0]
	g.ragdoll.segments[g.ragdoll.segments_count] = RagdollSegment{
		rl.Rectangle{joint.x, joint.y, ARM_SIZE1.x, ARM_SIZE1.y},
		{0, ARM_SIZE1.y/2},
		// {},
		g.ragdoll.segments[joint.parent_id].rotation+joint.rel_rotation,
		rl.GRAY,
	}
	g.ragdoll.segments_count += 1

	g.ragdoll.joints[g.ragdoll.joints_count] = {
		circle = Circle{
			segment_percent_offset_point(g.ragdoll.segments[1], {1.0, 0.5}),
			5,
			rl.GREEN,
		},
		parent_id= 1,
		child_id= 2,
		rel_rotation= 15,
	}

	joint = g.ragdoll.joints[g.ragdoll.joints_count]
	g.ragdoll.segments[g.ragdoll.segments_count] = RagdollSegment{
		rl.Rectangle{joint.x, joint.y, ARM_SIZE1.x, ARM_SIZE1.y},
		{0, ARM_SIZE1.y/2},
		g.ragdoll.segments[joint.parent_id].rotation+joint.rel_rotation,
		rl.GRAY,
	}
	g.ragdoll.segments_count += 1


	if rl.IsKeyPressed(.LEFT_CONTROL) && rl.IsKeyPressed(.LEFT_SHIFT) && rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	{
		rl.BeginMode2D(game_camera())



		// for segment in g.ragdoll.segments{
		for segment in g.ragdoll.segments{
			//rec: Rectangle, origin: Vector2, rotation: f32, color: Color
			rl.DrawRectanglePro(segment.rect, segment.origin, segment.rotation, segment.color)
		}
		for joint in g.ragdoll.joints{
			rl.DrawCircleV(joint.circle.center, 1, rl.GREEN)
		}
		// for i in -10..=10{
		// 	for j in -10..=i{
		// 		draw_point({f32(i*10),f32(j*10)}, rl.SKYBLUE)
		// 	}
		// }
		draw_point({0,0}, rl.GOLD)



		rl.EndMode2D()
	}

	{
		rl.BeginMode2D(ui_camera())

		// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
		// cleared at the end of the frame by the main application, meaning inside
		// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
		rl.DrawText(fmt.ctprintf("total_frame_count: %v\nplayer_pos: %v", g.total_frame_count, g.player_pos), 5, 5, 8, rl.WHITE)

		rl.EndMode2D()
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
		total_frame_count = 0,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
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
