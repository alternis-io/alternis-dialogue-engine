const std = @import("std");
const json = std.json;
const t = std.testing;
const Result = @import("./result.zig").Result;

const Index = usize;

const Next = packed struct {
  valid: bool = false,
  value: u31 = undefined,

  pub fn fromOptionalInt(int: anytype) Next {
    @setRuntimeSafety(true);
    return Next{
      .valid = int != null,
      .value = @intCast(int.?),
    };
  }
};

test "Next is u32" {
  try t.expectEqual(@bitSizeOf(Next), 32);
}

const DialogueEntry = struct {
  speaker: []const u8,
  text: []const u8,
  metadata: ?[]const u8 = null,
};

const Node = union (enum) {
  line: struct {
    data: DialogueEntry,
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
    strings: [][]const u8,
    // FIXME: use a dynamic bitset
    /// has upper size bound of Index
    booleans: std.DynamicBitSet,
  },

  currentNodeIndex: usize,

  pub const Option = struct {
    speaker: []const u8,
    text: []const u8,
  };

  // FIXME: the alignments are stupid large here
  pub const StepResult = union (enum) {
    none,
    options: []Option,
    line: DialogueEntry,
  };

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

    for (dialogue_data.nodes) |json_node| {
      const maybe_node = json_node.toNode();
      if (maybe_node) |node| {
        nodes.append(alloc, node)
          catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };
      } else {
        r = Result(DialogueContext).fmt_err(alloc, "{s}", .{"invalid node without type or data"});
        return r;
      }
    }

    var booleans = std.DynamicBitSet.initEmpty(alloc, 0)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    var strings = alloc.alloc([]const u8, 0)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    var callbacks = alloc.alloc(Callback, 0)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    r = Result(DialogueContext).ok(.{
      // FIXME:
      .nodes = nodes,
      .callbacks = callbacks,
      .variables = .{
        .strings = strings,
        .booleans = booleans,
      },
      .currentNodeIndex = 0,
    });

    return r;
  }

  fn currentNode(self: @This()) Node {
    return self.nodes.get(self.currentNodeIndex);
  }

  pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodes.deinit(alloc);
    alloc.free(self.callbacks);
    alloc.free(self.variables.strings);
    self.variables.booleans.deinit();
  }

  pub fn step(self: *@This()) StepResult {
    while (true) {
      switch (self.currentNode()) {
        .line => |n| {
          // FIXME: this technically makes it mean nextNodeIndex!
          self.currentNodeIndex = n.next.value;
          return .{ .line = n.data };
        },
        .randomSwitch => {},
        .reply => {},
        .lock => {},
        .unlock => {},
        .call => {},
        // does it make sense for self.next to be invalid?
        .goto => |n| { self.currentNodeIndex = n.next.value; },
      }
    }
  }
};

// FIXME: I think it would be more efficient to replace this with a custom json parsing routine
const DialogueJsonFormat = struct {
  nodes: []const struct {
    id: u64,

    // FIXME: these must be in sync with the implementation of Node!
    // TODO: generate these from Node...
    // perhaps a comptime function that takes a union and turns it into this kind of struct with an
    // appropriate `jsonParse` function is the way to do it
    line: ?@typeInfo(Node).Union.fields[0].type = null,
    randomSwitch: ?@typeInfo(Node).Union.fields[1].type = null,
    reply: ?@typeInfo(Node).Union.fields[2].type = null,
    lock: ?@typeInfo(Node).Union.fields[3].type = null,
    unlock: ?@typeInfo(Node).Union.fields[4].type = null,
    call: ?@typeInfo(Node).Union.fields[5].type = null,
    goto: ?@typeInfo(Node).Union.fields[6].type = null,

    fn toNode(self: @This()) ?Node {
      if (self.line) |v| return .{.line = v};
      if (self.randomSwitch) |v| return .{.randomSwitch = v};
      if (self.reply) |v| return .{.reply = v};
      if (self.lock) |v| return .{.lock = v};
      if (self.unlock) |v| return .{.unlock = v};
      if (self.call) |v| return .{.call = v};
      if (self.goto) |v| return .{.goto = v};
      return null;
    }
  },

  edges: []const []const u64,
};

test "create and run context to completion" {
  // FIXME: load a larger one from tests dir
  var ctx_result = DialogueContext.initFromJson(
    \\{
    \\  "nodes": [
    \\    {"type": "entry", "id": 0},
    \\    {"type": "line", "id": 1, "data": { "line": {
    \\      "speaker": "hello",
    \\      "text": "hello world!"
    \\    }}}
    \\  ],
    \\  "edges": [
    \\    [0, 1]
    \\  ]
    \\}
    , t.allocator
  );
  defer if (ctx_result.is_ok()) ctx_result.value.deinit(t.allocator);
    // FIXME: need to add freeing logic to Result
    //else t.allocator.free(@constCast(ctx_result.err.?));

  if (ctx_result.is_err())
    std.debug.print("err: '{s}'", .{ctx_result.err.?});
  try t.expect(ctx_result.is_ok());

  var ctx = ctx_result.value;
  // REPORTME: inlining expected causes comptiler alignment cast error
  const expected = DialogueContext.StepResult{
    .line = .{
      .speaker = "test",
      .text = "hello world!",
    },
  };
  _ = ctx.step();
  try t.expectEqual(expected, ctx.step());
  try t.expectEqual(@as(usize, 1), ctx.currentNodeIndex);
}
