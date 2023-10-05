const std = @import("std");
const builtin = @import("builtin");
const c_api = @import("./c_api.zig");
const alloc = std.heap.wasm_allocator;

fn wasm_malloc(size: usize) [*]anyopaque {
    var mem = alloc.alloc(u8, @sizeOf(usize) + size, 0)
        catch |e| return std.debug.panic("alloc error: {}", .{e});
    return mem.ptr + @sizeOf(usize);
}

fn wasm_free(ptr: [*]anyopaque) void {
    // FIXME: avoid storing the size, can the allocator do that?
    var mem = @as(*usize, @ptrCast(ptr - @sizeOf(usize)));
    var size = mem[0];
    alloc.free(mem[0..size]);
}

pub fn main() void {
    c_api.ade_set_alloc(wasm_malloc, wasm_free);
}
