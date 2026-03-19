package game

// For debugging traps
import "base:intrinsics"

// To allow debugging tests:
//  1. add a call to breakpoint()
//  2. call the test or tests from main()
//  3. `odin run tests/ -debug -o:none`
//  4. `gdb tests.bin`
//  5. `run`
//  6. `next` a few times until you are out of th breakpoint() proc
//  7. profit
//
//  Bonus:
//  you can use gdb's:
//   - `display` to see the state of expression on every break,
//   - `watch` break on any write
//   - `rwatch` break on any read
//   - `awatch` break on any read or write
breakpoint :: proc () {
    intrinsics.debug_trap()
}
