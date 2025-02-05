package game

Pool :: struct($T: typeid) {
    slots: []T,
    free_stack: []int,
    free_stack_top: int,
    is_occupied: []bool,
    generations: []u64,
}

Pool_Handle :: struct($T: typeid) {
    index: int,
    generation: u64,
    pool: ^Pool(T),
}

pool_init :: proc(pool: ^Pool($T), num_slots: int) {
    pool.slots = make([]T, num_slots)
    pool.is_occupied = make([]bool, num_slots)
    pool.generations = make([]u64, num_slots)
    pool.free_stack = make([]int, num_slots)
    pool.free_stack_top = 0
    // populate free stack
    for i in 0..<num_slots {
        pool.free_stack[i] = i
    }
}

pool_add :: proc(pool: ^Pool($T), value: T) -> Pool_Handle(T) {
    index, ok := pool_pop_free_index(pool)
    if !ok {
        // TODO: do something else than crashing the program
        panic("pool_add: pool is full")
    }

    pool.slots[index] = value
    pool.is_occupied[index] = true
    return {index, pool.generations[index], pool}
}

pool_pop_free_index :: proc(pool: ^Pool($T)) -> (int, bool) {
    if pool.free_stack_top >= len(pool.free_stack) {
        return {}, false
    }
    index := pool.free_stack[pool.free_stack_top]
    pool.free_stack_top += 1
    return index, true
}

// TODO: maybe we shouldn't crash on an invalid handle but it'll do the job for now
crash_on_invalid_handle :: proc(pool: Pool($T), handle: Pool_Handle(T)) {
    // TODO: maybe this shouldn't be checked?
    // if handle.index < 0 || handle.index >= len(pool.slots) {
    //     panic("pool_get: given handle's index is out of range")
    // }

    if handle.generation != pool.generations[handle.index] {
        panic("invalid handle: handle's generation doesn't match slot's generation")
    }
}

_pool_get :: proc(pool: Pool($T), handle: Pool_Handle(T)) -> ^T {
    crash_on_invalid_handle(pool, handle)
    return &pool.slots[handle.index]
}

pool_handle_get :: proc(handle: Pool_Handle($T)) -> ^T {
    return _pool_get(handle.pool^, handle)
}

pool_get :: proc{_pool_get, pool_handle_get}

pool_index_get :: proc(pool: Pool($T), index: int) -> (val:^T, gen:u64, success: bool) {
    if pool_is_free_index(pool, index) {
        return nil, 0, false
    }
    return &pool.slots[index], pool.generations[index], true
}

pool_get_handle_from_index :: proc(pool: ^Pool($T), index: int) -> Pool_Handle(T) {
    if pool_is_free_index(pool^, index) {
        // TODO: report error
        return {}
    }
    return {index=index, generation=pool.generations[index], pool=pool}
}

pool_free :: proc(pool: ^Pool($T), handle: Pool_Handle(T)) {
    crash_on_invalid_handle(pool^, handle)
    pool_index_free(pool, handle.index)
}

pool_index_free :: proc(pool: ^Pool($T), index: int) {
    pool.is_occupied[index] = false
    pool.free_stack_top -= 1
    pool.free_stack[pool.free_stack_top] = index
    pool.generations[index] += 1
}

pool_is_free_index :: proc(pool: Pool($T), index: int) -> bool {
    return !pool.is_occupied[index]
}

pool_size :: proc(pool: Pool($T)) -> int {
    return pool.free_stack_top
}

pool_capacity :: proc(pool: Pool($T)) -> int {
    return len(pool.slots)
}