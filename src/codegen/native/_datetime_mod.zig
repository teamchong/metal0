/// Python _datetime module - C accelerator for datetime (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "datetime", genDatetime },
    .{ "date", genDate },
    .{ "time", genTime },
    .{ "timedelta", genTimedelta },
    .{ "timezone", genTimezone },
    .{ "MINYEAR", genMinyear },
    .{ "MAXYEAR", genMaxyear },
    .{ "timezone_utc", genTimezoneUtc },
});

fn ic(self: *h.NativeCodegen, args: []ast.Node, idx: usize) h.CodegenError!void {
    if (args.len > idx) {
        {
            const b = try self.getBuilder();
            try b.write("@intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[idx]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("0");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genDatetime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 3) {
        {
            const b = try self.getBuilder();
            try b.write(".{ .year = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write("), .month = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write("), .day = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[2]);
        {
            const b = try self.getBuilder();
            try b.write("), .hour = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try ic(self, args, 3);
        {
            const b = try self.getBuilder();
            try b.write(", .minute = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try ic(self, args, 4);
        {
            const b = try self.getBuilder();
            try b.write(", .second = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try ic(self, args, 5);
        {
            const b = try self.getBuilder();
            try b.write(", .microsecond = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try ic(self, args, 6);
        {
            const b = try self.getBuilder();
            try b.write(" }");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genDate(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 3) {
        {
            const b = try self.getBuilder();
            try b.write(".{ .year = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write("), .month = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write("), .day = @intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[2]);
        {
            const b = try self.getBuilder();
            try b.write(") }");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .year = 1970, .month = 1, .day = 1 }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genTime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    {
        const b = try self.getBuilder();
        try b.write(".{ .hour = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 0);
    {
        const b = try self.getBuilder();
        try b.write(", .minute = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 1);
    {
        const b = try self.getBuilder();
        try b.write(", .second = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 2);
    {
        const b = try self.getBuilder();
        try b.write(", .microsecond = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 3);
    {
        const b = try self.getBuilder();
        try b.write(" }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genTimedelta(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    {
        const b = try self.getBuilder();
        try b.write(".{ .days = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 0);
    {
        const b = try self.getBuilder();
        try b.write(", .seconds = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 1);
    {
        const b = try self.getBuilder();
        try b.write(", .microseconds = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try ic(self, args, 2);
    {
        const b = try self.getBuilder();
        try b.write(" }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genTimezone(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write(".{ .offset = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", .name = ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        if (args.len > 1) {
            try self.genExpr(args[1]);
        } else {
            const b = try self.getBuilder();
            try b.write("null");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        {
            const b = try self.getBuilder();
            try b.write(" }");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .offset = 0, .name = null }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genMinyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 1)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genMaxyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 9999)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genTimezoneUtc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .offset = 0, .name = \"UTC\" }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
