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

Level_Up_Screen :: struct {
    pos: [2]f32,
    dim: [2]f32,
    entry_progress: int, // progress of entry "animation" of the screen
    options: sa.Small_Array(3, typeid), // Store Weapon union variant typeids
    selected_option: int,
}
LEVEL_UP_ENTRY_DURATION :: 30 // also in ticks

Game_State :: enum {
        IN_GAME,
        LEVEL_UP,
}

transition_to_game_state :: proc(game_state: ^Game_State, new_game_state: Game_State) {
    defer game_state^ = new_game_state
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

    game_state := Game_State.IN_GAME

    camera: rl.Camera2D
    camera.target = {level.player.pos.x + level.player.dim.x/2 , level.player.pos.y + level.player.dim.y/2}
    camera.offset = {SCREEN_DIM.x / 2, SCREEN_DIM.y / 2}
    camera.zoom = 1

    ticks: u64 = 0

    for !rl.WindowShouldClose() {

        // Update
        // ---------------
        defer ticks += 1

        if game_state == .LEVEL_UP {
            // Play screen animation
            if level_up_screen.entry_progress < LEVEL_UP_ENTRY_DURATION {
                progress := f32(level_up_screen.entry_progress) / LEVEL_UP_ENTRY_DURATION
                target_pos :: [2]f32{50,50}
                start_pos := target_pos - [2]f32{0, level_up_screen.dim.y }
                level_up_screen.pos = progress * target_pos + (1-progress) * start_pos
                level_up_screen.entry_progress += 1
            }

            if rl.IsKeyPressed(.W) {
                level_up_screen.selected_option = max(level_up_screen.selected_option-1, 0)
            }
            if rl.IsKeyPressed(.S) {
                level_up_screen.selected_option = min(level_up_screen.selected_option+1, sa.len(level_up_screen.options)-1)
            }

            if rl.IsKeyPressed(.SPACE) {
                if sa.len(level_up_screen.options) > 0 {
                    // Add selected weapon to weapons
                    selected_weapon := sa.get(level_up_screen.options, level_up_screen.selected_option)
                    switch selected_weapon {
                        case typeid_of(Whip):     { pool_add(&level.weapons, make_whip(&level.damage_zones)) }
                        case typeid_of(Bibles):   { pool_add(&level.weapons, make_bibles(&level.damage_zones)) }
                        case typeid_of(Magic_Wand):   { pool_add(&level.weapons, make_magic_wand(&level.damage_zones)) }
                    }
                }

                level.player.cur_level += 1
                if level.player.cur_level < level.player.target_level {
                    transition_to_game_state(&game_state, .LEVEL_UP)
                }
                else {
                    transition_to_game_state(&game_state, .IN_GAME)
                }
            }

            if rl.IsKeyPressed(.L) {
                level.player.cur_level += 1
                if level.player.cur_level < level.player.target_level {
                    transition_to_game_state(&game_state, .LEVEL_UP)
                }
                else {
                    transition_to_game_state(&game_state, .IN_GAME)
                }
            }
        }
        else if game_state == .IN_GAME {
            level_tick(&level, &game_state, &camera)
        }

        // Update music
        // ------------------
        rl.UpdateMusicStream(music)


        // Draw
        // ---------------
        rl.BeginDrawing()

        rl.ClearBackground(rl.GRAY)

        level_draw(level, camera)

        rl.DrawFPS(0,0)

        // Draw player's XP
        rl.DrawText(rl.TextFormat("Level: %d", level.player.cur_level), rl.GetScreenWidth() - 100, 20, 22, rl.GREEN)
        rl.DrawText(rl.TextFormat("Target Level: %d", level.player.target_level), rl.GetScreenWidth() - 200, 50, 22, rl.GREEN)

        if game_state == .LEVEL_UP {
            // Draw level up screen
            rl.DrawRectangleRec(to_rec(level_up_screen.pos, level_up_screen.dim), rl.Color{255, 0, 255, 127})
            rl.DrawText(rl.TextFormat("LEVEL UP!!!: %d", level.player.target_level), i32(level_up_screen.pos.x), i32(level_up_screen.pos.y), 50, rl.GREEN)
            // Draw weapon option buttons
            num_buttons := sa.len(level_up_screen.options)
            button_dim := [2]f32{level_up_screen.dim.x, (level_up_screen.dim.y / f32(num_buttons))}
            for button_i in 0..<num_buttons {
                button_pos := [2]f32{ level_up_screen.pos.x, level_up_screen.pos.y + button_dim.y * f32(button_i) }
                selection_tint: u8 = 200 if button_i == level_up_screen.selected_option else 127
                rl.DrawRectangleRec(to_rec(button_pos, button_dim), rl.Color{160, 100, 150, selection_tint})
                button_text := fmt.caprint("Option: ", sa.get(level_up_screen.options, button_i))
                defer delete(button_text)
                rl.DrawText(button_text, i32(button_pos.x), i32(button_pos.y), 50, rl.GREEN)
            }
        }

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
