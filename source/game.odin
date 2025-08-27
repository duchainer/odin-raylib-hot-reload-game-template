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
	// The .x and .y of that rect are calculated
	using rect: rl.Rectangle,
	origin: rl.Vector2,
	// The rotation is calculated from the sum of all ancestor joint rotation
	// and, in a sense, all the ancestor segment rotations
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
	percent_offset: rl.Vector2,
}

Game_Memory :: struct {
	player_pos: rl.Vector2,
	total_frame_count: int,
	run: bool,
	ragdoll : struct {
		segments: [6]RagdollSegment,
		joints : [6]RagdollJoint,
		segments_count, joints_count: int,
		selected_joint_id: int,
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

ROTATION_SPEED :: 2

update :: proc() {
	g.total_frame_count += 1

	// g.ragdoll.segments[0].rotation = f32(g.total_frame_count%360)

	if rl.IsKeyDown(.W){
		g.ragdoll.segments[0].rotation += ROTATION_SPEED
	}
	if rl.IsKeyDown(.S){
		g.ragdoll.segments[0].rotation -= ROTATION_SPEED
	}

	if rl.IsKeyDown(.A){
		g.ragdoll.joints[g.ragdoll.selected_joint_id].rel_rotation += ROTATION_SPEED
	}
	if rl.IsKeyDown(.D){
		g.ragdoll.joints[g.ragdoll.selected_joint_id].rel_rotation -= ROTATION_SPEED
	}

	world_mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera())


	// We recreate all non-base segments
	// As only their size (width & height) is constant
	g.ragdoll.segments_count = 1
	for &joint, i in g.ragdoll.joints{
		if i == 0 do continue
		if i > g.ragdoll.joints_count{
			// We have gone through all the created joints
			break
		}

		joint.center = segment_percent_offset_point(g.ragdoll.segments[joint.parent_id], joint.percent_offset)

		if rl.CheckCollisionPointCircle(world_mouse_pos, joint.center, joint.radius/2){
			joint.radius = 2*JOINT_BASE_RADIUS
			if rl.IsMouseButtonPressed(.LEFT){
				fmt.println("", world_mouse_pos, joint.center, joint.radius, i)
				fmt.println(g.ragdoll.selected_joint_id)
				g.ragdoll.joints[g.ragdoll.selected_joint_id].color = JOINT_BASE_COLOR
				g.ragdoll.selected_joint_id = i
				joint.color = JOINT_SELECTED_COLOR
			}
		} else {
			joint.radius = JOINT_BASE_RADIUS
		}

		_ = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)
	}


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
		for joint, i in g.ragdoll.joints{
			if i == 0 do continue
			rl.DrawCircleV(joint.circle.center, joint.circle.radius, joint.circle.color)
			rl.DrawText(fmt.ctprintf("%v", i), i32(joint.circle.center.x), i32(joint.circle.center.y-10), 5, rl.GOLD)
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

BODY_SIZE :: rl.Vector2{40, 50}
ARM_SIZE1 :: rl.Vector2{25, 10}

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

JOINT_BASE_COLOR :: rl.GREEN
JOINT_SELECTED_COLOR :: rl.RED
JOINT_BASE_RADIUS :: 2

ragdoll_joint_create:: proc(parent_id, child_id: RagdollSegmentId, percent_offset: rl.Vector2, rel_rotation: f32) -> RagdollJoint{
	g.ragdoll.joints_count += 1
	g.ragdoll.joints[g.ragdoll.joints_count] = {
		circle = Circle{
			segment_percent_offset_point(g.ragdoll.segments[parent_id], percent_offset),
			JOINT_BASE_RADIUS,
			JOINT_BASE_COLOR,
		},
		parent_id = parent_id,
		child_id = child_id,
		rel_rotation = rel_rotation,
		percent_offset = percent_offset,
	}
	return g.ragdoll.joints[g.ragdoll.joints_count]
}

ragdoll_segment_create:: proc(size: rl.Vector2, color: rl.Color = rl.GRAY, joint: RagdollJoint) -> RagdollSegmentId{
	g.ragdoll.segments[g.ragdoll.segments_count] = RagdollSegment{
		rl.Rectangle{joint.x, joint.y, size.x, size.y},
		{0, size.y/2},
		g.ragdoll.segments[joint.parent_id].rotation+joint.rel_rotation,
		color,
	}
	g.ragdoll.segments_count += 1
	return g.ragdoll.segments_count - 1
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)


	g.ragdoll.segments_count = 0
	g.ragdoll.joints_count = 0
	g.ragdoll.selected_joint_id = 0

	ragdoll_base_segment_create:: proc(size: rl.Vector2, color: rl.Color = rl.GRAY, rotation :f32 = 0) -> RagdollSegmentId{
		g.ragdoll.segments[g.ragdoll.segments_count] = RagdollSegment{
			rl.Rectangle{0, 0, size.x, size.y},
			{size.x/2, size.y/2},
			rotation,
			color,
		}
		g.ragdoll.segments_count += 1
		return g.ragdoll.segments_count
	}
	ragdoll_base_segment_create(BODY_SIZE, rl.DARKGRAY, f32(g.total_frame_count%360))

	segment_id : RagdollSegmentId
	joint : RagdollJoint

	joint = ragdoll_joint_create(RagdollSegmentId(0), segment_id+1, {1.0, 0.3}, 45)
	segment_id = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)

	joint = ragdoll_joint_create(segment_id, segment_id+1, {1.0, 0.5}, 15)
	segment_id = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)

	joint = ragdoll_joint_create(segment_id, segment_id+1, {1.0, 0.5}, 15)
	segment_id = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)


	joint = ragdoll_joint_create(RagdollSegmentId(0), segment_id+1, {0.0, 0.3}, 180)
	segment_id = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)

	joint = ragdoll_joint_create(segment_id, segment_id+1, {1.0, 0.5}, -15)
	segment_id = ragdoll_segment_create(ARM_SIZE1, rl.GRAY, joint)


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
