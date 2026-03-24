package game

import "core:fmt"
import sqlite "../vendor/odin-sqlite3"
import sa "../vendor/odin-sqlite3/addons"

db_init :: proc(db_path: string, commodino_struct_version: Commodino_Struct_Version,) -> (db: ^sqlite.Connection, ok: bool) {
    result := sqlite.open(cstring(raw_data(db_path)), &db)
    if result != .Ok {
        return db, false
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
CREATE TABLE IF NOT EXISTS commodino_structs (
    id BOOLEAN PRIMARY KEY,
    data BLOB
)`, nil, nil, nil)
    if result != .Ok {
        return db, false
    }

    // Existing table creation logic 
    result = sqlite.exec(db, `
CREATE TABLE IF NOT EXISTS recording_metadata (
    id BOOLEAN PRIMARY KEY,
    commit_hash CHAR(40), -- fixed length of full commit hash
    commodino_struct_version INTEGER
)`, nil, nil, nil)
    // TODO commodino_struct_version should auto-increment in some way.
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
        return db, false
    }

    commodino_struct_version := cast(i32)(commodino_struct_version)
    sa.on_fail_panic(db, sa.execute(
        db, 
        "INSERT INTO recording_metadata (id, commodino_struct_version) VALUES (?, ?);",
        {
            {1, true},
            {2, commodino_struct_version},
        },
    ))




    // CommodinoStructInnerArrays

    return db, (result == .Ok)
}

db_insert_initial_values :: proc(db: ^sqlite.Connection, commodino_struct: ^CommodinoStruct) -> (ok: bool) {
    // I put the table creation here, because we should only call this proc once per-db,
    //  And, worse case, it will just be a no-op, since we use "IF NOT EXISTS"


    // CommodinoStructInnerNonArrays
    sa.on_fail_panic(db, sa.execute(db, `
CREATE TABLE IF NOT EXISTS commodino_struct_inner_non_arrays (
        id BOOLEAN PRIMARY KEY,
        sheep_time_rand_gen_state_seed INTEGER,
        sheep_dir_rand_gen_state_seed INTEGER
)
`))
        // -- Calculated
        // --recorded_input_events_count : int `json:"count"`,
        // -- runtime values for UI
        // --replaying_prev_frame_index INTEGER,
        // --target_frame_index INTEGER,
        // --is_replaying: BOOLEAN `json:"is_replaying"`,
        // --is_dragging_playback_scrubber: bool `json:is_dragging_playback_scrubber`,

    sa.on_fail_panic(db, sa.execute(
        db, 
        "INSERT INTO commodino_struct_inner_non_arrays (id, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed) VALUES (?, ?, ?);",
        {
            {1, true},
            // NOTE For now, we cast u64 to i64 and back
            // TODO MAYBE, use sqlite bind_uint64 if that exists
            {2, cast(i64)commodino_struct.sheep_time_rand_gen_state_seed},
            {3, cast(i64)commodino_struct.sheep_dir_rand_gen_state_seed},
        },
    ))
    return true
}

db_load_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: ^CommodinoStruct) -> (ok: bool) {
    stmt: ^sqlite.Statement
    
    // Load the non-array fields (seeds)
    result := sqlite.prepare_v2(db, "SELECT sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed FROM commodino_struct_inner_non_arrays WHERE id = ?", -1, &stmt, nil)
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
        // Load the seeds
        commodino_struct.sheep_time_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 0)
        commodino_struct.sheep_dir_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 1)
    } else if result == .Done {
        fmt.println("No saved commodino_struct_inner_non_arrays found in database")
        return false
    } else {
        fmt.eprintfln("Error loading inner_non_arrays: %v", sqlite.errmsg(db))
        return false
    }
    
    // Load all recorded_input_events
    stmt2: ^sqlite.Statement
    result = sqlite.prepare_v2(db, "SELECT id, key1, key2, key3 FROM recorded_input_events ORDER BY id", -1, &stmt2, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT for recorded_input_events: %v", sqlite.errmsg(db))
        return false
    }
    defer sqlite.finalize(stmt2)
    
    frame_count : i32 = 0
    for {
        result = sqlite.step(stmt2)
        if result == .Row {
            frame_index := sqlite.column_int(stmt2, 0)
            commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(0)].pressed = bool(sqlite.column_int(stmt2, 1))
            commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(1)].pressed = bool(sqlite.column_int(stmt2, 2))
            commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(2)].pressed = bool(sqlite.column_int(stmt2, 3))
            frame_count = max(frame_count, frame_index)
        } else if result == .Done {
            break
        } else {
            fmt.eprintfln("Error loading recorded_input_events: %v", sqlite.errmsg(db))
            return false
        }
    }
    
    // Load all delta_times
    stmt3: ^sqlite.Statement
    result = sqlite.prepare_v2(db, "SELECT id, delta_time FROM delta_times ORDER BY id", -1, &stmt3, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT for delta_times: %v", sqlite.errmsg(db))
        return false
    }
    defer sqlite.finalize(stmt3)
    
    for {
        result = sqlite.step(stmt3)
        if result == .Row {
            frame_index := sqlite.column_int(stmt3, 0)
            commodino_struct.delta_times[frame_index] = cast(f32)sqlite.column_double(stmt3, 1)
            frame_count = max(frame_count, frame_index)
        } else if result == .Done {
            break
        } else {
            fmt.eprintfln("Error loading delta_times: %v", sqlite.errmsg(db))
            return false
        }
    }
    
    // Load all frame_checksums
    stmt4: ^sqlite.Statement
    result = sqlite.prepare_v2(db, `SELECT id, frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index, 
                                      lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed, 
                                      sheep_time_rand_gen_state, sheep_dir_rand_gen_state 
                                      FROM frame_checksums ORDER BY id`, -1, &stmt4, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT for frame_checksums: %v", sqlite.errmsg(db))
        return false
    }
    defer sqlite.finalize(stmt4)
    
    for {
        result = sqlite.step(stmt4)
        if result == .Row {
            frame_index := sqlite.column_int(stmt4, 0)
            commodino_struct.frame_checksums[frame_index].frame_count = cast(int)sqlite.column_int(stmt4, 1)
            commodino_struct.frame_checksums[frame_index].player_rect.x = cast(f32)sqlite.column_double(stmt4, 2)
            commodino_struct.frame_checksums[frame_index].player_rect.y = cast(f32)sqlite.column_double(stmt4, 3)
            commodino_struct.frame_checksums[frame_index].sheeps = cast(u64)sqlite.column_int64(stmt4, 4)
            commodino_struct.frame_checksums[frame_index].last_sheep_index = cast(u32)sqlite.column_int(stmt4, 5)
            commodino_struct.frame_checksums[frame_index].lava_height = cast(f32)sqlite.column_double(stmt4, 6)
            commodino_struct.frame_checksums[frame_index].lava_speed = cast(f32)sqlite.column_double(stmt4, 7)
            commodino_struct.frame_checksums[frame_index].last_sheep_spawn = cast(f32)sqlite.column_double(stmt4, 8)
            commodino_struct.frame_checksums[frame_index].count_sheep_sacrificed = cast(u32)sqlite.column_int(stmt4, 9)
            commodino_struct.frame_checksums[frame_index].sheep_time_rand_gen_state = cast(u64)sqlite.column_int64(stmt4, 10)
            commodino_struct.frame_checksums[frame_index].sheep_dir_rand_gen_state = cast(u64)sqlite.column_int64(stmt4, 11)
            frame_count = max(frame_count, frame_index)
        } else if result == .Done {
            break
        } else {
            fmt.eprintfln("Error loading frame_checksums: %v", sqlite.errmsg(db))
            return false
        }
    }
    
    // Set the recorded_input_events_count based on what we loaded
    commodino_struct.recorded_input_events_count = cast(int)frame_count
    
    return true
}

db_update_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: CommodinoStruct) -> (ok: bool) {
    // Begin transaction
    result := sa.execute(db, "BEGIN TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to begin transaction: %v", sqlite.errmsg(db))
        return false
    }
    
    frame_index := commodino_struct.recorded_input_events_count


    // TODO Find more forward-compatible way to store recorded inputs
    sa.on_fail_panic(db, sa.execute(db,`
        CREATE TABLE IF NOT EXISTS recorded_input_events (
                id BOOLEAN PRIMARY KEY,
                key1 BOOLEAN,
                key2 BOOLEAN,
                key3 BOOLEAN
        )
    `))
    // TODO Use loop instead of hardcoded values in keys[_]
    //       Using len(USED_KEY_TO_RL_KEY) or something
    // TODO Support when we have KeyState bigger than a single pressed:bool
    // Insert new record
    result = sa.execute(
        db, 
        "INSERT INTO recorded_input_events (id, data) VALUES (?, ?, ?, ?);",
        {
            {1, true},
            {2, commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(0)].pressed},
            {3, commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(1)].pressed},
            {4, commodino_struct.recorded_input_events[frame_index].keys[UsedKeysEnum(2)].pressed},
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert recorded_input_events: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }

    sa.on_fail_panic(db, sa.execute(db,`
        CREATE TABLE IF NOT EXISTS delta_times (
                id BOOLEAN PRIMARY KEY,
                delta_time DOUBLE
        )
    `))
    result = sa.execute(
        db, 
        "INSERT INTO delta_times(id, data) VALUES (?, ?);",
        {
            {1, true},
            // NOTE For now, we cast f32 to f64 and back
            // TODO MAYBE, use sqlite bind_f32 if that exists
            {2, cast(f64)commodino_struct.delta_times[frame_index]},
            // TODO MAYBE store float with hex value if needed, to prevent drifting like json's drift
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert delta_times: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }

    sa.on_fail_panic(db, sa.execute(db,`
        CREATE TABLE IF NOT EXISTS commodino_struct_inner_non_arrays (
            id BOOLEAN PRIMARY KEY,
            frame_count INTEGER,
            player_rect_x  DOUBLE,
            player_rect_y  DOUBLE,
            sheeps  INTEGER,
            last_sheep_index INTEGER,
            lava_height DOUBLE,
            lava_speed DOUBLE,
            last_sheep_spawn DOUBLE,
            count_sheep_sacrificed INTEGER,
            sheep_time_rand_gen_state INTEGER,
            sheep_dir_rand_gen_state  INTEGER
        )
    `))
    result = sa.execute(
        db, 
        "INSERT INTO frame_checksums(id, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
        {
            {1, true},
            // NOTE explicit cast from int to i32 for Query_Param_Value
            {2, cast(i32)commodino_struct.frame_checksums[frame_index].frame_count},
            {3, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.x },
            {4, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.y },
            {5, cast(i64)commodino_struct.frame_checksums[frame_index].sheeps },
            // NOTE cast u32 to i32
            {6, cast(i32)commodino_struct.frame_checksums[frame_index].last_sheep_index},
            {7, cast(f64)commodino_struct.frame_checksums[frame_index].lava_height},
            {8, cast(f64)commodino_struct.frame_checksums[frame_index].lava_speed},
            {9, cast(f64)commodino_struct.frame_checksums[frame_index].last_sheep_spawn},
            {10, cast(i32)commodino_struct.frame_checksums[frame_index].count_sheep_sacrificed},
            {11, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_time_rand_gen_state,},
            {12, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_dir_rand_gen_state },
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert frame_checksums: %v", sqlite.errmsg(db))
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

    fmt.println("END db_update_commodino_struct")
    return true
}

db_close :: proc(db: ^sqlite.Connection) -> (ok: bool) {
    result := sqlite.close(db)
    return (result == .Ok)
}
