const std = @import("std");
const json = std.json;

// FIXME: make these all just calls to a comptime GenericSlice(T: type, mutable: bool, optional: bool)
// type constructor

// TODO: give better name... C slice?
/// extern slice
pub fn Slice(comptime T: type) type {
    return extern struct {
        ptr: [*]const T = &[_]T{},
        len: usize = 0,

        pub fn fromZig(slice: []const T) @This() {
            return @This(){ .ptr = slice.ptr, .len = slice.len };
        }

        pub fn toZig(self: @This()) []const T {
            return self.ptr[0..self.len];
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
            return @This().fromZig(try json.innerParse([]const T, allocator, source, options));
        }
    };
}

pub fn MutSlice(comptime T: type) type {
    return extern struct {
        ptr: [*]T = &[_]T{},
        len: usize = 0,

        pub fn fromZig(slice: []T) @This() {
            return @This(){ .ptr = slice.ptr, .len = slice.len };
        }

        pub fn toZig(self: @This()) []T {
            return self.ptr[0..self.len];
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
            return @This().fromZig(try json.innerParse([]T, allocator, source, options));
        }

        pub fn asConst(self: @This()) Slice(T) {
            return Slice(T){ .ptr = self.ptr, .len = self.len };
        }
    };
}

pub fn OptSlice(comptime T: type) type {
    return extern struct {
        ptr: ?[*]const T = null,
        len: usize = 0,

        pub fn fromZig(slice: ?[]const T) @This() {
            return if (slice) |s| @This(){ .ptr = s.ptr, .len = s.len } else @This(){ .ptr = null, .len = 0 };
        }

        pub fn toZig(self: @This()) ?[]const T {
            return if (self.ptr) |p| p[0..self.len] else null;
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
            // FIXME: technically this should allow null as an entry or something
            return @This().fromZig(try json.innerParse([]const T, allocator, source, options));
        }
    };
}
