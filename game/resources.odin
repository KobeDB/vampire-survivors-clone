package game

import rl "vendor:raylib"
import "core:fmt"

load_resources :: proc() {
    load_textures()
}

textures: map[string]rl.Texture2D

load_textures :: proc() {
    load_texture :: proc(path: string, name: string) {
        path_cstr := fmt.caprint(path, allocator=context.temp_allocator)
        tex := rl.LoadTexture(path_cstr)
        if tex.id == 0 {
            err_str := fmt.aprint("Couldn't load texture:", path, allocator=context.temp_allocator)
            panic(err_str)
        }
        textures[name] = tex
    }

    load_texture("res/textures/scarfy.png", "scarfy")
    load_texture("res/textures/skeleton.png", "skeleton")
    load_texture("res/textures/bat.png", "bat")
    load_texture("res/textures/strong_bat.png", "strong_bat")
}

get_texture :: proc(name: string) -> rl.Texture2D {
    // TODO: log error if name not in textures
    return textures[name]
}