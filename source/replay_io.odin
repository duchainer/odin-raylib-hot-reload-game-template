package game


import sqlite "../vendor/odin-sqlite3"

DB_CONN :: ^sqlite.Connection

db_init :: proc(db_path: string) -> (db_conn: DB_CONN, ok: bool){
    result := sqlite.open(cstring(raw_data(db_path)), &db_conn)
    return db_conn, ( result == .Ok )
}

// insert_in_database :: proc(db_path: string) -> (db_conn: DB_CONN, ok: bool){
//     // result := sqlite.open(cstring(raw_data(db_path)), &db_conn)
//     // return db_conn, ( result == .Ok )
// }

db_close :: proc(db_conn: DB_CONN) -> ( ok:bool ){
    result := sqlite.close(db_conn)
    return ( result == .Ok )
}
