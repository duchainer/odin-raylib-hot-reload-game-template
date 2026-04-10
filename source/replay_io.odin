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
            -- Session identifiers
            -- NOTE: Both use timestamp_nanoseconds as i64 (60+ bits). SQLite INTEGER uses varint encoding,
            -- so values under 16384 use 2 bytes, and values up to 2^60+ fit in 9 bytes max.
            game_session_id INTEGER, -- timestamp_nanoseconds from host, to prevent merging different game sessions
            instance_id INTEGER,      -- this recording's primary instance identifier (timestamp_nanoseconds)
            -- Metadata for forward compatibility
            commodino_struct_version INTEGER,
            commit_hash CHAR(40), -- fixed length of full commit hash
            -- rand_gen seeds
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
        -- NOTE: instance_id uses SQLite INTEGER (varint encoding), typically 2 bytes for values under 16384
        instance_id INTEGER NOT NULL,
        id INTEGER NOT NULL,

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
        %v BOOLEAN,

        -- Source tracking: 0 = this instance generated it, >0 = remote instance origin
        source_instance_id INTEGER DEFAULT 0,

        PRIMARY KEY (instance_id, id)
    );`,// TODO NEXT strings.join(generated.frame_checksums_field_names[:],
        strings.join(generated.input_key_field_names[:],
        ` BOOLEAN,
        `, context.temp_allocator))))

    // session_instances: tracks all instances that contributed to this (possibly merged) session
    sa.on_fail_panic(db, sa.execute(db, `
        CREATE TABLE IF NOT EXISTS session_instances (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instance_id INTEGER NOT NULL UNIQUE
        );
    `))


    return db, (result == .Ok)
}

db_insert_initial_values :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct, commodino_struct_version: types.Commodino_Struct_Version) -> (ok: bool) {
    sa.on_fail_panic(db, sa.execute(
        db, 
        "INSERT INTO recording_metadata (id, game_session_id, instance_id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed, recorded_input_events_count)"+
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
        {
            {1, true},
            {2, commodino_struct.game_session_id},
            {3, commodino_struct.instance_id},
            {4, cast(i32)commodino_struct_version},
            {5, generated.COMMIT_HASH},
            {6, cast(i64)commodino_struct.sheep_time_rand_gen_state_seed},
            // NOTE For now, we cast u64 to i64 and back
            // TODO MAYBE, use sqlite bind_uint64 if that exists
            {7, cast(i64)commodino_struct.sheep_dir_rand_gen_state_seed},
            {8, cast(i32)commodino_struct.recorded_input_events_count},
        },
    ))

    // Insert this instance into session_instances
    sa.on_fail_panic(db, sa.execute(
        db,
        "INSERT INTO session_instances (instance_id) VALUES (?);",
        { {1, commodino_struct.instance_id} },
    ))

    return true
}

db_load_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: ^types.CommodinoStruct) -> (ok: bool) {
    stmt: ^sqlite.Statement

    result := sqlite.prepare_v2(db, "SELECT game_session_id, instance_id, commodino_struct_version, commit_hash, sheep_time_rand_gen_state_seed, sheep_dir_rand_gen_state_seed, recorded_input_events_count FROM recording_metadata WHERE id = ?", -1, &stmt, nil)
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
        commodino_struct.game_session_id = sqlite.column_int64(stmt, 0)
        commodino_struct.instance_id = sqlite.column_int64(stmt, 1)
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

db_prepare_replay_stmt :: proc(db: ^sqlite.Connection) -> (stmt: ^sqlite.Statement) {
    result := sqlite.prepare_v2(db, `SELECT
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index,
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed,
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,

        -- From delta_times
        delta_time,

        -- From recorded_input_events
        key_left, key_right, key_enter,
        source_instance_id
        FROM frame_data WHERE instance_id = ? AND id = ?`, -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare replay statement: %v", sqlite.errmsg(db))
        stmt = nil
    }
    return
}

db_prepare_replay_batch_stmt :: proc(db: ^sqlite.Connection) -> (stmt: ^sqlite.Statement) {
    result := sqlite.prepare_v2(db, `SELECT
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index,
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed,
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,
        delta_time,
        key_left, key_right, key_enter,
        source_instance_id
        FROM frame_data WHERE instance_id = ? AND id >= ? ORDER BY id ASC LIMIT ?`, -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintfln("Failed to prepare replay batch statement: %v", sqlite.errmsg(db))
        stmt = nil
    }
    return
}

db_load_replay_frame_batch :: proc(stmt: ^sqlite.Statement, batch: ^types.Replay_Frame_Batch, instance_id: i64, start_frame: int) -> (ok: bool) {
    if stmt == nil {
        fmt.eprintln("Replay batch statement is nil")
        return
    }

    sqlite.reset(stmt)
    result := sqlite.bind_int64(stmt, 1, instance_id)
    if result != .Ok {
        fmt.eprintfln("Failed to bind instance_id %d: %v", instance_id, sqlite.errmsg(stmt))
        return
    }
    result = sqlite.bind_int(stmt, 2, cast(i32)start_frame)
    if result != .Ok {
        fmt.eprintfln("Failed to bind start_frame %d: %v", start_frame, sqlite.errmsg(stmt))
        return
    }
    result = sqlite.bind_int(stmt, 3, types.REPLAY_BATCH_SIZE)
    if result != .Ok {
        fmt.eprintfln("Failed to bind batch size: %v", sqlite.errmsg(stmt))
        return
    }

    batch.count = 0
    batch.offset = start_frame
    coli32 :: sqlite.column_int
    coli64 :: sqlite.column_int64
    colf64 :: sqlite.column_double

    for {
        result = sqlite.step(stmt)
        if result != .Row {
            break
        }
        idx := batch.count
        batch.frames[idx].checksum.frame_count = cast(int)coli32(stmt, 0)
        batch.frames[idx].checksum.player_rect.x = cast(f32)colf64(stmt, 1)
        batch.frames[idx].checksum.player_rect.y = cast(f32)colf64(stmt, 2)
        batch.frames[idx].checksum.sheeps = cast(u64)coli64(stmt, 3)
        batch.frames[idx].checksum.last_sheep_index = cast(u32)coli32(stmt, 4)
        batch.frames[idx].checksum.lava_height = cast(f32)colf64(stmt, 5)
        batch.frames[idx].checksum.lava_speed = cast(f32)colf64(stmt, 6)
        batch.frames[idx].checksum.last_sheep_spawn = cast(f32)colf64(stmt, 7)
        batch.frames[idx].checksum.count_sheep_sacrificed = cast(u32)coli32(stmt, 8)
        batch.frames[idx].checksum.sheep_time_rand_gen_state = cast(u64)coli64(stmt, 9)
        batch.frames[idx].checksum.sheep_dir_rand_gen_state = cast(u64)coli64(stmt, 10)
        batch.frames[idx].delta_time = cast(f32)colf64(stmt, 11)
        batch.frames[idx].input_keys[types.UsedKeysEnum(0)] = bool(coli32(stmt, 12))
        batch.frames[idx].input_keys[types.UsedKeysEnum(1)] = bool(coli32(stmt, 13))
        batch.frames[idx].input_keys[types.UsedKeysEnum(2)] = bool(coli32(stmt, 14))
        batch.frames[idx].source_instance_id = coli64(stmt, 15)
        batch.count += 1
        if batch.count >= types.REPLAY_BATCH_SIZE {
            break
        }
    }

    ok = batch.count > 0
    return
}

db_load_replay_frame_stmt :: proc(stmt: ^sqlite.Statement, instance_id: i64, frame_index: int) -> (frame: types.Replay_Frame, ok: bool) {
    if stmt == nil {
        fmt.eprintln("Replay statement is nil")
        return
    }

    // TODO defer sqlite.finalize(stmt) even on crashes?

    sqlite.reset(stmt)
    result := sqlite.bind_int64(stmt, 1, instance_id)
    if result != .Ok {
        fmt.eprintfln("Failed to bind instance_id %d: %v", instance_id, sqlite.errmsg(stmt))
        return
    }
    result = sqlite.bind_int(stmt, 2, cast(i32)frame_index)
    if result != .Ok {
        fmt.eprintfln("Failed to bind frame_index %d: %v", frame_index, sqlite.errmsg(stmt))
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
        frame.source_instance_id = coli64(stmt, 15)
        ok = true
    } else if result == .Done {
        fmt.eprintfln("Frame %d not found in database", frame_index)
    } else {
        fmt.eprintfln("Error loading frame %d: %v", frame_index, sqlite.errmsg(stmt))
    }

    return
}

db_load_replay_frame :: proc(db: ^sqlite.Connection, instance_id: i64, frame_index: int) -> (frame: types.Replay_Frame, ok: bool) {
    stmt := db_prepare_replay_stmt(db)
    defer sqlite.finalize(stmt)
    return db_load_replay_frame_stmt(stmt, instance_id, frame_index)
}

db_save_frame :: proc(db: ^sqlite.Connection, instance_id: i64, frame_index: int, delta_time: f32, input_keys: [types.UsedKeysEnum]bool, source_instance_id: i64, checksum: types.Session_Memory_Checksums) -> (ok: bool) {
    result := sa.execute(db, "BEGIN TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to begin transaction: %v", sqlite.errmsg(db))
        return false
    }
    
    result = sa.execute(
        db, 
        fmt.tprintf(`INSERT INTO frame_data (instance_id, id, -- it auto-increments, so let's make use that, for that meta_frame_index
        -- From frame_checksums
        frame_count, player_rect_x, player_rect_y, sheeps, last_sheep_index,
        lava_height, lava_speed, last_sheep_spawn, count_sheep_sacrificed,
        sheep_time_rand_gen_state, sheep_dir_rand_gen_state,

        -- From delta_times
        delta_time,

        -- From recorded_input_events
        %v,

        -- Source tracking: 0 = this instance generated it, >0 = remote instance origin
        source_instance_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);`, generated.recorded_input_events_joined_keys),
        {
            {1, instance_id},
            {2, cast(i32)frame_index},
            {3, cast(i32)checksum.frame_count},
            {4, cast(f64)checksum.player_rect.x},
            {5, cast(f64)checksum.player_rect.y},
            {6, cast(i64)checksum.sheeps},
            {7, cast(i32)checksum.last_sheep_index},
            {8, cast(f64)checksum.lava_height},
            {9, cast(f64)checksum.lava_speed},
            {10, cast(f64)checksum.last_sheep_spawn},
            {11, cast(i32)checksum.count_sheep_sacrificed},
            {12, cast(i64)checksum.sheep_time_rand_gen_state},
            {13, cast(i64)checksum.sheep_dir_rand_gen_state},
            {14, cast(f64)delta_time},
            {15, input_keys[types.UsedKeysEnum(0)]},
            {16, input_keys[types.UsedKeysEnum(1)]},
            {17, input_keys[types.UsedKeysEnum(2)]},
            {18, source_instance_id},
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
