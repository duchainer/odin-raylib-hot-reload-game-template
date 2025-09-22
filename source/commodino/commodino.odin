package commodino

import "core:fmt"
import "core:time"

assert :: proc(break_only_game: ^bool, condition: bool, message:= "Failed on location: %v", loc := #caller_location) -> bool {
	if condition {
		break_only_game^ = false
	} else {
		fmt.print(time.now())
		fmt.println(message, loc)
		break_only_game^ = true
	}
	return condition
}
