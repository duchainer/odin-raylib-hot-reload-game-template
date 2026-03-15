package game

import "core:encoding/json"
import "core:fmt"
//import "core:mem"
import sqlite "../vendor/odin-sqlite3"
import sa "../vendor/odin-sqlite3/addons"

db_init :: proc(db_path: string) -> (db: ^sqlite.Connection, ok: bool) {
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

    return db, (result == .Ok)
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

db_replace_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: CommodinoStruct) -> (ok: bool) {
    // Begin transaction
    result := sa.execute(db, "BEGIN TRANSACTION;")
    if result != .Ok {
        fmt.eprintfln("Failed to begin transaction: %v", sqlite.errmsg(db))
        return false
    }
    
    // Delete existing record
    result = sa.execute(db, "DELETE FROM commodino_structs;")
    if result != .Ok {
        fmt.eprintfln("Failed to delete existing records: %v", sqlite.errmsg(db))
        sa.on_fail_panic(db, sa.execute(db, "ROLLBACK TRANSACTION;"))
        return false
    }
    
    // Convert struct to bytes
    // struct_bytes := mem.any_to_bytes(commodino_struct^)
    struct_bytes, err := json.marshal(commodino_struct, allocator=context.temp_allocator)
    if err != nil{
        fmt.panicf("failed to serialize commodino_struct: {}", err)
    }
    
    // Insert new record
    result = sa.execute(
        db, 
        "INSERT INTO commodino_structs (id, data) VALUES (?, ?);",
        {
            {1, true},
            {2, struct_bytes},
        },
    )
    
    if result != .Ok {
        fmt.eprintfln("Failed to insert commodino_struct: %v", sqlite.errmsg(db))
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
