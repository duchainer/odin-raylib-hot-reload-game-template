package game

import "core:strings"
import "./generated"
import "core:fmt"
import sqlite "./../vendor/odin-sqlite3"
import sa "./../vendor/odin-sqlite3/addons"
import "./types"

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
            commit_hash CHAR(40),
            sheep_time_rand_gen_state_seed INTEGER,
            sheep_dir_rand_gen_state_seed INTEGER,
            recorded_input_events_count INTEGER DEFAULT 0
        )`, nil, nil, nil)
    
    if result != .Ok {
        fmt.panicf("Result: %v", sqlite.errmsg(db))
    }

    // TODO Finish doing the more forward-compatible way to store frame_data
    // - We have to use the table schema on load to get all tthe fields and load them all,
    // - then to have the remaining field at zero or default values
    // - Than includes, the frame_checksums, the input events, AND the seeds
    sa.on_fail_panic(db, sa.execute(db, fmt.tprintf(`
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
    );`,// TODO NEXT strings.join(generated.frame_checksums_field_names[:],
        strings.join(generated.input_key_field_names[:],
        ` BOOLEAN,
        `, context.temp_allocator))))


    return db, (result == .Ok)
}

db_insert_initial_values :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct, commodino_struct_version: types.Commodino_Struct_Version) -> (ok: bool) {
    sa.on_fail_panic(db, sa.execute(
        db, 
        "INSERT INTO recording_metadata (id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed, recorded_input_events_count)"+
        "VALUES (?, ?, ?, ?, ?, ?);",
        {
            {1, true},
            {2, cast(i32)commodino_struct_version},
            {3, generated.COMMIT_HASH},
            {4, cast(i64)commodino_struct.sheep_time_rand_gen_state_seed},
            // NOTE For now, we cast u64 to i64 and back
            // TODO MAYBE, use sqlite bind_uint64 if that exists
            {5, cast(i64)commodino_struct.sheep_dir_rand_gen_state_seed},
            {6, cast(i32)commodino_struct.recorded_input_events_count},
        },
    ))

    return true
}

db_load_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct) -> (ok: bool) {
    stmt: ^sqlite.Statement

    result := sqlite.prepare_v2(db, "SELECT id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed, recorded_input_events_count FROM recording_metadata WHERE id = ?", -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT for metadata: %v", sqlite.errmsg(db))
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
        commodino_struct.sheep_time_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 3)
        commodino_struct.sheep_dir_rand_gen_state_seed = cast(u64)sqlite.column_int64(stmt, 4)
        commodino_struct.recorded_input_events_count = cast(int)sqlite.column_int(stmt, 5)
    } else if result == .Done {
        fmt.println("No saved commodino_struct found in database")
        return false
    } else {
        fmt.eprintfln("Error loading metadata: %v", sqlite.errmsg(db))
        return false
    }
    
    return true
}

db_load_replay_frame :: proc(db: ^sqlite.Connection, frame_index: int) -> (frame: types.Replay_Frame, ok: bool) {
    stmt: ^sqlite.Statement
    result := sqlite.prepare_v2(db, `SELECT
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index,
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed,
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,

        -- From delta_times
        delta_time,

        -- From recorded_input_events
        key_left, key_right, key_enter
        FROM frame_data WHERE id = ?`, -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare SELECT for frame %d: %v", frame_index, sqlite.errmsg(db))
        return
    }
    defer sqlite.finalize(stmt)
    
    result = sqlite.bind_int(stmt, 1, cast(i32)frame_index)
    if result != .Ok {
        fmt.eprintfln("Failed to bind frame_index %d: %v", frame_index, sqlite.errmsg(db))
        return
    }
    
    result = sqlite.step(stmt)
    if result == .Row {
        coli32 :: sqlite.column_int
        coli64 :: sqlite.column_int64
        colf64 :: sqlite.column_double

        frame.checksum.frame_count = cast(int)coli32(stmt, 0)
        frame.checksum.player_rect.x = cast(f32)colf64(stmt, 1)
        frame.checksum.player_rect.y = cast(f32)colf64(stmt, 2)
        frame.checksum.sheeps = cast(u64)coli64(stmt, 3)
        frame.checksum.last_sheep_index = cast(u32)coli32(stmt, 4)
        frame.checksum.lava_height = cast(f32)colf64(stmt, 5)
        frame.checksum.lava_speed = cast(f32)colf64(stmt, 6)
        frame.checksum.last_sheep_spawn = cast(f32)colf64(stmt, 7)
        frame.checksum.count_sheep_sacrificed = cast(u32)coli32(stmt, 8)
        frame.checksum.sheep_time_rand_gen_state = cast(u64)coli64(stmt, 9)
        frame.checksum.sheep_dir_rand_gen_state = cast(u64)coli64(stmt, 10)
        frame.delta_time = cast(f32)colf64(stmt, 11)
        frame.input_keys[types.UsedKeysEnum(0)] = bool(coli32(stmt, 12))
        frame.input_keys[types.UsedKeysEnum(1)] = bool(coli32(stmt, 13))
        frame.input_keys[types.UsedKeysEnum(2)] = bool(coli32(stmt, 14))
        ok = true
    } else if result == .Done {
        fmt.eprintfln("Frame %d not found in database", frame_index)
    } else {
        fmt.eprintfln("Error loading frame %d: %v", frame_index, sqlite.errmsg(db))
    }
    
    return
}

db_save_frame :: proc(db: ^sqlite.Connection, frame_index: int, delta_time: f32, input_keys: [types.UsedKeysEnum]bool, checksum: types.Session_Memory_Checksums) -> (ok: bool) {
    result := sa.execute(db, "BEGIN TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to begin transaction: %v", sqlite.errmsg(db))
        return false
    }
    
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
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);`, generated.recorded_input_events_joined_keys),
        {
// -            // -- From frame_checksums
// -            // NOTE explicit cast from int to i32 for Query_Param_Value
// -            {DB_OFFSET_FRAME_CHECKSUMS+1, cast(i32)commodino_struct.frame_checksums[frame_index].frame_count},
// -            {DB_OFFSET_FRAME_CHECKSUMS+2, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.x },
// -            {DB_OFFSET_FRAME_CHECKSUMS+3, cast(f64)commodino_struct.frame_checksums[frame_index].player_rect.y },
// -            {DB_OFFSET_FRAME_CHECKSUMS+4, cast(i64)commodino_struct.frame_checksums[frame_index].sheeps },
// -            // NOTE cast u32 to i32
// -            {DB_OFFSET_FRAME_CHECKSUMS+5, cast(i32)commodino_struct.frame_checksums[frame_index].last_sheep_index},
// -            {DB_OFFSET_FRAME_CHECKSUMS+6, cast(f64)commodino_struct.frame_checksums[frame_index].lava_height},
// -            {DB_OFFSET_FRAME_CHECKSUMS+7, cast(f64)commodino_struct.frame_checksums[frame_index].lava_speed},
// -            {DB_OFFSET_FRAME_CHECKSUMS+8, cast(f64)commodino_struct.frame_checksums[frame_index].last_sheep_spawn},
// -            {DB_OFFSET_FRAME_CHECKSUMS+9, cast(i32)commodino_struct.frame_checksums[frame_index].count_sheep_sacrificed},
// -            {DB_OFFSET_FRAME_CHECKSUMS+10, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_time_rand_gen_state,},
// -            {DB_OFFSET_FRAME_CHECKSUMS+11, cast(i64)commodino_struct.frame_checksums[frame_index].sheep_dir_rand_gen_state },
// -
// -            // -- From delta_times
// -            // NOTE For now, we cast f32 to f64 and back
// -            // TODO MAYBE, use sqlite bind_f32 if that exists
// -            {DB_OFFSET_DELTA_TIME+1, cast(f64)commodino_struct.delta_times[frame_index]},
// -
// -            // -- From recorded_input_events
// -            {DB_OFFSET_RECORDED_INPUT_EVENTS+1, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(0)].pressed},
// -            {DB_OFFSET_RECORDED_INPUT_EVENTS+2, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(1)].pressed},
// -            {DB_OFFSET_RECORDED_INPUT_EVENTS+3, commodino_struct.recorded_input_events[frame_index].keys[types.UsedKeysEnum(2)].pressed},
// -
// -            // TODO MAYBE store float with hex value if needed, to prevent drifting like json's drift
            {1, cast(i32)frame_index},
            {2, cast(i32)checksum.frame_count},
            {3, cast(f64)checksum.player_rect.x},
            {4, cast(f64)checksum.player_rect.y},
            {5, cast(i64)checksum.sheeps},
            {6, cast(i32)checksum.last_sheep_index},
            {7, cast(f64)checksum.lava_height},
            {8, cast(f64)checksum.lava_speed},
            {9, cast(f64)checksum.last_sheep_spawn},
            {10, cast(i32)checksum.count_sheep_sacrificed},
            {11, cast(i64)checksum.sheep_time_rand_gen_state},
            {12, cast(i64)checksum.sheep_dir_rand_gen_state},
            {13, cast(f64)delta_time},
            {14, input_keys[types.UsedKeysEnum(0)]},
            {15, input_keys[types.UsedKeysEnum(1)]},
            {16, input_keys[types.UsedKeysEnum(2)]},
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert frame_data: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }

    result = sa.execute(db, "UPDATE recording_metadata SET recorded_input_events_count = ? WHERE id = 1;", {
        {1, cast(i32)frame_index},
    })
    if result != .Ok {
        fmt.eprintfln("Failed to update metadata count: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }
    
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
