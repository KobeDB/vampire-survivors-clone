package game

import "core:fmt"
import sa "core:container/small_array"

import rl "vendor:raylib"


Level_Up_Screen :: struct {
    pos: [2]f32,
    dim: [2]f32,
    entry_progress: int, // progress of entry "animation" of the screen
    options: sa.Small_Array(3, typeid), // Store Weapon union variant typeids
    selected_option: int,
}
LEVEL_UP_ENTRY_DURATION :: 30 // also in ticks

level_up_screen_tick :: proc(level_up_screen: ^Level_Up_Screen, level: ^Level) {
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
            transition_to_game_state(.LEVEL_UP)
        }
        else {
            transition_to_game_state(.IN_GAME)
        }
    }

    if rl.IsKeyPressed(.L) {
        level.player.cur_level += 1
        if level.player.cur_level < level.player.target_level {
            transition_to_game_state(.LEVEL_UP)
        }
        else {
            transition_to_game_state(.IN_GAME)
        }
    }
}

level_up_screen_draw :: proc(level_up_screen: Level_Up_Screen, level: Level) {
    rl.DrawRectangleRec(to_rec(level_up_screen.pos, level_up_screen.dim), rl.Color{100, 100, 255, 127})
    //rl.DrawText(rl.TextFormat("LEVEL UP!!!: %d", level.player.target_level), i32(level_up_screen.pos.x), i32(level_up_screen.pos.y), 50, rl.GREEN)

    // Draw weapon option buttons
    num_buttons := sa.len(level_up_screen.options)
    if num_buttons == 0 {
        rl.DrawText(rl.TextFormat("You leveled up to level: %d\n\n\n No more things to upgrade tho...", level.player.target_level), i32(level_up_screen.pos.x), i32(level_up_screen.pos.y), 50, rl.GREEN)
    }
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
