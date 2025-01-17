package game

import rl "vendor:raylib"
import "core:math"

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
BIBLES_DAMAGE :: 80

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
