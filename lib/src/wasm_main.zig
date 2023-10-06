const std = @import("std");
const builtin = @import("builtin");
const c_api = @import("./c_api.zig");

export fn malloc(len: usize) [*]u8 {
    return (
        std.heap.wasm_allocator.alloc(u8, len)
            catch |e| return std.debug.panic("alloc error: {}", .{e})
    ).ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    return std.heap.wasm_allocator.free(ptr[0..len]);
}

// FIXME: eventually a comptime block will allow forcing exports to go through
// https://github.com/ziglang/zig/issues/8508
export fn _do_not_use() void {
    _ = c_api;
}
