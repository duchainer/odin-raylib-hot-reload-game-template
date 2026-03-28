package game

// Mostly done with Claude.ai help:
//  - general diff : https://claude.ai/chat/32eb8d88-4aa4-4b27-9463-cac4e7d97cb5
//  - diff between arrays: https://claude.ai/chat/996e8fcb-d53b-466e-ab81-bd2b63782fb0

import "core:mem"
import "core:fmt"
import "core:reflect"
// import "core:strings"

// Field difference result
Field_Diff :: struct {
    field_name: string,
    old_value: string,
    new_value: string,
}

// Compare two structs and return list of differences
diff_struct :: proc($T: typeid, old: T, new: T) -> [dynamic]Field_Diff {
    diffs := make([dynamic]Field_Diff)
    
    type_info := type_info_of(T)
    
	loop: for {
        #partial switch info in type_info.variant {
        case reflect.Type_Info_Named:   type_info = info.base
        case reflect.Type_Info_Struct:
            // Use field_count and slice the multi-pointers
            names := info.names[:info.field_count]

            for field_name, _ in names {
                old_field := reflect.struct_field_value_by_name(old, field_name)
                new_field := reflect.struct_field_value_by_name(new, field_name)

                if old_field.id != new_field.id {
                    continue
                }

                // Get detailed differences
                diff_values(&diffs, field_name, old_field, new_field)
            }
            break loop
        }
    }
    
    return diffs
}

// Recursively find differences between two values
diff_values :: proc(diffs: ^[dynamic]Field_Diff, path: string, a, b: any) {
    if a.id != b.id do return
    
    ti := type_info_of(a.id)
    
    #partial switch info in ti.variant {
    case reflect.Type_Info_Array:
        diff_arrays(diffs, path, a, b, info)
    case reflect.Type_Info_Dynamic_Array:
        diff_dynamic_arrays(diffs, path, a, b, info)
    case reflect.Type_Info_Slice:
        diff_slices(diffs, path, a, b, info)
    case reflect.Type_Info_Named:
        // Recurse into named types
        diff_values(diffs, path, any{a.data, info.base.id}, any{b.data, info.base.id})
    case reflect.Type_Info_Struct:
        diff_structs(diffs, path, a, b, info)
    case:
        // For primitive types, check if they're different
        if !values_equal(a, b) {
            append(diffs, Field_Diff{
                field_name = path,
                old_value = value_to_string(a),
                new_value = value_to_string(b),
            })
        }
    }
}

// Diff two structs field by field
diff_structs :: proc(diffs: ^[dynamic]Field_Diff, path: string, a, b: any, info: reflect.Type_Info_Struct) {
    names := info.names[:info.field_count]
    
    for field_name in names {
        a_field := reflect.struct_field_value_by_name(a, field_name)
        b_field := reflect.struct_field_value_by_name(b, field_name)
        
        if a_field.id != b_field.id {
            continue
        }
        
        field_path := fmt.tprintf("%s.%s", path, field_name)
        diff_values(diffs, field_path, a_field, b_field)
    }
}

// Diff two fixed arrays
diff_arrays :: proc(diffs: ^[dynamic]Field_Diff, path: string, a, b: any, info: reflect.Type_Info_Array) {
    elem_size := info.elem_size
    count := info.count
    
    a_data := (^u8)(a.data)
    b_data := (^u8)(b.data)
    
    for i in 0..<count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        elem_path := fmt.tprintf("%s[%d]", path, i)
        diff_values(diffs, elem_path, a_elem, b_elem)
    }
}

// Diff two dynamic arrays
diff_dynamic_arrays :: proc(diffs: ^[dynamic]Field_Diff, path: string, a, b: any, info: reflect.Type_Info_Dynamic_Array) {
    a_raw := (^mem.Raw_Dynamic_Array)(a.data)
    b_raw := (^mem.Raw_Dynamic_Array)(b.data)
    
    // Report length difference
    if a_raw.len != b_raw.len {
        append(diffs, Field_Diff{
            field_name = fmt.tprintf("%s.len", path),
            old_value = fmt.tprintf("%d", a_raw.len),
            new_value = fmt.tprintf("%d", b_raw.len),
        })
    }
    
    elem_size := info.elem_size
    min_count := min(a_raw.len, b_raw.len)
    
    a_data := (^u8)(a_raw.data)
    b_data := (^u8)(b_raw.data)
    
    // Compare common elements
    for i in 0..<min_count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        elem_path := fmt.tprintf("%s[%d]", path, i)
        diff_values(diffs, elem_path, a_elem, b_elem)
    }
}

// Diff two slices
diff_slices :: proc(diffs: ^[dynamic]Field_Diff, path: string, a, b: any, info: reflect.Type_Info_Slice) {
    a_raw := (^mem.Raw_Slice)(a.data)
    b_raw := (^mem.Raw_Slice)(b.data)
    
    // Report length difference
    if a_raw.len != b_raw.len {
        append(diffs, Field_Diff{
            field_name = fmt.tprintf("%s.len", path),
            old_value = fmt.tprintf("%d", a_raw.len),
            new_value = fmt.tprintf("%d", b_raw.len),
        })
    }
    
    elem_size := info.elem_size
    min_count := min(a_raw.len, b_raw.len)
    
    a_data := (^u8)(a_raw.data)
    b_data := (^u8)(b_raw.data)
    
    // Compare common elements
    for i in 0..<min_count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        elem_path := fmt.tprintf("%s[%d]", path, i)
        diff_values(diffs, elem_path, a_elem, b_elem)
    }
}

// Helper to check if two any values are equal
values_equal :: proc(a, b: any) -> bool {
    if a.id != b.id do return false
    
    ti := type_info_of(a.id)
    
    #partial switch info in ti.variant {
    case reflect.Type_Info_String:
        return (^string)(a.data)^ == (^string)(b.data)^
    case reflect.Type_Info_Integer:
        switch ti.size {
        case 4: return (^i32)(a.data)^ == (^i32)(b.data)^
        case 8: return (^i64)(a.data)^ == (^i64)(b.data)^
        case 2: return (^i16)(a.data)^ == (^i16)(b.data)^
        case 1: return (^i8)(a.data)^ == (^i8)(b.data)^
        }
    case reflect.Type_Info_Float:
        switch ti.size {
        case 4: return (^f32)(a.data)^ == (^f32)(b.data)^
        case 8: return (^f64)(a.data)^ == (^f64)(b.data)^
        }
    case reflect.Type_Info_Boolean:
        return (^bool)(a.data)^ == (^bool)(b.data)^
    case reflect.Type_Info_Enum:
        return enums_equal(a, b, info)
    case reflect.Type_Info_Array:
        return arrays_equal(a, b, info)
    case reflect.Type_Info_Dynamic_Array:
        return dynamic_arrays_equal(a, b, info)
    case reflect.Type_Info_Slice:
        return slices_equal(a, b, info)
    case reflect.Type_Info_Named:
        // Recurse into named types
        return values_equal(
            any{a.data, info.base.id},
            any{b.data, info.base.id},
        )
    case reflect.Type_Info_Struct:
        return structs_equal(a, b, info)
    case:
        data_size := ti.size
        ret := mem.compare_byte_ptrs((^u8)(a.data), (^u8)(b.data), data_size) == 0
        return ret
    }
    
    return false
}

// Compare enums
enums_equal :: proc(a, b: any, info: reflect.Type_Info_Enum) -> bool {
    base_ti := type_info_of(info.base.id)
    
    #partial switch base_info in base_ti.variant {
    case reflect.Type_Info_Integer:
        switch base_ti.size {
        case 4: return (^i32)(a.data)^ == (^i32)(b.data)^
        case 8: return (^i64)(a.data)^ == (^i64)(b.data)^
        case 2: return (^i16)(a.data)^ == (^i16)(b.data)^
        case 1: return (^i8)(a.data)^ == (^i8)(b.data)^
        }
    }
    
    return false
}

// Compare structs field by field
structs_equal :: proc(a, b: any, info: reflect.Type_Info_Struct) -> bool {
    names := info.names[:info.field_count]
    
    for field_name in names {
        a_field := reflect.struct_field_value_by_name(a, field_name)
        b_field := reflect.struct_field_value_by_name(b, field_name)
        
        if a_field.id != b_field.id {
            return false
        }
        
        if !values_equal(a_field, b_field) {
            return false
        }
    }
    
    return true
}

// Compare fixed-size arrays
arrays_equal :: proc(a, b: any, info: reflect.Type_Info_Array) -> bool {
    elem_size := info.elem_size
    count := info.count
    
    a_data := (^u8)(a.data)
    b_data := (^u8)(b.data)
    
    for i in 0..<count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        if !values_equal(a_elem, b_elem) {
            return false
        }
    }
    
    return true
}

// Compare dynamic arrays
dynamic_arrays_equal :: proc(a, b: any, info: reflect.Type_Info_Dynamic_Array) -> bool {
    a_raw := (^mem.Raw_Dynamic_Array)(a.data)
    b_raw := (^mem.Raw_Dynamic_Array)(b.data)
    
    if a_raw.len != b_raw.len {
        return false
    }
    
    elem_size := info.elem_size
    count := a_raw.len
    
    a_data := (^u8)(a_raw.data)
    b_data := (^u8)(b_raw.data)
    
    for i in 0..<count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        if !values_equal(a_elem, b_elem) {
            return false
        }
    }
    
    return true
}

// Compare slices
slices_equal :: proc(a, b: any, info: reflect.Type_Info_Slice) -> bool {
    a_raw := (^mem.Raw_Slice)(a.data)
    b_raw := (^mem.Raw_Slice)(b.data)
    
    if a_raw.len != b_raw.len {
        return false
    }
    
    elem_size := info.elem_size
    count := a_raw.len
    
    a_data := (^u8)(a_raw.data)
    b_data := (^u8)(b_raw.data)
    
    for i in 0..<count {
        a_elem := any{rawptr(uintptr(a_data) + uintptr(i * elem_size)), info.elem.id}
        b_elem := any{rawptr(uintptr(b_data) + uintptr(i * elem_size)), info.elem.id}
        
        if !values_equal(a_elem, b_elem) {
            return false
        }
    }
    
    return true
}

// Helper to convert any value to string for display
value_to_string :: proc(v: any) -> string {
    ti := type_info_of(v.id)
    
    #partial switch info in ti.variant {
    case reflect.Type_Info_String:
        return fmt.tprintf("%q", (^string)(v.data)^)
    case reflect.Type_Info_Integer:
        switch ti.size {
        case 4: return fmt.tprintf("%d", (^i32)(v.data)^)
        case 8: return fmt.tprintf("%d", (^i64)(v.data)^)
        case 2: return fmt.tprintf("%d", (^i16)(v.data)^)
        case 1: return fmt.tprintf("%d", (^i8)(v.data)^)
        }
    case reflect.Type_Info_Float:
        switch ti.size {
        case 4: return fmt.tprintf("%.9f", (^f32)(v.data)^)
        case 8: return fmt.tprintf("%.18f", (^f64)(v.data)^)
        }
    case reflect.Type_Info_Boolean:
        return fmt.tprintf("%v", (^bool)(v.data)^)
    case reflect.Type_Info_Enum:
        return enum_to_string(v, info)
    case reflect.Type_Info_Array:
        return array_to_string(v, info)
    case reflect.Type_Info_Dynamic_Array:
        return dynamic_array_to_string(v, info)
    case reflect.Type_Info_Slice:
        return slice_to_string(v, info)
    case reflect.Type_Info_Named:
        // Recurse into named types
        return value_to_string(any{v.data, info.base.id})
    case reflect.Type_Info_Struct:
        return struct_to_string(v, info)
    }
    
    return "<unknown>"
}

// Convert enum to string with name
enum_to_string :: proc(v: any, info: reflect.Type_Info_Enum) -> string {
    base_ti := type_info_of(info.base.id)
    
    // Get the integer value
    int_value: i64
    #partial switch base_info in base_ti.variant {
    case reflect.Type_Info_Integer:
        switch base_ti.size {
        case 4: int_value = i64((^i32)(v.data)^)
        case 8: int_value = (^i64)(v.data)^
        case 2: int_value = i64((^i16)(v.data)^)
        case 1: int_value = i64((^i8)(v.data)^)
        }
    }
    
    // Find the name for this value
    for name, i in info.names {
        // Type_Info_Enum_Value is just an i64
        enum_int := i64(info.values[i])
        
        if enum_int == int_value {
            return fmt.tprintf("%s(%d)", name, int_value)
        }
    }
    
    // Value not found in enum (invalid enum value)
    return fmt.tprintf("<invalid>(%d)", int_value)
}

// Convert struct to string
struct_to_string :: proc(v: any, info: reflect.Type_Info_Struct) -> string {
    names := info.names[:info.field_count]
    
    result := "{"
    for field_name, i in names {
        field_val := reflect.struct_field_value_by_name(v, field_name)
        if i > 0 do result = fmt.tprintf("%s, ", result)
        result = fmt.tprintf("%s%s: %s", result, field_name, value_to_string(field_val))
    }
    result = fmt.tprintf("%s}", result)
    
    return result
}

// Convert fixed array to string
array_to_string :: proc(v: any, info: reflect.Type_Info_Array) -> string {
    elem_size := info.elem_size
    count := info.count
    v_data := (^u8)(v.data)
    
    result := "["
    for i in 0..<count {
        elem := any{rawptr(uintptr(v_data) + uintptr(i * elem_size)), info.elem.id}
        if i > 0 do result = fmt.tprintf("%s, ", result)
        result = fmt.tprintf("%s%s", result, value_to_string(elem))
    }
    result = fmt.tprintf("%s]", result)
    
    return result
}

// Convert dynamic array to string
dynamic_array_to_string :: proc(v: any, info: reflect.Type_Info_Dynamic_Array) -> string {
    raw := (^mem.Raw_Dynamic_Array)(v.data)
    elem_size := info.elem_size
    count := raw.len
    v_data := (^u8)(raw.data)
    
    result := "["
    for i in 0..<count {
        elem := any{rawptr(uintptr(v_data) + uintptr(i * elem_size)), info.elem.id}
        if i > 0 do result = fmt.tprintf("%s, ", result)
        result = fmt.tprintf("%s%s", result, value_to_string(elem))
    }
    result = fmt.tprintf("%s]", result)
    
    return result
}

// Convert slice to string
slice_to_string :: proc(v: any, info: reflect.Type_Info_Slice) -> string {
    raw := (^mem.Raw_Slice)(v.data)
    elem_size := info.elem_size
    count := raw.len
    v_data := (^u8)(raw.data)
    
    result := "["
    for i in 0..<count {
        elem := any{rawptr(uintptr(v_data) + uintptr(i * elem_size)), info.elem.id}
        if i > 0 do result = fmt.tprintf("%s, ", result)
        result = fmt.tprintf("%s%s", result, value_to_string(elem))
    }
    result = fmt.tprintf("%s]", result)
    
    return result
}

// Pretty print the differences
print_diffs :: proc(diffs: [dynamic]Field_Diff, print_on_no_diff:=true) {
    if len(diffs) == 0 {
        if print_on_no_diff {
            fmt.println("No differences found")
        }
        return
    }
    
    fmt.printf("Found %d difference(s) (recorded -> replayed):\n", len(diffs))
    for diff in diffs {
        fmt.printf("  %s: %s -> %s\n", diff.field_name, diff.old_value, diff.new_value)
    }
}
