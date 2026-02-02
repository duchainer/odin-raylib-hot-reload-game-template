#!/usr/bin/env sh

# Compile
# -g is for debug symbols
gcc -c -g -fPIC sqlite-amalgamation-3510100/sqlite3.c -o sqlite3.o

# Make a static library archive
ar rcs libsqlite3.a sqlite3.o
