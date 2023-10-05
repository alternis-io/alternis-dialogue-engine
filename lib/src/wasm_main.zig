const std = @import("std");
const builtin = @import("builtin");
const c_api = @import("./c_api.zig");

export fn wasm_init() void {
    _ = c_api;
    // FIXME: allow setting a zig allocator and do that here instead of redirection
    //c_api.setZigAlloc(std.heap.wasm_allocator);
}
