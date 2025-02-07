package game

import rl "vendor:raylib"

Particle :: struct {
    position: [2]f32,
    velocity: [2]f32,
    rotation: f32,
    rotation_speed: f32,
    lifetime: int,
    scaling: [2]f32,
    flip_x: bool,
    alpha: f32,
    color: [3]f32,
}

Particle_Emitter :: struct {
    particles: Pool(Particle),
    texture: rl.Texture2D,
    particle_lifetime: int,
    scaling: [2]f32,
    start_color: [3]f32,
    end_color: [3]f32,
}

Particle_Emitter_Init_Info :: struct {
    start_color: Maybe([3]f32),
    end_color: Maybe([3]f32),
    max_particles: Maybe(int),
    particle_lifetime: Maybe(int),
    scaling: Maybe([2]f32),
}

particle_emitter_init_1 :: proc(emitter: ^Particle_Emitter, texture: rl.Texture2D, start_color: [3]f32, end_color: [3]f32, max_particles: int, particle_lifetime: int, scaling: [2]f32) {
    pool_init(&emitter.particles, max_particles)
    emitter.texture = texture
    emitter.particle_lifetime = particle_lifetime
    emitter.scaling = scaling
    emitter.start_color = start_color
    emitter.end_color = end_color
}

particle_emitter_init_2 :: proc(emitter: ^Particle_Emitter, texture: rl.Texture2D, info: Particle_Emitter_Init_Info) {
    pool_init(&emitter.particles, info.max_particles.? or_else 1000)
    emitter.texture = texture
    emitter.particle_lifetime = info.particle_lifetime.? or_else 60
    emitter.scaling = info.scaling.? or_else [2]f32{1,1}
    emitter.start_color = info.start_color.? or_else [3]f32{1,1,1}
    emitter.end_color = info.end_color.? or_else [3]f32{1,1,1}
}

particle_emitter_init :: proc{ particle_emitter_init_1, particle_emitter_init_2 }

particle_emitter_tick :: proc(emitter: ^Particle_Emitter) {
    for i in 0..<len(emitter.particles.slots) {
        particle, _ := pool_index_get(emitter.particles, i) or_continue

        particle.position += particle.velocity * TICK_TIME
        particle.rotation += particle.rotation_speed * TICK_TIME
        particle.lifetime -= 1
        particle.alpha = f32(particle.lifetime) / f32(emitter.particle_lifetime)
        particle.color = particle.alpha * emitter.start_color + (1-particle.alpha) * emitter.end_color

        if particle.lifetime <= 0 {
            pool_index_free(&emitter.particles, i)
        }
    }
}

// I miss custom default member values...
Emit_Info :: struct {
    position: [2]f32,
    velocity: Maybe([2]f32),
    rotation: Maybe(f32),
    rotation_speed: Maybe(f32),
    flip_x: Maybe(bool),
}

particle_emitter_emit_1 :: proc(emitter: ^Particle_Emitter, position: [2]f32, velocity: [2]f32, flip_x: bool = false) {
    if pool_size(emitter.particles) == pool_capacity(emitter.particles) {
        return
    }

    p: Particle
    p.position = position
    p.velocity = velocity
    p.rotation = 0
    p.lifetime = emitter.particle_lifetime
    p.scaling = emitter.scaling
    p.flip_x = flip_x
    p.alpha = 1
    p.color = emitter.start_color

    pool_add(&emitter.particles, p)
}

particle_emitter_emit_2 :: proc(emitter: ^Particle_Emitter, info: Emit_Info) {
    p: Particle
    p.position = info.position
    p.velocity = info.velocity.? or_else 0
    p.rotation = info.rotation.? or_else 0
    p.rotation_speed = info.rotation_speed.? or_else 0
    p.lifetime = emitter.particle_lifetime
    p.scaling = emitter.scaling
    p.flip_x = info.flip_x.? or_else false
    p.alpha = 1
    p.color = emitter.start_color

    pool_add(&emitter.particles, p)
}

particle_emitter_emit :: proc { particle_emitter_emit_1, particle_emitter_emit_2 }

particle_emitter_draw :: proc(emitter: Particle_Emitter) {
    for i in 0..<len(emitter.particles.slots) {
        particle, _ := pool_index_get(emitter.particles, i) or_continue

        src_rec_dim := [2]f32{f32(emitter.texture.width), f32(emitter.texture.height)}
        if particle.flip_x { src_rec_dim.x = -src_rec_dim.x }
        src_rec := to_rec({0,0}, src_rec_dim)

        dest_rec_dim := [2]f32{50,50} * particle.scaling
        //dest_rec_pos := particle.position - dest_rec_dim/2
        dest_rec := to_rec(particle.position, dest_rec_dim)

        origin := dest_rec_dim / 2

        color := rl.Fade(to_color(particle.color), particle.alpha)
        rl.DrawTexturePro(emitter.texture, src_rec, dest_rec, origin, particle.rotation, color)
    }
}