let script_dir = ($env.CURRENT_FILE | path dirname)
let name = ($script_dir | path basename)

# Configurable options
let config = {
    enable_tracking_allocator: true,
    enable_hot_reload:         true,
    standalone:                false,
    raylib_shared:             true,
}

# Create define strings based on config
let defines = [
    (if $config.enable_tracking_allocator { "-define:ENABLE_TRACKING_ALLOCATOR=true" }),
    (if $config.enable_hot_reload         { "-define:ENABLE_HOT_RELOAD=true" }),
    (if $config.standalone                { "-define:STANDALONE=true" }),
] | compact

let vet = [-strict-style -vet -vet-using-param -vet-style -vet-semicolon -disallow-do -warnings-as-errors]
let args = [-show-timings -use-separate-modules -debug -o:none ...$defines]

# Ensure the bin directory exists
if ("bin" | path exists) == false { mkdir "bin" }

# Determine dynamic library extension based on OS
let dyn_ext = if $nu.os-info.name == "windows" { "dll" } else if $nu.os-info.name == "macos" { "dylib" } else { "so" }

# Set paths for raylib libraries
let odin_root = odin root
let rl_path = $"($odin_root)/vendor/raylib/"
let lib_source = if $nu.os-info.name == "macos" {
    $"($rl_path)/macos-arm64/libraylib.500.dylib"
} else {
    $"($rl_path)/macos-arm64/libraylib.500.dylib"
}

# Copy raylib libraries to bin
try {
    if $nu.os-info.name == "macos" {
        cp $lib_source "bin/libraylib.500.dylib"
        cp $lib_source "bin/libraygui.dylib"
    } else if $nu.os-info.name == "windows" { 
        cp $lib_source "bin/raylib.dll"
        cp $lib_source "bin/raygui.dll"
    }
}

# Build the game library
let raylib_shared = if $config.raylib_shared { "-define:RAYLIB_SHARED=true" }
odin build src/game ...$args ...$vet -build-mode:shared -out:$"bin/game.($dyn_ext)" $raylib_shared

# Build the main executable if it doesn't exist
let exec_name = if $nu.os-info.name == "windows" { $"($name).exe" } else { $name }

if (ps | where name == $exec_name | is-empty) {
    odin build src/main ...$args ...$vet -out:$"bin/($exec_name)"
    glob $"bin/game_*.($dyn_ext)" | each { |it| rm $it }
}