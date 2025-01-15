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

    SCREEN_DIM :: [2]f32{1270, 720}

    rl.InitWindow(i32(SCREEN_DIM.x), i32(SCREEN_DIM.y) , "The window")
    rl.InitAudioDevice()

    music := rl.LoadMusicStream("res/sounds/vampire_jam.mp3")
    rl.PlayMusicStream(music)

    rl.SetTargetFPS(1.0/TICK_TIME)

    player: Player
    player.pos = [2]f32{10,10}
    player.dim = [2]f32{50,50}
    player.move_speed = f32(100)
    player.facing_dir = [2]f32{1,0}

    MAX_ENEMIES :: 1000
    enemies: Pool(Entity)
    pool_init(&enemies, MAX_ENEMIES)

    for i in 0..<MAX_ENEMIES {
        enemy_spread: f32 = MAX_ENEMIES * 10
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

    camera: rl.Camera2D
    camera.target = {player.pos.x + player.dim.x/2 , player.pos.y + player.dim.y/2}
    camera.offset = {SCREEN_DIM.x / 2, SCREEN_DIM.y / 2}
    camera.zoom = 1

    ticks: u64 = 0

    for !rl.WindowShouldClose() {

        // Update
        // ---------------
        defer ticks += 1

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
        collisions_remaining := true
        max_iterations := 2
        iterations := 0
        for collisions_remaining && iterations < max_iterations {
            collisions_remaining = false
            iterations += 1
            for i in 0..<len(enemies.slots) {
                e0, _ := pool_index_get(enemies, i) or_continue
                for j in (i+1)..<len(enemies.slots) {
                    e1, _ := pool_index_get(enemies, j) or_continue

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

        // Free killed enemies
        for ei in 0..<len(enemies.slots) {
            e, _ := pool_index_get(enemies, ei) or_continue
            if e.health <= 0 {
                pool_index_free(&enemies, ei)
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

            // Draw damage zones
            for i in 0..<len(damage_zones.slots) {
                dz, _ := pool_index_get(damage_zones, i) or_continue
                if !dz.is_active { continue }
                rl.DrawRectangleRec(to_rec(dz.pos,dz.dim), dz.color)
            }

            // Draw test rectangle
            rect_pos := [2]f32{70,70}
            rect_dim := [2]f32{100,20}
            overlap := aabb_collision_check(player.pos, player.dim, rect_pos, rect_dim)
            rect_color := rl.RED if overlap else rl.GREEN
            rl.DrawRectangleRec(to_rec(rect_pos, rect_dim), rect_color)

            //Draw enemies
            for i in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, i) or_continue
                rl.DrawRectangleRec(to_rec(e.pos, e.dim+{2,2}), rl.BLACK)
                rl.DrawRectangleRec(to_rec(e.pos, e.dim), rl.MAROON)
            }

            // Draw damage indicators
            for i in 0..<len(damage_indicators.slots) {
                indicator, _ := pool_index_get(damage_indicators, i) or_continue
                rl.DrawText(rl.TextFormat("%d", indicator.damage), i32(indicator.pos.x), i32(indicator.pos.y), 22, rl.BLACK)
                rl.DrawText(rl.TextFormat("%d", indicator.damage), i32(indicator.pos.x), i32(indicator.pos.y), 20, rl.WHITE)
            }

        rl.EndMode2D()

        rl.DrawFPS(0,0)

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
}

Entity :: struct {
    pos: [2]f32,
    dim: [2]f32,
    velocity: [2]f32,
    max_move_speed: f32,
    health: f32,
    damage_zones_prev_tick: sa.Small_Array(20, Pool_Handle(Damage_Zone))
}


Weapon :: union {
    Whip,
    Bibles,
    Magic_Wand,
}

weapon_tick :: proc(weapon: ^Weapon, player: Player, damage_zones: ^Pool(Damage_Zone)) {
    switch &w in weapon {

        case Whip: {
            w.remaining_ticks -= 1
            if w.remaining_ticks <= 0 {
                dz := pool_get(damage_zones^, w.dz)
                if w.is_cooling_down {
                    // was cooling down, going to attack
                    w.remaining_ticks = WHIP_LIFETIME
                    dz.is_active = true
                    dz.pos = player.pos + player.dim/2
                    if player.facing_dir.x < 0 {
                        dz.pos.x -= dz.dim.x
                    }
                }
                else {
                    // was attacking, going to cooldown
                    w.remaining_ticks = WHIP_COOLDOWN
                    dz.is_active = false
                }
                w.is_cooling_down = !w.is_cooling_down // flip state
            }
        }

        case Bibles: {
            w.remaining_ticks -= 1
            if w.remaining_ticks <= 0 {
                for i in 0..<len(w.bibles) {
                    bible_handle := w.bibles[i]
                    bible := pool_get(damage_zones^, bible_handle)
                    bible.is_active = w.is_cooling_down
                }
                w.remaining_ticks = BIBLES_LIFETIME if w.is_cooling_down else BIBLES_COOLDOWN
                w.is_cooling_down = !w.is_cooling_down // flip state
            }

            for i in 0..<len(w.bibles) {
                bible_handle := w.bibles[i]
                bible := pool_get(damage_zones^, bible_handle)
                bible.pos = calc_bible_center_pos(i, player.pos, len(w.bibles), w.remaining_ticks)
            }
        }

        case Magic_Wand: {
            // tick the projectiles
            for pi in 0..<len(w.projectiles.slots) {
                projectile, _ := pool_index_get(w.projectiles, pi) or_continue
                dz := pool_get(damage_zones^, projectile.dz)
                projectile.lifetime -= 1
                // free expired projectiles (lifetime expired or projectile has hit its max amount of enemies)
                if projectile.lifetime <= 0 || dz.enemy_hit_count >= projectile.health {
                    // first free the projectile's Damage_Zone
                    pool_free(damage_zones, projectile.dz)
                    // free the projectile itself
                    pool_index_free(&w.projectiles, pi)
                }
                else {
                    // Update projectile's movement
                    dz.pos += projectile.velocity * TICK_TIME
                }
            }

            w.remaining_ticks -= 1
            if w.remaining_ticks <= 0 {
                for i in 0..<w.num_projectiles_to_fire {
                    dz: Damage_Zone
                    dz.pos = player.pos
                    dz.dim = {20,20}
                    dz.damage = MAGIC_WAND_DAMAGE
                    dz.color = rl.SKYBLUE
                    dz.is_active = true
                    dz_handle := pool_add(damage_zones, dz)

                    projectile: Magic_Wand_Projectile
                    projectile.dz = dz_handle
                    projectile.lifetime = MAGIC_WAND_PROJECTILE_LIFETIME
                    projectile.health = 1
                    // TODO: Shoot at nearest enemy instead of random direction
                    projectile.velocity = random_unit_vec() * MAGIC_WAND_PROJECTILE_SPEED

                    pool_add(&w.projectiles, projectile)
                }
                w.remaining_ticks = MAGIC_WAND_COOLDOWN
            }

        }
    }
}

Whip :: struct {
    dz: Pool_Handle(Damage_Zone),
    remaining_ticks: int,
    is_cooling_down: bool, // if false => executing attack
}

WHIP_COOLDOWN :: 100
WHIP_LIFETIME :: 1

make_whip :: proc(damage_zones: ^Pool(Damage_Zone)) -> Whip {
    dz: Damage_Zone
    dz.dim = {200,100}
    dz.damage = 50
    dz.color = rl.PINK
    dz.is_active = false
    dz_handle := pool_add(damage_zones, dz)
    return {dz_handle, WHIP_COOLDOWN, true}
}

Bibles :: struct {
    bibles: [3]Pool_Handle(Damage_Zone),
    remaining_ticks: int,
    is_cooling_down: bool, // if false => executing attack
}

BIBLES_LIFETIME :: 500
BIBLES_COOLDOWN :: 200
BIBLES_REVOLUTIONS :: 3
BIBLES_RADIUS :: 200
BIBLES_DAMAGE :: 20

make_bibles :: proc(damage_zones: ^Pool(Damage_Zone)) -> Bibles {
    bibles: [3]Pool_Handle(Damage_Zone)
    for i in 0..<len(bibles) {
        bible: Damage_Zone
        bible.dim = {50,75}
        bible.damage = BIBLES_DAMAGE
        bible.color = rl.BLUE
        bible.is_active = false
        bible_handle := pool_add(damage_zones, bible)
        bibles[i] = bible_handle
    }
    return {bibles, BIBLES_COOLDOWN, true}
}

calc_bible_center_pos :: proc(bible: int, orbit_center: [2]f32, num_bibles: int, remaining_lifetime: int) -> [2]f32 {
    angle_between_bibles := 2*math.PI/f32(num_bibles)
    animation_progress := f32(BIBLES_LIFETIME-remaining_lifetime) / f32(BIBLES_LIFETIME)
    angle_offset := (BIBLES_REVOLUTIONS * 2*math.PI) * animation_progress
    bible_angle :f32= angle_between_bibles * f32(bible) + angle_offset
    bible_center_on_unit_circle := [2]f32{math.cos(bible_angle), math.sin(bible_angle)}
    bible_center := bible_center_on_unit_circle * BIBLES_RADIUS + orbit_center
    return bible_center
}

Magic_Wand :: struct {
    projectiles: Pool(Magic_Wand_Projectile),
    remaining_ticks: int, // remaining ticks until shooting new projectiles
    num_projectiles_to_fire: int,
}

Magic_Wand_Projectile :: struct {
    dz: Pool_Handle(Damage_Zone),
    lifetime: int,
    velocity: [2]f32,
    health: int, // The maximum amount of enemies that can be hit by this projectile
}

MAGIC_WAND_COOLDOWN :: 200
MAGIC_WAND_DAMAGE :: 30
MAGIC_WAND_MAX_PROJECTILES :: 1000
MAGIC_WAND_PROJECTILE_LIFETIME :: 300
MAGIC_WAND_PROJECTILE_SPEED :: 300
MAGIC_WAND_DEFAULT_NUM_PROJECTILES :: 10

make_magic_wand :: proc(damage_zones: ^Pool(Damage_Zone)) -> Magic_Wand {
    result: Magic_Wand
    pool_init(&result.projectiles, MAGIC_WAND_MAX_PROJECTILES)
    result.remaining_ticks = MAGIC_WAND_COOLDOWN
    result.num_projectiles_to_fire = MAGIC_WAND_DEFAULT_NUM_PROJECTILES
    return result
}

Damage_Zone :: struct {
    pos: [2]f32,
    dim: [2]f32,
    damage: f32,
    is_active: bool,
    color: rl.Color,
    enemy_hit_count: int,
}
