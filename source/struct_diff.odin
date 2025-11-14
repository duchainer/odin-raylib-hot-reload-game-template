package game

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

                // Compare values using any comparison
                if !values_equal(old_field, new_field) {
                    diff := Field_Diff{
                        field_name = field_name,
                        old_value = value_to_string(old_field),
                        new_value = value_to_string(new_field),
                    }
                    append(&diffs, diff)
                }
            }
            break loop
        }
    }
    
    return diffs
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
    case reflect.Type_Info_Array:
        return arrays_equal(a, b, info)
    case reflect.Type_Info_Dynamic_Array:
        return dynamic_arrays_equal(a, b, info)
    case reflect.Type_Info_Slice:
        return slices_equal(a, b, info)
    case:
        data_size := ti.size
        ret := mem.compare_byte_ptrs((^u8)(a.data), (^u8)(b.data), data_size) == 0
        return ret
    }
    
    return false
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
        case 4: return fmt.tprintf("%.2f", (^f32)(v.data)^)
        case 8: return fmt.tprintf("%.2f", (^f64)(v.data)^)
        }
    case reflect.Type_Info_Boolean:
        return fmt.tprintf("%v", (^bool)(v.data)^)
    case reflect.Type_Info_Array:
        return array_to_string(v, info)
    case reflect.Type_Info_Dynamic_Array:
        return dynamic_array_to_string(v, info)
    case reflect.Type_Info_Slice:
        return slice_to_string(v, info)
    }
    
    return "<gdb knows>"
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
print_diffs :: proc(diffs: [dynamic]Field_Diff) {
    if len(diffs) == 0 {
        fmt.println("No differences found")
        return
    }
    
    fmt.printf("Found %d difference(s):\n", len(diffs))
    for diff in diffs {
        fmt.printf("  %s: %s -> %s\n", diff.field_name, diff.old_value, diff.new_value)
    }
}
