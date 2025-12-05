package game

import "core:time"
import "core:fmt"
import "core:mem"
import "core:encoding/json"
import sqlite "../vendor/odin-sqlite3"

DB_Connection :: struct {
    db: ^sqlite.Sqlite3,
}

// Initialize the database and create tables
init_database :: proc(db_path: string) -> (DB_Connection, bool) {
    conn: DB_Connection
    
    result := sqlite.open(cstring(raw_data(db_path)), &conn.db)
    if result != .OK {
        fmt.eprintln("Failed to open database:", sqlite.errmsg(conn.db))
        return {}, false
    }
    
    // Enable WAL mode for crash safety and better concurrency
    // WAL writes are durable immediately, even if app crashes
    if !execute_sql(conn.db, "PRAGMA journal_mode=WAL;") {
        fmt.eprintln("Warning: Failed to enable WAL mode")
    }
    
    // Synchronous=NORMAL with WAL is safe and faster
    // Data is safe even on crash, but checkpoints may be lost
    if !execute_sql(conn.db, "PRAGMA synchronous=NORMAL;") {
        fmt.eprintln("Warning: Failed to set synchronous mode")
    }
    
    // Create table for the main state
    create_table_sql := `
    CREATE TABLE IF NOT EXISTS game_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        recorded_input_events BLOB,
        recorded_input_events_count INTEGER,
        replaying_prev_frame_index INTEGER,
        target_frame_index INTEGER,
        frame_checksums BLOB,
        sheep_time_rand_gen_state_seed INTEGER,
        sheep_dir_rand_gen_state_seed INTEGER,
        is_replaying INTEGER,
        is_dragging_playback_scrubber INTEGER,
        delta_times BLOB,
        git_commit_hash TEXT
    );`
    
    if !execute_sql(conn.db, create_table_sql) {
        sqlite.close(conn.db)
        return {}, false
    }
    
    return conn, true
}

// Execute a shell command and return output
execute_command :: proc(command: string) -> (output: string, success: bool) {
    when ODIN_OS == .Windows {
        // Windows command execution
        handle := _popen(cstring(raw_data(command)), "r")
        if handle == nil {
            return "", false
        }
        defer _pclose(handle)
        
        buf: [4096]u8
        result_builder := make([dynamic]u8)
        defer delete(result_builder)
        
        for {
            bytes_read := _fread(raw_data(buf[:]), 1, len(buf), handle)
            if bytes_read == 0 do break
            append(&result_builder, ..buf[:bytes_read])
        }
        
        return string(result_builder[:]), true
    } else {
        // Unix-like systems
        handle := _popen(cstring(raw_data(command)), "r")
        if handle == nil {
            return "", false
        }
        defer _pclose(handle)
        
        buf: [4096]u8
        result_builder := make([dynamic]u8)
        defer delete(result_builder)
        
        for {
            if _fgets(raw_data(buf[:]), i32(len(buf)), handle) == nil {
                break
            }
            str_len := 0
            for buf[str_len] != 0 {
                str_len += 1
            }
            append(&result_builder, ..buf[:str_len])
        }
        
        return string(result_builder[:]), true
    }
}

// Foreign functions for popen/pclose
foreign import libc "system:c"

when ODIN_OS == .Windows {
    foreign libc {
        _popen :: proc(command: cstring, mode: cstring) -> rawptr ---
        _pclose :: proc(stream: rawptr) -> i32 ---
        _fread :: proc(ptr: rawptr, size: uint, count: uint, stream: rawptr) -> uint ---
    }
} else {
    foreign libc {
        _popen :: proc(command: cstring, mode: cstring) -> rawptr ---
        _pclose :: proc(stream: rawptr) -> i32 ---
        _fgets :: proc(str: rawptr, size: i32, stream: rawptr) -> rawptr ---
    }
}

// Get current git commit hash
get_git_commit :: proc() -> (hash: string, success: bool) {
    output, ok := execute_command("git rev-parse HEAD")
    if !ok {
        return "", false
    }
    
    // Trim whitespace/newlines
    trimmed := output
    for len(trimmed) > 0 && (trimmed[len(trimmed)-1] == '\n' || trimmed[len(trimmed)-1] == '\r') {
        trimmed = trimmed[:len(trimmed)-1]
    }
    
    return trimmed, len(trimmed) > 0
}

// Git commit and push all changes
git_commit_and_push :: proc() -> (commit_hash: string, success: bool) {
    // Stage all changes
    _, ok1 := execute_command("git add -A")
    if !ok1 {
        fmt.eprintln("Failed to stage git changes")
        return "", false
    }
    
    // Commit with timestamp
    timestamp := time.now()
    commit_msg := fmt.aprintf("Auto-save game state at %v", timestamp)
    defer delete(commit_msg)
    
    commit_cmd := fmt.aprintf("git commit -m \"%s\"", commit_msg)
    defer delete(commit_cmd)
    
    _, ok2 := execute_command(commit_cmd)
    // Note: commit might "fail" if there are no changes, which is ok
    
    // Push to remote
    _, ok3 := execute_command("git push")
    if !ok3 {
        fmt.eprintln("Warning: Failed to push to git remote (no remote configured or network issue)")
        // Continue anyway - we still have local commit
    }
    
    // Get the current commit hash
    return get_git_commit()
}

// Check if current git commit matches stored commit
check_git_commit_match :: proc(conn: DB_Connection) -> bool {
    current_commit, ok := get_git_commit()
    if !ok {
        fmt.eprintln("Warning: Failed to get current git commit")
        return false
    }
    
    select_sql := "SELECT git_commit_hash FROM game_state WHERE id = 1;"
    
    stmt: ^sqlite.Stmt
    result := sqlite.prepare_v2(conn.db, cstring(raw_data(select_sql)), -1, &stmt, nil)
    if result != .OK {
        fmt.eprintln("Failed to check git commit:", sqlite.errmsg(conn.db))
        return false
    }
    defer sqlite.finalize(stmt)
    
    step_result := sqlite.step(stmt)
    if step_result == .ROW {
        stored_commit_cstr := sqlite.column_text(stmt, 0)
        if stored_commit_cstr != nil {
            stored_commit := string(stored_commit_cstr)
            
            if current_commit != stored_commit {
                fmt.eprintln("==============================================")
                fmt.eprintln("WARNING: Git commit mismatch!")
                fmt.eprintln("Stored commit: ", stored_commit)
                fmt.eprintln("Current commit:", current_commit)
                fmt.eprintln("The code has changed since this save was made!")
                fmt.eprintln("==============================================")
                return false
            }
            
            fmt.println("Git commit match: ", current_commit)
            return true
        }
    }
    
    // No stored commit found
    fmt.println("No stored git commit found (first run?)")
    return true
}

// Helper to execute SQL without results
execute_sql :: proc(db: ^sqlite.Sqlite3, sql: string) -> bool {
    result := sqlite.exec(db, cstring(raw_data(sql)), nil, nil, nil)
    if result != .OK {
        fmt.eprintln("SQL Error:", sqlite.errmsg(db))
        return false
    }
    return true
}

// Save CommodinoStruct to database
save_commodino_state :: proc(conn: DB_Connection, state: ^CommodinoStruct, git_commit_hash: string) -> bool {
    // First, delete existing row (we only keep one state)
    delete_sql := "DELETE FROM game_state WHERE id = 1;"
    if !execute_sql(conn.db, delete_sql) {
        return false
    }
    
    // Prepare insert statement
    insert_sql := `
    INSERT INTO game_state (
        id,
        recorded_input_events,
        recorded_input_events_count,
        replaying_prev_frame_index,
        target_frame_index,
        frame_checksums,
        sheep_time_rand_gen_state_seed,
        sheep_dir_rand_gen_state_seed,
        is_replaying,
        is_dragging_playback_scrubber,
        delta_times,
        git_commit_hash
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);`
    
    stmt: ^sqlite.Stmt
    result := sqlite.prepare_v2(conn.db, cstring(raw_data(insert_sql)), -1, &stmt, nil)
    if result != .OK {
        fmt.eprintln("Failed to prepare statement:", sqlite.errmsg(conn.db))
        return false
    }
    defer sqlite.finalize(stmt)
    
    // Bind parameters
    sqlite.bind_int(stmt, 1, 1) // id
    
    // Bind recorded_input_events as blob
    input_events_size := size_of(state.recorded_input_events)
    sqlite.bind_blob(stmt, 2, &state.recorded_input_events, i32(input_events_size), nil)
    
    sqlite.bind_int(stmt, 3, i32(state.recorded_input_events_count))
    sqlite.bind_int(stmt, 4, i32(state.replaying_prev_frame_index))
    sqlite.bind_int(stmt, 5, i32(state.target_frame_index))
    
    // Bind frame_checksums as blob
    checksums_size := size_of(state.frame_checksums)
    sqlite.bind_blob(stmt, 6, &state.frame_checksums, i32(checksums_size), nil)
    
    sqlite.bind_int64(stmt, 7, i64(state.sheep_time_rand_gen_state_seed))
    sqlite.bind_int64(stmt, 8, i64(state.sheep_dir_rand_gen_state_seed))
    sqlite.bind_int(stmt, 9, i32(state.is_replaying ? 1 : 0))
    sqlite.bind_int(stmt, 10, i32(state.is_dragging_playback_scrubber ? 1 : 0))
    
    // Bind delta_times as blob
    delta_times_size := size_of(state.delta_times)
    sqlite.bind_blob(stmt, 11, &state.delta_times, i32(delta_times_size), nil)
    
    // Bind git commit hash
    sqlite.bind_text(stmt, 12, cstring(raw_data(git_commit_hash)), i32(len(git_commit_hash)), nil)
    
    // Execute
    step_result := sqlite.step(stmt)
    if step_result != .DONE {
        fmt.eprintln("Failed to insert data:", sqlite.errmsg(conn.db))
        return false
    }
    
    return true
}

// Load CommodinoStruct from database
load_commodino_state :: proc(conn: DB_Connection, state: ^CommodinoStruct) -> bool {
    select_sql := `
    SELECT 
        recorded_input_events,
        recorded_input_events_count,
        replaying_prev_frame_index,
        target_frame_index,
        frame_checksums,
        sheep_time_rand_gen_state_seed,
        sheep_dir_rand_gen_state_seed,
        is_replaying,
        is_dragging_playback_scrubber,
        delta_times
    FROM game_state WHERE id = 1;`
    
    stmt: ^sqlite.Stmt
    result := sqlite.prepare_v2(conn.db, cstring(raw_data(select_sql)), -1, &stmt, nil)
    if result != .OK {
        fmt.eprintln("Failed to prepare statement:", sqlite.errmsg(conn.db))
        return false
    }
    defer sqlite.finalize(stmt)
    
    step_result := sqlite.step(stmt)
    if step_result == .ROW {
        // Read blobs
        input_events_blob := sqlite.column_blob(stmt, 0)
        input_events_size := sqlite.column_bytes(stmt, 0)
        if input_events_size == size_of(state.recorded_input_events) {
            mem.copy(&state.recorded_input_events, input_events_blob, input_events_size)
        }
        
        state.recorded_input_events_count = int(sqlite.column_int(stmt, 1))
        state.replaying_prev_frame_index = int(sqlite.column_int(stmt, 2))
        state.target_frame_index = int(sqlite.column_int(stmt, 3))
        
        checksums_blob := sqlite.column_blob(stmt, 4)
        checksums_size := sqlite.column_bytes(stmt, 4)
        if checksums_size == size_of(state.frame_checksums) {
            mem.copy(&state.frame_checksums, checksums_blob, checksums_size)
        }
        
        state.sheep_time_rand_gen_state_seed = u64(sqlite.column_int64(stmt, 5))
        state.sheep_dir_rand_gen_state_seed = u64(sqlite.column_int64(stmt, 6))
        state.is_replaying = sqlite.column_int(stmt, 7) != 0
        state.is_dragging_playback_scrubber = sqlite.column_int(stmt, 8) != 0
        
        delta_times_blob := sqlite.column_blob(stmt, 9)
        delta_times_size := sqlite.column_bytes(stmt, 9)
        if delta_times_size == size_of(state.delta_times) {
            mem.copy(&state.delta_times, delta_times_blob, delta_times_size)
        }
        
        return true
    } else if step_result == .DONE {
        fmt.println("No saved state found")
        return false
    } else {
        fmt.eprintln("Error reading state:", sqlite.errmsg(conn.db))
        return false
    }
}

// Close database connection
close_database :: proc(conn: DB_Connection) {
    if conn.db != nil {
        sqlite.close(conn.db)
    }
}

// Usage example in your game loop:
/*
// At initialization - with git commit and push:
commit_hash, commit_ok := git_commit_and_push()
if !commit_ok {
    fmt.eprintln("Warning: Failed to commit/push to git")
    // You can decide whether to continue or not
}

db_conn, ok := init_database("game_state.db")
if !ok {
    fmt.eprintln("Failed to initialize database")
    return
}
defer close_database(db_conn)

// Check if current code matches saved state
check_git_commit_match(db_conn)

// Load previous state (optional)
load_commodino_state(db_conn, &game_memory.commodino)

// In your game loop (every frame):
save_commodino_state(db_conn, &game_memory.commodino, commit_hash)
*/
