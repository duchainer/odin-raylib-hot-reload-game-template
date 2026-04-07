package types

import rl "vendor:raylib"


//
// COMMODINO (Record-and-replay, etc)
//

commodino_assert_message : string

// Have it distinct to avoid calling db_init with some other integer by accident
Commodino_Struct_Version :: distinct i32

// TODO NOTE Increment on each CommodinoStruct change
// TODO NOTE Nested types too, like Session_Memory_Checksums
COMMODINO_STRUCT_VERSION :: Commodino_Struct_Version(3)
KeyState :: struct{
	pressed : bool,
}
CachedInput :: struct {
    // Might be a PITA to version if we keep adding new UsedKeys
    // TODO(Raph)THINK Find a better way post-proof-of-concept to forward/backward compatible keystates
    //  Might have to be an Enumerated Array of doubled capacity and static constant values for keys
    //   Like dynamic arrays are (array, len, capacity)
    //  NOTE Will also depend on the actual compression achievable in sqlite for streams of key states
    //    So it might move to parallel arrays of [key][frame] instead of [frame][key]KeyState anyway
	keys : [UsedKeysEnum]KeyState,
}
Session_Memory_Checksums :: struct {
	frame_count: int,
	player_rect : rl.Rectangle,
	sheeps : u64,
	last_sheep_index: u32,
	lava_height: f32,
	lava_speed: f32,
	last_sheep_spawn: f32,
	count_sheep_sacrificed: u32,
	sheep_time_rand_gen_state, sheep_dir_rand_gen_state : u64,//rand.Default_Random_State,
}
CommodinoStructInnerArrays :: struct {
    // Only marshal up to recorded_input_events_count
	// +1, because we don't do anything to the 0th element, it is a null element
	recorded_input_events : [MAX_FRAME_COUNT+1]CachedInput `json:"input_events"`,
    delta_times : [MAX_FRAME_COUNT+1]f32 `json:"delta_times"`,

    // For checksums, you may want to use a slice to avoid marshaling the empty rest of the array
	// +1, because we don't do anything to the 0th element, it is a null element
    frame_checksums : [MAX_FRAME_COUNT+1]Session_Memory_Checksums `json:"frame_checksums"`,
}

CommodinoStruct :: struct {
    using inner_non_arrays : CommodinoStructInnerNonArrays,
    // NOTE using is not seen by json.marshall, so `using` is a breaking change of the COMMODINO_STRUCT_VERSION, you NEED to increment it
    using inner_arrays : CommodinoStructInnerArrays,
}

CommodinoStructInnerNonArrays :: struct{
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
