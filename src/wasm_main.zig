const std = @import("std");
const builtin = @import("builtin");
const DialogueContext = @import("./main.zig").DialogueContext;

// FIXME use wasm known memory limits or something
var alloc_buffer: [std.mem.page_size * 512]u8 = undefined;
var global_allocator_inst = std.heap.FixedBufferAllocator.init(&alloc_buffer);
pub const global_alloc = global_allocator_inst.allocator();

export fn alloc_string(byte_count: usize) [*:0]u8 {
  return (
    global_alloc.allocSentinel(u8, byte_count, 0)
      catch |e| return std.debug.panic("alloc error: {}", .{e})
  ).ptr;
}

export fn free_string(str: [*:0]u8) void {
  // FIXME: avoid runtime length check
  return global_alloc.free(str[0..std.mem.len(str)]);
}

// needed for wasm lib build
pub fn main() void {}
