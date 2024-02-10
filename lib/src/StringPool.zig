const std = @import("std");
const usz = @import("./config.zig").usz;

next: usz = 0,
to_id: std.StringHashMapUnmanaged(usz) = .{},
from_id: std.AutoHashMapUnmanaged(usz, []const u8) = .{},

fn put(self: *@This(), str: []const u8, alloc: std.mem.Allocator) !void {
    const duped = try alloc.dupe(u8, str);
    self.to_id.put(alloc, duped, self.next) catch |e| std.debug.panic("put memory error: {}", .{e});
    self.from_id.put(alloc, self.next, duped) catch |e| std.debug.panic("put memory error: {}", .{e});
    self.next += 1;
}

fn get(self: *@This(), str: []const u8) ?usz {
    return self.to_id.get(str);
}

fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    var iter = self.to_id.iterator();
    while (iter.next()) |str| {
        alloc.free(str.key_ptr.*);
    }
    self.to_id.deinit(alloc);
    self.from_id.deinit(alloc);
}

const t = std.testing;

test {
    var pool = @This(){};
    defer pool.deinit(t.allocator);
    try pool.put("hello", t.allocator);
    try pool.put("world", t.allocator);
    try t.expectEqual(pool.get("world"), 1);
}
