package metaprogramming

import "core:os" 
import "core:fmt"

main :: proc() {
    
    err_remove_all := os.remove_all("../generated/")
    if err_remove_all != nil {
        fmt.panicf("Failed to remove the old generated/ directory: %v", err_remove_all) 
    }

    err_make_directory := os.make_directory("../generated/")
    if err_make_directory != nil && err_make_directory != os.General_Error.Exist{
        fmt.panicf("Failed to create the generated/ directory: %v", err_make_directory) 
    }
    commit_hash, ok := git_get_commit();
    if !ok {
        fmt.panicf("Failed to get the git commit") 
    }
    fmt.printfln("COMMIT_HASH :: %v", commit_hash)
	_ = os.write_entire_file("../generated/generated_commit.odin", transmute([]byte)fmt.tprintf(
`// GENERATED FROM metaprogramming/meta_main.odin

package generated

COMMIT_HASH :: "%v"
`, commit_hash
    ))
    free_all(context.temp_allocator)
}
