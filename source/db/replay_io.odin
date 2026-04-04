package db

import "core:strings"
import "../generated"
import "core:fmt"
import sqlite "../../vendor/odin-sqlite3"
import sa "../../vendor/odin-sqlite3/addons"
import "../types"

db_init :: proc(db_path: string) -> (db: ^sqlite.Connection, ok: bool) {
    result := sqlite.open(cstring(raw_data(db_path)), &db)
    if result != .Ok {
        fmt.panicf("Result: %v", sqlite.errmsg(db))
    }

    // Enable WAL Mode
    // This PRAGMA returns a result set, but for simple initialization, 
    // we just ensure it executes successfully.
    result = sqlite.exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    if result != .Ok {
        fmt.eprintln("Failed to set WAL mode")
        // We can continue, but it's good to log
    }

    // Set Synchronous to NORMAL for better performance with WAL
    sqlite.exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)

    // Existing table creation logic 
    result = sqlite.exec(db, `
        CREATE TABLE IF NOT EXISTS recording_metadata (
            id BOOLEAN PRIMARY KEY,
            -- Metadata for forward compatibility
            commodino_struct_version INTEGER,
            commit_hash CHAR(40), -- fixed length of full commit hash
            -- rand_gen seeds
            sheep_time_rand_gen_state_seed INTEGER,
            sheep_dir_rand_gen_state_seed INTEGER
        )`, nil, nil, nil)
    // -- Calculated
    // --recorded_input_events_count : int `json:"count"`,
    // -- runtime values for UI
    // --replaying_prev_frame_index INTEGER,
    // --target_frame_index INTEGER,
    // --is_replaying: BOOLEAN `json:"is_replaying"`,
    // --is_dragging_playback_scrubber: bool `json:is_dragging_playback_scrubber`,

    // TODO MAYBE commodino_struct_version should auto-increment in some way.
    //   - MAYBE all the game recording should start either with:
    //     - some recording, or game_state.db with recording_metadata
    //     - asking about the commodino_struct_version?
    //   - Or I could have the commodino_structs have the versionning on it, and increment manually in code
    //     - That sound more straightforward and preventing of dumb mistakes:
    //       - Because I will quickly see if I did wrong when a commit decrement that version instead ^^""
    // Because I know that I'm using core:encoding/json for forward/backward compatibility,
    // but versioning might also help for the branching on diverging behavior of data, maybe?
    // Though I could retroactively add it with matching on the commit_hash
    
    if result != .Ok {
        fmt.panicf("Result: %v", sqlite.errmsg(db))
    }

    return db, (result == .Ok)
}

db_insert_initial_values :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct, commodino_struct_version: types.Commodino_Struct_Version) -> (ok: bool) {

    sa.on_fail_panic(db, sa.execute(
        db, 
        "INSERT INTO recording_metadata (id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed)"+
        "VALUES (?, ?, ?, ?, ?);",
        {
            {1, true},
            {2, cast(i32)commodino_struct_version},
            {3, generated.COMMIT_HASH},
            {4, cast(i64)commodino_struct.sheep_time_rand_gen_state_seed},
            {5, cast(i64)commodino_struct.sheep_dir_rand_gen_state_seed},
            // NOTE For now, we cast u64 to i64 and back
            // TODO MAYBE, use sqlite bind_uint64 if that exists
        },
    ))
    return true
}

db_load_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct) -> (ok: bool) {
    // Load the non-array fields (seeds)
    {
        stmt: ^sqlite.Statement

        result := sqlite.prepare_v2(db, "SELECT id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed FROM recording_metadata WHERE id = ?", -1, &stmt, nil)
        if result != .Ok {
            fmt.eprintfln("Failed to prepare SELECT for inner_non_arrays: %v", sqlite.errmsg(db))
            return false
        }
        defer sqlite.finalize(stmt)
        
        result = sqlite.bind_int(stmt, 1, 1)
        if result != .Ok {
            fmt.eprintfln("Failed to bind parameter: %v", sqlite.errmsg(db))
            return false
        }
        
        result = sqlite.step(stmt)
        if result == .Row {
            // Column indices:
            // - 0: id
            // - 1: commodino_struct_version
            // - 2: commit_hash
            // - 3: sheep_time_rand_gen_state_seed
            // - 4: sheep_dir_rand_gen_state_seed

            // Load the seeds
            commodino_struct.sheep_time_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 3)
            commodino_struct.sheep_dir_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 4)
        } else if result == .Done {
            fmt.println("No saved commodino_struct_inner_non_arrays found in database")
            return false
        } else {
            fmt.eprintfln("Error loading inner_non_arrays: %v", sqlite.errmsg(db))
            return false
        }
    }
    
    // Load all frame_data
    {

        stmt: ^sqlite.Statement
        result := sqlite.prepare_v2(db, `SELECT id,
        -- From frame_checksums
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index, 
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed, 
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,

        -- From delta_times
        delta_time,

        -- From recorded_input_events
        key_left, key_right, key_enter
        FROM frame_data ORDER BY id DESC`,
                                   -1, &stmt, nil)
        if result != .Ok {
            fmt.eprintfln("Failed to prepare SELECT for frame_data: %v", sqlite.errmsg(db))
            return false
        }
        defer sqlite.finalize(stmt)
        
        frame_count : i32
        for {
            result = sqlite.step(stmt)
            if result == .Row {
                frame_index := sqlite.column_int(stmt, 0)
                //From frame_checksums
                commodino_struct.frame_checksums[frame_index].frame_count = cast(int)sqlite.column_int(stmt, DB_OFFSET_FRAME_CHECKSUMS+1)
                commodino_struct.frame_checksums[frame_index].player_rect.x = cast(f32)sqlite.column_double(stmt, DB_OFFSET_FRAME_CHECKSUMS+2)
                commodino_struct.frame_checksums[frame_index].player_rect.y = cast(f32)sqlite.column_double(stmt, DB_OFFSET_FRAME_CHECKSUMS+3)
                commodino_struct.frame_checksums[frame_index].sheeps = cast(u64)sqlite.column_int64(stmt, DB_OFFSET_FRAME_CHECKSUMS+4)
                commodino_struct.frame_checksums[frame_index].last_sheep_index = cast(u32)sqlite.column_int(stmt, DB_OFFSET_FRAME_CHECKSUMS+5)
                commodino_struct.frame_checksums[frame_index].lava_height = cast(f32)sqlite.column_double(stmt, DB_OFFSET_FRAME_CHECKSUMS+6)
                commodino_struct.frame_checksums[frame_index].lava_speed = cast(f32)sqlite.column_double(stmt, DB_OFFSET_FRAME_CHECKSUMS+7)
                commodino_struct.frame_checksums[frame_index].last_sheep_spawn = cast(f32)sqlite.column_double(stmt, DB_OFFSET_FRAME_CHECKSUMS+8)
                commodino_struct.frame_checksums[frame_index].count_sheep_sacrificed = cast(u32)sqlite.column_int(stmt, DB_OFFSET_FRAME_CHECKSUMS+9)
                commodino_struct.frame_checksums[frame_index].sheep_time_rand_gen_state = cast(u64)sqlite.column_int64(stmt, DB_OFFSET_FRAME_CHECKSUMS+10)
                commodino_struct.frame_checksums[frame_index].sheep_dir_rand_gen_state = cast(u64)sqlite.column_int64(stmt, DB_OFFSET_FRAME_CHECKSUMS+11)
                // From delta_times
                commodino_struct.delta_times[frame_index] = cast(f32)sqlite.column_double(stmt, DB_OFFSET_DELTA_TIME+1)
                // From recorded_input_events
                commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(0)].pressed = bool(sqlite.column_int(stmt, DB_OFFSET_RECORDED_INPUT_EVENTS+1))
                commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(1)].pressed = bool(sqlite.column_int(stmt, DB_OFFSET_RECORDED_INPUT_EVENTS+2))
                commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(2)].pressed = bool(sqlite.column_int(stmt, DB_OFFSET_RECORDED_INPUT_EVENTS+3))

                frame_count = max(frame_count, frame_index)
            } else if result == .Done {
                break
            } else {
                fmt.eprintfln("Error loading frame_data: %v", sqlite.errmsg(db))
                return false
            }
        }
        
        // Set the recorded_input_events_count based on what we loaded
        commodino_struct.recorded_input_events_count = cast(int)frame_count
    }
    
    return true
}

db_update_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: types.CommodinoStruct) -> (ok: bool) {
    // Begin transaction
    result := sa.execute(db, "BEGIN TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to begin transaction: %v", sqlite.errmsg(db))
        return false
    }
    
    frame_index := commodino_struct.recorded_input_events_count



    create_frame_data_table_query := fmt.tprintf(`
    CREATE TABLE IF NOT EXISTS frame_data (
        -- NOTE, it can't be used as a single with minimum-discontinuities sequential counter, because we can go back to a branch and continue doing input. So it WILL potentially bounce around
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        -- TODO Properly populate and use that for our tree view of the splitting timeline
        -- branch_id INTEGER,
        -- game_frame_index INTEGER,
        -- UNIQUE(game_frame_index, game_frame_index)

        -- From frame_checksums
        frame_count INTEGER,
        player_rect_x REAL,
        player_rect_y REAL,
        sheeps INTEGER,
        last_sheep_index INTEGER,
        lava_height REAL,
        lava_speed REAL,
        last_sheep_spawn REAL,
        count_sheep_sacrificed INTEGER,
        sheep_time_rand_gen_state INTEGER,
        sheep_dir_rand_gen_state INTEGER,

        -- From delta_times
        delta_time REAL,

        -- From recorded_input_events
        %v BOOLEAN
    );`, strings.join(generated.input_key_field_names[:],
        ` BOOLEAN,
        `, context.temp_allocator))
    // fmt.println("create_frame_data_table_query: ", create_frame_data_table_query)
    // TODO Find more forward-compatible way to store frame_data
    sa.on_fail_panic(db, sa.execute(db, create_frame_data_table_query))


    result = sa.execute(
        db, 
        fmt.tprintf(`INSERT INTO frame_data (-- id, -- it auto-increments, so let's make use that, for that meta_frame_index
        -- From frame_checksums
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index, 
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed, 
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,

        -- From delta_times
        delta_time,

        -- From recorded_input_events
        %v
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);`, generated.recorded_input_events_joined_keys),
        {
            // {1, cast(i32)frame_index},

            // -- From frame_checksums
            // NOTE explicit cast from int to i32 for Query_Param_Value
            {DB_OFFSET_FRAME_CHECKSUMS+1, cast(i32)commodino_struct.frame_checksums[frame_index].frame_count},
            {DB_OFFSET_FRAME_CHECKSUMS+2, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.x },
            {DB_OFFSET_FRAME_CHECKSUMS+3, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.y },
            {DB_OFFSET_FRAME_CHECKSUMS+4, cast(i64)commodino_struct.frame_checksums[frame_index].sheeps },
            // NOTE cast u32 to i32
            {DB_OFFSET_FRAME_CHECKSUMS+5, cast(i32)commodino_struct.frame_checksums[frame_index].last_sheep_index},
            {DB_OFFSET_FRAME_CHECKSUMS+6, cast(f64)commodino_struct.frame_checksums[frame_index].lava_height},
            {DB_OFFSET_FRAME_CHECKSUMS+7, cast(f64)commodino_struct.frame_checksums[frame_index].lava_speed},
            {DB_OFFSET_FRAME_CHECKSUMS+8, cast(f64)commodino_struct.frame_checksums[frame_index].last_sheep_spawn},
            {DB_OFFSET_FRAME_CHECKSUMS+9, cast(i32)commodino_struct.frame_checksums[frame_index].count_sheep_sacrificed},
            {DB_OFFSET_FRAME_CHECKSUMS+10, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_time_rand_gen_state,},
            {DB_OFFSET_FRAME_CHECKSUMS+11, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_dir_rand_gen_state },

            // -- From delta_times
            // NOTE For now, we cast f32 to f64 and back
            // TODO MAYBE, use sqlite bind_f32 if that exists
            {DB_OFFSET_DELTA_TIME+1, cast(f64)commodino_struct.delta_times[frame_index]},

            // -- From recorded_input_events
            {DB_OFFSET_RECORDED_INPUT_EVENTS+1, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(0)].pressed},
            {DB_OFFSET_RECORDED_INPUT_EVENTS+2, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(1)].pressed},
            {DB_OFFSET_RECORDED_INPUT_EVENTS+3, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(2)].pressed},

            // TODO MAYBE store float with hex value if needed, to prevent drifting like json's drift
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert frame_data: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }
    
    // Commit transaction
    result = sa.execute(db, "COMMIT TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to commit transaction: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }
    
    // Periodic WAL checkpoint for better performance
    sa.on_fail_panic(db, sa.execute(db, "PRAGMA wal_checkpoint(PASSIVE);"))

    return true
}

db_close :: proc(db: ^sqlite.Connection) -> (ok: bool) {
    result := sqlite.close(db)
    return (result == .Ok)
}
