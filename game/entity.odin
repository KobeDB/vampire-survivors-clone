package game

import rl "vendor:raylib"
import sa "core:container/small_array"
import "core:math/linalg"

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

    animation: Animation,
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

    anim: Animation
    anim.frame_elapsed_ticks = 0
    anim.frame_time_ticks = 10
    anim.frame = 0
    anim.frame_count = 6
    anim.texture = get_texture("scarfy")
    anim.frame_width = f32(anim.texture.width) / f32(anim.frame_count)
    player.animation = anim
}

player_tick :: proc(player: ^Player) {
    move_dir: [2]f32
    if rl.IsKeyDown(.D) {
        move_dir.x += 1
        player.facing_dir = {1,0}
    }
    if rl.IsKeyDown(.A) {
        move_dir.x -= 1
        player.facing_dir = {-1,0}
    }
    if rl.IsKeyDown(.S) {
        move_dir.y += 1
    }
    if rl.IsKeyDown(.W) {
        move_dir.y -= 1
    }
    if move_dir != 0 {
        move_dir = linalg.normalize(move_dir)
        animation_tick(&player.animation)
    }
    player.pos += player.move_speed * move_dir * TICK_TIME
}

player_draw :: proc(player: Player) {
    dest_rec := to_rec(player.pos, player.dim)
    animation_draw(player.animation, dest_rec, player.facing_dir.x < 0)
}

Entity :: struct {
    pos: [2]f32,
    dim: [2]f32,
    velocity: [2]f32,
    max_move_speed: f32,
    health: f32,
    damage_zones_prev_tick: sa.Small_Array(20, Pool_Handle(Damage_Zone)),
    color: rl.Color,
    animation: Animation,
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
