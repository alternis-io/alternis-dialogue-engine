const std = @import("std");
const builtin = @import("builtin");
const t = std.testing;
const usz = @import("./config.zig").usz;

extern fn _debug_print([*]const u8, len: usize) void;
// fn _debug_print(ptr: [*]const u8, len: usize) void {
//     std.debug.print("{s}\n", .{ptr[0..len]});
// }

const Api = @import("./main.zig");
const Slice = @import("./slice.zig").Slice;
const OptSlice = @import("./slice.zig").OptSlice;
const FileBuffer = @import("./FileBuffer.zig");

const ConfigurableSimpleAlloc = @import("./simple_alloc.zig").ConfigurableSimpleAlloc;
var configured_raw_alloc: ?ConfigurableSimpleAlloc = null;
var alloc: std.mem.Allocator =
    if (builtin.os.tag == .freestanding and builtin.target.cpu.arch == .wasm32)
    std.heap.wasm_allocator
else
    std.testing.failing_allocator;

// FIXME: read https://nullprogram.com/blog/2023/12/17/
export fn ade_set_alloc(
    in_malloc: *const fn (usize) callconv(.C) ?*anyopaque,
    in_free: *const fn (?*anyopaque) callconv(.C) void,
) void {
    configured_raw_alloc = ConfigurableSimpleAlloc.init(in_malloc, in_free);
    alloc = configured_raw_alloc.?.allocator();
}

/// the the allocator directly, possible from zig code
pub fn setZigAlloc(in_alloc: std.mem.Allocator) void {
    alloc = in_alloc;
}

export fn ade_dialogue_ctx_create_json(json_ptr: [*]const u8, json_len: usize, random_seed: u64, no_interpolate: bool, err: ?*?[*:0]const u8) ?*Api.DialogueContext {
    const ctx_result = Api.DialogueContext.initFromJson(
        json_ptr[0..json_len],
        alloc,
        .{ .random_seed = random_seed, .no_interpolate = no_interpolate },
    );

    // FIXME: better return err (e.g. this leaks)
    if (ctx_result.is_err() and err != null) {
        err.?.* = ctx_result.err.?.ptr;
        return null;
    }

    var ctx_slot = alloc.create(Api.DialogueContext) catch |e| std.debug.panic("alloc error: {}", .{e});
    ctx_slot.* = ctx_result.value;

    return ctx_slot;
}

export fn ade_dialogue_ctx_destroy(in_dialogue_ctx: ?*Api.DialogueContext) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.deinit(alloc);
    alloc.destroy(ctx);
}

export fn ade_dialogue_ctx_reset(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usize, node_index: usize) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.reset(node_index, dialogue_id);
}

export fn ade_dialogue_ctx_reply(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usize, reply_id: usize) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.reply(reply_id, dialogue_id);
}

export fn ade_dialogue_ctx_get_node_by_label(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usize, label_ptr: [*]const u8, label_len: usize) usize {
    const ctx = in_dialogue_ctx orelse unreachable;
    return ctx.getNodeByLabel(dialogue_id, label_ptr[0..label_len]) orelse unreachable; // FIXME: return -1?
}

/// the passed in pointers must exist as long as this is set
export fn ade_dialogue_ctx_set_variable_boolean(
    in_dialogue_ctx: ?*Api.DialogueContext,
    name: [*]const u8,
    len: usize,
    value: bool,
) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.setVariableBoolean(name[0..len], value);
}

/// the passed in pointers must exist as long as this is set
export fn ade_dialogue_ctx_set_variable_string(
    in_dialogue_ctx: ?*Api.DialogueContext,
    name: [*]const u8,
    len: usize,
    value_ptr: [*]const u8,
    value_len: usize,
) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.setVariableString(name[0..len], value_ptr[0..value_len]);
}

/// the passed in pointers must exist as long as this is set
export fn ade_dialogue_ctx_set_callback(
    in_dialogue_ctx: ?*Api.DialogueContext,
    name: [*]const u8,
    len: usize,
    function: *const fn (?*anyopaque) callconv(.C) void,
    payload: ?*anyopaque,
) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.setCallback(name[0..len], .{ .function = function, .payload = payload });
}

/// the passed in pointers must exist as long as this is set
export fn ade_dialogue_ctx_set_all_callbacks(
    in_dialogue_ctx: ?*Api.DialogueContext,
    function: *const fn (*Api.DialogueContext.SetAllCallbacksPayload) callconv(.C) void,
    /// stored into SetAllCallbacksPayload.inner_payload
    inner_payload: ?*anyopaque,
) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.setAllCallbacks(.{ .function = @ptrCast(function), .payload = inner_payload });
}

const Line = extern struct {
    speaker: Slice(u8),
    text: Slice(u8),
    metadata: OptSlice(u8),

    pub fn fromZig(zig_line: Api.Line) @This() {
        return @This(){
            .speaker = Slice(u8).fromZig(zig_line.speaker),
            .text = Slice(u8).fromZig(zig_line.text),
            .metadata = OptSlice(u8).fromZig(zig_line.metadata),
        };
    }
};

export fn ade_dialogue_ctx_step(dialogue_ctx: *Api.DialogueContext, dialogue_id: usz, result_loc: ?*Api.DialogueContext.StepResult) void {
    std.debug.assert(result_loc != null);
    result_loc.?.* = dialogue_ctx.step(dialogue_id);
}

// for now this just invokes failing allocator and panics...
// test "create context without allocator set fails" {
//     const dialogue = "{}";
//     try t.expectEqual(@as(?*Api.DialogueContext, null), ade_dialogue_ctx_create_json(dialogue.ptr, dialogue.len));
// }

// FIXME: source json from same file as main.zig tests
test "run small dialogue under c api" {
    setZigAlloc(t.allocator);

    const src = try FileBuffer.fromDirAndPath(t.allocator, std.fs.cwd(), "./test/assets/simple1.alternis.json");
    defer src.free(t.allocator);

    var ctx = ade_dialogue_ctx_create_json(src.buffer.ptr, src.buffer.len, 0, false, null);
    try t.expect(ctx != null);
    defer ade_dialogue_ctx_destroy(ctx.?);

    var step_result: Api.DialogueContext.StepResult = undefined;
    ade_dialogue_ctx_step(ctx.?, &step_result);
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("hello world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, 1), ctx.?.current_node_index);

    ade_dialogue_ctx_step(ctx.?, &step_result);
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("goodbye cruel world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, null), ctx.?.current_node_index);

    ade_dialogue_ctx_step(ctx.?, &step_result);
    try t.expect(step_result.tag == .done);
    try t.expectEqual(@as(?usize, null), ctx.?.current_node_index);
}
