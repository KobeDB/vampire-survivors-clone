package game

import "core:fmt"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math/linalg"
import "core:math/rand"
import sa "core:container/small_array"
import "core:math"

main :: proc() {
    fmt.println("Hello there")

    SCREEN_DIM :: [2]f32{1270, 720}
    TICK_TIME :: 1.0/60.0

    rl.InitWindow(i32(SCREEN_DIM.x), i32(SCREEN_DIM.y) , "The window")
    rl.SetTargetFPS(1.0/TICK_TIME)

    player_pos := [2]f32{10,10}
    player_dim := [2]f32{50,50}
    player_move_speed := f32(100)
    player_facing_dir := [2]f32{1,0}

    MAX_ENEMIES :: 100000
    enemies: Pool(Entity)
    pool_init(&enemies, MAX_ENEMIES)

    for i in 0..<MAX_ENEMIES {
        pos := [2]f32{rand.float32_range(-1000,1000), rand.float32_range(-1000,1000)}
        e: Entity
        e.pos = pos
        e.dim = {20,20}
        e.move_speed = 50
        e.health = 100
        pool_add(&enemies, e)
    }

    MAX_DAMAGE_ZONES :: 100
    damage_zones: Pool(Damage_Zone)
    pool_init(&damage_zones, MAX_DAMAGE_ZONES)

    camera: rl.Camera2D
    camera.target = {player_pos.x + player_dim.x/2 , player_pos.y + player_dim.y/2}
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
            player_facing_dir = {1,0}
        }
        if rl.IsKeyDown(.A) {
            move_dir.x -= 1
            player_facing_dir = {-1,0}
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
        player_pos += player_move_speed * move_dir * TICK_TIME

        // Update camera target to follow player
        camera.target = {player_pos.x + player_dim.x/2 , player_pos.y + player_dim.y/2}

        // Update damage zones
        // ----------------------

        // decrement lifetimes of damage zones
        for i in 0..<len(damage_zones.slots) {
            dz, _ := pool_index_get(damage_zones, i) or_continue
            dz.lifetime_ticks -= 1
            if dz.lifetime_ticks <= 0 {
                pool_index_free(&damage_zones, i)
            }
        }

        // update movement of damage zones
        for i in 0..<len(damage_zones.slots) {
            dz, _ := pool_index_get(damage_zones, i) or_continue
            if dz.movement == .Bible {
                dz.pos = calc_bible_center_pos(dz.id, player_pos, 3, u64(dz.lifetime_ticks))
            }
        }

        if ticks % 200 == 0 {
            // spawn damage zone
            dz: Damage_Zone
            dz.dim = {200,100}
            dz.pos = player_pos + player_dim/2
            if player_facing_dir.x < 0 {
                dz.pos.x -= dz.dim.x
            }
            dz.lifetime_ticks = 100
            dz.damage = 50
            dz.color = rl.PINK
            pool_add(&damage_zones, dz)
        }

        if ticks % (BIBLES_LIFETIME+BIBLES_COOLDOWN) == 0 {
            // spawn bibles
            num_bibles := 3
            for i in 0..<num_bibles {
                bible: Damage_Zone
                bible.dim = {50,75}
                // TODO: calculate corner pos of bible
                bible.pos = calc_bible_center_pos(i, player_pos, num_bibles, BIBLES_LIFETIME)
                bible.movement = .Bible
                bible.damage = BIBLES_DAMAGE
                bible.lifetime_ticks = BIBLES_LIFETIME
                bible.color = rl.BLUE
                bible.id = i
                pool_add(&damage_zones, bible)
            }
        }

        // Move enemies
        for i in 0..<len(enemies.slots) {
            e, _ := pool_index_get(enemies, i) or_continue
            to_player := linalg.normalize((player_pos + player_dim/2) - (e.pos + e.dim/2))
            e.pos += e.move_speed * to_player * TICK_TIME
        }

        // Damage enemies
        for ei in 0..<len(enemies.slots) {
            e, _ := pool_index_get(enemies, ei) or_continue

            damage_zones_cur_tick := e.damage_zones_prev_tick
            damage_zones_cur_tick = {} // reset array
            defer e.damage_zones_prev_tick = damage_zones_cur_tick

            for dzi in 0..<len(damage_zones.slots) {
                dz, gen := pool_index_get(damage_zones, dzi) or_continue
                in_zone := aabb_collision_check(e.pos, e.dim, dz.pos, dz.dim)
                if in_zone {
                    zone_handle := Pool_Handle{dzi, gen}
                    sa.append(&damage_zones_cur_tick, zone_handle)
                    was_in_zone_prev_tick := false
                    for dz_prev_tick in sa.slice(&e.damage_zones_prev_tick) {
                        if dz_prev_tick == zone_handle {
                            was_in_zone_prev_tick = true
                            break
                        }
                    }
                    if !was_in_zone_prev_tick {
                        e.health -= dz.damage
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


        // Draw
        // ---------------
        rl.BeginDrawing()

        rl.ClearBackground(rl.RAYWHITE)


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
            rl.DrawRectangleRec(to_rec(player_pos, player_dim), rl.MAGENTA)

            // Draw damage zones
            for i in 0..<len(damage_zones.slots) {
                dz, _ := pool_index_get(damage_zones, i) or_continue
                rl.DrawRectangleRec(to_rec(dz.pos,dz.dim), dz.color)
            }

            // Draw test rectangle
            rect_pos := [2]f32{70,70}
            rect_dim := [2]f32{100,20}
            overlap := aabb_collision_check(player_pos, player_dim, rect_pos, rect_dim)
            rect_color := rl.RED if overlap else rl.GREEN
            rl.DrawRectangleRec(to_rec(rect_pos, rect_dim), rect_color)

            //Draw enemies
            for i in 0..<len(enemies.slots) {
                e, _ := pool_index_get(enemies, i) or_continue
                rl.DrawRectangleRec(to_rec(e.pos, e.dim), rl.RED)
            }

        rl.EndMode2D()

        rl.DrawText("BOI", 50, 50, 50, rl.GREEN)
        rl.DrawFPS(0,0)

        rl.EndDrawing()
    }
}

to_rec :: proc(pos: [2]f32, dim: [2]f32) -> rl.Rectangle {
    return {pos.x, pos.y, dim.x, dim.y}
}

aabb_collision_check :: proc(pos0: [2]f32, dim0: [2]f32, pos1: [2]f32, dim1: [2]f32) -> bool {
    return ((pos0.x <= pos1.x+dim1.x && pos0.x >= pos1.x) \
            || (pos1.x <= pos0.x+dim0.x && pos1.x >= pos0.x)) \
           && \
           ((pos0.y <= pos1.y+dim1.y && pos0.y >= pos1.y) \
            || (pos1.y <= pos0.y+dim0.y && pos1.y >= pos0.y))
}

Entity :: struct {
    pos: [2]f32,
    dim: [2]f32,
    move_speed: f32,
    health: f32,
    damage_zones_prev_tick: sa.Small_Array(20, Pool_Handle)
}

Damage_Zone :: struct {
    pos: [2]f32,
    dim: [2]f32,
    damage: f32,
    lifetime_ticks: int,
    color: rl.Color,
    movement: Damage_Zone_Movement,
    id: int, // e.g. used to identify which bible this zone represents
}

Damage_Zone_Movement :: enum {
    Static = 0,
    Bible,
}

BIBLES_LIFETIME :: 1000
BIBLES_COOLDOWN :: 200
BIBLES_REVOLUTIONS :: 5
BIBLES_RADIUS :: 200
BIBLES_DAMAGE :: 100

calc_bible_center_pos :: proc(bible: int, orbit_center: [2]f32, num_bibles: int, remaining_lifetime: u64) -> [2]f32 {
    angle_between_bibles := 2*math.PI/f32(num_bibles)
    animation_progress := f32(BIBLES_LIFETIME-remaining_lifetime) / f32(BIBLES_LIFETIME)
    angle_offset := (BIBLES_REVOLUTIONS * 2*math.PI) * animation_progress
    bible_angle :f32= angle_between_bibles * f32(bible) + angle_offset
    bible_center_on_unit_circle := [2]f32{math.cos(bible_angle), math.sin(bible_angle)}
    bible_center := bible_center_on_unit_circle * BIBLES_RADIUS + orbit_center
    return bible_center
}