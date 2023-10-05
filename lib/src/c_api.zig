const std = @import("std");
const t = std.testing;

const DialogueContext = @import("./main.zig").DialogueContext;

const ConfigurableSimpleAlloc = @import("./simple_alloc.zig").ConfigurableSimpleAlloc;
var alloc: ?ConfigurableSimpleAlloc = null;

export fn ade_set_alloc(
    in_malloc: *fn(usize) ?*anyopaque,
    in_free: *fn(?*anyopaque) void,
) void {
    alloc = ConfigurableSimpleAlloc.init(in_malloc, in_free);
}

export fn ade_dialogue_ctx_create_json(json_ptr: [*]const u8, json_len: usize) ?*DialogueContext {
    // FIXME: use a result type? or panic?
    if (alloc == null)
        return null;

    const ctx_result = DialogueContext.initFromJson(json_ptr[0..json_len], alloc.?.allocator(), .{});
    if (ctx_result.is_err())
        return null;

    var ctx_slot = alloc.?.allocator().create(DialogueContext)
        catch |e| std.debug.panic("alloc error: {}", .{e});
    ctx_slot.* = ctx_result.value;

    return ctx_slot;
}

test "create context without allocator set fails" {
    t.expectEqual(null, ade_dialogue_ctx_create_json("{}", 2));
}

