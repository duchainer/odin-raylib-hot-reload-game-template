package types

import rl "vendor:raylib"

//
// COMMODINO (Record-and-replay, etc)
//

commodino_assert_message : string

// Have it distinct to avoid calling db_init with some other integer by accident
Commodino_Struct_Version :: distinct i32

KeyState :: struct{
	pressed : bool,
}
Session_Memory_Checksums :: struct {
	frame_count: int,
	player_rect : rl.Rectangle,
	player2_rect : rl.Rectangle,
	sheeps : u64,
	last_sheep_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_sheep_spawn: f32,
	count_sheep_sacrificed: u32,
	sheep_time_rand_gen_state, sheep_dir_rand_gen_state : u64,//rand.Default_Random_State,
}

Replay_Frame :: struct {
	input_keys : [UsedKeysEnum]bool,
	delta_time : f32,
	checksum   : Session_Memory_Checksums,
	source_instance_id : i64, // 0 = self, >0 = remote origin
}

// ===============================================
// TODO NOTE(Raph) Increment on each CommodinoStruct change =====================================
// TODO NOTE(Raph) Nested types too, like Session_Memory_Checksums =============================
COMMODINO_STRUCT_VERSION :: Commodino_Struct_Version(5)
// TODO NOTE(Raph) Increment on each CommodinoStruct change =====================================
// TODO NOTE(Raph) Nested types too, like Session_Memory_Checksums =============================
// ===============================================

CommodinoStruct :: struct {
	instance_id : i64 `json:"instance_id"`,      // timestamp_nanoseconds: 60+ bits, stored as i64
	game_session_id : i64 `json:"game_session_id"`, // timestamp_nanoseconds from host

	recorded_input_events_count : int `json:"count"`,
	replaying_prev_frame_index: int `json:"replaying_prev_frame_index"`,
	target_frame_index: int `json:"target_frame_index"`,

	sheep_time_rand_gen_state_seed: u64 `json:"sheep_time_seed"`,
	sheep_dir_rand_gen_state_seed: u64 `json:"sheep_dir_seed"`,

	is_replaying: bool `json:"is_replaying"`,
	is_dragging_playback_scrubber: bool `json:is_dragging_playback_scrubber`,
}

SCRUBBER_HEIGHT :: 30.0
SCRUBBER_PADDING :: 5.0

Hot_Reload_Mode :: enum{
	HOT_RELOAD,
	FORCE_RESTART,
	FORCE_REPLAY,
}

REPLAY_BATCH_SIZE :: 256

Replay_Frame_Batch :: struct {
	frames : [REPLAY_BATCH_SIZE]Replay_Frame,
	count  : int,
	offset : int, // first frame index in this batch
}
