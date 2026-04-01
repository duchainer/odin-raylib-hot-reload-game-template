package metaprogramming

import "core:os"
import "core:fmt"
import "core:strings"

git_get_commit :: proc(allocator := context.temp_allocator) -> (commit_hash: string, ok: bool) {
    desc := os.Process_Desc{
        command = {"git", "rev-parse", "HEAD"},
    }
    
    state, stdout, stderr, err := os.process_exec(desc, allocator)
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
