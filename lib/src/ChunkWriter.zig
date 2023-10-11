const std = @import("std");


/// A writer that writes to the last chunk in a list of chunks,
/// appending a new chunk to the list every time the end is reached.
/// can be used to efficiently write data of unknown length and then you
/// may call `concat` to get one buffer with of the chunks copied linearly
pub fn ChunkWriter(comptime chunk_size: usize) type {
    return struct {
        chunk_size: usize = chunk_size,
        chunks: std.SegmentedList(Chunk, 0),
        writable_chunk: []u8,
        // TODO: allow default allocator? e.g. system page allocator?
        alloc: std.mem.Allocator,

        const Chunk = [chunk_size]u8;

        const Self = @This();

        /// return a linear memory slice of all the written chunks, allocated by the passed in allocator
        /// you must free it yourself
        pub fn concat(self: Self, alloc: std.mem.Allocator) ![]u8 {
            var chunks_iter = self.chunks.constIterator(0);
            const last_page_written_num = chunk_size - self.writable_chunk.len;
            const buff_size = (self.chunks.count() - 1) * chunk_size + last_page_written_num;
            const buff = try alloc.alloc(u8, buff_size);
            var cursor: usize = 0;

            var index: usize = 0;
            while (chunks_iter.next()) |page| {
                const is_last = index == self.chunks.count() - 1;
                const copy_size = if (is_last) last_page_written_num else chunk_size;
                std.mem.copy(u8, buff[cursor .. cursor + copy_size], page[0..copy_size]);
                index += 1;
                cursor += copy_size;
            }

            return buff;
        }

        pub fn init(alloc: std.mem.Allocator) !Self {
            var chunks = std.SegmentedList(Chunk, 0){};
            var first_page = try chunks.addOne(alloc);
            return Self{
                .alloc = alloc,
                .chunks = chunks,
                .writable_chunk = first_page,
            };
        }

        pub fn deinit(self: *Self) void {
            self.chunks.deinit(self.alloc);
        }

        pub const WriteError = error{} || std.mem.Allocator.Error;

        fn writeFn(self: *Self, bytes: []const u8) WriteError!usize {
            var remaining_bytes = bytes;

            while (remaining_bytes.len > 0) {
                if (self.writable_chunk.len == 0) {
                    self.writable_chunk = (try self.chunks.addOne(self.alloc))[0..chunk_size];
                }
                const next_end = @min(self.writable_chunk.len, remaining_bytes.len);
                const bytes_for_current_page = remaining_bytes[0..next_end];
                std.mem.copy(u8, self.writable_chunk, bytes_for_current_page);
                self.writable_chunk = self.writable_chunk[bytes_for_current_page.len..self.writable_chunk.len];
                remaining_bytes = remaining_bytes[bytes_for_current_page.len..];
            }
            return bytes.len;
        }

        pub fn writer(self: *Self) std.io.Writer(*Self, WriteError, writeFn) {
            return std.io.Writer(*Self, WriteError, writeFn){
                .context = self,
            };
        }
    };
}

pub const PageWriter = ChunkWriter(std.mem.page_size);

test "write some pages" {
    const data = try std.testing.allocator.alloc(u8, std.mem.page_size * 3 + std.mem.page_size / 2 + 11);
    defer std.testing.allocator.free(data);
    for (data) |*b| b.* = 'a';

    var page_writer = try PageWriter.init(std.testing.allocator);
    defer page_writer.deinit();
    const writer = page_writer.writer();

    _ = try writer.write(data);

    const concated = try page_writer.concat(std.testing.allocator);
    defer std.testing.allocator.free(concated);
    try std.testing.expectEqualSlices(u8, data, concated);

    _ = try writer.write(data);
}
