const std = @import("std");
const json = std.json;
const t = std.testing;
const Result = @import("./result.zig").Result;

const Index = usize;

const Next = packed struct {
  valid: u1 = false,
  value: u31 = undefined,
};

const Node = packed union {
  line: packed struct {
    text: []const u8 = "",
    // TODO: should this be optional?
    metadata: []const u8 = "",
    next: Next,
  },
  randomSwitch: packed struct {
    nexts: []const Next, // does it make sense for these to be optional?
    chances: []const u32,
  },
  reply: packed struct {
    nexts: []const Next, // does it make sense for these to be optional?
    /// utf8 assumed
    texts: []const u8,
  },
  lock: packed struct {
    booleanVariableIndex: Index,
    next: Next,
  },
  unlock: packed struct {
    booleanVariableIndex: Index,
    next: Next,
  },
  call: packed struct {
    functionIndex: Index,
    next: Next,
  },
  goto: packed struct {
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
const Callback = fn() void;

/// The possible types for a variable
const VariableType = enum {
  /// also known as "text"
  string,
  /// also known as "true/false"
  boolean,
};

pub const DialogueContext = struct {
  entryNodeIndex: usize,
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // allocator for temporary allocations, for permanent ones, use the 'alloc' parameter
    const arena_alloc = arena.allocator();

    var json_diagnostics = json.Diagnostics{};
    var json_reader = json.Scanner.initCompleteInput(arena_alloc, json_text);
    json_reader.enableDiagnostics(&json_diagnostics);

    const dialogue_data = json.parseFromTokenSourceLeaky(DialogueJsonFormat, arena_alloc, &json_reader, .{
        .ignore_unknown_fields = true,
    }) catch |e| return Result(DialogueContext).fmt_err(alloc, "{}: {}", .{e, json_diagnostics});

    var nodes = std.MultiArrayList(Node){};
    nodes.ensureTotalCapacity(dialogue_data.nodes.len);

    return .{
      .nodes = nodes,
      .callbacks = &.{},
    };
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
  const ctx_result = DialogueContext.initFromJson(
    \\{
    \\  "nodes": [
    \\    {"type": "entry", "id": 0},
    \\    {"type": "line", "id": 1}
    \\  ],
    \\  "edges": [
    \\    [0, 1]
    \\  ],
    \\}
  );

  t.expect(ctx_result.is_ok());
}
