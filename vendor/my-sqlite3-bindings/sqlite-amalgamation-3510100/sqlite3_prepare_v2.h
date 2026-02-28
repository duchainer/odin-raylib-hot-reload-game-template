int sqlite3_prepare_v2(
    int *db,            /* Database handle */
    const char *zSql,   /* SQL statement, UTF-8 encoded */
    int nByte,          /* Maximum length of zSql in bytes. */
    int **ppStmt,       /* OUT: Statement handle */
    const char **pzTail /* OUT: Pointer to unused portion of zSql */
);
