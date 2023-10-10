const std = @import("std");
const builtin = @import("builtin");
const t = std.testing;

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

export fn ade_dialogue_ctx_create_json(
    json_ptr: [*]const u8,
    json_len: usize,
    random_seed: u64,
    no_interpolate: bool,
    err: ?*?[*:0]const u8
) ?*Api.DialogueContext {
    const ctx_result = Api.DialogueContext.initFromJson(
        json_ptr[0..json_len],
        alloc,
        .{
            .random_seed = random_seed,
            .no_interpolate = no_interpolate
        },
    );

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

export fn ade_dialogue_ctx_reset(dialogue_ctx: ?*Api.DialogueContext) void {
    if (dialogue_ctx) |ptr| {
        ptr.reset();
    }
}

export fn ade_dialogue_ctx_reply(dialogue_ctx: ?*Api.DialogueContext, replyId: usize) void {
    if (dialogue_ctx) |ptr| {
        ptr.reply(replyId);
    }
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

const StepResult = extern struct {
    /// tag indicates which field is active
    tag: enum (u8) {
        none = 0,
        options = 1,
        line = 2,
        function_called = 3,
    } = .none,

    /// data for each field
    data: extern union {
        none: void,
        options: extern struct {
            /// this should be allocated explicitly due to having to convert the Line
            texts: Slice(Line),
        },
        line: Line,
    } = undefined,

    pub fn free() void {

    }
};

export fn ade_dialogue_ctx_step(dialogue_ctx: *Api.DialogueContext, result_loc: ?*StepResult) void {
    std.debug.assert(result_loc != null);

    const result = dialogue_ctx.step();

    result_loc.?.* = switch (std.meta.activeTag(result)) {
        // FIXME: surely there is a better way to do this?
        .line => .{ .tag = .line, .data = .{ .line = Line.fromZig(result.line) } },
        .options => _: {
            const texts = alloc.alloc(Line, result.options.texts.len);
            for (result.options.texts, texts) |src, *dst| dst.* = Line.fromZig(src);
            break :_ .{
                .tag = .options,
                .data = .{ .options = .{
                    .texts = texts
                } },
            };
        },
        .none => .{ .tag = .none },
        .function_called => .{ .tag = .function_called },
    };
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

    var ctx = ade_dialogue_ctx_create_json(src.buffer.ptr, src.buffer.len, 0, null);
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
