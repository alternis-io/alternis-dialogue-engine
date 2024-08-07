const std = @import("std");
const builtin = @import("builtin");

fn fmtStringId(
    comptime fmt_str: []const u8,
    // FIXME: also need to take the args into account, which can be done by generating a custom type
    // comptime fmt_args_type: type
) usize {
    return @intFromPtr(fmt_str.ptr);
}

fn ResultDecls(comptime R: type, comptime E: type, comptime Self: type) type {
    return struct {
        pub fn is_ok(self: Self) bool {
            return self.err == null;
        }

        pub fn is_err(self: Self) bool {
            return !self.is_ok();
        }

        pub fn ok(r: R) Self {
            return Self{
                .value = r,
                .err = null,
                .errCode = 0,
            };
        }

        pub fn err(e: E) Self {
            return Self{
                .value = undefined,
                .err = e,
                // FIXME: not used
                .errCode = 1,
            };
        }

        pub fn err_as(self: @This(), comptime T: type) Result(T) {
            std.debug.assert(self.is_err());
            return Result(T){
                .value = undefined,
                .err = self.err,
                .errCode = self.errCode,
            };
        }

        pub fn fmt_err(alloc: std.mem.Allocator, comptime fmt_str: []const u8, fmt_args: anytype) Self {
            const unknown_src = std.builtin.SourceLocation{ .fn_name = "???", .file = "???", .line = 0, .column = 0 };

            const src = if (builtin.os.tag != .freestanding) _: {
                const debug_info = std.debug.getSelfDebugInfo() catch unreachable;

                const module = debug_info.getModuleForAddress(@returnAddress()) catch |er| switch (er) {
                    error.MissingDebugInfo, error.InvalidDebugInfo => break :_ unknown_src,
                    else => |e| std.debug.panic("error getting module for address from debug info: {}", .{e}),
                };

                const symbol_info = module.getSymbolAtAddress(debug_info.allocator, @returnAddress()) catch |er| switch (er) {
                    error.MissingDebugInfo, error.InvalidDebugInfo => break :_ unknown_src,
                    else => |e| std.debug.panic("error getting symbol for at address from debug info: {}", .{e}),
                };
                defer symbol_info.deinit(debug_info.allocator);

                break :_ std.builtin.SourceLocation{
                    .line = if (symbol_info.line_info) |li| @intCast(li.line) else unknown_src.line,
                    // FIXME: leaks!
                    .fn_name = alloc.dupeZ(u8, symbol_info.symbol_name) catch |e| std.debug.panic("error copying symbol name: {}", .{e}),
                    .file = if (symbol_info.line_info) |li|
                        alloc.dupeZ(u8, li.file_name) catch |e| std.debug.panic("error copying file name: {}", .{e})
                    else
                        unknown_src.file,
                    .column = if (symbol_info.line_info) |li| @intCast(li.column) else unknown_src.column,
                };
            } else @src();

            return Self{
                .value = undefined,
                .err = std.fmt.allocPrintZ(alloc, "Error at {s}:{}:\n" ++ fmt_str, .{ src.file, src.line } ++ fmt_args) catch |sub_err|
                    std.debug.panic("error '{}' while explaining an error", .{sub_err}),
                .errCode = fmtStringId(fmt_str),
            };
        }

        // this is if we need caller information on platforms that don't support finding it
        pub fn fmt_err_src(alloc: std.mem.Allocator, comptime fmt_str: []const u8, fmt_args: anytype, src: std.builtin.SourceLocation) Self {
            return Self{
                .value = undefined,
                .err = std.fmt.allocPrintZ(alloc, "Error at {s}:{}\n" ++ fmt_str, .{ src.file, src.line } ++ fmt_args) catch |sub_err| std.debug.panic("error '{}' while explaining an error", .{sub_err}),
                .errCode = fmtStringId(fmt_str),
            };
        }

        pub fn c_fmt_err(comptime fmt_str: []const u8, fmt_args: anytype) Self {
            return if (builtin.link_libc)
                Result(@TypeOf(R.value)).fmt_err(std.heap.raw_c_allocator, fmt_str, fmt_args)
            else
                @compileError("Must compile with libc");
        }
    };
}

pub fn Result(comptime R: type) type {
    // zig claims it will add a syntax to select the externess of a struct at comptime
    if (@typeInfo(R) == .Struct and @typeInfo(R).Struct.layout == .@"extern" or @typeInfo(R) == .Union and @typeInfo(R).Union.layout == .@"extern") {
        return extern struct {
            /// not initialized if err is not 0/null
            value: R = undefined,
            /// must be null terminated!
            err: ?[*:0]const u8 = null,
            // TODO: try to compress to u16 if possible
            /// 0 if value is valid
            errCode: usize = 0,

            const Self = @This();

            pub usingnamespace ResultDecls(R, @typeInfo(@This()).Struct.fields[1].type, @This());
        };
    } else {
        return struct {
            /// not initialized if err is not 0/null
            value: R,
            err: ?[:0]const u8 = null,
            // TODO: try to compress to u16 if possible
            /// 0 if value is valid
            errCode: usize,

            pub usingnamespace ResultDecls(R, @typeInfo(@This()).Struct.fields[1].type, @This());
        };
    }
}

test "result" {
    const T = extern struct { i: i64 };
    try std.testing.expectEqual(Result(T).ok(T{ .i = 100 }), Result(T){
        .value = T{ .i = 100 },
        .errCode = 0,
        .err = null,
    });
}
