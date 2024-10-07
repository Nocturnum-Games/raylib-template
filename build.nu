let script_dir = ($env.CURRENT_FILE | path dirname)

let name = ($script_dir | path basename)
let vet = [-strict-style -vet -vet-using-param -vet-style -vet-semicolon -disallow-do -warnings-as-errors]
let args = [-show-timings -use-separate-modules -debug -o:none -define:ENABLE_TRACKING_ALLOCATOR=true -define:STANDALONE=false]

if ("bin" | path exists) == false {
  mkdir "bin"
}

let dyn_ext = if $nu.os-info.name == "windows" {
  "dll"
} else if $nu.os-info.name == "macos" {
  "dylib"
} else {
  "so"
}

let odin_root = odin root
let rl_path = $"($odin_root)/vendor/raylib/"

try {
  if $nu.os-info.name == "macos" {
    cp $"($rl_path)/macos-arm64/libraylib.500.dylib" "bin/libraylib.500.dylib"
    cp $"($rl_path)/macos-arm64/libraylib.500.dylib" "bin/libraygui.dylib"
  } else if $nu.os-info.name == "windows" { 
    cp $"($rl_path)/macos-arm64/libraylib.500.dylib" "bin/raylib.dll"
    cp $"($rl_path)/macos-arm64/libraylib.500.dylib" "bin/raygui.dll"
  }
}

# Build the game library
odin build src/game ...$args ...$vet -build-mode:shared -out:$"bin/game.($dyn_ext)" -define:RAYLIB_SHARED=true 

# Build the main executable if it doesn't exist
let exec_name = if $nu.os-info.name == "windows" {
  $"($name).exe"
} else {
  $name
}

if (ps | where name == $exec_name | is-empty) {
  odin build src/main ...$args ...$vet -out:$"bin/($exec_name)" -define:ENABLE_HOT_RELOAD=true
  safe_remove $"bin/game_*.($dyn_ext)"
}

def safe_remove [pattern: string] {
  try {
    if not (glob $pattern | is-empty) {
      rm $pattern
    }
  }
}
