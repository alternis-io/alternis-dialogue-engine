//! this is mostly copied from the zig standard library's raw_c_allocator

const std = @import("std");

pub const ConfigurableSimpleAlloc = struct {
    malloc: *const fn(usize) callconv(.C) ?*anyopaque,
    free: *const fn(?*anyopaque) callconv(.C) void,

    pub fn init(
        in_malloc: *const fn(usize) callconv(.C) ?*anyopaque,
        in_free: *const fn(?*anyopaque) callconv(.C) void,
    ) @This() {
        return .{
            .malloc = in_malloc,
            .free = in_free,
        };
    }

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &vtable
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = _alloc,
        .resize = _resize,
        .free = _free,
    };

    fn _alloc(
        _self: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *ConfigurableSimpleAlloc = @alignCast(@ptrCast(_self));
        _ = ret_addr;
        std.debug.assert(log2_ptr_align <= comptime std.math.log2_int(usize, @alignOf(std.c.max_align_t)));
        // Note that this pointer cannot be aligncasted to max_align_t because if
        // len is < max_align_t then the alignment can be smaller. For example, if
        // max_align_t is 16, but the user requests 8 bytes, there is no built-in
        // type in C that is size 8 and has 16 byte alignment, so the alignment may
        // be 8 bytes rather than 16. Similarly if only 1 byte is requested, malloc
        // is allowed to return a 1-byte aligned pointer.
        return @as(?[*]u8, @ptrCast(self.malloc(len)));
    }

    fn _resize(
        _: *anyopaque,
        buf: []u8,
        log2_old_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        _ = log2_old_align;
        _ = ret_addr;
        return new_len <= buf.len;
    }

    fn _free(
        _self: *anyopaque,
        buf: []u8,
        log2_old_align: u8,
        ret_addr: usize,
    ) void {
        const self: *ConfigurableSimpleAlloc = @alignCast(@ptrCast(_self));
        _ = log2_old_align;
        _ = ret_addr;
        self.free(buf.ptr);
    }
};
