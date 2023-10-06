const std = @import("std");
const builtin = @import("builtin");
const t = std.testing;

const Api = @import("./main.zig");
const Slice = @import("./slice.zig").Slice;
const OptSlice = @import("./slice.zig").OptSlice;

const ConfigurableSimpleAlloc = @import("./simple_alloc.zig").ConfigurableSimpleAlloc;
var configured_raw_alloc: ?ConfigurableSimpleAlloc = null;
var alloc: std.mem.Allocator =
    if (builtin.os.tag == .freestanding and builtin.target.cpu.arch == .wasm32)
        std.heap.wasm_allocator
    else std.testing.failing_allocator;

export fn ade_set_alloc(
    in_malloc: *const fn(usize) callconv(.C) ?*anyopaque,
    in_free: *const fn(?*anyopaque) callconv(.C) void,
) void {
    configured_raw_alloc = ConfigurableSimpleAlloc.init(in_malloc, in_free);
    alloc = configured_raw_alloc.?.allocator();
}

pub fn setZigAlloc(in_alloc: std.mem.Allocator) void {
    alloc = in_alloc;
}

export fn ade_dialogue_ctx_create_json(json_ptr: [*]const u8, json_len: usize, err: ?*?[*:0]const u8) ?*Api.DialogueContext {
    const ctx_result = Api.DialogueContext.initFromJson(json_ptr[0..json_len], alloc, .{});

    // FIXME: better return err (e.g. this leaks)
    if (ctx_result.is_err() and err != null) {
        err.?.* = ctx_result.err.?.ptr;
        return null;
    }

    var ctx_slot = alloc.create(Api.DialogueContext)
        catch |e| std.debug.panic("alloc error: {}", .{e});
    ctx_slot.* = ctx_result.value;

    return ctx_slot;
}

export fn ade_dialogue_ctx_destroy(dialogue_ctx: ?*Api.DialogueContext) void {
    if (dialogue_ctx) |ptr| {
        ptr.deinit(alloc);
        alloc.destroy(ptr);
    }
}

// FIXME: extern'ing slices (this way) is ugly..
const Line = extern struct {
    speaker: Slice(u8),
    text: Slice(u8),
    metadata: OptSlice(u8),
};

const StepResult = extern struct {
    /// tag indicates which field is active
    tag: enum (u8) {
        none = 0,
        options = 1,
        line = 2,
    } = .none,

    /// data for each field
    data: extern union {
        none: void,
        options: extern struct {
            texts: Slice(Slice(u8)),
        },
        line: Line,
    } = undefined,
};

export fn ade_dialogue_ctx_step(dialogue_ctx: *Api.DialogueContext, result_loc: ?*StepResult) void {
    std.debug.assert(result_loc != null);

    const result = dialogue_ctx.step();

    result_loc.?.* = switch (std.meta.activeTag(result)) {
        // FIXME: surely there is a better way to do this? maybe using @tagName and inline else?
        //inline else => |_, tag| @tagName(tag),
        .none => .{ .tag = .none },
        .line => .{ .tag = .line, .data = .{ .line = .{
            .speaker = Slice(u8).fromZig(result.line.speaker),
            .text = Slice(u8).fromZig(result.line.text),
            .metadata = OptSlice(u8).fromZig(result.line.metadata),
        } } },
        .options => .{ .tag = .options, .data = .{ .options = .{
            .texts = Slice(Slice(u8)).fromZig(result.options.texts),
        } } },
    };
}

// for now this just invokes failing allocator and panics...
// test "create context without allocator set fails" {
//     const dialogue = "{}";
//     try t.expectEqual(@as(?*Api.DialogueContext, null), ade_dialogue_ctx_create_json(dialogue.ptr, dialogue.len));
// }

test "c_api smoke test" {
    setZigAlloc(std.testing.allocator);

    var ctx = ade_dialogue_ctx_create_json(Api.small_test_json.ptr, Api.small_test_json.len);
    try t.expect(ctx != null);
    defer ade_dialogue_ctx_destroy(ctx.?);

    var step_result: StepResult = undefined;
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
    try t.expect(step_result.tag == .none);
    try t.expectEqual(@as(?usize, null), ctx.?.current_node_index);
}
