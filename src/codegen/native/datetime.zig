/// DateTime module codegen - datetime.datetime.now(), datetime.date.today(), datetime.timedelta()
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for datetime.datetime.now()
/// Returns current datetime as string
pub fn genDatetimeNow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // datetime.now() takes no arguments
    try self.output.appendSlice(self.allocator, "try runtime.datetime.datetimeNow(allocator)");
}

/// Generate code for datetime.date.today()
/// Returns current date as string
pub fn genDateToday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // date.today() takes no arguments
    try self.output.appendSlice(self.allocator, "try runtime.datetime.dateToday(allocator)");
}

/// Generate code for datetime.timedelta(days=N)
/// Returns timedelta as PyString for easy printing
/// Note: keyword args are passed via Call.keyword_args, not in args array
pub fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // timedelta() with no args = 0 days
        try self.output.appendSlice(self.allocator, "try runtime.datetime.timedeltaToPyString(allocator, 0)");
        return;
    }

    // Positional argument: timedelta(7) means days=7
    if (args.len >= 1) {
        try self.output.appendSlice(self.allocator, "try runtime.datetime.timedeltaToPyString(allocator, ");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")");
    }
}
