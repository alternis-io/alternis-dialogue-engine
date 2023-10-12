const std = @import("std");
const builtin = @import("builtin");
const Api = @import("./main.zig");
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

/// the js environment must export this, and can dispatch from here calls into js
extern fn _call_js(?*anyopaque) void;

export const INVALID_CALLBACK_HANDLE: usize = 0;
var next_callback_handle: usize = 1;

/// the passed in pointers must exist as long as this is set
/// @returns a unique handle that will be passed as the single argument to _call_js when
///          this callback is called. The host (JavaScript) is responsible for dispatching
///          based on the unique handle to the appropriate JavaScript
export fn ade_dialogue_ctx_set_callback_js(
    in_dialogue_ctx: ?*Api.DialogueContext,
    name: [*]const u8,
    len: usize,
) usize {
    const ctx = in_dialogue_ctx orelse return INVALID_CALLBACK_HANDLE;

    const callback_handle = next_callback_handle;
    next_callback_handle += 1;

    ctx.setCallback(name[0..len], .{
        .function = _call_js,
        .payload = @ptrFromInt(callback_handle),
    });

    return callback_handle;
}

// FIXME: eventually a comptime block will allow forcing exports to go through
// https://github.com/ziglang/zig/issues/8508
export fn _do_not_use() void {
    _ = c_api;
}
