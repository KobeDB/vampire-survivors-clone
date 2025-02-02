package game

import rl "vendor:raylib"
import sa "core:container/small_array"


Player :: struct {
    pos: [2]f32,
    dim: [2]f32,
    move_speed: f32,
    facing_dir: [2]f32,

    // Since it is possible that the player may level up multiple times in a single tick,
    // we use these cur_level and target_level variables (target_level is the actual up-to-date player level).
    // (target_level - cur_level) is the amount of level-up screens that the player still needs to select.
    // If target_level == cur_level then the player can continue playing.
    cur_level: int,
    target_level: int,

    req_xp: int, // required xp to level up to next level
    cur_xp: int,

    frame_elapsed_ticks: int,
    frame_time_ticks: int,
    frame: int,
}

PLAYER_START_REQ_XP :: 5

player_init :: proc(player: ^Player) {
    player.pos = [2]f32{10,10}
    player.dim = [2]f32{75,75}
    player.move_speed = f32(170)
    player.facing_dir = [2]f32{1,0}
    player.cur_level = 0
    player.target_level = player.cur_level
    player.req_xp = PLAYER_START_REQ_XP
    player.cur_xp = 0
    player.frame_elapsed_ticks = 0
    player.frame_time_ticks = 10
    player.frame = 0
}

player_draw :: proc(player: Player) {
    scarfy_tex := get_texture("scarfy")
    dest_rec := to_rec(player.pos, player.dim)
    frame_pos: [2]f32
    frame_pos.x = f32(player.frame) * f32(scarfy_tex.width)/6
    frame_pos.y = 0
    frame_dim := [2]f32{f32(scarfy_tex.width)/6,f32(scarfy_tex.height)}
    if player.facing_dir.x < 0 {
        frame_dim.x *= -1
    }
    frame_rec := to_rec(frame_pos, frame_dim)
    rl.DrawTexturePro(scarfy_tex, frame_rec, dest_rec, {}, 0, rl.WHITE)
}

Entity :: struct {
    pos: [2]f32,
    dim: [2]f32,
    velocity: [2]f32,
    max_move_speed: f32,
    health: f32,
    damage_zones_prev_tick: sa.Small_Array(20, Pool_Handle(Damage_Zone)),
    color: rl.Color,
}

Enemy_Type :: enum {
    Bat=0,
    Zombie,
    Strong_Bat,
    Skeleton,
}

Damage_Zone :: struct {
    pos: [2]f32,
    dim: [2]f32,
    damage: f32,
    is_active: bool,
    color: rl.Color,
    enemy_hit_count: int,
}

Damage_Indicator :: struct {
        damage: int,
        pos: [2]f32,
        remaining_display_time: int, // in ticks
}
DAMAGE_INDICATOR_DISPLAY_TIME :: 50

XP_Drop :: struct {
        using entity: Entity,
        xp: int,
        accelerate_towards_player: bool,
}
XP_DROP_DIM :: [2]f32{10,15}
XP_DROP_ACCEL :: 1000
XP_PICKUP_RANGE :: 200
