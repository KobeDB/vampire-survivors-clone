package game

import "core:fmt"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math/linalg"
import "core:math/rand"
import sa "core:container/small_array"
import "core:math"

TICK_TIME :: 1.0/60.0

main :: proc() {
    fmt.println("Hello there")

    //SCREEN_DIM :: [2]f32{1270, 720}
    SCREEN_DIM :: [2]f32{1600, 900}

    rl.InitWindow(i32(SCREEN_DIM.x), i32(SCREEN_DIM.y) , "The window")
    rl.InitAudioDevice()

    music := rl.LoadMusicStream("res/sounds/vampire_jam.mp3")
    rl.PlayMusicStream(music)

    rl.SetTargetFPS(1.0/TICK_TIME)

    player: Player
    player_init(&player)

    MAX_ENEMIES :: 10000
    enemies: Pool(Entity)
    pool_init(&enemies, MAX_ENEMIES)

    for i in 0..<MAX_ENEMIES {
        enemy_spread: f32 = MAX_ENEMIES * 1
        pos := [2]f32{rand.float32_range(-enemy_spread,enemy_spread), rand.float32_range(-enemy_spread,enemy_spread)}
        e: Entity
        e.pos = pos
        e.dim = {40,40}
        e.max_move_speed = 50
        e.health = 150
        pool_add(&enemies, e)
    }

    MAX_DAMAGE_ZONES :: 500
    damage_zones: Pool(Damage_Zone)
    pool_init(&damage_zones, MAX_DAMAGE_ZONES)

    MAX_WEAPONS :: 10
    weapons: Pool(Weapon)
    pool_init(&weapons, MAX_WEAPONS)

    pool_add(&weapons, make_whip(&damage_zones))
    pool_add(&weapons, make_bibles(&damage_zones))
    pool_add(&weapons, make_magic_wand(&damage_zones))

    Damage_Indicator :: struct {
        damage: int,
        pos: [2]f32,
        remaining_display_time: int, // in ticks
    }
    MAX_DAMAGE_INDICATORS :: 10000
    DAMAGE_INDICATOR_DISPLAY_TIME :: 50
    damage_indicators: Pool(Damage_Indicator)
    pool_init(&damage_indicators, MAX_DAMAGE_INDICATORS)

    XP_Drop :: struct {
        using entity: Entity,
        xp: int,
    }
    XP_DROP_DIM :: [2]f32{10,15}
    XP_DROP_ACCEL :: 1000
    XP_PICKUP_RANGE :: 200
    MAX_XP_DROPS :: 10000
    xp_drops: Pool(XP_Drop)
    pool_init(&xp_drops, MAX_XP_DROPS)

    Game_State :: enum {
        IN_GAME,
        LEVEL_UP_ENTRY,
        LEVEL_UP,
    }

    game_state := Game_State.IN_GAME

    Level_Up_Screen :: struct {
        pos: [2]f32,
        dim: [2]f32,
    }
    level_up_screen: Level_Up_Screen
    level_up_screen.dim = { 0.8 * f32(rl.GetScreenWidth()), 0.8 * f32(rl.GetScreenHeight())}
    level_up_entry_progress: int
    LEVEL_UP_ENTRY_DURATION :: 30 // also in ticks

    camera: rl.Camera2D
    camera.target = {player.pos.x + player.dim.x/2 , player.pos.y + player.dim.y/2}
    camera.offset = {SCREEN_DIM.x / 2, SCREEN_DIM.y / 2}
    camera.zoom = 1

    ticks: u64 = 0

    for !rl.WindowShouldClose() {

        // Update
        // ---------------
        defer ticks += 1

        if game_state == .LEVEL_UP_ENTRY {
            progress := f32(level_up_entry_progress) / LEVEL_UP_ENTRY_DURATION
            target_pos :: [2]f32{50,50}
            start_pos := target_pos - [2]f32{0, level_up_screen.dim.y }
            level_up_screen.pos = progress * target_pos + (1-progress) * start_pos
            if level_up_entry_progress == LEVEL_UP_ENTRY_DURATION {
                game_state = .LEVEL_UP
            }
            level_up_entry_progress += 1
        }
        else if game_state == .LEVEL_UP {
            if rl.IsKeyDown(.L) {
                player.cur_level += 1
                if player.cur_level < player.target_level {
                    level_up_entry_progress = 0
                    game_state = .LEVEL_UP_ENTRY
                }
                else {
                    game_state = .IN_GAME
                }
            }
        }
        else if game_state == .IN_GAME {

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
            }
            player.pos += player.move_speed * move_dir * TICK_TIME

            // Update camera target to follow player
            camera.target = {player.pos.x + player.dim.x/2 , player.pos.y + player.dim.y/2}

            // Update weapons
            // ----------------------
            for wi in 0..<len(weapons.slots) {
                weapon, _ := pool_index_get(weapons, wi) or_continue
                weapon_tick(weapon, player, &damage_zones)
            }

            // Move enemies
            for i in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, i) or_continue
                to_player := linalg.normalize(get_center(player.pos, player.dim) - get_center(e.pos, e.dim))
                // apply acceleration towards player
                e.velocity += to_player * 200 * TICK_TIME
                if linalg.dot(e.velocity, to_player) > 0 && linalg.length(e.velocity) > e.max_move_speed {
                    e.velocity = linalg.normalize(e.velocity) * e.max_move_speed
                }
                e.pos += e.velocity * TICK_TIME
            }


            // Resolve enemy collisions
            enemy_enemy_collision_zone_pos := get_center(player.pos, player.dim) - camera.offset
            enemy_enemy_collision_zone_dim := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
            collisions_remaining := true
            max_iterations := 2
            iterations := 0
            for collisions_remaining && iterations < max_iterations {
                collisions_remaining = false
                iterations += 1
                for i in 0..<len(enemies.slots) {
                    e0, _ := pool_index_get(enemies, i) or_continue

                    // If enemy is not in view (+ some margin), then don't bother resolving collisions
                    if !aabb_collision_check(e0.pos, e0.dim, enemy_enemy_collision_zone_pos, enemy_enemy_collision_zone_dim) {
                        continue
                    }

                    for j in (i+1)..<len(enemies.slots) {
                        e1, _ := pool_index_get(enemies, j) or_continue

                        // We don't check if e1 is in the collision zone because we already do a (simple)
                        // collision check here anyway and so we wouldn't save any time by skipping!

                        e1_to_e0 := get_center(e0.pos, e0.dim) - get_center(e1.pos, e1.dim)
                        distance := linalg.length(e1_to_e0)

                        // temporarily use the width of an enemy's rectangle as a radius
                        overlap := (e0.dim.x/2 + e1.dim.x/2) - distance
                        if overlap > 0 {
                            // avoid zero division
                            if distance == 0 {
                                distance = 0.01
                            }

                            push_e0 := linalg.normalize(e1_to_e0) * overlap / 2
                            push_e1 := -push_e0
                            e0.pos += push_e0
                            e1.pos += push_e1

                            collisions_remaining = true
                        }
                    }
                }
            }

            // Update damage indicators
            for i in 0..<len(damage_indicators.slots) {
                indicator, _ := pool_index_get(damage_indicators, i) or_continue
                indicator.remaining_display_time -= 1
                if indicator.remaining_display_time <= 0 {
                    pool_index_free(&damage_indicators, i)
                }
            }

            // Damage enemies
            for ei in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, ei) or_continue

                // TODO: use bigger collision zone boundaries than enemy-enemy collsion zone
                if !aabb_collision_check(e.pos, e.dim, enemy_enemy_collision_zone_pos, enemy_enemy_collision_zone_dim) {
                    continue
                }

                damage_zones_cur_tick := e.damage_zones_prev_tick
                damage_zones_cur_tick = {} // reset array
                defer e.damage_zones_prev_tick = damage_zones_cur_tick

                for dzi in 0..<len(damage_zones.slots) {
                    dz, gen := pool_index_get(damage_zones, dzi) or_continue
                    if !dz.is_active { continue }
                    in_zone := aabb_collision_check(e.pos, e.dim, dz.pos, dz.dim)
                    if in_zone {
                        zone_handle := Pool_Handle(Damage_Zone){dzi, gen}
                        sa.append(&damage_zones_cur_tick, zone_handle)
                        was_in_zone_prev_tick := false
                        for dz_prev_tick in sa.slice(&e.damage_zones_prev_tick) {
                            if dz_prev_tick == zone_handle {
                                was_in_zone_prev_tick = true
                                break
                            }
                        }
                        if !was_in_zone_prev_tick {
                            // apply damage
                            e.health -= dz.damage

                            // apply knockback
                            // TODO: should knockback be applied right here?
                            away_from_player := -linalg.normalize(get_center(player.pos, player.dim) - get_center(e.pos, e.dim))
                            e.velocity = away_from_player * 100

                            // create damage indicator
                            pool_add(&damage_indicators, Damage_Indicator{ damage=int(dz.damage), pos=e.pos, remaining_display_time=DAMAGE_INDICATOR_DISPLAY_TIME})

                            // register hit in damage zone
                            dz.enemy_hit_count += 1
                        }
                    }
                }
            }

            // Process enemy deaths
            for ei in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, ei) or_continue
                if e.health <= 0 {
                    // spawn XP drop
                    pool_add(&xp_drops, XP_Drop{xp=1, pos=e.pos})

                    // Free killed enemy
                    pool_index_free(&enemies, ei)
                }
            }

            // Update xp drops
            for i in 0..<len(xp_drops.slots) {
                drop, _ := pool_index_get(xp_drops, i) or_continue
                drop.pos += drop.velocity * TICK_TIME
                // If player touches xp drop, pick it up
                if aabb_collision_check(player.pos, player.dim, drop.pos, XP_DROP_DIM) {
                    player.cur_xp += drop.xp
                    // delete xp drop
                    pool_index_free(&xp_drops, i)
                }
                else {
                    // If player is in proximity of xp drop, make xp drop accelerate towards player
                    player_center := get_center(player.pos, player.dim)
                    drop_center := get_center(drop.pos, drop.dim)
                    if linalg.length(player_center - drop_center) <= XP_PICKUP_RANGE {
                        to_player := linalg.normalize(get_center(player.pos, player.dim) - get_center(drop.pos, drop.dim))
                        drop.velocity += to_player * XP_DROP_ACCEL * TICK_TIME
                    }
                }
            }

            // Level up player based on gained xp
            leveled_up := false
            for player.cur_xp >= player.req_xp {
                player.cur_xp -= player.req_xp
                player.target_level += 1
                leveled_up = true

                // determine next required xp
                if player.target_level < 20 {
                    player.req_xp += 10
                }
                else if player.target_level < 40 {
                    player.req_xp += 13
                }
                else {
                    player.req_xp += 20
                }
            }

            if leveled_up {
                game_state = .LEVEL_UP_ENTRY
                level_up_entry_progress = 0
            }

        }

        // Update music
        // ------------------
        rl.UpdateMusicStream(music)


        // Draw
        // ---------------
        rl.BeginDrawing()

        rl.ClearBackground(rl.GRAY)


        rl.BeginMode2D(camera)

            // Draw grid
            rlgl.PushMatrix();
                    rlgl.Translatef(0, 25*50, 0);
                    rlgl.Rotatef(90, 1, 0, 0);
                    rl.DrawGrid(100, 50);
            rlgl.PopMatrix();

            // Draw unit vectors
            rl.DrawRectangleRec(to_rec({10,0}, {5,5}), rl.RED)
            rl.DrawRectangleRec(to_rec({0,10}, {5,5}), rl.GREEN)

            // Draw player
            rl.DrawRectangleRec(to_rec(player.pos, player.dim), rl.MAGENTA)

            //Draw enemies
            for i in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, i) or_continue
                border := [2]f32{3,3}
                rl.DrawRectangleRec(to_rec(e.pos, e.dim), rl.BLACK)
                rl.DrawRectangleRec(to_rec(e.pos + border, e.dim - 2 * border), rl.MAROON)
            }

            // Draw damage zones
            for i in 0..<len(damage_zones.slots) {
                dz, _ := pool_index_get(damage_zones, i) or_continue
                if !dz.is_active { continue }
                rl.DrawRectangleRec(to_rec(dz.pos,dz.dim), dz.color)
            }

            // // Draw test rectangle
            // {
            // rect_pos := [2]f32{70,70}
            // rect_dim := [2]f32{100,20}
            // overlap := aabb_collision_check(player.pos, player.dim, rect_pos, rect_dim)
            // rect_color := rl.RED if overlap else rl.GREEN
            // rl.DrawRectangleRec(to_rec(rect_pos, rect_dim), rect_color)
            // }

            // Draw XP drops
            for i in 0..<len(xp_drops.slots) {
                drop, _ := pool_index_get(xp_drops, i) or_continue
                border := [2]f32{3,3}
                rl.DrawRectangleRec(to_rec(drop.pos, XP_DROP_DIM), rl.BLACK)
                rl.DrawRectangleRec(to_rec(drop.pos + border, XP_DROP_DIM - 2 * border), rl.SKYBLUE)
            }

            // Draw damage indicators
            for i in 0..<len(damage_indicators.slots) {
                indicator, _ := pool_index_get(damage_indicators, i) or_continue
                rl.DrawText(rl.TextFormat("%d", indicator.damage), i32(indicator.pos.x), i32(indicator.pos.y), 22, rl.BLACK)
                rl.DrawText(rl.TextFormat("%d", indicator.damage), i32(indicator.pos.x), i32(indicator.pos.y), 20, rl.WHITE)
            }

        rl.EndMode2D()

        rl.DrawFPS(0,0)

        // Draw player's XP
        rl.DrawText(rl.TextFormat("Level: %d", player.cur_level), rl.GetScreenWidth() - 100, 20, 22, rl.GREEN)
        rl.DrawText(rl.TextFormat("Target Level: %d", player.target_level), rl.GetScreenWidth() - 200, 50, 22, rl.GREEN)


        if game_state == .LEVEL_UP || game_state == .LEVEL_UP_ENTRY {
            // Draw level up screen
            rl.DrawRectangleRec(to_rec(level_up_screen.pos, level_up_screen.dim), rl.Color{255, 0, 255, 127})
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
