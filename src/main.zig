const std = @import("std");
const json = std.json;
const t = std.testing;

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
      .goto => { ctx.currentNode = self.next.value },
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

  pub fn initFromJson(json: []const u8, al: std.mem.Allocator) DialogueContext {
    return .{
      .nodes = std.MultiArrayList(Node){},
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

  t.expect(ctx.result.is_ok());
}
