package game

Pool :: struct($T: typeid) {
    slots: []T,
    free_stack: []int,
    free_stack_top: int,
    is_occupied: []bool,
    generations: []u64,
}

Pool_Handle :: struct {
    index: int,
    generation: u64,
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

pool_add :: proc(pool: ^Pool($T), value: T) -> Pool_Handle {
    index, ok := pool_pop_free_index(pool)
    if !ok {
        // TODO: do something else than crashing the program
        panic("pool_add: pool is full")
    }

    pool.slots[index] = value
    pool.is_occupied[index] = true
    return {index, pool.generations[index]}
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
crash_on_invalid_handle :: proc(pool: Pool($T), handle: Pool_Handle) {
    // TODO: maybe this shouldn't be checked?
    if handle.index < 0 || handle.index >= len(pool.slots) {
        panic("pool_get: given handle's index is out of range")
    }

    found_in_free_stack := false
    for i in pool.free_stack_top..<len(pool.free_stack) {
        found_in_free_stack |= (pool.free_stack[i] == handle.index)
    }

    if found_in_free_stack {
        panic("pool_get: given handle points to freed slot")
    }

    if handle.generation != pool.generations[handle.index] {
        panic("invalid handle: handle's generation doesn't match slot's generation")
    }
}

pool_get :: proc(pool: Pool($T), handle: Pool_Handle) -> ^T {
    crash_on_invalid_handle(pool, handle)
    return &pool.slots[handle.index]
}

pool_index_get :: proc(pool: Pool($T), index: int) -> (val:^T, gen:u64, success: bool) {
    if pool_is_free_index(pool, index) {
        return nil, 0, false
    }
    return &pool.slots[index], pool.generations[index], true
}

pool_free :: proc(pool: ^Pool($T), handle: Pool_Handle) {
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