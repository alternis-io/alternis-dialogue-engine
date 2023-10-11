//! utilities for interpolating text in a simple "static {or variable} static" format

const std = @import("std");
const ChunkWriter = @import("./ChunkWriter.zig").ChunkWriter;

// dialogues are unlikely to have very long text
const SmallChunkWriter = ChunkWriter(512);

pub fn interpolate_template(
    template: []const u8,
    alloc: std.mem.Allocator,
    vars: *std.StringHashMap([]const u8)
) ![]u8 {
    // FIXME: would be nicer if the writer were an argument
    var chunk_writer = try SmallChunkWriter.init(alloc);
    defer chunk_writer.deinit();
    var writer = chunk_writer.writer();

    var state: enum { in_text, in_var, in_escape_text, in_escape_var } = .in_text;
    var i: usize = 0;
    var section_start: usize = 0;
    while (i < template.len) : (i += 1) {
        const c = template[i];
        const section_end_index = i;
        const section = template[section_start..section_end_index];
        switch (c) {
            '{' => switch (state) {
                .in_text => {
                    _ = try writer.write(section);
                    section_start = i + 1;
                    state = .in_var;
                },
                .in_escape_text => {
                    _ = try writer.write(section);
                    section_start = i;
                    state = .in_text;
                },
                .in_escape_var => {},
                .in_var => {},
            },
            '\\' => switch (state) {
                .in_text, .in_escape_text => { state = .in_escape_text; },
                .in_var, .in_escape_var => { state = .in_escape_var; },
            },
            '}' => switch (state) {
                .in_text => {},
                .in_escape_text => {},
                // FIXME: not handling this specially means the variable text "{my\}var}"
                // will refer to variable "my\}var" and that it is not possible to refer
                // to a variable with a }, which is a bug that I'm ok with leaving in for now
                .in_escape_var => {
                    state = .in_var;
                },
                .in_var => {
                    const var_name = section;
                    const var_value = vars.get(var_name) orelse return error.NoSuchVar;
                    _ = try writer.write(var_value);
                    section_start = i + 1;
                    state = .in_text;
                },
            },
            else => {},
        }
    }

    _ = try writer.write(template[section_start..]);

    return try chunk_writer.concat(alloc);
}

test "correctly interpolate many" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    try vars.put("begin", "hello");
    try vars.put("middle", "how do you do");
    try vars.put("next_to", "?");
    try vars.put("end", " goodbye");
    defer vars.deinit();

    var actual = try interpolate_template(
        "{begin}, {middle}{next_to} \\{...and{end}}. the end",
        std.testing.allocator,
        &vars
    );

    defer std.testing.allocator.free(actual);

    // FIXME: note that escape handling is broken, it's not hard to fix but I'm lazy and have too much to do
    try std.testing.expectEqualStrings("hello, how do you do? \\{...and goodbye}. the end", actual);
}

