package game

import "core:fmt"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math/linalg"
import "core:math/rand"
import sa "core:container/small_array"
import "core:math"
import "core:reflect"
import "base:runtime"


TICK_TIME :: 1.0/60.0


// All state
// --------------
@(private="file")
level: Level
@(private="file")
level_up_screen: Level_Up_Screen

Game_State :: enum {
        IN_GAME,
        LEVEL_UP,
}

game_state := Game_State.IN_GAME


transition_to_game_state :: proc(new_game_state: Game_State) {
    defer game_state = new_game_state
    #partial switch new_game_state {
        case .LEVEL_UP: {
            level_up_screen.entry_progress = 0

            // Add available weapons to level-up options
            sa.clear(&level_up_screen.options)
            weapon_variants := runtime.type_info_base(type_info_of(Weapon)).variant.(runtime.Type_Info_Union).variants
            for weapon_variant in weapon_variants {
                taken := false
                for wi in 0..<len(level.weapons.slots) {
                    taken_weapon, _ := pool_index_get(level.weapons, wi) or_continue
                    if reflect.union_variant_typeid(taken_weapon^) == weapon_variant.id {
                        taken = true
                        break
                    }
                }
                if !taken {
                    sa.append(&level_up_screen.options, weapon_variant.id)
                }
            }

        }
    }
}

main :: proc() {
    fmt.println("Hello there")

    //SCREEN_DIM :: [2]f32{1270, 720}
    SCREEN_DIM :: [2]f32{1600, 900}

    rl.InitWindow(i32(SCREEN_DIM.x), i32(SCREEN_DIM.y) , "The window")
    rl.InitAudioDevice()

    music := rl.LoadMusicStream("res/sounds/vampire_jam.mp3")
    rl.PlayMusicStream(music)

    rl.SetTargetFPS(1.0/TICK_TIME)

    // Init state
    // -------------------
    level_init(&level)

    level_up_screen.dim = { 0.8 * f32(rl.GetScreenWidth()), 0.8 * f32(rl.GetScreenHeight())}
    // ------------------

    camera: rl.Camera2D
    camera.target = {level.player.pos.x + level.player.dim.x/2 , level.player.pos.y + level.player.dim.y/2}
    camera.offset = {SCREEN_DIM.x / 2, SCREEN_DIM.y / 2}
    camera.zoom = 1

    ticks: u64 = 0

    for !rl.WindowShouldClose() {

        // Update
        // ---------------
        defer ticks += 1

        if game_state == .IN_GAME {
            level_tick(&level, &camera)
        }
        else if game_state == .LEVEL_UP {
            level_up_screen_tick(&level_up_screen, &level)
        }

        // Update music
        // ------------------
        rl.UpdateMusicStream(music)

        // Draw
        // ---------------
        rl.BeginDrawing()

        rl.ClearBackground(rl.GRAY)

        if game_state == .IN_GAME {
            level_draw(level, camera)
        }
        else if game_state == .LEVEL_UP {
            level_draw(level, camera)
            level_up_screen_draw(level_up_screen, level)
        }

        rl.DrawFPS(0,0)

        // Draw player's XP
        rl.DrawText(rl.TextFormat("Level: %d", level.player.cur_level), rl.GetScreenWidth() - 100, 20, 22, rl.GREEN)
        rl.DrawText(rl.TextFormat("Target Level: %d", level.player.target_level), rl.GetScreenWidth() - 200, 50, 22, rl.GREEN)

        rl.EndDrawing()
    }
}



to_rec :: proc(pos: [2]f32, dim: [2]f32) -> rl.Rectangle {
    return {pos.x, pos.y, dim.x, dim.y}
}

get_center :: proc(corner: [2]f32, dim: [2]f32) -> [2]f32 {
    return corner + dim/2
}

random_unit_vec :: proc() -> [2]f32 {
    for {
        v := [2]f32{rand.float32_range(-1,1), rand.float32_range(-1,1)}
        v_len := linalg.length(v)
        if v_len <= 1 && 0.0001 < v_len {
            return linalg.normalize(v)
        }
    }
}

aabb_collision_check :: proc(pos0: [2]f32, dim0: [2]f32, pos1: [2]f32, dim1: [2]f32) -> bool {
    return ((pos0.x <= pos1.x+dim1.x && pos0.x >= pos1.x) \
            || (pos1.x <= pos0.x+dim0.x && pos1.x >= pos0.x)) \
           && \
           ((pos0.y <= pos1.y+dim1.y && pos0.y >= pos1.y) \
            || (pos1.y <= pos0.y+dim0.y && pos1.y >= pos0.y))
}
