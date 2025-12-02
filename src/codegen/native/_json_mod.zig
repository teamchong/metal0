/// Python _json module - C accelerator for json (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

const encBaseBody = "; var result: std.ArrayList(u8) = .{}; result.append(__global_allocator, '\"') catch {}; for (s) |c| { switch (c) { '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch {}, '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch {}, '\\n' => result.appendSlice(__global_allocator, \"\\\\n\") catch {}, '\\r' => result.appendSlice(__global_allocator, \"\\\\r\") catch {}, '\\t' => result.appendSlice(__global_allocator, \"\\\\t\") catch {}, else => result.append(__global_allocator, c) catch {}, } } result.append(__global_allocator, '\"') catch {}; break :blk result.items; }";
const encAsciiBody = "; var result: std.ArrayList(u8) = .{}; result.append(__global_allocator, '\"') catch {}; for (s) |c| { if (c < 0x20 or c > 0x7e) { result.appendSlice(__global_allocator, \"\\\\u\") catch {}; var buf: [4]u8 = undefined; _ = std.fmt.bufPrint(&buf, \"{x:0>4}\", .{c}) catch {}; result.appendSlice(__global_allocator, &buf) catch {}; } else { switch (c) { '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch {}, '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch {}, else => result.append(__global_allocator, c) catch {}, } } } result.append(__global_allocator, '\"') catch {}; break :blk result.items; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode_basestring", h.wrap("blk: { const s = ", encBaseBody, "\"\\\"\\\"\"") },
    .{ "encode_basestring_ascii", h.wrap("blk: { const s = ", encAsciiBody, "\"\\\"\\\"\"") },
    .{ "scanstring", h.wrap2("blk: { const string = ", "; const end_idx = ", "; _ = string; break :blk .{ \"\", end_idx }; }", ".{ \"\", 0 }") },
    .{ "make_encoder", h.c(".{}") }, .{ "make_scanner", h.c(".{}") },
});
