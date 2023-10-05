const DialogueContext = @import("./main.zig").DialogueContext;

var malloc: ?*fn(c_uint) *anyopaque = null;
var free: ?*fn(*anyopaque) void = null;

export fn ade_set_alloc(
  in_malloc: *fn(c_uint) *anyopaque,
  in_free: *fn(*anyopaque) void,
) void {
  malloc = in_malloc;
  free = in_free;
}

export fn ade_dialogue_ctx_create_json(json_ptr: [*]const u8, json_len: usize) ?*DialogueContext {
  // FIXME: use a result type
  if (malloc == null)
  return null;
}

test "create context without allocator set fails" {
  DialogueContext.
}

