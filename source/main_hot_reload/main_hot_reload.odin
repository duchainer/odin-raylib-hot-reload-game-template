/*
Development game exe. Loads build/hot_reload/game.dll and reloads it whenever it
changes.

Multiple instances are supported by using GAME_hot_reload_INSTANCE_ID env var.
If not set, uses PID as the instance ID.
*/

package main

import "core:dynlib"
import "core:fmt"
import "core:c/libc"
import "core:os"
import "core:log"
import "core:mem"
import "core:path/filepath"
import "core:time"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "build/hot_reload/"

hot_reload_instance_id: int
game_dll_path: string


// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	copy_err := os.copy_file(to, game_dll_path)

	if copy_err != nil {
		log.errorf("[pid:%d] Failed to copy %v to %v: %v", hot_reload_instance_id, game_dll_path, to, copy_err)
		return false
	}

	return true
}

Game_API :: struct {
	lib: dynlib.Library,
	init_window: proc(),
	init: proc(),
	update: proc(),
	should_run: proc() -> bool,
	shutdown: proc(),
	shutdown_window: proc(),
	memory: proc() -> rawptr,
	memory_size: proc() -> int,
	hot_reloaded: proc(mem: rawptr, mode: int),
	force_reload: proc() -> bool,
	force_restart: proc() -> bool,
	force_replay: proc() -> bool,
	modification_time: time.Time,
	api_version: int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(game_dll_path)
	if mod_time_error != os.ERROR_NONE {
		log.errorf("[pid:%d] Failed getting last write time of %v, error code: %v", hot_reload_instance_id, game_dll_path, mod_time_error)
		return
	}

	copy_dll(game_dll_path) or_return

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_path, "game_", "lib")
	if !ok {
		log.errorf("[pid:%d] Failed initializing symbols: %v", hot_reload_instance_id, dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			log.errorf("[pid:%d] Failed unloading lib: %v", hot_reload_instance_id, dynlib.last_error())
		}
	}

	if os.remove(game_dll_path) != nil {
		log.errorf("[pid:%d] Failed to remove %v copy", hot_reload_instance_id, game_dll_path)
	}
}

main :: proc() {
	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_working_directory(exe_dir)

	context.logger = log.create_console_logger()

    // TODO See if we can stay quite close to the upstream odin-raylib-hot-reload-template repo code,
    //       and not fork too much this file
	hot_reload_instance_id = os.get_pid()
	log.infof("[pid:%d] Hot-reload instance ID: %d", hot_reload_instance_id, hot_reload_instance_id)
	log.infof("[pid:%d] size_of(int)=%d", hot_reload_instance_id, size_of(int))

    get_game_dll_copy_path :: proc(hot_reload_instance_id: int) -> string {
        return fmt.tprintf("%vgame_%v%v", GAME_DLL_DIR, hot_reload_instance_id, DLL_EXT)
    }

    game_dll_path = get_game_dll_copy_path(hot_reload_instance_id)

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			log.errorf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

if !game_api_ok {
		log.errorf("[pid:%d] Failed to load Game API", hot_reload_instance_id)
		return
	}

	game_api_version += 1
	game_api.init_window()
	game_api.init()

	old_game_apis := make([dynamic]Game_API, default_allocator)

	for game_api.should_run() {
		old_rand_gen := context.random_generator
		game_api.update()
		assert(old_rand_gen == context.random_generator, "Context should only be affecting callees, not callers, no?")

		force_reload := game_api.force_reload()
		force_restart := game_api.force_restart()
		force_replay := game_api.force_replay()
		reload := force_reload || force_restart || force_replay
		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(game_dll_path)

		if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
			reload = true
		}

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				force_restart = force_restart || force_replay || game_api.memory_size() != new_game_api.memory_size()

				if !force_restart {
					// This does the normal hot reload

					// Note that we don't unload the old game APIs because that
					// would unload the DLL. The DLL can contain stored info
					// such as string literals. The old DLLs are only unloaded
					// on a full reset or on shutdown.
					append(&old_game_apis, game_api)
					game_memory := game_api.memory()


					game_api = new_game_api
					game_api.hot_reloaded(game_memory, 0) // 0 = .HOT_RELOAD
				} else {
					// This does a full reset. That's basically like opening and
					// closing the game, without having to restart the executable.
					//
					// You end up in here if the game requests a full reset OR
					// if the size of the game memory has changed. That would
					// probably lead to a crash anyways.

					game_api.shutdown()
					reset_tracking_allocator(&tracking_allocator)

					for &g in old_game_apis {
						unload_game_api(&g)
					}

					clear(&old_game_apis)
					unload_game_api(&game_api)
					game_api = new_game_api

					// Determine which restart mode to use
					restart_mode: int
					if force_replay {
						restart_mode = 2 // .FORCE_REPLAY - normal speed
					} else {
						restart_mode = 1 // .FORCE_RESTART - fast replay
					}

					game_api.init()
					game_api.hot_reloaded(game_api.memory(), restart_mode)
				}

				game_api_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			// This prevents the game from closing without you seeing the bad
			// frees. This is mostly needed because I use Sublime Text and my game's
			// console isn't hooked up into Sublime's console properly.
			libc.getchar()
			panic("Bad free detected")
		}
	}

	free_all(context.temp_allocator)
	game_api.shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		// This prevents the game from closing without you seeing the memory
		// leaks. This is mostly needed because I use Sublime Text and my game's
		// console isn't hooked up into Sublime's console properly.
		libc.getchar()
	}

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	game_api.shutdown_window()
	unload_game_api(&game_api)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
