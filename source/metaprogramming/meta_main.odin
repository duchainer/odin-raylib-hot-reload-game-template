package metaprogramming

import "core:os" 
import "core:fmt"
import "core:strings"
import "core:reflect"
import "../types"

main :: proc() {
    
    err_remove_all := os.remove_all("source/generated/")
    if err_remove_all != nil && err_remove_all != os.General_Error.Not_Exist{
        fmt.panicf("Failed to remove the old generated/ directory: %v", err_remove_all) 
    }

    err_make_directory := os.make_directory("source/generated/")
    if err_make_directory != nil && err_make_directory != os.General_Error.Exist{
        fmt.panicf("Failed to create the generated/ directory: %v", err_make_directory) 
    }
    commit_hash, ok := git_get_commit();
    if !ok {
        fmt.panicf("Failed to get the git commit") 
    }



    recorded_input_events_joined_keys : string
    input_key_field_names: [len(types.UsedKeysEnum)]string //[field_count]string
    {
        field_names := reflect.enum_field_names(types.UsedKeysEnum)
        for name, i in field_names{
            input_key_field_names[i] = fmt.tprintf("key_%v", strings.to_lower(name))
        }
        recorded_input_events_joined_keys = strings.join(input_key_field_names[:], ", ")
    }

    FILE_HEADER ::`// GENERATED FROM metaprogramming/meta_main.odin
package generated
`

    buf: strings.Builder
    strings.builder_init(&buf, 0, len(FILE_HEADER)*2, context.temp_allocator)

    fmt.sbprint(&buf, FILE_HEADER)
    fmt.sbprintf(&buf, "\nCOMMIT_HASH :: \"%v\"", commit_hash)
    fmt.sbprintf(&buf, "\nrecorded_input_events_joined_keys : string = \"%v\"\n", recorded_input_events_joined_keys)
    fmt.sbprintf(&buf, "input_key_field_names: [%v]string = {{\"%v\"}}\n", len(types.UsedKeysEnum), strings.join(input_key_field_names[:], "\", \""))
    content := strings.to_string(buf)

    if write_err := os.write_entire_file("source/generated/generated_db.odin", transmute([]byte)content); write_err != nil {
        fmt.panicf("Failed to create file generated_db: %v", write_err)
    }

    free_all(context.temp_allocator)
}
