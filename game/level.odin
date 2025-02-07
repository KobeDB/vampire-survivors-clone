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
    weapons: Pool(Weapon_Union),
    damage_indicators: Pool(Damage_Indicator),
    xp_drops: Pool(XP_Drop),
    wave: Wave,
    camera: rl.Camera2D,
    countdowns: Pool(Countdown),
    emitter: Particle_Emitter,
    emitter_countdown: Pool_Handle(Countdown),
}

MAX_ENEMIES :: 10000
MAX_DAMAGE_ZONES :: 500
MAX_WEAPONS :: 10
MAX_DAMAGE_INDICATORS :: 10000
MAX_XP_DROPS :: 10000
MAX_COUNTDOWNS :: 1000

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

    pool_init(&countdowns, MAX_COUNTDOWNS)


    pool_init(&weapons, MAX_WEAPONS)
    pool_add(&weapons, make_whip(&damage_zones))
    //pool_add(&weapons, make_bibles(&damage_zones))
    //pool_add(&weapons, make_magic_wand(&damage_zones))

    pool_init(&damage_indicators, MAX_DAMAGE_INDICATORS)

    pool_init(&xp_drops, MAX_XP_DROPS)

    wave_init(&wave, level)

    camera.target = {level.player.pos.x + level.player.dim.x/2 , level.player.pos.y + level.player.dim.y/2}
    camera.offset = {screen_dim.x / 2, screen_dim.y / 2}
    camera.zoom = 1

    // test particles
    start_color := [3]f32{1, 0, 1}
    end_color := [3]f32{1, 0, 0}
    particle_emitter_init(&level.emitter, get_texture("bible"), start_color, end_color, BIBLES_MAX_PARTICLES, 90, 1)
    emitter_countdown = add_countdown(level, 30)
}

level_tick :: proc(using level: ^Level) {

    player_movement(&player)

    // Update camera target to follow player
    camera.target = {player.pos.x + player.dim.x/2 , player.pos.y + player.dim.y/2}

    // Tick Countdowns
    // ---------------------
    tick_countdowns(level)
    defer reset_expired_countdowns(level)

    // Update weapons
    // ----------------------
    for wi in 0..<len(weapons.slots) {
        weapon, _ := pool_index_get(weapons, wi) or_continue
        weapon_tick((^Weapon)(weapon), player, &damage_zones, enemies)
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

    // Tick enemy animations
    for i in 0..<len(enemies.slots) {
        e, _ := pool_index_get(enemies, i) or_continue
        animation_tick(&e.animation)
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

            // If enemy is already dead (because of prev damage zones) then don't register collisions anymore
            if e.health <= 0 {
                break
            }

            in_zone := aabb_collision_check(e.pos, e.dim, dz.pos, dz.dim)
            if in_zone {
                zone_handle := pool_get_handle_from_index(&damage_zones, dzi)
                // zone_handle := Pool_Handle(Damage_Zone){dzi, gen, }
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

    // tick test particles
    particle_emitter_tick(&emitter)
    if countdown_expired(pool_get(emitter_countdown)^) {
        num_particles := int(rand.float32_range(0,10))
        for _ in 0..<num_particles {
            emitter_pos := [2]f32{0,0}
            vel := random_unit_vec() * 50
            particle_emitter_emit(&emitter, emitter_pos, vel)
        }
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
        player_draw(player)
        //rl.DrawRectangleRec(to_rec(player.pos, player.dim), rl.MAGENTA)

        //Draw enemies
        for i in 0..<len(enemies.slots) {
            e, _ := pool_index_get(enemies, i) or_continue
            enemy_draw(e^)
        }

        // Draw damage zones
        for i in 0..<len(damage_zones.slots) {
            dz, _ := pool_index_get(damage_zones, i) or_continue
            if !dz.is_active { continue }
            rl.DrawRectangleLinesEx(to_rec(dz.pos,dz.dim), 2, dz.color)
        }

        // Draw weapons
        for i in 0..<len(weapons.slots) {
            weapon, _ := pool_index_get(weapons, i) or_continue
            weapon_draw((^Weapon)(weapon), player)
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

        // Draw test particles
        particle_emitter_draw(emitter)

    rl.EndMode2D()

    // Draw wave number
    rl.DrawText(rl.TextFormat("Wave: %d", wave.wave_number), rl.GetScreenWidth() - 100, 80, 22, rl.GREEN)

    // Draw number of living enemies
    rl.DrawText(rl.TextFormat("Enemies left: %d", pool_size(enemies)), rl.GetScreenWidth() - 200, 100, 22, rl.GREEN)

}

add_countdown :: proc(level: ^Level, interval: int) -> Pool_Handle(Countdown) {
    return pool_add(&level.countdowns, make_countdown(interval))
}

Countdown :: struct {
    remaining_ticks: int,
    interval: int,
}

make_countdown :: proc(interval: int) -> Countdown {
    return {remaining_ticks=interval, interval=interval}
}

countdown_expired :: proc(countdown: Countdown) -> bool {
    return countdown.remaining_ticks <= 0
}

countdown_set_to_expired :: proc(countdown: ^Countdown) {
    countdown.remaining_ticks = 0
}

tick_countdowns :: proc(level: ^Level) {
    for i in 0..<len(level.countdowns.slots) {
        countdown, _ := pool_index_get(level.countdowns, i) or_continue
        countdown.remaining_ticks -= 1
    }
}

reset_expired_countdowns :: proc(level: ^Level) {
    for i in 0..<len(level.countdowns.slots) {
        countdown, _ := pool_index_get(level.countdowns, i) or_continue
        if countdown_expired(countdown^) {
            countdown.remaining_ticks = countdown.interval
        }
    }
}

Wave :: struct {
    wave_number: int,
    next_wave_countdown: Pool_Handle(Countdown),
    next_spawn_countdown: Pool_Handle(Countdown),
}

SPAWN_INTERVAL :: 600
WAVE_INTERVAL :: 1800

WAVE_1_ENEMIES :: [?]Enemy_Type{.Bat, .Zombie}
WAVE_1_DIST :: [?]f32{0.7,0.3}

wave_init :: proc(using wave: ^Wave, level: ^Level) {
    wave_number = 0
    next_wave_countdown = pool_add(&level.countdowns, make_countdown(WAVE_INTERVAL))
    next_spawn_countdown = pool_add(&level.countdowns, make_countdown(int(f32(SPAWN_INTERVAL) * 0.2)) )
}

wave_tick :: proc(using wave: ^Wave, level: ^Level) {
    if countdown_expired(pool_get(next_wave_countdown)^) {
        wave_number += 1
        countdown_set_to_expired(pool_get(next_spawn_countdown))
    }

    if countdown_expired(pool_get(next_spawn_countdown)^) {
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
        // sample entity position
        viewport_pos, viewport_dim := get_viewport(level.player, level.camera)
        spawn_area_thickness := f32(200)
        offset := [2]f32{rand.float32_range(20, spawn_area_thickness), rand.float32_range(20,spawn_area_thickness)}
        spawn_on_sides := true if math.sign(rand.float32_range(-1,1)) <= 0 else false
        spawn_on_first := true if math.sign(rand.float32_range(-1,1)) <= 0 else false

        enemy_pos: [2]f32

        if spawn_on_sides {
            max_y: f32 = level.player.pos.y + viewport_dim.y/2 + spawn_area_thickness
            min_y: f32 = level.player.pos.y - viewport_dim.y/2 - spawn_area_thickness
            enemy_pos.y = rand.float32_range(min_y, max_y)
            if spawn_on_first {
                enemy_pos.x = level.player.pos.x - viewport_dim.x/2 - offset.x
            }
            else {
                enemy_pos.x = level.player.pos.x + viewport_dim.x/2 + offset.x
            }
        }
        else {
            max_x: f32 = level.player.pos.x + viewport_dim.x/2 + spawn_area_thickness
            min_x: f32 = level.player.pos.x - viewport_dim.x/2 - spawn_area_thickness
            enemy_pos.x = rand.float32_range(min_x, max_x)
            if spawn_on_first {
                enemy_pos.y = level.player.pos.y - viewport_dim.y/2 - offset.y
            }
            else {
                enemy_pos.y = level.player.pos.y + viewport_dim.y/2 + offset.y
            }
        }

        enemy_type := Enemy_Type(sample_dist(enemy_dist))
        enemy := make_enemy(enemy_type, enemy_pos)

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

Animation :: struct {
    frame_elapsed_ticks: int,
    frame_time_ticks: int,
    frame: int,
    frame_count: int, // number of frames in the texture
    frame_width: f32, // width of a single frame in pixels
    texture: rl.Texture2D,
    flip_horizontally_by_default: bool, // flag indicating whether sprite should be mirrored by default when drawn
    scaling: [2]f32, // To rescale the sprite when drawing
}

animation_make :: proc(frame_time_ticks: int, frame_count: int, texture: rl.Texture2D, flip_horizontally: bool = false, frame_scaling_factor: [2]f32 = {1,1}) -> Animation {
    anim: Animation
    anim.frame_elapsed_ticks = 0
    anim.frame_time_ticks = frame_time_ticks
    anim.frame = 0
    anim.frame_count = frame_count
    anim.texture = texture
    anim.frame_width = f32(anim.texture.width) / f32(anim.frame_count)
    anim.flip_horizontally_by_default = flip_horizontally
    anim.scaling = frame_scaling_factor
    return anim
}

animation_tick :: proc(using animation: ^Animation) {
    if animation.frame_count == 0 {
        return
    }

    frame_elapsed_ticks += 1
    if frame_elapsed_ticks >= frame_time_ticks {
        frame_elapsed_ticks = 0
        frame = (frame + 1) % frame_count
    }
}

animation_draw :: proc(using animation: Animation, center_pos: [2]f32, flip_horizontal: bool) {
    frame_pos := [2]f32{ f32(frame) * frame_width, 0 }
    frame_dim := [2]f32{ frame_width, f32(texture.height) }
    if flip_horizontal { frame_dim.x = -frame_dim.x }
    if flip_horizontally_by_default { frame_dim.x = -frame_dim.x } // TODO: this kinda cringe?
    frame_rec := to_rec(frame_pos, frame_dim)

    dest_rec_dim := [2]f32{75,75} * scaling
    dest_rec_pos := center_pos - dest_rec_dim/2
    dest_rec := to_rec(dest_rec_pos, dest_rec_dim)

    rl.DrawTexturePro(texture, frame_rec, dest_rec, {}, 0, rl.WHITE)
}