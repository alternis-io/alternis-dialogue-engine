const std = @import("std");
const json = std.json;
const t = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

export fn alternis_set_allocators(
    malloc: *fn(c_uint) *anyopaque,
    free: *fn(*anyopaque) void,
    realloc: *fn(*anyopaque, c_uint) *anyopaque
) void {
    _ = malloc;
    _ = free;
    _ = realloc;
}

const Variable = union (enum) {

};

export fn alternis_dlgctx_create_json(json: string) *DialogueContext {
    _ = json;
}

export fn alternis_dlgctx_create_json(json: string) *DialogueContext {
    _ = json;
}


test "basic add functionality" {
    try t.expect(add(3, 7) == 10);
}
