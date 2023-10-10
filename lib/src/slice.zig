const std = @import("std");
const json = std.json;

// TODO: give better name... C slice?
/// extern slice
pub fn Slice(comptime T: type) type {
    return extern struct {
        ptr: [*]const T,
        len: usize,

        pub fn fromZig(slice: []const T) @This() {
            return @This(){ .ptr = slice.ptr, .len = slice.len };
        }

        pub fn toZig(self: @This()) []const T {
            return self.ptr[0..self.len];
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
            const is_string_slice =
                    @typeInfo(T)               == .Pointer
                and @typeInfo(T).Pointer.Size  == .Slice
                and @typeInfo(T).Pointer.child == u8;

            if (is_string_slice) {
                return @This().fromZig(try json.innerParse([]const u8, allocator, source, options));
            } else {
                return @This().fromZig(try json.innerParse([]const T, allocator, source, options));
            }
        }
    };
}

pub fn OptSlice(comptime T: type) type {
    return extern struct {
        ptr: ?[*]const T = null,
        len: usize = 0,

        pub fn fromZig(slice: ?[]const T) @This() {
            return if (slice) |s| @This(){ .ptr = s.ptr, .len = s.len }
                else @This(){ .ptr = null, .len = 0 };
        }

        pub fn toZig(self: @This()) ?[]const T {
            return if (self.ptr) |p| p[0..self.len] else null;
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
            return @This().fromZig(try json.innerParse([]const u8, allocator, source, options));
        }
    };
}
