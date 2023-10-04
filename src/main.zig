const std = @import("std");
const json = std.json;
const t = std.testing;
const Result = @import("./result.zig").Result;

const Index = usize;

const Next = packed struct {
  valid: bool = false,
  value: u31 = undefined,
};

test "Next is u32" {
  try t.expectEqual(@bitSizeOf(Next), 32);
}

const Node = union (enum) {
  line: struct {
    text: []const u8 = "",
    // TODO: should this be optional?
    metadata: []const u8 = "",
    next: Next,
  },
  randomSwitch: struct {
    nexts: []const Next, // does it make sense for these to be optional?
    chances: []const u32,
  },
  reply: struct {
    nexts: []const Next, // does it make sense for these to be optional?
    /// utf8 assumed
    texts: []const u8,
  },
  lock: struct {
    booleanVariableIndex: Index,
    next: Next,
  },
  unlock: struct {
    booleanVariableIndex: Index,
    next: Next,
  },
  call: struct {
    functionIndex: Index,
    next: Next,
  },
  goto: struct {
    next: Next,
  },

  pub fn execute(self: @This(), ctx: *DialogueContext) void {
    switch (self.data) {
      .line => {},
      .randomSwitch => {},
      .reply => {},
      .lock => {},
      .unlock => {},
      .call => {},
      // does it make sense for self.next to be invalid?
      .goto => { ctx.currentNode = self.next.value; },
    }
  }
};

/// A function implemented by the environment
const Callback = *fn() void;

/// The possible types for a variable
const VariableType = enum {
  /// also known as "text"
  string,
  /// also known as "true/false"
  boolean,
};

pub const DialogueContext = struct {
  nodes: std.MultiArrayList(Node),
  callbacks: []const Callback,
  variables: struct {
    /// has upper size bound of Index
    strings: []u8,
    /// has upper size bound of Index
    booleans: []bool,
  },

  currentNode: usize,

  pub fn initFromJson(json_text: []const u8, alloc: std.mem.Allocator) Result(DialogueContext) {
    var r = Result(DialogueContext).err("not initialized");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // allocator for temporary allocations, for permanent ones, use the 'alloc' parameter
    const arena_alloc = arena.allocator();

    var json_diagnostics = json.Diagnostics{};
    var json_reader = json.Scanner.initCompleteInput(arena_alloc, json_text);
    json_reader.enableDiagnostics(&json_diagnostics);

    const dialogue_data = json.parseFromTokenSourceLeaky(DialogueJsonFormat, arena_alloc, &json_reader, .{
      .ignore_unknown_fields = true,
    }) catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}: {}", .{e, json_diagnostics}); return r; };

    var nodes = std.MultiArrayList(Node){};
    defer if (r.is_err()) nodes.deinit(alloc);
    nodes.ensureTotalCapacity(alloc, dialogue_data.nodes.len)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    r = Result(DialogueContext).ok(.{
      // FIXME:
      .nodes = nodes,
      .callbacks = &.{},
      .variables = .{
        .strings = &.{},
        .booleans = &.{},
      },
      .currentNode = 0,
    });

    return r;
  }

  pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodes.deinit(alloc);
    // FIXME:
    // alloc.free(self.callbacks);
    // alloc.free(self.variables.strings);
    // alloc.free(self.variables.booleans);
  }
};

// FIXME: I think it would be better to replace this with a custom
// json parsing routine
const DialogueJsonFormat = struct {
  nodes: []const struct {
    type: []const u8,
    id: u64,
  },
  edges: []const []const u64,
};

test "create and run context to completion" {
  // FIXME: load from tests/dir
  var ctx_result = DialogueContext.initFromJson(
    \\{
    \\  "nodes": [
    \\    {"type": "entry", "id": 0},
    \\    {"type": "line", "id": 1}
    \\  ],
    \\  "edges": [
    \\    [0, 1]
    \\  ]
    \\}
    , t.allocator
  );
  defer if (ctx_result.is_ok()) ctx_result.value.deinit(t.allocator)
    // FIXME: need custom freeing logic
    else t.allocator.free(@constCast(ctx_result.err.?));

  if (ctx_result.is_err())
    std.debug.print("err: '{s}'", .{ctx_result.err.?});
  try t.expect(ctx_result.is_ok());
}
