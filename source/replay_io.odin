package game

import "core:fmt"

//// BEGIN-SECTION_GIT
import "core:os/os2"
import "core:strings"

// Execute git commit -a
git_commit_all :: proc(message: string, allocator := context.temp_allocator) -> (success: bool) {
    desc := os2.Process_Desc{
        command = {
            "git",
            "commit",
            "-a",
            "-m",
            message,
        },
    }
    
    state, stdout, stderr, err := os2.process_exec(desc, allocator)
    // defer delete(stdout)
    // defer delete(stderr)
    
    if err != nil {
        fmt.eprintln("Error executing git commit:", err)
        fmt.eprintln("stderr:", string(stderr))
        return false
    }
    
    fmt.println("stdout:", string(stdout))
    
    if !state.success || state.exit_code != 0 {
        fmt.eprintln("git commit failed with exit code:", state.exit_code)
        return false
    }
    
    return true
}

// Execute git push
git_push :: proc(allocator := context.temp_allocator) -> (success: bool) {
    desc := os2.Process_Desc{
        command = {"git", "push"},
    }
    
    state, stdout, stderr, err := os2.process_exec(desc, allocator)
    // defer delete(stdout)
    // defer delete(stderr)
    
    if err != nil {
        fmt.eprintln("Error executing git push:", err)
        fmt.eprintln("stderr:", string(stderr))
        return false
    }
    
    fmt.println("stdout:", string(stdout))
    
    if !state.success || state.exit_code != 0 {
        fmt.eprintln("git push failed with exit code:", state.exit_code)
        return false
    }
    
    return true
}

// Read current commit hash
git_get_commit :: proc(allocator := context.temp_allocator) -> (commit_hash: string, ok: bool) {
    desc := os2.Process_Desc{
        command = {"git", "rev-parse", "HEAD"},
    }
    
    state, stdout, stderr, err := os2.process_exec(desc, allocator)
    defer delete(stderr)
    
    if err != nil {
        fmt.eprintln("Error executing git rev-parse:", err)
        return "", false
    }
    
    if !state.success || state.exit_code != 0 {
        delete(stdout)
        return "", false
    }
    
    // Remove trailing newline
    commit_str := string(stdout)
    commit_hash = strings.trim_right(commit_str, "\n\r")
    
    return commit_hash, true
}

// Usage example
/*
main :: proc() {
    // Commit all changes
    if commit_all("My commit message") {
        fmt.println("Committed successfully")
        
        // Push to remote
        if push() {
            fmt.println("Pushed successfully")
        }
    }
    
    // Get current commit
    if commit, ok := get_current_commit(); ok {
        fmt.println("Current commit:", commit)
    }
}
*/

//// END-SECTION_GIT

/// BEGIN-SECTION_SQLITE
import "core:mem"
import "core:time"
import sqlite "../vendor/odin-sqlite3"

// Initialize the database and create tables
init_database :: proc(db_path: string) -> (^sqlite.Connection, bool) {
    db_conn: ^sqlite.Connection
    
    result := sqlite.open(cstring(raw_data(db_path)), &db_conn)
    if result != .Ok {
        fmt.eprintln("Failed to open database:", sqlite.errmsg(db_conn))
        return {}, false
    }
    
    // Enable WAL mode for crash safety and better concurrency
    // WAL writes are durable immediately, even if app crashes
    if !execute_sql(db_conn, "PRAGMA journal_mode=WAL;") {
        fmt.eprintln("Warning: Failed to enable WAL mode")
    }
    
    // Synchronous=NORMAL with WAL is safe and faster
    // Data is safe even on crash, but checkpoints may be lost
    if !execute_sql(db_conn, "PRAGMA synchronous=NORMAL;") {
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
    
    if !execute_sql(db_conn, create_table_sql) {
        sqlite.close(db_conn)
        return {}, false
    }
    
    return db_conn, true
}

// Helper to execute SQL without results
execute_sql :: proc(db: ^sqlite.Connection, sql: string) -> bool {
    result := sqlite.exec(db, cstring(raw_data(sql)), nil, nil, nil)
    if result != .Ok {
        fmt.eprintln("SQL Error:", sqlite.errmsg(db))
        return false
    }
    return true
}

// Get current git commit hash
get_git_commit :: proc() -> (hash: string, success: bool) {
    trimmed, ok := git_get_commit()
    return trimmed, ok
}

// Git commit and push all changes
git_commit_and_push :: proc() -> (commit_hash: string, success: bool) {
    // Commit all, with timestamp
    timestamp := time.now()
    commit_msg := fmt.tprintf("AUTO-SAVE game state at %v", timestamp)
    // defer delete(commit_msg)
    
    _ = git_commit_all(commit_msg)
    // Note: commit might "fail" if there are no changes, which is ok
    
    // Push to remote
    ok2 := git_push()
    if !ok2 {
        fmt.eprintln("Warning: Failed to push to git remote (no remote configured or network issue)")
        // Continue anyway - we still have local commit
    }
    
    // Get the current commit hash
    return git_get_commit()
}

// Check if current git commit matches stored commit
check_git_commit_match :: proc(db_conn: ^sqlite.Connection) -> bool {
    current_commit, ok := get_git_commit()
    if !ok {
        fmt.eprintln("Warning: Failed to get current git commit")
        return false
    }
    
    select_sql := "SELECT git_commit_hash FROM game_state WHERE id = 1;"
    
    stmt: ^sqlite.Statement
    result := sqlite.prepare_v2(db_conn, cstring(raw_data(select_sql)), -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintln("Failed to check git commit:", sqlite.errmsg(db_conn))
        return false
    }
    defer sqlite.finalize(stmt)
    
    step_result := sqlite.step(stmt)
    if step_result == .Row {
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

// Save CommodinoStruct to database
save_commodino_state :: proc(db_conn: ^sqlite.Connection, state: ^CommodinoStruct, git_commit_hash: string) -> bool {
    assert(db_conn != nil)
    assert(state != nil)

    // First, delete existing row (we only keep one state)
    delete_sql := "DELETE FROM game_state WHERE id = 1;"
    if !execute_sql(db_conn, delete_sql) {
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
    
    stmt: ^sqlite.Statement
    result := sqlite.prepare_v2(db_conn, cstring(raw_data(insert_sql)), -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintln("Failed to prepare statement:", sqlite.errmsg(db_conn))
        return false
    }
    defer sqlite.finalize(stmt)
    
    // Bind parameters
    sqlite.bind_int(stmt, 1, 1) // id
    
    // Bind recorded_input_events as blob
    input_events_size := size_of(state.recorded_input_events)
    sqlite.bind_blob(stmt, 2, cast([^]u8)&state.recorded_input_events, i32(input_events_size), {behaviour = .Static})
    
    sqlite.bind_int(stmt, 3, i32(state.recorded_input_events_count))
    sqlite.bind_int(stmt, 4, i32(state.replaying_prev_frame_index))
    sqlite.bind_int(stmt, 5, i32(state.target_frame_index))
    
    // Bind frame_checksums as blob
    checksums_size := size_of(state.frame_checksums)
    sqlite.bind_blob(stmt, 6, cast([^]u8)&state.frame_checksums, i32(checksums_size), {behaviour = .Static})
    
    sqlite.bind_int64(stmt, 7, i64(state.sheep_time_rand_gen_state_seed))
    sqlite.bind_int64(stmt, 8, i64(state.sheep_dir_rand_gen_state_seed))
    sqlite.bind_int(stmt, 9, i32(state.is_replaying ? 1 : 0))
    sqlite.bind_int(stmt, 10, i32(state.is_dragging_playback_scrubber ? 1 : 0))
    
    // Bind delta_times as blob
    delta_times_size := size_of(state.delta_times)
    sqlite.bind_blob(stmt, 11, cast([^]u8)&state.delta_times, i32(delta_times_size), {behaviour = .Static})
    
    // Bind git commit hash
    sqlite.bind_text(stmt, 12, cstring(raw_data(git_commit_hash)), i32(len(git_commit_hash)), {behaviour = .Static})
    
    // Execute
    step_result := sqlite.step(stmt)
    if step_result != .Done {
        fmt.eprintln("Failed to insert data:", sqlite.errmsg(db_conn))
        return false
    }
    
    return true
}

// Load CommodinoStruct from database
load_commodino_state :: proc(db_conn: ^sqlite.Connection, state: ^CommodinoStruct) -> bool {
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
    
    stmt: ^sqlite.Statement
    result := sqlite.prepare_v2(db_conn, cstring(raw_data(select_sql)), -1, &stmt, nil)
    if result != .Ok {
        fmt.eprintln("Failed to prepare statement:", sqlite.errmsg(db_conn))
        return false
    }
    defer sqlite.finalize(stmt)
    
    step_result := sqlite.step(stmt)
    if step_result == .Row {
        // Read blobs
        input_events_blob := sqlite.column_blob(stmt, 0)
        input_events_size := int(sqlite.column_bytes(stmt, 0))
        if input_events_size == size_of(state.recorded_input_events) {
            mem.copy(&state.recorded_input_events, input_events_blob, input_events_size)
        }
        
        state.recorded_input_events_count = int(sqlite.column_int(stmt, 1))
        state.replaying_prev_frame_index = int(sqlite.column_int(stmt, 2))
        state.target_frame_index = int(sqlite.column_int(stmt, 3))
        
        checksums_blob := sqlite.column_blob(stmt, 4)
        checksums_size := int(sqlite.column_bytes(stmt, 4))
        if checksums_size == size_of(state.frame_checksums) {
            mem.copy(&state.frame_checksums, checksums_blob, checksums_size)
        }
        
        state.sheep_time_rand_gen_state_seed = u64(sqlite.column_int64(stmt, 5))
        state.sheep_dir_rand_gen_state_seed = u64(sqlite.column_int64(stmt, 6))
        state.is_replaying = sqlite.column_int(stmt, 7) != 0
        state.is_dragging_playback_scrubber = sqlite.column_int(stmt, 8) != 0
        
        delta_times_blob := sqlite.column_blob(stmt, 9)
        delta_times_size := int(sqlite.column_bytes(stmt, 9))
        if delta_times_size == size_of(state.delta_times) {
            mem.copy(&state.delta_times, delta_times_blob, delta_times_size)
        }
        
        return true
    } else if step_result == .Done {
        fmt.println("No saved state found")
        return false
    } else {
        fmt.eprintln("Error reading state:", sqlite.errmsg(db_conn))
        return false
    }
}

// Close database connection
close_database :: proc(db_conn: ^sqlite.Connection) {
    if db_conn != nil {
        sqlite.close(db_conn)
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
/// END-SECTION_SQLITE
