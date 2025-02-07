package game

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"
import "core:fmt"

// Weapon base struct
Weapon :: struct {
    weapon_type: typeid,
    remaining_ticks: int,
    is_cooling_down: bool, // if false => executing attack
    cooldown_time: int,
    attack_time: int,
    on_attack_event: bool, // if true => this tick started an attack
}

// !IMPORTANT!: All members of this union *must* derive from Weapon_Base
Weapon_Union :: union {
    Whip,
    Bibles,
    Magic_Wand,
    Cross,
}

weapon_tick :: proc(using weapon: ^Weapon, player: Player, damage_zones: ^Pool(Damage_Zone), enemies: Pool(Entity)) {
    remaining_ticks -= 1
    if remaining_ticks <= 0 {
        if is_cooling_down {
            // Was cooling down, going to attack
            on_attack_event = true
        }
        remaining_ticks = attack_time if is_cooling_down else cooldown_time
        is_cooling_down = !is_cooling_down // flip state
    }

    // Call derived Weapons' ticks
    switch weapon_type {
        case Whip: { whip_tick((^Whip)(weapon), player) }
        case Bibles: { bibles_tick((^Bibles)(weapon), player) }
        case Magic_Wand: { magic_wand_tick((^Magic_Wand)(weapon), player, damage_zones, enemies) }
        case Cross: { cross_tick((^Cross)(weapon), player, enemies, damage_zones) }
        case: { fmt.eprintln("unhandled weapon tick") }
    }

    // Turn off on-attack event
    weapon.on_attack_event = false
}

weapon_draw :: proc(using weapon: ^Weapon, player: Player) {
    switch weapon_type {
        case Whip: { whip_draw((^Whip)(weapon)) }
        case Bibles: { bibles_draw((^Bibles)(weapon), player) }
        case Magic_Wand: { magic_wand_draw((^Magic_Wand)(weapon)) }
        case Cross: { cross_draw((^Cross)(weapon)) }
        case: { fmt.eprintln("unhandled weapon draw") }
    }
}

Whip :: struct {
    using base: Weapon,
    dz: Pool_Handle(Damage_Zone),
    emitter: Particle_Emitter, // emits the "slash"
}

WHIP_COOLDOWN :: 100
WHIP_LIFETIME :: 10

make_whip :: proc(damage_zones: ^Pool(Damage_Zone)) -> Whip {
    dz: Damage_Zone
    dz.dim = {200,100}
    dz.damage = 50
    dz.color = rl.PINK
    dz.is_active = false
    dz_handle := pool_add(damage_zones, dz)

    emitter: Particle_Emitter
    color := [3]f32{1,1,1}
    particle_emitter_init(&emitter, get_texture("slash"), color, color, 60, int(f32(WHIP_LIFETIME) * 4), [2]f32{7,3})

    result: Whip
    result.weapon_type = Whip
    result.cooldown_time = WHIP_COOLDOWN
    result.attack_time = WHIP_LIFETIME
    result.dz = dz_handle
    result.emitter = emitter

    return result
}

whip_tick :: proc(w: ^Whip, player: Player) {
    dz := pool_get(w.dz)

    if w.on_attack_event {
        dz.is_active = true
        dz.pos.x = player.pos.x + player.dim.x
        dz.pos.y = player.pos.y + player.dim.y/4
        if player.facing_dir.x < 0 {
            dz.pos.x -= dz.dim.x+ player.dim.x
        }
        particle_emitter_emit(&w.emitter, get_center(dz.pos, dz.dim), player.facing_dir, flip_x=player.facing_dir.x < 0)
    }

    if w.is_cooling_down {
        dz.is_active = false
    }

    particle_emitter_tick(&w.emitter)
}

whip_draw :: proc(w: ^Whip) {
    particle_emitter_draw(w.emitter)
}

Bibles :: struct {
    using base: Weapon,
    bibles: [3]Pool_Handle(Damage_Zone),
    page_emitter: Particle_Emitter,
}

BIBLES_LIFETIME :: 500
BIBLES_COOLDOWN :: 200
BIBLES_REVOLUTIONS :: 3
BIBLES_RADIUS :: 100
BIBLES_DAMAGE :: 80
BIBLES_MAX_PARTICLES :: 1000

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

    page_emitter: Particle_Emitter
    start_color := [3]f32{1, 0, 1}
    end_color := [3]f32{1, 0, 0}
    particle_emitter_init(&page_emitter, get_texture("bible"), start_color, end_color, BIBLES_MAX_PARTICLES, 40, [2]f32{0.8,0.8})

    result: Bibles
    result.weapon_type = Bibles
    result.cooldown_time = BIBLES_COOLDOWN
    result.attack_time = BIBLES_LIFETIME
    result.bibles = bibles
    result.page_emitter = page_emitter

    return result
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

bibles_tick :: proc(bibles: ^Bibles, player: Player) {

    for i in 0..<len(bibles.bibles) {
        bible_handle := bibles.bibles[i]
        bible := pool_get(bible_handle)
        bible.is_active = !bibles.is_cooling_down
    }

    // Move bible damage zones
    for i in 0..<len(bibles.bibles) {
        bible_handle := bibles.bibles[i]
        bible := pool_get(bible_handle)
        bible.pos = calc_bible_center_pos(i, get_center(player.pos,player.dim), len(bibles.bibles), bibles.remaining_ticks) - bible.dim/2
    }

    // spawn particles
    if rand.float32() < 0.05 {
        for i in 0..<len(bibles.bibles) {
            bible_center := calc_bible_center_pos(i, get_center(player.pos,player.dim), len(bibles.bibles), bibles.remaining_ticks)
            r := player.pos - bible_center
            page_velocity := linalg.normalize([2]f32{-r.y, r.x}) * 10
            particle_emitter_emit(&bibles.page_emitter, bible_center, page_velocity)
        }
    }

    particle_emitter_tick(&bibles.page_emitter)
}

bibles_draw :: proc(bibles: ^Bibles, player: Player) {
    if bibles.is_cooling_down { return }

    for i in 0..<len(bibles.bibles) {
        bible_center := calc_bible_center_pos(i, get_center(player.pos,player.dim), len(bibles.bibles), bibles.remaining_ticks)

        tex := get_texture("bible")

        src_rec := to_rec({0,0},{f32(tex.width), f32(tex.height)})

        dest_rec_dim := [2]f32{50,50}
        dest_rec_pos := bible_center - dest_rec_dim/2
        dest_rec := to_rec(dest_rec_pos, dest_rec_dim)

        rl.DrawTexturePro(tex, src_rec, dest_rec, {}, 0, rl.WHITE)
    }

    // draw particles
    particle_emitter_draw(bibles.page_emitter)
}

Magic_Wand :: struct {
    using base: Weapon,
    projectiles: Pool(Magic_Wand_Projectile),
    num_projectiles_to_fire: int,
    emitter: Particle_Emitter,
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

    result.weapon_type = Magic_Wand
    result.cooldown_time = MAGIC_WAND_COOLDOWN
    result.attack_time = 1 // Right now, the magic wand fires all its projectiles in one tick

    pool_init(&result.projectiles, MAGIC_WAND_MAX_PROJECTILES)
    result.remaining_ticks = MAGIC_WAND_COOLDOWN
    result.num_projectiles_to_fire = MAGIC_WAND_DEFAULT_NUM_PROJECTILES

    particle_tex := get_texture("flare")
    start_color := [3]f32{0,0,1}
    end_color := [3]f32{0,1,1}
    max_particles := 1000
    particle_lifetime := 100
    scaling := [2]f32{1,1}
    particle_emitter_init(&result.emitter, particle_tex, start_color, end_color, max_particles, particle_lifetime, scaling)

    return result
}

magic_wand_tick :: proc(w: ^Magic_Wand, player: Player, damage_zones: ^Pool(Damage_Zone), enemies: Pool(Entity)) {
    // tick the projectiles
    for pi in 0..<len(w.projectiles.slots) {
        projectile, _ := pool_index_get(w.projectiles, pi) or_continue
        dz := pool_get(projectile.dz)
        projectile.lifetime -= 1
        // free expired projectiles (lifetime expired or projectile has hit its max amount of enemies)
        if projectile.lifetime <= 0 || dz.enemy_hit_count >= projectile.health {
            // first free the projectile's Damage_Zone
            pool_free(projectile.dz)
            // free the projectile itself
            pool_index_free(&w.projectiles, pi)
        }
        else {
            // Update projectile's movement
            dz.pos += projectile.velocity * TICK_TIME
        }

        // emit trail particles
        emit_interval := int(f32(MAGIC_WAND_PROJECTILE_LIFETIME) / 100)
        if projectile.lifetime % emit_interval == 0 {
            particle_emitter_emit(&w.emitter, get_center(dz.pos, dz.dim), 0)
        }
    }

    if w.on_attack_event {
        enemy_distances := find_nearest_enemies(player, enemies)

        targeted_enemy := 0 // index in enemy_distances

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

            // Go to next nearest enemy if currently targeted enemy would be dead
            // because of previously fired projectiles
            for targeted_enemy < len(enemy_distances) && enemy_distances[targeted_enemy].health <= 0 {
                targeted_enemy += 1
            }

            if targeted_enemy < len(enemy_distances) {
                target, _, ok := pool_index_get(enemies, enemy_distances[targeted_enemy].enemy_pool_index)
                if !ok { panic("magic_wand_tick: getting target enemy from the enemy pool gone horribly wrong!") }
                projectile.velocity = linalg.normalize(get_center(target.pos,target.dim)-get_center(player.pos,player.dim)) * MAGIC_WAND_PROJECTILE_SPEED

                enemy_distances[targeted_enemy].health -= dz.damage
            } else {
                // No enemy target => shoot in random direction
                projectile.velocity = random_unit_vec() * MAGIC_WAND_PROJECTILE_SPEED
            }

            pool_add(&w.projectiles, projectile)
        }
    }

    // tick particles
    particle_emitter_tick(&w.emitter)
}

magic_wand_draw :: proc(w: ^Magic_Wand) {
    particle_emitter_draw(w.emitter)
}

// NOTE: Allocates on context.temp_allocator
// Returns a sorted array of the nearest enemies from closest to farthest
find_nearest_enemies :: proc(player: Player, enemies: Pool(Entity)) -> []Enemy_Distance_Pair {
    enemy_distances := make([dynamic]Enemy_Distance_Pair, context.temp_allocator)

    for i in 0..<len(enemies.slots) {
        e, _ := pool_index_get(enemies, i) or_continue
        if e.health <= 0 { continue } // NOTE: Probably redundant check, keep anyway for robustness
        dist := linalg.length(get_center(e.pos,e.dim) - get_center(player.pos,player.dim))
        append(&enemy_distances, Enemy_Distance_Pair{i, dist, e.health})
    }

    less_func :: proc(ed0, ed1: Enemy_Distance_Pair) -> bool { return ed0.dist < ed1.dist }
    slice.sort_by(enemy_distances[:], less_func)
    return enemy_distances[:]
}
Enemy_Distance_Pair :: struct {
    enemy_pool_index: int,
    dist: f32,
    health: f32,
}

Cross :: struct {
    using base: Weapon,
    projectiles: Pool(Cross_Projectile),
    ticks_until_next_fire: int,
    pending_projectiles: int,
    emitter: Particle_Emitter,
}

CROSS_PROJECTILE_COUNT :: 2
CROSS_MAX_PROJECTILES :: 100
CROSS_TICKS_BETWEEN_SHOTS :: 5
CROSS_PROJECTILE_SPEED :: 250
CROSS_PROJECTILE_LIFETIME :: 360
CROSS_PROJECTILE_DAMAGE :: 1000
CROSS_COOLDOWN :: 200

Cross_Projectile :: struct {
    dz: Pool_Handle(Damage_Zone),
    lifetime: int,
    velocity: [2]f32,
    initial_direction: [2]f32,
    rotation: f32,
}

make_cross :: proc(damage_zones: ^Pool(Damage_Zone)) -> Cross {
    result: Cross

    result.weapon_type = Cross
    result.cooldown_time = CROSS_COOLDOWN
    result.attack_time = (CROSS_PROJECTILE_COUNT-1) * CROSS_TICKS_BETWEEN_SHOTS

    pool_init(&result.projectiles, CROSS_MAX_PROJECTILES)

    result.pending_projectiles = 0

    emitter_info: Particle_Emitter_Init_Info
    emitter_info.start_color = [3]f32{1,1,0}
    emitter_info.end_color = emitter_info.start_color
    emitter_info.scaling = [2]f32{2,2}
    emitter_info.particle_lifetime = 20
    particle_emitter_init(&result.emitter, get_texture("cross"), emitter_info)

    return result
}

cross_tick :: proc(cross: ^Cross, player: Player, enemies: Pool(Entity), damage_zones: ^Pool(Damage_Zone)) {
    if cross.on_attack_event {
        cross.pending_projectiles = CROSS_PROJECTILE_COUNT
    }

    cross.ticks_until_next_fire -= 1

    if cross.pending_projectiles > 0 && cross.ticks_until_next_fire <= 0 {
        cross.pending_projectiles -= 1
        cross.ticks_until_next_fire = CROSS_TICKS_BETWEEN_SHOTS

        // Fire a single cross
        enemy_distances := find_nearest_enemies(player, enemies)
        proj_vel := [2]f32{}
        if len(enemy_distances) != 0 {
            target, _, ok := pool_index_get(enemies, enemy_distances[0].enemy_pool_index)
            to_nearest_enemy := linalg.normalize(get_center(target.pos,target.dim)-get_center(player.pos,player.dim))
            proj_vel = to_nearest_enemy * CROSS_PROJECTILE_SPEED
        }
        else {
            proj_vel = random_unit_vec() * MAGIC_WAND_PROJECTILE_SPEED
        }

        dz: Damage_Zone
        dz.pos = player.pos
        dz.dim = {50,50}
        dz.damage = CROSS_PROJECTILE_DAMAGE
        dz.color = rl.BLUE
        dz.is_active = true

        proj: Cross_Projectile
        proj.dz = pool_add(damage_zones, dz)
        proj.lifetime = CROSS_PROJECTILE_LIFETIME
        proj.velocity = proj_vel
        proj.initial_direction = linalg.normalize(proj.velocity)

        pool_add(&cross.projectiles, proj)
    }

    // tick projectiles
    for pi in 0..<len(cross.projectiles.slots) {
        projectile, _ := pool_index_get(cross.projectiles, pi) or_continue
        dz := pool_get(projectile.dz)
        projectile.lifetime -= 1
        // free expired projectiles (lifetime expired or projectile has hit its max amount of enemies)
        if projectile.lifetime <= 0 {
            // first free the projectile's Damage_Zone
            pool_free(projectile.dz)
            // free the projectile itself
            pool_index_free(&cross.projectiles, pi)
        }
        else {
            // Update projectile's movement
            projectile.velocity += -500 * projectile.initial_direction * TICK_TIME // backwards acceleration for "boomerang" effect
            dz.pos += projectile.velocity * TICK_TIME
            projectile.rotation += 200 * TICK_TIME
        }

        // emit trail particles
        emit_interval := 10
        if projectile.lifetime % emit_interval == 0 {
            info: Emit_Info
            info.position = get_center(dz.pos, dz.dim)
            info.rotation_speed = 200
            particle_emitter_emit(&cross.emitter, info)
        }
    }

    particle_emitter_tick(&cross.emitter)
}

cross_draw :: proc(cross: ^Cross) {
    particle_emitter_draw(cross.emitter)

    // draw cross projectiles themselves
    for pi in 0..<len(cross.projectiles.slots) {
        projectile, _ := pool_index_get(cross.projectiles, pi) or_continue
        dz := pool_get(projectile.dz)

        src_rec_dim := [2]f32{f32(cross.emitter.texture.width), f32(cross.emitter.texture.height)}
        src_rec := to_rec({0,0}, src_rec_dim)

        dest_rec_dim := [2]f32{100,100}
        dest_rec := to_rec(get_center(dz.pos, dz.dim), dest_rec_dim)

        origin := dest_rec_dim / 2

        rl.DrawTexturePro(cross.emitter.texture, src_rec, dest_rec, origin, projectile.rotation, rl.WHITE)
    }
}