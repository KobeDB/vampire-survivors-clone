package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math/linalg"
import sa "core:container/small_array"
import "core:math/rand"
import "core:math"

Level :: struct {
    player: Player,
    enemies: Pool(Entity),
    damage_zones: Pool(Damage_Zone),
    weapons: Pool(Weapon),
    damage_indicators: Pool(Damage_Indicator),
    xp_drops: Pool(XP_Drop),
    wave: Wave,
    camera: rl.Camera2D,
}

MAX_ENEMIES :: 10000
MAX_DAMAGE_ZONES :: 500
MAX_WEAPONS :: 10
MAX_DAMAGE_INDICATORS :: 10000
MAX_XP_DROPS :: 10000


level_init :: proc(using level: ^Level, screen_dim: [2]f32) {
    player_init(&player)

    pool_init(&enemies, MAX_ENEMIES)
    // for i in 0..<MAX_ENEMIES {
    //     enemy_spread: f32 = MAX_ENEMIES * 1
    //     pos := [2]f32{rand.float32_range(-enemy_spread,enemy_spread), rand.float32_range(-enemy_spread,enemy_spread)}
    //     e: Entity
    //     e.pos = pos
    //     e.dim = {40,40}
    //     e.max_move_speed = 50
    //     e.health = 150
    //     e.color = rl.MAROON
    //     pool_add(&enemies, e)
    // }

    pool_init(&damage_zones, MAX_DAMAGE_ZONES)

    pool_init(&weapons, MAX_WEAPONS)
    pool_add(&weapons, make_whip(&damage_zones))
    //pool_add(&weapons, make_bibles(&damage_zones))
    //pool_add(&weapons, make_magic_wand(&damage_zones))

    pool_init(&damage_indicators, MAX_DAMAGE_INDICATORS)

    pool_init(&xp_drops, MAX_XP_DROPS)

    wave_init(&wave)

    camera.target = {level.player.pos.x + level.player.dim.x/2 , level.player.pos.y + level.player.dim.y/2}
    camera.offset = {screen_dim.x / 2, screen_dim.y / 2}
    camera.zoom = 1
}

level_tick :: proc(using level: ^Level) {
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

    // Potentially spawn enemies
    wave_tick(&wave, level)

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
            continue
        }
        else {
            // If player is in proximity of xp drop, make xp drop permanently accelerate towards player
            player_center := get_center(player.pos, player.dim)
            drop_center := get_center(drop.pos, drop.dim)
            if linalg.length(player_center - drop_center) <= XP_PICKUP_RANGE {
                drop.accelerate_towards_player = true
            }

            if drop.accelerate_towards_player {
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
        transition_to_game_state(.LEVEL_UP)
    }
}

level_draw :: proc(using level: Level) {
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
            rl.DrawRectangleRec(to_rec(e.pos + border, e.dim - 2 * border), e.color)
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

    // Draw wave number
    rl.DrawText(rl.TextFormat("Wave: %d", wave.wave_number), rl.GetScreenWidth() - 100, 80, 22, rl.GREEN)

    // Draw number of living enemies
    rl.DrawText(rl.TextFormat("Enemies left: %d", pool_size(enemies)), rl.GetScreenWidth() - 200, 100, 22, rl.GREEN)

}

Wave :: struct {
    wave_number: int,
    ticks_until_next_wave: int,
    ticks_until_next_spawn: int,
}

SPAWN_INTERVAL :: 600
WAVE_INTERVAL :: 1800

WAVE_1_ENEMIES :: [?]Enemy_Type{.Bat, .Zombie}
WAVE_1_DIST :: [?]f32{0.7,0.3}

wave_init :: proc(using wave: ^Wave) {
    wave_number = 0
    ticks_until_next_wave = WAVE_INTERVAL
    ticks_until_next_spawn = int(f32(SPAWN_INTERVAL) * 0.2)
}

wave_tick :: proc(using wave: ^Wave, level: ^Level) {
    ticks_until_next_wave -= 1
    ticks_until_next_spawn -= 1
    if ticks_until_next_wave <= 0 {
        wave_number += 1
        ticks_until_next_wave = WAVE_INTERVAL
        ticks_until_next_spawn = 0
    }

    if ticks_until_next_spawn <= 0 {
        ticks_until_next_spawn = SPAWN_INTERVAL
        // spawn enemies
        spawn_enemies(level)
    }
}

spawn_enemies :: proc(level: ^Level) {
    wave_enemy_limit: int
    enemy_dist: []f32
    switch level.wave.wave_number {
        case 0: {
            enemy_dist = make([]f32, 1, context.temp_allocator)
            enemy_dist[0] = 1
            wave_enemy_limit = 10
        }
        case 1: {
            enemy_dist = make([]f32, 2, context.temp_allocator)
            enemy_dist[0] = 0.7
            enemy_dist[1] = 0.3
            wave_enemy_limit = 20
        }
        case 2: {
            enemy_dist = make([]f32, 3, context.temp_allocator)
            enemy_dist[0] = 0.4
            enemy_dist[1] = 0.3
            enemy_dist[2] = 0.3
            wave_enemy_limit = 20
        }
        case 3: case: {
            enemy_dist = make([]f32, 4, context.temp_allocator)
            enemy_dist[0] = 0.0
            enemy_dist[1] = 0.0
            enemy_dist[2] = 0.1
            enemy_dist[3] = 0.9
            wave_enemy_limit = 40
        }

    }

    enemy_deficit := wave_enemy_limit - pool_size(level.enemies)
    for _ in 0..<enemy_deficit {
        enemy: Entity

        // sample entity position
        viewport_pos, viewport_dim := get_viewport(level.player, level.camera)
        spawn_area_thickness := f32(200)
        offset := [2]f32{rand.float32_range(20, spawn_area_thickness), rand.float32_range(20,spawn_area_thickness)}
        spawn_on_sides := true if math.sign(rand.float32_range(-1,1)) <= 0 else false
        spawn_on_first := true if math.sign(rand.float32_range(-1,1)) <= 0 else false

        if spawn_on_sides {
            max_y: f32 = level.player.pos.y + viewport_dim.y/2 + spawn_area_thickness
            min_y: f32 = level.player.pos.y - viewport_dim.y/2 - spawn_area_thickness
            enemy.pos.y = rand.float32_range(min_y, max_y)
            if spawn_on_first {
                enemy.pos.x = level.player.pos.x - viewport_dim.x/2 - offset.x
            }
            else {
                enemy.pos.x = level.player.pos.x + viewport_dim.x/2 + offset.x
            }
        }
        else {
            max_x: f32 = level.player.pos.x + viewport_dim.x/2 + spawn_area_thickness
            min_x: f32 = level.player.pos.x - viewport_dim.x/2 - spawn_area_thickness
            enemy.pos.x = rand.float32_range(min_x, max_x)
            if spawn_on_first {
                enemy.pos.y = level.player.pos.y - viewport_dim.y/2 - offset.y
            }
            else {
                enemy.pos.y = level.player.pos.y + viewport_dim.y/2 + offset.y
            }
        }

        // TODO: sample enemy type from a non-uniform distribution
        enemy_type := Enemy_Type(sample_dist(enemy_dist))
        switch enemy_type {
            case .Bat: {
                enemy.dim = {40,40}
                enemy.max_move_speed = 80
                enemy.health = 75
                enemy.color = rl.MAROON
            }
            case .Zombie: {
                enemy.dim = {40,75}
                enemy.max_move_speed = 50
                enemy.health = 150
                enemy.color = rl.GREEN
            }
            case .Strong_Bat: {
                enemy.dim = {50,50}
                enemy.max_move_speed = 80
                enemy.health = 130
                enemy.color = rl.MAROON
            }
            case .Skeleton: {
                enemy.dim = {40, 75}
                enemy.max_move_speed = 40
                enemy.health = 220
                enemy.color = rl.RAYWHITE
            }
        }

        pool_add(&level.enemies, enemy)
    }
}

sample_dist :: proc(distribution: []f32) -> int {
    r := rand.float32()
    cur := f32(0)
    for i in 0..<len(distribution) {
        next := cur + distribution[i]
        if r <= next {
            return i
        }
        cur = next
    }
    // shouldn't get here I think ?
    return len(distribution)-1
}

get_viewport :: proc(player: Player, camera: rl.Camera2D) -> (pos: [2]f32, dim: [2]f32) {
    return get_center(player.pos, player.dim) - camera.offset, {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
}