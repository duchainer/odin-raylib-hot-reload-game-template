package game


import sqlite "../vendor/odin-sqlite3"

DB_CONN :: ^sqlite.Connection
CREATE_COMMODINO_TABLE_SQL :: "CREATE TABLE IF NOT EXISTS commodino_structs (id BOOLEAN PRIMARY KEY, data BLOB)" 

db_init :: proc(db_path: string) -> (db_conn: DB_CONN, ok: bool){
    result := sqlite.open(cstring(raw_data(db_path)), &db_conn)
    if result != .Ok {
        return db_conn, ( result == .Ok )
    }
    result = sqlite.exec(db_conn, CREATE_COMMODINO_TABLE_SQL, nil, nil, nil)
    return db_conn, ( result == .Ok )
}

db_insert_in :: proc(db_conn: DB_CONN, commodino_struct: ^CommodinoStruct) -> (ok: bool){

    breakpoint()
    // sqlite.prepare_v2(db_conn)

    // // Bind parameters  id
    // sqlite.bind_int(stmt, 1, 1) 
    // sqlite.bind_

    // struct_size := size_of(commodino_struct)
    // sqlite.bind_blob(stmt, 2, cast([^]u8)&commodino_struct, i32(struct_size), {behaviour = .Static})
    return true
}

db_close :: proc(db_conn: DB_CONN) -> ( ok:bool ){
    result := sqlite.close(db_conn)
    return ( result == .Ok )
}
