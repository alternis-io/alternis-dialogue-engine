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
    // note this is intended to be overridden by a call to ade_set_alloc
    // FIXME: a null allocator state which yields a custom error is in order
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

/// set the allocator directly, useful when using the c_api and zig code (e.g. tests)
pub fn setZigAlloc(in_alloc: std.mem.Allocator) void {
    alloc = in_alloc;
}

const _InitDlgReturnType = @TypeOf(Api.DialogueContext.initFromJson).ReturnType;
const _InitDlgErrorType = @typeInfo(_InitDlgReturnType).ErrorUnion.error_set;

pub const DiagnosticErrors = enum(c_int) {
    NoError = 0,

    OutOfMemory = 1,

    MissingField = 2,
    UnexpectedToken = 3,

    AlternisUnknownVersion = 4,
    AlternisBadNextNode = 5,
    AlternisInvalidNode = 6,
    AlternisDefaultSeedUnsupportedPlatform = 7,

    pub fn fromZig(err: _InitDlgErrorType) @This() {
        return switch (err) {
            error.OutOfMemory => .OutOfMemory,
            error.MissingField => .MissingField,
            error.UnexpectedToken => .UnexpectedToken,
            error.AlternisUnknownVersion => .AlternisUnknownVersion,
            error.AlternisBadNextNode => .AlternisBadNextNode,
            error.AlternisInvalidNode => .AlternisInvalidNode,
            error.AlternisDefaultSeedUnsupportedPlatform => .AlternisDefaultSeedUnsupportedPlatform,
        };
    }
};

pub const Diagnostic = extern struct {
    // copied from Api.DialogueContext.Diagnostic
    _needs_free: bool = false,
    error_code: DiagnosticErrors = .NoError,
    error_message: Slice(u8) = undefined,

    pub export fn ade_diagnostic_destroy(maybe_self: ?*@This()) void {
        if (maybe_self) |self| {
            const zig_diagnostic = Api.DialogueContext.Diagnostic{
                .error_message = self.error_message,
                ._needs_free = self._needs_free,
            };
            zig_diagnostic.free(alloc);
        }
    }

    pub fn fromZigErr(
        err: _InitDlgErrorType,
        zig_diagnostic: Api.DialogueContext.Diagnostic,
    ) @This() {
        var result = Diagnostic{};
        result.error_code = DiagnosticErrors.fromZig(err);
        result.error_message = zig_diagnostic.error_message;
        result._needs_free = zig_diagnostic._needs_free;
        return result;
    }
};

/// when returning null, the diagnostic will be set with an error code
pub export fn ade_dialogue_ctx_create_json(
    json_ptr: [*]const u8,
    json_len: usize,
    random_seed: u64,
    no_interpolate: bool,
    c_diagnostic: *Diagnostic,
) ?*Api.DialogueContext {
    c_diagnostic.error_code = .NoError;
    var zig_diagnostic = Diagnostic{};

    const ctx_result = Api.DialogueContext.initFromJson(
        json_ptr[0..json_len],
        alloc,
        .{ .random_seed = random_seed, .no_interpolate = no_interpolate },
        &zig_diagnostic,
    ) catch |e| return {
        c_diagnostic.* = Diagnostic.fromZigErr(e, zig_diagnostic);
        return null;
    };

    errdefer ctx_result.deinit(alloc);

    const ctx_slot = alloc.create(Api.DialogueContext) catch |e| {
        c_diagnostic.*.error_message = "failed to allocate, see error code";
        c_diagnostic.*.error_code = DiagnosticErrors.fromZig(e);
        c_diagnostic.*._needs_free = false;
    };
    ctx_slot.* = ctx_result;

    return ctx_slot;
}

export fn ade_dialogue_ctx_destroy(in_dialogue_ctx: ?*Api.DialogueContext) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.deinit(alloc);
    alloc.destroy(ctx);
}

export fn ade_dialogue_ctx_reset(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usz, node_index: usz) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.reset(node_index, dialogue_id);
}

export fn ade_dialogue_ctx_reply(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usz, reply_id: usize) void {
    const ctx = in_dialogue_ctx orelse return;
    ctx.reply(dialogue_id, reply_id);
}

export fn ade_dialogue_ctx_get_node_by_label(in_dialogue_ctx: ?*Api.DialogueContext, dialogue_id: usz, label_ptr: [*]const u8, label_len: usize) usz {
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

// FIXME; store internal Line as extern and use functions to get zig slices
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
    (result_loc orelse return).* = dialogue_ctx.step(dialogue_id);
}

// export fn ade_diagnostic_destroy(in_diagnostic: ?*Api.DialogueContext.Diagnostic) void {
// (in_diagnostic orelse return).free(alloc);
// }

// for now this just invokes failing allocator and panics...
test "create context without allocator set fails" {
    const dialogue = "{}";
    try t.expectEqual(@as(?*Api.DialogueContext, null), ade_dialogue_ctx_create_json(dialogue.ptr, dialogue.len));
}

// FIXME: source json from same file as main.zig tests
test "run small dialogue under c api" {
    setZigAlloc(t.allocator);

    const src = try FileBuffer.fromDirAndPath(t.allocator, std.fs.cwd(), "./test/assets/simple1.alternis.json");
    defer src.free(t.allocator);

    var err: ?[*:0]const u8 = null;
    var ctx = ade_dialogue_ctx_create_json(src.buffer.ptr, src.buffer.len, 0, false, &err);
    if (err) |err_str| {
        std.debug.print("err: {s}", .{err_str});
    }
    try t.expectEqual(err, null);
    try t.expect(ctx != null);
    defer ade_dialogue_ctx_destroy(ctx.?);

    var step_result: Api.DialogueContext.StepResult = undefined;
    ade_dialogue_ctx_step(ctx.?, 0, &step_result);
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("hello world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usz, 1), ctx.?.getCurrentNodeIndex(0));

    ade_dialogue_ctx_step(ctx.?, 0, &step_result);
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("goodbye cruel world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usz, null), ctx.?.getCurrentNodeIndex(0));

    ade_dialogue_ctx_step(ctx.?, 0, &step_result);
    try t.expect(step_result.tag == .done);
    try t.expectEqual(@as(?usz, null), ctx.?.getCurrentNodeIndex(0));
}
