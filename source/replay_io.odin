package game

import "core:encoding/json"
import "core:fmt"
//import "core:mem"
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
        id BOOLEAN PRIMARY KEY
        sheep_time_rand_gen_state_seed INTEGER,
        sheep_dir_rand_gen_state_seed INTEGER,

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
    
    // Prepare the SELECT query
    result := sqlite.prepare_v2(db, "SELECT data FROM commodino_structs WHERE id = ?", -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT statement: %v", sqlite.errmsg(db))
        return false
    }
    defer sqlite.finalize(stmt)
    
    // Bind the id parameter (true/1)
    result = sqlite.bind_int(stmt, 1, 1)
    if result != .Ok {
        fmt.eprintfln("Failed to bind parameter: %v", sqlite.errmsg(db))
        return false
    }
    
    // Execute and fetch the row
    result = sqlite.step(stmt)
    if result == .Row {
        // Get the blob data
        blob_ptr := sqlite.column_blob(stmt, 0)
        blob_size := sqlite.column_bytes(stmt, 0)
        
        if blob_ptr == nil || blob_size == 0 {
            fmt.eprintln("No data found or empty blob")
            return false
        }
        
        blob_slice := ([^]byte)(blob_ptr)[:blob_size]
        err := json.unmarshal(blob_slice, commodino_struct)
        assert(err == nil)

        // // Verify the blob size matches our struct size
        // expected_size := size_of(CommodinoStruct)
        // if int(blob_size) != expected_size {
        //     fmt.eprintfln("Size mismatch: expected %d bytes, got %d bytes", expected_size, blob_size)
        //     return false
        // }
        
        // // Copy the blob data into our struct
        // mem.copy(commodino_struct, blob_ptr, expected_size)
        
        return true
    } else if result == .Done {
        // No rows found - this is okay, just means no saved state yet
        fmt.println("No saved commodino_struct found in database")
        return false
    } else {
        fmt.eprintfln("Error stepping through query: %v", sqlite.errmsg(db))
        return false
    }
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
