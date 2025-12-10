/// AST Executor - Executes AST nodes at runtime
/// Used for eval() support
const std = @import("std");
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PyInt = @import("../Objects/intobject.zig").PyInt;
const PyFloat = @import("../Objects/floatobject.zig").PyFloat;
const PyBool = @import("../Objects/boolobject.zig").PyBool;
const PyString = @import("../Objects/unicodeobject.zig").PyString;
const PythonError = runtime.PythonError;

// AST Node types for runtime eval() - supports expressions only
// Full AST is in the compiler; this is the runtime subset for eval()
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

/// Execution context with variable bindings
pub const ExecutionContext = struct {
    allocator: std.mem.Allocator,
    locals: std.StringHashMapUnmanaged(*PyObject),
    globals: std.StringHashMapUnmanaged(*PyObject),

    pub fn init(allocator: std.mem.Allocator) ExecutionContext {
        return .{
            .allocator = allocator,
            .locals = .{},
            .globals = .{},
        };
    }

    pub fn deinit(self: *ExecutionContext) void {
        self.locals.deinit(self.allocator);
        self.globals.deinit(self.allocator);
    }

    pub fn setLocal(self: *ExecutionContext, name: []const u8, value: *PyObject) !void {
        try self.locals.put(self.allocator, name, value);
    }

    pub fn setGlobal(self: *ExecutionContext, name: []const u8, value: *PyObject) !void {
        try self.globals.put(self.allocator, name, value);
    }

    pub fn lookup(self: *ExecutionContext, name: []const u8) ?*PyObject {
        // Check locals first, then globals (Python scoping rules)
        return self.locals.get(name) orelse self.globals.get(name);
    }
};

/// Thread-local execution context for eval()
threadlocal var current_context: ?*ExecutionContext = null;

/// Set the current execution context
pub fn setContext(ctx: *ExecutionContext) void {
    current_context = ctx;
}

/// Clear the current execution context
pub fn clearContext() void {
    current_context = null;
}

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
        .name => |n| {
            return try executeName(allocator, n);
        },
    }
}

/// Execute with explicit context
pub fn executeWithContext(allocator: std.mem.Allocator, node: *const Node, ctx: *ExecutionContext) anyerror!*PyObject {
    const old_ctx = current_context;
    current_context = ctx;
    defer current_context = old_ctx;
    return execute(allocator, node);
}

/// Execute a name lookup
fn executeName(allocator: std.mem.Allocator, name: Node.Name) !*PyObject {
    // Check current execution context for variable
    if (current_context) |ctx| {
        if (ctx.lookup(name.id)) |value| {
            // Increment reference count and return
            runtime.incref(value);
            return value;
        }
    }

    // Check for builtin names
    if (lookupBuiltin(allocator, name.id)) |builtin| {
        return builtin;
    }

    // Name not found - raise NameError
    return error.NameError;
}

/// Look up a builtin name
fn lookupBuiltin(allocator: std.mem.Allocator, name: []const u8) ?*PyObject {
    // Common builtins that might be used in eval()
    if (std.mem.eql(u8, name, "True")) {
        return PyBool.create(allocator, true) catch null;
    }
    if (std.mem.eql(u8, name, "False")) {
        return PyBool.create(allocator, false) catch null;
    }
    if (std.mem.eql(u8, name, "None")) {
        // Return proper None singleton
        return runtime.Py_None;
    }

    return null;
}

fn executeConstant(allocator: std.mem.Allocator, constant: Node.Constant) !*PyObject {
    switch (constant.value) {
        .int => |val| {
            return try PyInt.create(allocator, val);
        },
        .float => |val| {
            return try PyFloat.create(allocator, val);
        },
        .string => |val| {
            const str_copy = try allocator.dupe(u8, val);
            return try PyString.create(allocator, str_copy);
        },
        .bool => |val| {
            return try PyBool.create(allocator, val);
        },
    }
}

fn executeBinOp(allocator: std.mem.Allocator, binop: Node.BinOp) !*PyObject {
    const left = try execute(allocator, binop.left);
    defer runtime.decref(left, allocator);

    const right = try execute(allocator, binop.right);
    defer runtime.decref(right, allocator);

    const left_is_int = runtime.PyLong_Check(left);
    const left_is_float = runtime.PyFloat_Check(left);
    const right_is_int = runtime.PyLong_Check(right);
    const right_is_float = runtime.PyFloat_Check(right);

    // Handle int-int operations
    if (left_is_int and right_is_int) {
        const left_val = PyInt.getValue(left);
        const right_val = PyInt.getValue(right);

        // True division always returns float
        if (binop.op == .Div) {
            const left_f: f64 = @floatFromInt(left_val);
            const right_f: f64 = @floatFromInt(right_val);
            if (right_f == 0) return error.ZeroDivisionError;
            return try PyFloat.create(allocator, left_f / right_f);
        }

        const result_val: i64 = switch (binop.op) {
            .Add => left_val + right_val,
            .Sub => left_val - right_val,
            .Mult => left_val * right_val,
            .FloorDiv => if (right_val == 0) return error.ZeroDivisionError else @divFloor(left_val, right_val),
            .Mod => if (right_val == 0) return error.ZeroDivisionError else @mod(left_val, right_val),
            .Pow => std.math.pow(i64, left_val, right_val),
            .Div => unreachable, // handled above
        };
        return try PyInt.create(allocator, result_val);
    }

    // Handle operations involving floats (promote to float)
    if ((left_is_int or left_is_float) and (right_is_int or right_is_float)) {
        const left_f: f64 = if (left_is_float)
            PyFloat.getValue(left)
        else
            @floatFromInt(PyInt.getValue(left));

        const right_f: f64 = if (right_is_float)
            PyFloat.getValue(right)
        else
            @floatFromInt(PyInt.getValue(right));

        const result_f: f64 = switch (binop.op) {
            .Add => left_f + right_f,
            .Sub => left_f - right_f,
            .Mult => left_f * right_f,
            .Div => if (right_f == 0) return error.ZeroDivisionError else left_f / right_f,
            .FloorDiv => if (right_f == 0) return error.ZeroDivisionError else @floor(left_f / right_f),
            .Mod => if (right_f == 0) return error.ZeroDivisionError else @mod(left_f, right_f),
            .Pow => std.math.pow(f64, left_f, right_f),
        };
        return try PyFloat.create(allocator, result_f);
    }

    return error.TypeError;
}

fn executeCall(allocator: std.mem.Allocator, call: Node.Call) !*PyObject {
    // Handle name-based function calls (most common case)
    if (call.func.* == .name) {
        return executeNamedCall(allocator, call.func.name.id, call.args);
    }

    // Handle attribute calls like obj.method()
    // For now, evaluate the function expression and see if it's callable
    const func_obj = try execute(allocator, call.func);
    defer runtime.decref(func_obj, allocator);

    // Check if it's a callable object
    if (runtime.PyCallable_Check(func_obj)) {
        // Build argument tuple
        var args_list = std.ArrayList(*PyObject).init(allocator);
        defer args_list.deinit();

        for (call.args) |arg| {
            const arg_obj = try execute(allocator, &arg);
            try args_list.append(arg_obj);
        }

        // Call the function (simplified - would need proper PyObject_Call)
        // For now, return None for complex callables
        for (args_list.items) |arg| {
            runtime.decref(arg, allocator);
        }
        runtime.incref(runtime.Py_None);
        return runtime.Py_None;
    }

    return error.TypeError;
}

fn executeNamedCall(allocator: std.mem.Allocator, func_name: []const u8, args: []Node) !*PyObject {
    // Built-in functions
    if (std.mem.eql(u8, func_name, "print")) {
        for (args) |arg| {
            const obj = try execute(allocator, &arg);
            defer runtime.decref(obj, allocator);
            runtime.printPyObject(obj);
        }
        runtime.incref(runtime.Py_None);
        return runtime.Py_None;
    } else if (std.mem.eql(u8, func_name, "len")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        if (runtime.PyUnicode_Check(obj)) {
            const str = PyString.getValue(obj);
            return try PyInt.create(allocator, @intCast(str.len));
        } else if (runtime.PyList_Check(obj)) {
            return try PyInt.create(allocator, runtime.Py_SIZE(obj));
        } else if (runtime.PyTuple_Check(obj)) {
            return try PyInt.create(allocator, runtime.Py_SIZE(obj));
        } else if (runtime.PyDict_Check(obj)) {
            const dict_obj: *runtime.PyDictObject = @ptrCast(@alignCast(obj));
            return try PyInt.create(allocator, dict_obj.ma_used);
        }
        return error.TypeError;
    } else if (std.mem.eql(u8, func_name, "int")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        if (runtime.PyLong_Check(obj)) {
            runtime.incref(obj);
            return obj;
        } else if (runtime.PyFloat_Check(obj)) {
            const f = PyFloat.getValue(obj);
            return try PyInt.create(allocator, @intFromFloat(f));
        } else if (runtime.PyUnicode_Check(obj)) {
            const str = PyString.getValue(obj);
            const val = std.fmt.parseInt(i64, str, 10) catch return error.ValueError;
            return try PyInt.create(allocator, val);
        }
        return error.TypeError;
    } else if (std.mem.eql(u8, func_name, "float")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        if (runtime.PyFloat_Check(obj)) {
            runtime.incref(obj);
            return obj;
        } else if (runtime.PyLong_Check(obj)) {
            const i = PyInt.getValue(obj);
            return try PyFloat.create(allocator, @floatFromInt(i));
        } else if (runtime.PyUnicode_Check(obj)) {
            const str = PyString.getValue(obj);
            const val = std.fmt.parseFloat(f64, str) catch return error.ValueError;
            return try PyFloat.create(allocator, val);
        }
        return error.TypeError;
    } else if (std.mem.eql(u8, func_name, "str")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        if (runtime.PyUnicode_Check(obj)) {
            runtime.incref(obj);
            return obj;
        } else if (runtime.PyLong_Check(obj)) {
            const i = PyInt.getValue(obj);
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.ValueError;
            return try PyString.create(allocator, str);
        } else if (runtime.PyFloat_Check(obj)) {
            const f = PyFloat.getValue(obj);
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.ValueError;
            return try PyString.create(allocator, str);
        } else if (runtime.PyBool_Check(obj)) {
            const b = PyBool.getValue(obj);
            return try PyString.create(allocator, if (b) "True" else "False");
        }
        return error.TypeError;
    } else if (std.mem.eql(u8, func_name, "bool")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        // Python truthiness
        const is_true = runtime.PyObject_IsTrue(obj);
        return try PyBool.create(allocator, is_true);
    } else if (std.mem.eql(u8, func_name, "abs")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        if (runtime.PyLong_Check(obj)) {
            const i = PyInt.getValue(obj);
            return try PyInt.create(allocator, if (i < 0) -i else i);
        } else if (runtime.PyFloat_Check(obj)) {
            const f = PyFloat.getValue(obj);
            return try PyFloat.create(allocator, @abs(f));
        }
        return error.TypeError;
    } else if (std.mem.eql(u8, func_name, "min")) {
        if (args.len < 1) return error.TypeError;
        var min_obj = try execute(allocator, &args[0]);
        for (args[1..]) |arg| {
            const obj = try execute(allocator, &arg);
            if (runtime.PyObject_RichCompareBool(obj, min_obj, .Lt)) {
                runtime.decref(min_obj, allocator);
                min_obj = obj;
            } else {
                runtime.decref(obj, allocator);
            }
        }
        return min_obj;
    } else if (std.mem.eql(u8, func_name, "max")) {
        if (args.len < 1) return error.TypeError;
        var max_obj = try execute(allocator, &args[0]);
        for (args[1..]) |arg| {
            const obj = try execute(allocator, &arg);
            if (runtime.PyObject_RichCompareBool(obj, max_obj, .Gt)) {
                runtime.decref(max_obj, allocator);
                max_obj = obj;
            } else {
                runtime.decref(obj, allocator);
            }
        }
        return max_obj;
    } else if (std.mem.eql(u8, func_name, "type")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        // Return type name as string
        const type_name = runtime.Py_TYPE_NAME(obj);
        return try PyString.create(allocator, type_name);
    } else if (std.mem.eql(u8, func_name, "repr")) {
        if (args.len != 1) return error.TypeError;
        const obj = try execute(allocator, &args[0]);
        defer runtime.decref(obj, allocator);

        // Get string representation
        const repr = runtime.PyObject_Repr(obj, allocator) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return try PyString.create(allocator, "<object>");
        };
        return repr;
    }

    // Unknown function - raise NameError
    return error.NameError;
}
