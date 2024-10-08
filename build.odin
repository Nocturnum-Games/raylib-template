package main

import "core:fmt"
import os "core:os/os2"
import "core:path/filepath"
import "core:strings"

ENABLE_TRACKING_ALLOCATOR := true
ENABLE_HOT_RELOAD         := true
STANDALONE                := false
RAYLIB_SHARED             := true

sb_write_str :: strings.write_string

build_command :: proc(builder: ^strings.Builder, command_name, target, exec_name, args: string, vet: []string, shared: bool) {
    fmt.sbprintf(builder, "%s %s -out:\"bin/%s\" %s %s", command_name, target, exec_name, args, strings.join(vet, " "))
    if shared do sb_write_str(builder, " -build-mode:shared")
}

main :: proc() {
    script_dir := filepath.dir(#file)
    os.set_working_directory(script_dir)
    name := filepath.base(script_dir)

    vet := []string{"-strict-style", "-vet", "-vet-using-param", "-vet-style", "-vet-semicolon", "-disallow-do", "-warnings-as-errors"}
    
    args_builder := strings.builder_make(context.temp_allocator)

    sb_write_str(&args_builder, "-show-timings -use-separate-modules -debug -o:none")
    if ENABLE_TRACKING_ALLOCATOR { sb_write_str(&args_builder, " -define:ENABLE_TRACKING_ALLOCATOR=true")}
    if ENABLE_HOT_RELOAD         { sb_write_str(&args_builder, " -define:ENABLE_HOT_RELOAD=true")}
    if STANDALONE                { sb_write_str(&args_builder, " -define:STANDALONE=true")}
    if RAYLIB_SHARED             { sb_write_str(&args_builder, " -define:RAYLIB_SHARED=true")}
    args := strings.to_string(args_builder)

    // Ensure the bin directory exists
    if !os.exists("bin") do os.mkdir("bin")

    rl_path := filepath.join({ODIN_ROOT, "vendor", "raylib"})
    os_subdir: string
    files: []string

    #partial switch ODIN_OS {
        case .Darwin:  os_subdir = "macos-arm64"; files = {"libraylib.500.dylib", "libraygui.dylib"}
        case .Windows: os_subdir = "windows";     files = {"raylib.dll", "raygui.dll"}
        case: return
    }

    for file in files do os.copy_file(fmt.tprintf("bin/%s", file), filepath.join({rl_path, os_subdir, file}))

    builder := strings.builder_make(context.temp_allocator)

    dyn_ext: string = "dll"
    when ODIN_OS == .Darwin do dyn_ext = "dylib"; else when ODIN_OS == .Linux do dyn_ext = "so"

    build_command(&builder, "odin build", "src/game", fmt.tprintf("game.%s", dyn_ext), args, vet, true)
    game_cmd := strings.to_string(builder)
    
    state, stdout, stderr, err := os.process_exec({command = strings.split(game_cmd, " ")}, context.temp_allocator)
    if err != nil || !state.success {
        panic(fmt.tprintf("Error building game library: %v\nStdout: %s\nStderr: %s\n", err, stdout, stderr))
    }

    exec_name: string; when ODIN_OS == .Windows do exec_name = fmt.tprintf("%s.exe", name); else do exec_name = name

    if !os.exists(fmt.tprintf("bin/%s", exec_name)) {
        strings.builder_reset(&builder)
        build_command(&builder, "odin build", "src/main", exec_name, args, vet, false)
        main_cmd := strings.to_string(builder)

        state, stdout, stderr, err = os.process_exec({command = strings.split(main_cmd, " ")}, context.temp_allocator)

        if err != nil || !state.success {
            panic(fmt.tprintf("Error building main executable: %v\nStdout: %s\nStderr: %s\n", err, stdout, stderr))
        }

        // Remove old game libraries
        old_libs, _ := filepath.glob(fmt.tprintf("bin/game_*.%s", dyn_ext))
        for lib in old_libs do os.remove(lib)
    }
    fmt.printfln("Finished Building Project: %v", name)
}