package game


import sqlite "../vendor/odin-sqlite3"
import sa "../vendor/odin-sqlite3/addons"

db_init :: proc(db_path: string) -> (db: ^sqlite.Connection, ok: bool){
    result := sqlite.open(cstring(raw_data(db_path)), &db)
    if result != .Ok {
        return db, ( result == .Ok )
    }
    result = sqlite.exec(db, `
CREATE TABLE IF NOT EXISTS commodino_structs (
    id BOOLEAN PRIMARY KEY, data BLOB
)`, nil, nil, nil)
    return db, ( result == .Ok )
}

db_replace_commodino_struct :: proc(db: ^sqlite.Connection, commodino_struct: ^CommodinoStruct) -> (ok: bool){
    sa.on_fail_panic(db, sa.execute(
        db, 
        `
        BEGIN TRANSACTION;
    `))
    sa.on_fail_panic(db, sa.execute(
        db, 
        `
        DELETE FROM commodino_structs;
    `))
    sa.on_fail_panic(db, sa.execute(
        db, 
        `
        INSERT INTO commodino_structs VALUES (?);
        `, {commodino_struct},
    ))
    sa.on_fail_panic(db, sa.execute(db, "COMMIT TRANSACTION;"))
    return true
}

db_close :: proc(db: ^sqlite.Connection) -> ( ok:bool ){
    result := sqlite.close(db)
    return ( result == .Ok )
}
