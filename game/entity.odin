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

    player.animation = animation_make(10, 6, get_texture("scarfy"), false)
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
    animation_draw(player.animation, get_center(player.pos, player.dim), player.facing_dir.x < 0)
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

make_enemy :: proc(enemy_type: Enemy_Type, pos: [2]f32) -> Entity {
    enemy: Entity
    enemy.pos = pos
    switch enemy_type {
        case .Bat: {
            enemy.dim = {40,40}
            enemy.max_move_speed = 80
            enemy.health = 75
            enemy.color = rl.MAROON
            enemy.animation = animation_make(5, 8, get_texture("bat"), true, {2,2})
        }
        case .Zombie: {
            enemy.dim = {40,75}
            enemy.max_move_speed = 100
            enemy.health = 150
            enemy.color = rl.GREEN
            enemy.animation = animation_make(10, 8, get_texture("zombie"), false, {1.25,1.5})
        }
        case .Strong_Bat: {
            enemy.dim = {50,50}
            enemy.max_move_speed = 80
            enemy.health = 130
            enemy.color = rl.MAROON
            enemy.animation = animation_make(5, 8, get_texture("strong_bat"), true, {3,3})
        }
        case .Skeleton: {
            enemy.dim = {40, 75}
            enemy.max_move_speed = 40
            enemy.health = 220
            enemy.color = rl.RAYWHITE
            enemy.animation = animation_make(10, frame_count=13, texture=get_texture("skeleton"))
        }
    }
    return enemy
}

enemy_tick :: proc(enemy: Entity) {

}

enemy_draw :: proc(enemy: Entity) {
    dest_rec := to_rec(enemy.pos, enemy.dim)
    if enemy.animation.texture.id == 0 {
        border := [2]f32{3,3}
        rl.DrawRectangleRec(dest_rec, rl.BLACK)
        rl.DrawRectangleRec(to_rec(enemy.pos + border, enemy.dim - 2 * border), enemy.color)
    }
    else {
        animation_draw(enemy.animation, get_center(enemy.pos, enemy.dim), enemy.velocity.x < 0)
    }
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
