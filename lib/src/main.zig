const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const t = std.testing;
const Result = @import("./result.zig").Result;
const Slice = @import("./slice.zig").Slice;
const OptSlice = @import("./slice.zig").OptSlice;
const FileBuffer = @import("./FileBuffer.zig");


// FIXME: only in wasm
extern fn _debug_print([*]const u8, len: usize) void;

fn debug_print(msg: []const u8) void {
    _debug_print(msg.ptr, msg.len);
}

/// basically packed ?u31
const Next = packed struct {
  valid: bool = false,
  value: u31 = undefined,

  pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: json.ParseOptions) !@This() {
    if (try source.peekNextTokenType() == .null) {
      _ = try source.next(); // consume null
      return .{};
    }
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

const Line = extern struct {
  speaker: Slice(u8),
  text: Slice(u8),
  metadata: OptSlice(u8) = .{},

  /// free the text, since it is allocated for formatting
  pub fn free(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.free(self.text.toZig());
  }
};

const RandomSwitch = struct {
  nexts: []const Next,
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
    texts: Slice(Line),
  },
  lock: struct {
    boolean_var_name: []const u8,
    next: Next = .{},
  },
  unlock: struct {
    boolean_var_name: []const u8,
    next: Next = .{},
  },
  call: struct {
    function_name: []const u8,
    next: Next = .{},
  }
};

/// A function implemented by the environment
/// the payload must live as long as the callback is registered
const Callback = extern struct {
  function: *const fn(?*anyopaque) void,
  payload: ?*anyopaque = null,
};

/// The possible types for a variable
const VariableType = enum {
  /// also known as "text"
  string,
  /// also known as "true/false"
  boolean,
};

pub const DialogueContext = struct {
  // FIXME: deep copy the relevant results, this keeps unused strings
  arena: std.heap.ArenaAllocator,

  nodes: std.MultiArrayList(Node),
  functions: std.StringHashMap(?Callback),
  variables: struct {
    strings: std.StringHashMap([]const u8),
    // FIXME: use custom dynamic bit set like structure for this2
    // maybe just a String->index hash map + dynamic bit set
    booleans: std.StringHashMap(bool),
  },

  entry_node_index: usize,
  // FIXME: optimize to fit in usize
  current_node_index: ?usize,

  /// the pseudo-random number generator for the RandomSwitch
  rand: std.rand.DefaultPrng,

  // FIXME: the alignments are stupid large here
  pub const StepResult = extern struct {
    /// tag indicates which field is active
    tag: enum (u8) {
        done = 0,
        options = 1,
        line = 2,
        /// this allows consumers to not call step until async actions complete
        function_called = 3,
    } = .done,

    /// data for each field
    data: extern union {
        finished: void,
        options: extern struct {
            texts: Slice(Line),
        },
        line: Line,
        function_called: void,
    } = undefined,

    pub fn free(self: *@This(), alloc: std.mem.Allocator) void {
      switch (self.tag) {
        .line => self.list.free(alloc),
        .options => { for (self.options.texts) |l| l.free(alloc); },
        else => {}
      }
    }
  };

  pub const InitOpts = struct {
    // would it be more space-efficient to require u63? does it matter?
    random_seed: ?u64 = null,
    /// do not interpolate text variables in texts when stepping through the dialogue
    no_interpolate: bool = false,
    // /// a plugin to transform text. e.g. add/strip html/bbcode, etc, for any environment
    // textPlugin: TextPlugin? = null,
  };

  pub fn initFromJson(
    json_text: []const u8,
    alloc: std.mem.Allocator,
    opts: InitOpts,
  ) Result(DialogueContext) {
    var r = Result(DialogueContext).err("not initialized");

    // FIXME: use a separate arena for json parsing, deinit it that one,
    // and deep clone out all needed strings into this one (@see toNodeAlloc)
    var arena = std.heap.ArenaAllocator.init(alloc);
    const arena_alloc = arena.allocator();

    // FIXME: cloning only the necessary strings will lower memory footprint,

    var json_diagnostics = json.Diagnostics{};
    var json_scanner = json.Scanner.initCompleteInput(arena_alloc, json_text);
    json_scanner.enableDiagnostics(&json_diagnostics);

    const dialogue_data = json.parseFromTokenSourceLeaky(DialogueJsonFormat, arena_alloc, &json_scanner, .{
      .ignore_unknown_fields = true,
      .allocate = .alloc_always,
    }) catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}: {}", .{e, json_diagnostics}); return r; };

    if (dialogue_data.version != 1) {
        r = Result(DialogueContext).fmt_err(alloc, "unknown file version. Only version '1' is supported by this engine", .{});
        return r;
    }

    var nodes = std.MultiArrayList(Node){};
    defer if (r.is_err()) nodes.deinit(alloc);
    nodes.ensureTotalCapacity(alloc, dialogue_data.nodes.len)
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    for (dialogue_data.nodes, 0..) |json_node, i| {
      const maybe_node = json_node.toNode();
      if (maybe_node) |node| {
        nodes.append(alloc, node)
          catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

        switch (node) {
          inline .reply, .random_switch => |v| {
            for (v.nexts) |maybe_next| {
              if (maybe_next.toOptionalInt(usize)) |next| if (next >= dialogue_data.nodes.len) {
                r = Result(DialogueContext).fmt_err(alloc, "bad next node '{}' on node '{}'", .{next, i});
                return r;
              };
            }
          },
          inline else => |n| if (n.next.toOptionalInt(usize)) |next| if (next >= dialogue_data.nodes.len) {
            r = Result(DialogueContext).fmt_err(alloc, "bad next node '{}' on node '{}'", .{next, i});
            return r;
          },
        }
      } else {
        r = Result(DialogueContext).fmt_err(alloc, "invalid node (index={}) without type or data", .{i});
        return r;
      }
    }

    var booleans = std.StringHashMap(bool).init(alloc);
    booleans.ensureTotalCapacity(@intCast(dialogue_data.variables.boolean.len))
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    var strings = std.StringHashMap([]const u8).init(alloc);
    strings.ensureTotalCapacity(@intCast(dialogue_data.variables.string.len))
      catch |e| { r = Result(DialogueContext).fmt_err(alloc, "{}", .{e}); return r; };

    var functions = std.StringHashMap(?Callback).init(alloc);
    functions.ensureTotalCapacity(@intCast(dialogue_data.functions.len))
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
      .arena = arena,
    });

    return r;
  }

  fn currentNode(self: @This()) ?Node {
    return if (self.current_node_index) |index| self.nodes.get(index) else null;
  }

  pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodes.deinit(alloc);
    self.functions.deinit();
    // NOTE: keys and string values are in the arena
    self.variables.booleans.deinit();
    self.variables.strings.deinit();
    self.arena.deinit();
  }

  pub fn reset(self: *@This()) void {
    self.current_node_index = self.entry_node_index;
  }

  // FIXME: isn't this technically next node?
  /// returns -1 if current node index is invalid. 0 is the entry node
  pub fn getCurrentNodeIndex(self: *@This()) i32 {
    return @intCast(self.current_node_index orelse -1);
  }

  pub fn setCallback(self: *@This(), name: []const u8, callback: Callback) void {
    // FIXME: use a pre-calculated-size map and error on "unknown name"
    self.functions.put(name, callback)
      catch |e| std.debug.panic("put memory error, shouldn't be possible?: {}", .{e});
  }

  pub fn setVariableBoolean(self: *@This(), name: []const u8, value: bool) void {
    self.variables.booleans.put(name, value)
      catch |e| std.debug.panic("Put memory error, how did that happen?: {}", .{e});
  }

  pub fn setVariableString(self: *@This(), name: []const u8, value: []const u8) void {
    // will be cleaned up when area is deinited
    const duped = self.arena.allocator().dupe(u8, value)
      catch |e| std.debug.panic("{}", .{e});
    self.variables.strings.put(name, duped)
      catch |e| std.debug.panic("{}", .{e});
  }

  /// if the current node is an options node, choose the reply
  pub fn reply(self: *@This(), reply_index: usize) void {
    const currNode = self.currentNode() orelse return;
    std.debug.assert(currNode == .reply);
    {
      @setRuntimeSafety(true);
      self.current_node_index = currNode.reply.nexts[reply_index].toOptionalInt(usize);
    }
  }

  pub fn step(self: *@This()) StepResult {
    while (true) {
      const current_node = self.currentNode() orelse return .{ .tag = .done };

      switch (current_node) {
        .line => |v| {
          // FIXME: technically this seems to mean nextNodeIndex!
          self.current_node_index = v.next.toOptionalInt(usize);
          return .{ .tag = .line, .data = .{.line = v.data}};
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
          return .{ .tag = .options, .data = .{.options = .{ .texts = v.texts }}};
        },
        .lock => |v| {
          self.variables.booleans.put(v.boolean_var_name, false)
            // FIXME: validate lock variable names at start time
            catch |e| std.debug.panic("error getting variable '{s}' to lock: {}", .{v.boolean_var_name, e});
          self.current_node_index = v.next.toOptionalInt(usize);
        },
        .unlock => |v| {
          self.variables.booleans.put(v.boolean_var_name, true)
            // FIXME: validate lock variable names at start time
            catch |e| std.debug.panic("error getting variable '{s}' to lock: {}", .{v.boolean_var_name, e});
          self.current_node_index = v.next.toOptionalInt(usize);
        },
        .call => |v| {
          if (self.functions.get(v.function_name)) |stored_cb| if (stored_cb) |cb| cb.function(cb.payload);
          self.current_node_index = v.next.toOptionalInt(usize);
          // the user must call 'step' again to get the real step
          return .{ .tag = .function_called };
        },
      }
    }
  }
};

const DialogueJsonFormat = struct {
  version: usize,
  entryId: usize,
  nodes: []const struct {
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
  functions: []const struct {
    name: []const u8
  } = &.{},
  participants: []const struct {
    name: []const u8
  } = &.{},
  variables: struct {
    boolean: []const struct {
      name: []const u8,
    } = &.{},
    string: []const struct {
      name: []const u8,
    } = &.{}
  } = .{
    .boolean = &.{},
    .string = &.{},
  },
};

test "run small dialogue under zig api" {
  const src = try FileBuffer.fromDirAndPath(t.allocator, std.fs.cwd(), "./test/assets/simple1.alternis.json");
  defer src.free(t.allocator);

  var ctx_result = DialogueContext.initFromJson(src.buffer, t.allocator , .{});

  defer if (ctx_result.is_ok()) ctx_result.value.deinit(t.allocator)
    // FIXME: need to add freeing logic to Result
    else t.allocator.free(@constCast(ctx_result.err.?));

  if (ctx_result.is_err())
    std.debug.print("\nerr: '{s}'", .{ctx_result.err.?});
  try t.expect(ctx_result.is_ok());

  var ctx = ctx_result.value;
  try t.expectEqual(@as(?usize, 0), ctx.current_node_index);

  {
    const step_result = ctx.step();
    // FIXME: add pointer-descending eql impl
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("hello world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, 1), ctx.current_node_index);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("test", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("goodbye cruel world!", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, null), ctx.current_node_index);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .done);
    try t.expectEqual(@as(?usize, null), ctx.current_node_index);
  }
}

test "run large dialogue under zig api" {
  const src = try FileBuffer.fromDirAndPath(t.allocator, std.fs.cwd(), "./test/assets/sample1.alternis.json");
  defer src.free(t.allocator);

  var ctx_result = DialogueContext.initFromJson(src.buffer, t.allocator , .{ .random_seed = 0 });

  defer if (ctx_result.is_ok()) ctx_result.value.deinit(t.allocator)
    // FIXME: need to add freeing logic to Result
    else t.allocator.free(@constCast(ctx_result.err.?));

  if (ctx_result.is_err())
    std.debug.print("\nerr: '{s}'", .{ctx_result.err.?});
  try t.expect(ctx_result.is_ok());

  var ctx = ctx_result.value;
  try t.expectEqual(@as(?usize, 0), ctx.current_node_index);

  const SetNameCallback = struct {
    pub fn impl(payload: ?*anyopaque) void {
      var dialogue_ctx: *DialogueContext = @alignCast(@ptrCast(payload orelse unreachable));
      dialogue_ctx.setVariableString("name", "Testy McTester");
    }
  };

  ctx.setCallback("ask player name", .{ .function = &SetNameCallback.impl, .payload = &ctx });

  {
    const step_result = ctx.step();
    // FIXME: add pointer-descending eql impl
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("Aisha", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("Hey", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, 2), ctx.current_node_index);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("Aaron", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("Yo", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, 2), ctx.current_node_index);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .line);
    try t.expectEqualStrings("Aaron", step_result.data.line.speaker.toZig());
    try t.expectEqualStrings("What's your name?", step_result.data.line.text.toZig());
    try t.expectEqual(@as(?usize, 2), ctx.current_node_index);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .function_called);
  }

  {
    const step_result = ctx.step();
    try t.expect(step_result.tag == .options);
    try t.expectEqual(@as(usize, 2), step_result.data.options.texts.len);
    try t.expectEqualStrings("It's Testy McTester and I like waffles", step_result.data.options.texts.ptr[0].text.toZig());
    try t.expectEqualStrings("It's Testy McTester", step_result.data.options.texts.ptr[1].text.toZig());
    try t.expectEqual(@as(?usize, 2), ctx.current_node_index);
  }
}
