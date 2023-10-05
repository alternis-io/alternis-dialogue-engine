const std = @import("std");
const t = std.testing;

const Api = @import("./main.zig");

const ConfigurableSimpleAlloc = @import("./simple_alloc.zig").ConfigurableSimpleAlloc;
var alloc: ?ConfigurableSimpleAlloc = null;

export fn ade_set_alloc(
    in_malloc: *const fn(usize) callconv(.C) ?*anyopaque,
    in_free: *const fn(?*anyopaque) callconv(.C) void,
) void {
    alloc = ConfigurableSimpleAlloc.init(in_malloc, in_free);
}

export fn ade_dialogue_ctx_create_json(json_ptr: [*]const u8, json_len: usize) ?*Api.DialogueContext {
    // FIXME: use a result type? or panic?
    if (alloc == null)
        return null;

    const ctx_result = Api.DialogueContext.initFromJson(json_ptr[0..json_len], alloc.?.allocator(), .{});
    // FIXME: log/set/return error somewhere!
    if (ctx_result.is_err())
        return null;

    var ctx_slot = alloc.?.allocator().create(Api.DialogueContext)
        catch |e| std.debug.panic("alloc error: {}", .{e});
    ctx_slot.* = ctx_result.value;

    return ctx_slot;
}

export fn ade_dialogue_ctx_destroy(dialogue_ctx: ?*Api.DialogueContext) void {
    if (dialogue_ctx) |ptr|
        alloc.?.allocator().destroy(ptr);
}

const Line = extern struct {
    speaker_ptr: [*]const u8,
    speaker_len: usize = 0,
    text_ptr: [*]const u8,
    text_len: usize = 0,
    metadata: ?[*]const u8,
    metadata_len: usize = 0,
};

// FIXME: is it really better to have to convert all this instead of just making the api
// internal layout extern compatible?
const StepResult = extern struct {
    /// tag indicates which field is active
    tag: enum (u8) {
        none,
        options,
        line,
    } = .none,

    /// data for each field
    data: extern union {
        none: void,
        options: extern struct {
            texts: [*]const u8,
            texts_len: usize,
        },
        line: Line,
    } = undefined,
};

export fn ade_dialogue_ctx_step(dialogue_ctx: *Api.DialogueContext) StepResult {
    const result = dialogue_ctx.step();
    return switch (std.meta.activeTag(result)) {
        // FIXME: surely there is a better way to do this? maybe using @tagName and inline else?
        //inline else => |_, tag| @tagName(tag),
        .none => .{ .tag = .none },
        .line => .{ .tag = .line, .data = .{ .line = .{
            .speaker_ptr = result.line.speaker.ptr,
            .speaker_len = result.line.speaker.len,
            .text_ptr = result.line.text.ptr,
            .text_len = result.line.text.len,
            .metadata = if (result.line.metadata) |m| m.ptr else null,
            .metadata_len = if (result.line.metadata) |m| m.len else 0,
        } } },
        .options => .{ .tag = .options, .data = .{ .options = .{
            .texts = result.options.texts.ptr,
            .texts_len = result.options.texts.len,
        } } },
    };
}

test "create context without allocator set fails" {
    const dialogue = "{}";
    try t.expectEqual(@as(?*Api.DialogueContext, null), ade_dialogue_ctx_create_json(dialogue.ptr, dialogue.len));
}

test "c_api smoke test" {
    ade_set_alloc(std.c.malloc, std.c.free);

    var ctx = ade_dialogue_ctx_create_json(Api.small_test_json.ptr, Api.small_test_json.len);
    try t.expect(ctx != null);
    defer ade_dialogue_ctx_destroy(ctx.?);

    const step_result_1 = ade_dialogue_ctx_step(ctx.?);
    try t.expect(step_result_1.tag == .line);
    try t.expectEqualStrings("test", step_result_1.data.line.speaker_ptr[0..step_result_1.data.line.speaker_len]);
    try t.expectEqualStrings("hello world!", step_result_1.data.line.text_ptr[0..step_result_1.data.line.text_len]);
    try t.expectEqual(@as(?usize, 1), ctx.?.current_node_index);

    const step_result_2 = ade_dialogue_ctx_step(ctx.?);
    try t.expect(step_result_2.tag == .line);
    try t.expectEqualStrings("test", step_result_2.data.line.speaker_ptr[0..step_result_2.data.line.speaker_len]);
    try t.expectEqualStrings("goodbye cruel world!", step_result_2.data.line.text_ptr[0..step_result_2.data.line.text_len]);
    try t.expectEqual(@as(?usize, null), ctx.?.current_node_index);

    const step_result_3 = ade_dialogue_ctx_step(ctx.?);
    try t.expect(step_result_3.tag == .none);
    try t.expectEqual(@as(?usize, null), ctx.?.current_node_index);
}
