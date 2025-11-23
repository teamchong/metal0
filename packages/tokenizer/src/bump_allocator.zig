const std = @import("std");
const Allocator = std.mem.Allocator;

/// Fixed-size bump allocator - no TLB invalidation on reset
pub const BumpAllocator = struct {
    buffer: []u8,
    offset: usize = 0,
    parent: Allocator,

    pub fn init(parent: Allocator, size: usize) !BumpAllocator {
        const buffer = try parent.alloc(u8, size);
        return BumpAllocator{
            .buffer = buffer,
            .offset = 0,
            .parent = parent,
        };
    }

    pub fn deinit(self: *BumpAllocator) void {
        self.parent.free(self.buffer);
    }

    pub fn allocator(self: *BumpAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = Allocator.noRemap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *BumpAllocator = @ptrCast(@alignCast(ctx));

        // Align offset
        const aligned_offset = std.mem.alignForward(usize, self.offset, @intFromEnum(ptr_align));
        const new_offset = aligned_offset + len;

        if (new_offset > self.buffer.len) return null; // Out of space

        self.offset = new_offset;
        return self.buffer[aligned_offset..new_offset].ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx; _ = buf; _ = buf_align; _ = new_len; _ = ret_addr;
        return false; // No resize support
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx; _ = buf; _ = buf_align; _ = ret_addr;
        // No-op (bulk free on reset)
    }

    /// Fast reset - just reset offset, memory stays hot
    pub fn reset(self: *BumpAllocator) void {
        self.offset = 0;
        // No TLB invalidation! Buffer stays mapped and hot
    }
};
