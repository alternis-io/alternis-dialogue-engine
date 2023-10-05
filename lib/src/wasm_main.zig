const std = @import("std");
const builtin = @import("builtin");
const c_api = @import("./c_api.zig");

export fn alloc_string(byte_count: usize) [*:0]u8 {
    return (
        std.heap.wasm_allocator.allocSentinel(u8, byte_count, 0)
            catch |e| return std.debug.panic("alloc error: {}", .{e})
    ).ptr;
}

export fn free_string(str: [*:0]u8) void {
    // FIXME: remove wasteful length check
    return std.heap.wasm_allocator.free(str[0..std.mem.len(str)]);
}

// FIXME: eventually a comptime block will allow forcing exports to go through
// https://github.com/ziglang/zig/issues/8508
export fn _do_not_use() void {
    _ = c_api;
}
