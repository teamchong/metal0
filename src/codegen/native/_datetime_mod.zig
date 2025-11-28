/// Python _datetime module - C accelerator for datetime (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _datetime.datetime(year, month, day, hour=0, minute=0, second=0, microsecond=0, tzinfo=None)
pub fn genDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), .month = @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), .day = @intCast(");
        try self.genExpr(args[2]);
        try self.emit("), .hour = ");
        if (args.len > 3) {
            try self.emit("@intCast(");
            try self.genExpr(args[3]);
            try self.emit(")");
        } else {
            try self.emit("0");
        }
        try self.emit(", .minute = ");
        if (args.len > 4) {
            try self.emit("@intCast(");
            try self.genExpr(args[4]);
            try self.emit(")");
        } else {
            try self.emit("0");
        }
        try self.emit(", .second = ");
        if (args.len > 5) {
            try self.emit("@intCast(");
            try self.genExpr(args[5]);
            try self.emit(")");
        } else {
            try self.emit("0");
        }
        try self.emit(", .microsecond = ");
        if (args.len > 6) {
            try self.emit("@intCast(");
            try self.genExpr(args[6]);
            try self.emit(")");
        } else {
            try self.emit("0");
        }
        try self.emit(" }");
    } else {
        try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
    }
}

/// Generate _datetime.date(year, month, day)
pub fn genDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), .month = @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), .day = @intCast(");
        try self.genExpr(args[2]);
        try self.emit(") }");
    } else {
        try self.emit(".{ .year = 1970, .month = 1, .day = 1 }");
    }
}

/// Generate _datetime.time(hour=0, minute=0, second=0, microsecond=0, tzinfo=None)
pub fn genTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .hour = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(", .minute = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(", .second = ");
    if (args.len > 2) {
        try self.emit("@intCast(");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(", .microsecond = ");
    if (args.len > 3) {
        try self.emit("@intCast(");
        try self.genExpr(args[3]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(" }");
}

/// Generate _datetime.timedelta(days=0, seconds=0, microseconds=0, milliseconds=0, minutes=0, hours=0, weeks=0)
pub fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .days = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(", .seconds = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(", .microseconds = ");
    if (args.len > 2) {
        try self.emit("@intCast(");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
    try self.emit(" }");
}

/// Generate _datetime.timezone(offset, name=None)
pub fn genTimezone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ .offset = ");
        try self.genExpr(args[0]);
        try self.emit(", .name = ");
        if (args.len > 1) {
            try self.genExpr(args[1]);
        } else {
            try self.emit("null");
        }
        try self.emit(" }");
    } else {
        try self.emit(".{ .offset = 0, .name = null }");
    }
}

// Constants
pub fn genMINYEAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genMAXYEAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9999)");
}

pub fn genTimezoneUtc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .offset = 0, .name = \"UTC\" }");
}
