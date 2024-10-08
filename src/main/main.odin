package main

import "core:mem"
import "core:fmt"
import "core:dynlib"
import "core:path/filepath"
import "core:os"
import "core:os/os2"
import "core:log"
import "../game"

_ :: mem
_ :: os
_ :: os2
_ :: dynlib
_ :: game

ENABLE_TRACKING_ALLOCATOR :: #config(ENABLE_TRACKING_ALLOCATOR, false)
ENABLE_PROFILER           :: #config(ENABLE_PROFILER, false)
ENABLE_HOT_RELOAD         :: #config(ENABLE_HOT_RELOAD, false)
STANDALONE                :: #config(STANDALONE, true)

main :: proc() {
    args := os.args
    root := filepath.dir(args[0], context.temp_allocator)
    os.set_current_directory(root)

    mode: int = 0
    when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
    }

    logh, logh_err := os.open("log.txt", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)
    defer os.close(logh)
    
    if logh_err == os.ERROR_NONE {
        fmt.printfln("Logging enabled")
        os.stdout = logh
        os.stderr = logh
    } else {
        fmt.printfln("Failed to open log file: err = {}", logh_err)
    }

    logger := logh_err == os.ERROR_NONE ? log.create_file_logger(logh) : log.create_console_logger()
    context.logger = logger

    when ENABLE_TRACKING_ALLOCATOR {
        log.info("Tracking allocator enabled")
        default_allocator := context.allocator
        tracking_allocator: Tracking_Allocator
        tracking_allocator_init(&tracking_allocator, default_allocator)
        context.allocator = tracking_allocator_create(&tracking_allocator)
    }

    log.info("Starting Game!")

    when ENABLE_HOT_RELOAD {
        game_api_version := 0
        game_api, game_api_ok := load_game_api(game_api_version)

        if !game_api_ok {
            log.error("Failed to load Game API")
            return
        }

        game_api_version += 1
        game_api.init_window()
        game_api.init()

        old_game_apis := make([dynamic]GameAPI, context.allocator)
    } else {
        game.game_init_window()
        game.game_init()
    }


    window_open := true

    for window_open {
        when ENABLE_HOT_RELOAD {
            window_open = game_api.update()
            force_reload := game_api.force_reload()
            force_restart := game_api.force_restart()
            reload := force_reload || force_restart
            game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(get_game_lib_name())

            if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
                reload = true
            }

            if reload {
                new_game_api, new_game_api_ok := load_game_api(game_api_version)

                if new_game_api_ok {
                    if game_api.memory_size() != new_game_api.memory_size() || force_restart {
                        game_api.shutdown()

                        when ENABLE_TRACKING_ALLOCATOR {            
                            reset_tracking_allocator(&tracking_allocator)
                        }
                    
                        for &g in old_game_apis {
                            unload_game_api(&g)
                        }

                        clear(&old_game_apis)
                        unload_game_api(&game_api)
                        game_api = new_game_api
                        game_api.init()
                    } else {
                        append(&old_game_apis, game_api)
                        game_memory := game_api.memory()
                        game_api = new_game_api
                        game_api.hot_reloaded(game_memory)
                    }
                    game_api_version += 1
                } 
            }
        } else {
            window_open = game.game_update()
        }

        when ENABLE_TRACKING_ALLOCATOR {
            for b in tracking_allocator.bad_free_array {
                log.errorf("Bad free at: %v", b.location)
            }
            clear(&tracking_allocator.bad_free_array)
        }
        free_all(context.temp_allocator)
    }

    when ENABLE_HOT_RELOAD {
        game_api.shutdown()
        game_api.shutdown_window()
        for &g in old_game_apis {
            unload_game_api(&g)
        }
        delete(old_game_apis)
        unload_game_api(&game_api)
    } else {
        game.game_shutdown()
        game.game_shutdown_window()
    }

    when ENABLE_TRACKING_ALLOCATOR {
        mem.tracking_allocator_destroy(&tracking_allocator)
    }
}

when ENABLE_HOT_RELOAD {
    GameAPI :: struct {
        lib:               dynlib.Library,
        init_window:       proc(),
        init:              proc(),
        update:            proc() -> bool,
        shutdown:          proc(),
        shutdown_window:   proc(),
        memory:            proc() -> rawptr,
        memory_size:       proc() -> int,
        hot_reloaded:      proc(mem: rawptr),
        force_reload:      proc() -> bool,
        force_restart:     proc() -> bool,
        modification_time: os.File_Time,
        api_version:       int,
    }

     get_game_lib_name :: proc() -> string {
        when ODIN_OS == .Windows {
            return "game.dll"
        } else when ODIN_OS == .Darwin {
            return "game.dylib"
        } else {
            return "game.so"
        }
    }

    get_lib_extension :: proc() -> string {
        when ODIN_OS == .Windows {
            return "dll"
        } else when ODIN_OS == .Darwin {
            return "dylib"
        } else {
            return "so"
        }
    }

    load_game_api :: proc(api_version: int) -> (api: GameAPI, ok: bool) {
        lib_name := get_game_lib_name()
        mod_time, mod_time_err := os.last_write_time_by_name(lib_name)
        if mod_time_err != os.ERROR_NONE {
            fmt.printfln("Failed to get last write time for {}! Error: {}", lib_name, mod_time_err)
            return  
        }

        new_lib_name := fmt.tprintf("game_{}.{}", api_version, get_lib_extension())
        copy_lib(new_lib_name) or_return

        if _, ok = dynlib.initialize_symbols(&api, new_lib_name, "game_", "lib"); !ok {
            fmt.printfln("Failed initializing symbols: {}", dynlib.last_error())
        }

        api.api_version = api_version
        api.modification_time = mod_time
        ok = true
        return
    }

    copy_lib :: proc(to: string) -> bool {
        err := os2.copy_file(to, get_game_lib_name())
        
        if err != nil {
            fmt.printfln("Failed to copy game lib to {}", to)
            return false
        }
        return true
    }

    unload_game_api :: proc (api: ^GameAPI) {
        if api.lib == nil || !dynlib.unload_library(api.lib) {
            fmt.printfln("Failed to unload game lib: {}", dynlib.last_error())
        }

        lib_name := fmt.tprintf("game_{}.{}", api.api_version, get_lib_extension())
        if os.remove(lib_name) != nil {
            fmt.printfln("Failed to remove {}", lib_name)
        }
    }
}

when  ENABLE_TRACKING_ALLOCATOR {
    Tracking_Allocator         :: mem.Tracking_Allocator
    tracking_allocator_init    :: mem.tracking_allocator_init
    tracking_allocator_create  :: mem.tracking_allocator
    tracking_allocator_destroy :: mem.tracking_allocator_destroy

    reset_tracking_allocator :: proc(a: ^Tracking_Allocator) -> bool {
        err := false
        for _, value in a.allocation_map {
            fmt.printf("%v: leaked %v bytes\n", value.location, value.size)
            err = true
        }
        return err  
    }
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1