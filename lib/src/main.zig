const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const t = std.testing;
const Result = @import("./result.zig").Result;
const Slice = @import("./slice.zig").Slice;


// FIXME: only in wasm
extern fn _debug_print([*]const u8, len: usize) void;

fn debug_print(msg: []const u8) void {
    _debug_print(msg.ptr, msg.len);
}

const Index = usize;

/// basically packed ?u31
const Next = packed struct {
  valid: bool = false,
  value: u31 = undefined,

  pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
    if (try source.peekNextTokenType() == .null)
      return .{};
    const value = try json.innerParse(u31, allocator, source, options);
    return .{ .value = value, .valid = true };
  }

  /// for more idiomatic usage in contexts where packing is unimportant
  pub fn toOptionalInt(self: @This(), comptime T: type) ?T {
    return if (!self.valid) null else @intCast(self.value);
  }
};

test "Next is u32" {
  try t.expectEqual(@bitSizeOf(Next), 32);
}

const Line = struct {
  speaker: []const u8,
  text: []const u8,
  metadata: ?[]const u8 = null,
};

const RandomSwitch = struct {
  nexts: []const Next, // does it make sense for these to be optional?
  chances: []const u32,
  total_chances: u64,

  fn init(nexts: []const Next, chances: []const u32) @This() {
    var total_chances: u64 = 0;
    for (chances) |chance| total_chances += chance;
    return .{ .nexts = nexts, .chances = chances, .total_chances = total_chances };
  }
};

const Node = union (enum) {
  line: struct {
    data: Line,
    next: Next = .{},
  },
  random_switch: RandomSwitch,
  reply: struct {
    nexts: []const Next, // does it make sense for these to be optional?
    /// utf8 assumed (uses externable type)
    texts: []const Slice(u8),
  },
  lock: struct {
    booleanVariableIndex: Index,
    next: Next = .{},
  },
  unlock: struct {
    booleanVariableIndex: Index,
    next: Next = .{},
  },
  call: struct {
    functionIndex: Index,
    next: Next = .{},
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
  functions: []const ?Callback,
  variables: struct {
    /// has upper size bound of Index
    strings: [][]const u8,
    // FIXME: use a dynamic bitset
    /// has upper size bound of Index
    booleans: std.DynamicBitSet,
  },

  entry_node_index: usize,
  // FIXME: optimize to fit in usize
  current_node_index: ?usize,

  rand: std.rand.DefaultPrng,

  // FIXME: the alignments are stupid large here
  pub const StepResult = union (enum) {
    none,
    options: struct {
      // FIXME: not as easy to extern-ize
      texts: []const Slice(u8),
    },
    line: Line,
  };

  pub const InitOpts = struct {
    // would it be more space-efficient to require u63? does it matter?
    random_seed: ?u64 = null,
  };

  pub fn initFromJson(
    json_text: []const u8,
    alloc: std.mem.Allocator,
    opts: InitOpts,
  ) Result(DialogueContext) {
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

    var functions = alloc.alloc(Callback, 0)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    const seed = opts.random_seed orelse _: {
      if (builtin.os.tag == .freestanding) {
        r = Result(DialogueContext).fmt_err_src(alloc, "automatic seed not supported on this platform", .{}, @src());
        return r;
      }

      var time: std.os.system.timespec = undefined;
      std.os.clock_gettime(std.os.CLOCK.REALTIME, &time)
        catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };
      const time_seed: u64 = @bitCast(time.tv_nsec);
      break :_ time_seed; 
    };

    r = Result(DialogueContext).ok(.{
      // FIXME:
      .nodes = nodes,
      .functions = functions,
      .variables = .{
        .strings = strings,
        .booleans = booleans,
      },
      .current_node_index = dialogue_data.entryId,
      .entry_node_index = dialogue_data.entryId,
      .rand = std.rand.DefaultPrng.init(seed),
    });

    return r;
  }

  fn currentNode(self: @This()) ?Node {
    return if (self.current_node_index) |index| self.nodes.get(index) else null;
  }

  pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodes.deinit(alloc);
    alloc.free(self.functions);
    alloc.free(self.variables.strings);
    self.variables.booleans.deinit();
  }

  pub fn reset(self: @This()) void {
    self.current_node_index = self.entry_node_index;
  }

  /// if the current node is an options node, choose the reply
  pub fn reply(self: *@This(), reply_index: usize) StepResult {
    const currNode = self.currentNode();
    std.debug.assert(currNode == .reply);
    {
      @setRuntimeSafety(true);
      self.current_node_index = currNode.reply.nexts[reply_index];
    }
    return self.step();
  }

  pub fn step(self: *@This()) StepResult {
    while (true) {
      const current_node = self.currentNode();
      if (current_node == null)
        return .none;

      switch (current_node.?) {
        .line => |v| {
          // FIXME: technically this seems to mean nextNodeIndex!
          self.current_node_index = v.next.toOptionalInt(usize);
          return .{ .line = v.data };
        },
        .random_switch => |v| {
          // guaranteed to be in [0, 1) range
          const shot = self.rand.random().float(f32);
          var acc: u64 = 0;
          for (v.nexts, v.chances) |next, chance_count| {
            const chance_proportion = @as(f64, @floatFromInt(acc))
                                    / @as(f64, @floatFromInt(v.total_chances));
            if (shot < chance_proportion) {
              self.current_node_index = next.toOptionalInt(usize);
              break;
            }
            acc += chance_count;
          }
        },
        .reply => |v| {
          return .{.options = .{ .texts = v.texts }};
        },
        .lock => |v| {
          self.variables.booleans.unset(v.booleanVariableIndex);
          self.current_node_index = v.next.toOptionalInt(usize);
        },
        .unlock => |v| {
          self.variables.booleans.set(v.booleanVariableIndex);
          self.current_node_index = v.next.toOptionalInt(usize);
        },
        .call => |v| {
          if (self.functions[v.functionIndex]) |func| func();
          self.current_node_index = v.next.toOptionalInt(usize);
          // the user must call 'step' again to declare to "finish" their function
        },
      }
    }
  }
};

const DialogueJsonFormat = struct {
  entryId: usize,
  nodes: []const struct {
    id: usize,

    // FIXME: these must be in sync with the implementation of Node!
    // TODO: generate these from Node type...
    // NOTE: this scales poorly of course, a custom json parser would be much better
    line: ?@typeInfo(Node).Union.fields[0].type = null,
    random_switch: ?struct {
      nexts: []const Next,
      chances: []const u32,
    } = null,
    reply: ?@typeInfo(Node).Union.fields[2].type = null,
    lock: ?@typeInfo(Node).Union.fields[3].type = null,
    unlock: ?@typeInfo(Node).Union.fields[4].type = null,
    call: ?@typeInfo(Node).Union.fields[5].type = null,

    pub fn toNode(self: @This()) ?Node {
      if (self.line)          |v| return .{.line = v};
      if (self.random_switch) |v| return .{.random_switch = RandomSwitch.init(v.nexts, v.chances)};
      if (self.reply)         |v| return .{.reply = v};
      if (self.lock)          |v| return .{.lock = v};
      if (self.unlock)        |v| return .{.unlock = v};
      if (self.call)          |v| return .{.call = v};
      return null;
    }

    // FIXME: add a deep clone utility
    // FIXME: maybe I should just copy/own the json document?
    pub fn toNodeAlloc(self: @This(), alloc: std.mem.Allocator) !?Node {
      if (self.line)          |v| return .{.line = .{
        .data = .{
          .speaker = try alloc.dupe(u8, v.data.speaker),
          .text = try alloc.dupe(u8, v.data.text),
          .metadata = try alloc.dupe(u8, v.data.metadata),
        },
        .next = v.next,
      }};
      if (self.random_switch) |v| return .{.random_switch = RandomSwitch.init(
          try alloc.dupe(Next, v.nexts),
          try alloc.dupe(u32, v.chances),
        )};
      if (self.reply) |v| {
        return .{.reply = .{
          .nexts = alloc.dupe(Next, v.nexts),
          .texts = alloc.dupe(Slice(u8), v.texts),
        }};
      }
      if (self.lock)          |v| return .{.lock = v};
      if (self.unlock)        |v| return .{.unlock = v};
      if (self.call)          |v| return .{.call = v};
      return null;
    }
  },
};

pub const small_test_json =
    \\{
    \\  "entryId": 0,
    \\  "nodes": [
    \\    {
    \\      "id": 0,
    \\      "line": {
    \\        "data": {
    \\          "speaker": "test",
    \\          "text": "hello world!"
    \\        },
    \\        "next": 1
    \\      }
    \\    },
    \\    {
    \\      "id": 1,
    \\      "line": {
    \\        "data": {
    \\          "speaker": "test",
    \\          "text": "goodbye cruel world!"
    \\        }
    \\      }
    \\    }
    \\  ]
    \\}
;

test "create and run context to completion" {
  // FIXME: load a larger one from tests dir
  var ctx_result = DialogueContext.initFromJson(small_test_json, t.allocator , .{});

  defer if (ctx_result.is_ok()) ctx_result.value.deinit(t.allocator)
    // FIXME: need to add freeing logic to Result
    else t.allocator.free(@constCast(ctx_result.err.?));

  if (ctx_result.is_err())
    std.debug.print("\nerr: '{s}'", .{ctx_result.err.?});
  try t.expect(ctx_result.is_ok());

  var ctx = ctx_result.value;
  try t.expectEqual(@as(?usize, 0), ctx.current_node_index);

  const step_result_1 = ctx.step();
  // FIXME: add pointer-descending eql impl
  try t.expect(step_result_1 == .line);
  try t.expectEqualStrings("test", step_result_1.line.speaker);
  try t.expectEqualStrings("hello world!", step_result_1.line.text);
  try t.expectEqual(@as(?usize, 1), ctx.current_node_index);

  const step_result_2 = ctx.step();
  try t.expect(step_result_2 == .line);
  try t.expectEqualStrings("test", step_result_2.line.speaker);
  try t.expectEqualStrings("goodbye cruel world!", step_result_2.line.text);
  try t.expectEqual(@as(?usize, null), ctx.current_node_index);

  const step_result_3 = ctx.step();
  try t.expect(step_result_3 == .none);
  try t.expectEqual(@as(?usize, null), ctx.current_node_index);
}
