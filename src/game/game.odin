package game

import rl "vendor:raylib"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:path/filepath"

ENABLE_TRACKING_ALLOCATOR :: #config(ENABLE_TRACKING_ALLOCATOR, false)
ENABLE_PROFILER           :: #config(ENABLE_PROFILER, false)
ENABLE_HOT_RELOAD         :: #config(ENABLE_HOT_RELOAD, false)
STANDALONE                :: #config(STANDALONE, true)

PIXEL_WINDOW_HEIGHT :: 180

Game_Memory :: struct {

}

g_mem: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
    w := f32(rl.GetScreenWidth())
    h := f32(rl.GetScreenHeight())

    return {
        zoom = h/PIXEL_WINDOW_HEIGHT,
        target = 0,
        offset = { w/2, h/2 },
    }
}

ui_camera :: proc() -> rl.Camera2D {
    return {
        zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
    }
}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)

    rl.BeginMode2D(game_camera())

    rl.EndMode2D()

    rl.BeginMode2D(ui_camera())

    rl.EndMode2D()

    rl.EndDrawing()
}

@(export)
game_update :: proc() -> bool {
    update()
    draw()
    return !rl.WindowShouldClose()
}

@(export)
game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(1280, 720, fmt.ctprintf(format_window_title(filepath.base(os.args[0]))))
    rl.SetWindowPosition(200, 200)
    rl.SetTargetFPS(500)
}

@(export)
game_init :: proc() {
    g_mem = new(Game_Memory)

    g_mem^ = Game_Memory {
        
    }

    game_hot_reloaded(g_mem)
}

@(export)
game_shutdown :: proc() {
    free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
    rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
    return g_mem
}

@(export)
game_memory_size :: proc() -> int {
    return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
    g_mem = (^Game_Memory)(mem)
}

@(export)
game_force_reload :: proc() -> bool {
    return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
    return rl.IsKeyPressed(.F6)
}

format_window_title :: proc(title: string) -> string {
    title := title
    
    title = strings.trim_suffix(title, filepath.ext(title))
    
    title, _ = strings.replace_all(title, "_", " ")
    title, _ = strings.replace_all(title, "-", " ")
    
    words := strings.split(title, " ")
    defer delete(words)
    
    for word, i in words {
        if len(word) > 0 {
            words[i] = strings.concatenate({strings.to_upper(word[:1]), strings.to_lower(word[1:])})
        }
    }
    
    return strings.join(words, " ")
}