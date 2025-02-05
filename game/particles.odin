package game

import rl "vendor:raylib"

Particle :: struct {
    position: [2]f32,
    velocity: [2]f32,
    rotation: f32,
    lifetime: int,
    scaling: f32,
    alpha: f32,
    color: [3]f32,
}

Particle_Emitter :: struct {
    particles: Pool(Particle),
    texture: rl.Texture2D,
    particle_lifetime: int,
    scaling: f32,
    start_color: [3]f32,
    end_color: [3]f32,
}

particle_emitter_init :: proc(emitter: ^Particle_Emitter, texture: rl.Texture2D, start_color: [3]f32, end_color: [3]f32, max_particles: int, particle_lifetime: int, scaling: f32) {
    pool_init(&emitter.particles, max_particles)
    emitter.texture = texture
    emitter.particle_lifetime = particle_lifetime
    emitter.scaling = scaling
    emitter.start_color = start_color
    emitter.end_color = end_color
}

particle_emitter_tick :: proc(emitter: ^Particle_Emitter) {
    for i in 0..<len(emitter.particles.slots) {
        particle, _ := pool_index_get(emitter.particles, i) or_continue

        particle.position += particle.velocity * TICK_TIME
        particle.lifetime -= 1
        particle.alpha = f32(particle.lifetime) / f32(emitter.particle_lifetime)
        particle.color = particle.alpha * emitter.start_color + (1-particle.alpha) * emitter.end_color

        if particle.lifetime <= 0 {
            pool_index_free(&emitter.particles, i)
        }
    }
}

particle_emitter_emit :: proc(emitter: ^Particle_Emitter, position: [2]f32, velocity: [2]f32) {
    if pool_size(emitter.particles) == pool_capacity(emitter.particles) {
        return
    }

    p: Particle
    p.position = position
    p.velocity = velocity
    p.rotation = 0
    p.lifetime = emitter.particle_lifetime
    p.scaling = emitter.scaling
    p.alpha = 1
    p.color = emitter.start_color

    pool_add(&emitter.particles, p)
}

particle_emitter_draw :: proc(emitter: Particle_Emitter) {
    for i in 0..<len(emitter.particles.slots) {
        particle, _ := pool_index_get(emitter.particles, i) or_continue

        src_rec := to_rec({0,0},{f32(emitter.texture.width), f32(emitter.texture.height)})

        dest_rec_dim := [2]f32{50,50} * particle.scaling
        dest_rec_pos := particle.position - dest_rec_dim/2
        dest_rec := to_rec(dest_rec_pos, dest_rec_dim)

        color := rl.Fade(to_color(particle.color), particle.alpha)
        rl.DrawTexturePro(emitter.texture, src_rec, dest_rec, {}, particle.rotation, color)
    }
}