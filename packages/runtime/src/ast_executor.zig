/// AST Executor - Executes AST nodes at runtime
/// Used for eval() support
const std = @import("std");
const runtime = @import("runtime.zig");
const PyObject = runtime.PyObject;
const PyInt = @import("pyint.zig").PyInt;
const PyString = @import("pystring.zig").PyString;
const PythonError = runtime.PythonError;

// Forward declare AST types (will need to import from compiler)
// For now, define minimal types needed for basic eval
pub const Node = union(enum) {
    constant: Constant,
    binop: BinOp,
    call: Call,
    name: Name,

    pub const Constant = struct {
        value: Value,
    };

    pub const Value = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
        bool: bool,
    };

    pub const BinOp = struct {
        left: *Node,
        op: Operator,
        right: *Node,
    };

    pub const Operator = enum {
        Add,
        Sub,
        Mult,
        Div,
        FloorDiv,
        Mod,
        Pow,
    };

    pub const Call = struct {
        func: *Node,
        args: []Node,
    };

    pub const Name = struct {
        id: []const u8,
    };
};

/// Execute an AST node and return PyObject
pub fn execute(allocator: std.mem.Allocator, node: *const Node) anyerror!*PyObject {
    switch (node.*) {
        .constant => |c| {
            return try executeConstant(allocator, c);
        },
        .binop => |b| {
            return try executeBinOp(allocator, b);
        },
        .call => |c| {
            return try executeCall(allocator, c);
        },
        .name => {
            return error.NotImplemented; // Variables need scope
        },
    }
}

fn executeConstant(allocator: std.mem.Allocator, constant: Node.Constant) !*PyObject {
    switch (constant.value) {
        .int => |val| {
            return try PyInt.create(allocator, val);
        },
        .float => {
            return error.NotImplemented; // TODO: PyFloat.create
        },
        .string => |val| {
            const str_copy = try allocator.dupe(u8, val);
            return try PyString.create(allocator, str_copy);
        },
        .bool => {
            return error.NotImplemented; // TODO: PyBool.create
        },
    }
}

fn executeBinOp(allocator: std.mem.Allocator, binop: Node.BinOp) !*PyObject {
    const left = try execute(allocator, binop.left);
    defer runtime.decref(left, allocator);

    const right = try execute(allocator, binop.right);
    defer runtime.decref(right, allocator);

    // For now, only support int operations
    if (left.type_id != .int or right.type_id != .int) {
        return error.TypeError;
    }

    const left_val = PyInt.getValue(left);
    const right_val = PyInt.getValue(right);

    const result_val = switch (binop.op) {
        .Add => left_val + right_val,
        .Sub => left_val - right_val,
        .Mult => left_val * right_val,
        .Div => try runtime.divideInt(left_val, right_val),
        .FloorDiv => @divFloor(left_val, right_val),
        .Mod => try runtime.moduloInt(left_val, right_val),
        .Pow => std.math.pow(i64, left_val, right_val),
    };

    return try PyInt.create(allocator, result_val);
}

fn executeCall(allocator: std.mem.Allocator, call: Node.Call) !*PyObject {
    // Only support name-based function calls for now
    if (call.func.* != .name) {
        return error.NotImplemented;
    }

    const func_name = call.func.name.id;

    // Built-in functions
    if (std.mem.eql(u8, func_name, "print")) {
        for (call.args) |arg| {
            const obj = try execute(allocator, &arg);
            defer runtime.decref(obj, allocator);
            runtime.printPyObject(obj);
        }
        // Return None (for now, just return 0)
        return try PyInt.create(allocator, 0);
    } else if (std.mem.eql(u8, func_name, "len")) {
        if (call.args.len != 1) {
            return error.TypeError;
        }
        const obj = try execute(allocator, &call.args[0]);
        defer runtime.decref(obj, allocator);

        const len_val: i64 = switch (obj.type_id) {
            .string => blk: {
                const str = PyString.getValue(obj);
                break :blk @intCast(str.len);
            },
            else => return error.TypeError,
        };

        return try PyInt.create(allocator, len_val);
    }

    return error.NotImplemented;
}
