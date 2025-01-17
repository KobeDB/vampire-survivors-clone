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
}

PLAYER_START_REQ_XP :: 5

player_init :: proc(player: ^Player) {
    player.pos = [2]f32{10,10}
    player.dim = [2]f32{50,50}
    player.move_speed = f32(100)
    player.facing_dir = [2]f32{1,0}
    player.cur_level = 0
    player.target_level = player.cur_level
    player.req_xp = PLAYER_START_REQ_XP
    player.cur_xp = 0
}

Entity :: struct {
    pos: [2]f32,
    dim: [2]f32,
    velocity: [2]f32,
    max_move_speed: f32,
    health: f32,
    damage_zones_prev_tick: sa.Small_Array(20, Pool_Handle(Damage_Zone))
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
