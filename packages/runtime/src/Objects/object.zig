/// Unified PyValue - Runtime-typed value for both AOT and VM paths
/// This is THE SINGLE source of truth for dynamic Python values.
/// Both the bytecode VM and AOT-compiled code use this same type.
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const bigint = @import("bigint");
const pytype = @import("pytype.zig");
const cpython = @import("../cpython.zig");

/// PyValue - Unified runtime value type for AOT and VM
/// Uses tagged union for type safety
pub const PyValue = union(enum) {
    // === Primitive types ===
    int: i64,
    float: f64,
    string: []const u8,
    bytes: @import("../runtime/builtins.zig").PyBytes, // Python bytes type
    bool: bool,
    none: void,
    not_implemented: void, // Python's NotImplemented singleton

    // === Container types ===
    list: *std.ArrayListUnmanaged(PyValue), // Mutable list
    tuple: []const PyValue,
    dict: *Dict, // Python dict (shared with VM)

    // === Numeric types ===
    bigint: bigint.BigInt, // For integers that don't fit in i64
    complex: Complex, // Python complex number

    // === Type/class types ===
    type_obj: *pytype.PyType, // Python type/class object (for metaclasses)
    ptr: *anyopaque, // For types that can't be represented (no type info)
    object: ObjectInstance, // Class instance with type information for method dispatch
    pylist: *cpython.PyListObject, // Python list from eval() - allows len() etc.

    // === VM-specific types (also usable by AOT for eval/exec) ===
    code: *const CodeObject, // Compiled bytecode
    function: *Function, // Python function object
    builtin_fn: *const BuiltinFn, // Built-in function pointer
    iterator: *Iterator, // Iterator for for loops
    range: Range, // range() object
    exception: *Exception, // Exception object
    generator: *Generator, // Generator object (suspended coroutine)

    /// Dict type - uses StringHashMapUnmanaged for Zig 0.15 compatibility
    pub const Dict = std.StringHashMapUnmanaged(PyValue);

    /// Built-in function signature
    pub const BuiltinFn = fn (std.mem.Allocator, []const PyValue) anyerror!PyValue;

    /// Python range object
    pub const Range = struct {
        start: i64,
        stop: i64,
        step: i64 = 1,

        /// Create an iterator from this range
        pub fn iter(self: Range) Iterator {
            return .{ .source = .{ .range = self } };
        }
    };

    /// Iterator over sequences
    pub const Iterator = struct {
        source: IterSource,
        index: usize = 0,

        pub const IterSource = union(enum) {
            list: *std.ArrayListUnmanaged(PyValue),
            tuple: []const PyValue,
            string: []const u8,
            range: Range,
        };

        /// Get next value or null if exhausted
        pub fn next(self: *Iterator) ?PyValue {
            switch (self.source) {
                .list => |l| {
                    if (self.index < l.items.len) {
                        const val = l.items[self.index];
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .tuple => |t| {
                    if (self.index < t.len) {
                        const val = t[self.index];
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .string => |s| {
                    if (self.index < s.len) {
                        const val = PyValue{ .string = s[self.index..][0..1] };
                        self.index += 1;
                        return val;
                    }
                    return null;
                },
                .range => |r| {
                    const current = r.start + @as(i64, @intCast(self.index)) * r.step;
                    if ((r.step > 0 and current < r.stop) or (r.step < 0 and current > r.stop)) {
                        self.index += 1;
                        return .{ .int = current };
                    }
                    return null;
                },
            }
        }
    };

    /// Exception object for exception handling
    pub const Exception = struct {
        exc_type: []const u8, // Exception type name (e.g., "ValueError")
        message: []const u8, // Exception message
        cause: ?*Exception = null, // Chained exception (__cause__)
    };

    /// Generator object - suspended coroutine
    pub const Generator = struct {
        code: *const CodeObject,
        ip: usize = 0, // Saved instruction pointer
        locals: [256]?PyValue = [_]?PyValue{null} ** 256, // Saved locals
        stack: std.ArrayListUnmanaged(PyValue) = .{}, // Saved stack
        cells: []?*Cell = &.{}, // Closure cells
        globals: *Dict,
        running: bool = false,
        exhausted: bool = false,

        pub fn deinit(self: *Generator, allocator: std.mem.Allocator) void {
            self.stack.deinit(allocator);
        }
    };

    /// Python function object
    pub const Function = struct {
        code: *const CodeObject,
        globals: *Dict,
        defaults: []const PyValue = &.{},
        name: []const u8 = "<function>",
        closure: []?*Cell = &.{}, // Captured free variables
    };

    /// Closure cell for captured variables
    pub const Cell = struct {
        value: ?PyValue = null,
    };

    /// Code object flags
    pub const CodeFlags = packed struct {
        generator: bool = false,
        coroutine: bool = false,
        async_generator: bool = false,
        varargs: bool = false, // Function accepts *args
        varkeywords: bool = false, // Function accepts **kwargs
        nested: bool = false, // Nested function
        nofree: bool = false, // No free variables
        _padding: u1 = 0,
    };

    /// Exception table entry for mapping bytecode ranges to handlers
    pub const ExcEntry = struct {
        start: u32, // Start of try block
        end: u32, // End of try block
        target: u32, // Handler target
        depth: u16, // Stack depth at start
        lasti: bool, // Push lasti to stack
    };

    /// CodeObject - compiled bytecode for a function or module
    /// This is the unified representation for both VM execution and AOT eval/exec
    pub const CodeObject = struct {
        /// Raw bytecode instructions
        bytecode: []const u8,

        /// Constant pool (literals, nested code objects, etc.)
        constants: []const PyValue,

        /// Local variable names (indexed by LOAD_FAST/STORE_FAST)
        varnames: []const []const u8,

        /// Free variable names (closures from enclosing scopes)
        freevars: []const []const u8 = &.{},

        /// Cell variable names (locals captured by nested functions)
        cellvars: []const []const u8 = &.{},

        /// Global/attribute names (indexed by LOAD_GLOBAL/LOAD_ATTR)
        names: []const []const u8,

        /// Number of local variables
        nlocals: u16 = 0,

        /// Maximum stack depth needed
        stacksize: u16 = 256,

        /// Number of arguments (positional)
        argcount: u16 = 0,

        /// Number of positional-only arguments
        posonlyargcount: u16 = 0,

        /// Number of keyword-only arguments
        kwonlyargcount: u16 = 0,

        /// Code flags
        flags: CodeFlags = .{},

        /// Source filename
        filename: []const u8 = "<string>",

        /// Function/module name
        name: []const u8 = "<module>",

        /// First source line number
        firstlineno: u32 = 1,

        /// Line number table (maps bytecode offset to source line)
        linetable: []const u8 = &.{},

        /// Exception table
        exctable: []const ExcEntry = &.{},

        /// Get line number for bytecode offset
        pub fn getLineNo(self: *const CodeObject, offset: usize) u32 {
            // Simple line table format: pairs of (bytecode_delta, line_delta)
            var current_offset: usize = 0;
            var current_line: u32 = self.firstlineno;
            var i: usize = 0;

            while (i + 1 < self.linetable.len) {
                const bc_delta = self.linetable[i];
                const line_delta: i8 = @bitCast(self.linetable[i + 1]);
                current_offset += bc_delta;
                if (current_offset > offset) break;
                current_line = @intCast(@as(i64, current_line) + line_delta);
                i += 2;
            }

            return current_line;
        }

        /// Find exception handler for offset
        pub fn findHandler(self: *const CodeObject, offset: usize) ?*const ExcEntry {
            for (self.exctable) |*entry| {
                if (offset >= entry.start and offset < entry.end) {
                    return entry;
                }
            }
            return null;
        }
    };

    pub const Complex = struct { real: f64, imag: f64 };

    /// Virtual table for Python object dunder methods
    /// Follows the same pattern as WakerVTable in async/future/waker.zig
    pub const PyObjectVTable = struct {
        /// __eq__ method: equality comparison
        eq: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __ne__ method: inequality comparison
        ne: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __lt__ method: less than comparison
        lt: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __le__ method: less than or equal comparison
        le: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __gt__ method: greater than comparison
        gt: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __ge__ method: greater than or equal comparison
        ge: ?*const fn (*anyopaque, PyValue) PyValue = null,
        /// __call__ method: callable protocol
        __call__: ?*const fn (*anyopaque, []const PyValue) anyerror!PyValue = null,
        /// Class name for type identification (Python's __name__)
        class_name: ?[]const u8 = null,
        /// Base class vtables for subclass checking (Python's __bases__)
        /// Used to implement Python's rich comparison protocol where subclass methods
        /// take priority over base class methods
        bases: ?[]const *const PyObjectVTable = null,
    };

    /// Class instance with vtable for dynamic method dispatch
    /// Uses the same vtable pattern as WakerData in async/future/waker.zig
    pub const ObjectInstance = struct {
        ptr: *anyopaque,
        type_info: ?*pytype.PyType, // Optional type for method lookup via MRO
        vtable: *const PyObjectVTable, // Function pointers for dunder methods

        /// Check if this object's class is a proper subclass of the other object's class
        /// Used to implement Python's rich comparison protocol where subclass methods
        /// take priority over base class methods
        /// Returns true if self's class inherits from other's class (but is not the same class)
        pub fn isProperSubclassOf(self: ObjectInstance, other: ObjectInstance) bool {
            // Same vtable = same class, not a proper subclass
            if (self.vtable == other.vtable) return false;

            // Check if other's vtable is in our bases chain (recursively)
            return isVtableInBases(self.vtable, other.vtable);
        }

        /// Helper: recursively check if target vtable is in the bases chain of source
        fn isVtableInBases(source: *const PyObjectVTable, target: *const PyObjectVTable) bool {
            const bases = source.bases orelse return false;
            for (bases) |base| {
                if (base == target) return true;
                // Recursively check base's bases
                if (isVtableInBases(base, target)) return true;
            }
            return false;
        }
    };

    /// Generate a vtable for a given type T at comptime
    /// Returns a static const vtable with function pointers for available dunder methods
    fn generateVTable(comptime T: type) PyObjectVTable {
        var vtable = PyObjectVTable{};

        // Helper to wrap comparison result - handles bool or PyValue return types
        const wrapCompResult = struct {
            fn wrap(result: anytype) PyValue {
                const ResultT = @TypeOf(result);
                if (ResultT == PyValue) {
                    return result;
                } else if (ResultT == bool) {
                    return PyValue.from(result);
                } else {
                    // For other types, wrap in PyValue
                    return PyValue.from(result);
                }
            }
        }.wrap;

        // Generate __eq__ wrapper if the type has it
        if (@hasDecl(T, "__eq__")) {
            const EqWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    // Try to unwrap PyValue based on variant type
                    // This allows isinstance(other, T) checks to work in user-defined __eq__ methods
                    switch (other) {
                        .object => |other_obj| {
                            // Check if pointing to same object (identity - handles thread-local storage)
                            if (other_obj.ptr == ptr) {
                                return .{ .bool = true };
                            }
                            // Check if the vtable matches by class name
                            const self_class = if (@hasDecl(T, "__name__")) @field(T, "__name__") else "";
                            const other_class = if (other_obj.vtable.class_name) |cn| cn else "";
                            if (self_class.len > 0 and std.mem.eql(u8, self_class, other_class)) {
                                const other_t: *T = @ptrCast(@alignCast(other_obj.ptr));
                                return wrapCompResult(self.__eq__(other_t));
                            }
                            // Different class - pass PyValue and let __eq__ return NotImplemented
                            return wrapCompResult(self.__eq__(other));
                        },
                        // Extract primitive values so isinstance checks work
                        .int => |v| return wrapCompResult(self.__eq__(v)),
                        .float => |v| return wrapCompResult(self.__eq__(v)),
                        .bool => |v| return wrapCompResult(self.__eq__(v)),
                        .string => |v| return wrapCompResult(self.__eq__(v)),
                        // For other types, pass PyValue directly
                        else => return wrapCompResult(self.__eq__(other)),
                    }
                }
            };
            vtable.eq = EqWrapper.call;
        }

        // Generate __ne__ wrapper if the type has it
        if (@hasDecl(T, "__ne__")) {
            const NeWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return wrapCompResult(self.__ne__(other));
                }
            };
            vtable.ne = NeWrapper.call;
        }

        // Generate __lt__ wrapper if the type has it
        if (@hasDecl(T, "__lt__")) {
            const LtWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return wrapCompResult(self.__lt__(other));
                }
            };
            vtable.lt = LtWrapper.call;
        }

        // Generate __le__ wrapper if the type has it
        if (@hasDecl(T, "__le__")) {
            const LeWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return wrapCompResult(self.__le__(other));
                }
            };
            vtable.le = LeWrapper.call;
        }

        // Generate __gt__ wrapper if the type has it
        if (@hasDecl(T, "__gt__")) {
            const GtWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return wrapCompResult(self.__gt__(other));
                }
            };
            vtable.gt = GtWrapper.call;
        }

        // Generate __ge__ wrapper if the type has it
        if (@hasDecl(T, "__ge__")) {
            const GeWrapper = struct {
                fn call(ptr: *anyopaque, other: PyValue) PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return wrapCompResult(self.__ge__(other));
                }
            };
            vtable.ge = GeWrapper.call;
        }

        // Generate __call__ wrapper if the type has it
        if (@hasDecl(T, "__call__")) {
            const CallWrapper = struct {
                fn call(ptr: *anyopaque, args: []const PyValue) anyerror!PyValue {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    return self.__call__(args);
                }
            };
            vtable.__call__ = CallWrapper.call;
        }

        // Set class name if available
        if (@hasDecl(T, "__name__")) {
            vtable.class_name = @field(T, "__name__");
        }

        // Set bases for subclass checking
        // Classes define __bases_vtables__ as a static array of parent vtable pointers
        if (@hasDecl(T, "__bases_vtables__")) {
            vtable.bases = @field(T, "__bases_vtables__");
        }

        return vtable;
    }

    /// Public wrapper for generateVTable for use from generated code
    /// This allows classes to pre-generate their vtable as a static const
    pub fn generateVTableForType(comptime T: type) PyObjectVTable {
        return generateVTable(T);
    }

    /// Wrapper for storing callable functions as PyValue.object
    /// This enables first-class functions to be stored and called dynamically
    pub fn CallableWrapper(comptime FnType: type) type {
        const fn_info = @typeInfo(FnType).@"fn";
        const ReturnType = fn_info.return_type orelse void;
        const params = fn_info.params;

        return struct {
            const Self = @This();

            fn_ptr: *const FnType,

            /// VTable with __call__ for this callable
            pub const vtable: PyObjectVTable = .{
                .__call__ = callImpl,
            };

            fn callImpl(ptr: *anyopaque, args: []const PyValue) anyerror!PyValue {
                const self: *const Self = @ptrCast(@alignCast(ptr));
                const func = self.fn_ptr.*;

                // Handle different arities
                if (params.len == 0) {
                    const result = @call(.auto, func, .{});
                    return resultToPyValue(ReturnType, result);
                } else if (params.len == 1) {
                    const arg0 = if (args.len > 0) args[0] else PyValue{ .none = {} };
                    const converted0 = convertArg(params[0].type.?, arg0);
                    const result = @call(.auto, func, .{converted0});
                    return resultToPyValue(ReturnType, result);
                } else if (params.len == 2) {
                    const arg0 = if (args.len > 0) args[0] else PyValue{ .none = {} };
                    const arg1 = if (args.len > 1) args[1] else PyValue{ .none = {} };
                    const converted0 = convertArg(params[0].type.?, arg0);
                    const converted1 = convertArg(params[1].type.?, arg1);
                    const result = @call(.auto, func, .{ converted0, converted1 });
                    return resultToPyValue(ReturnType, result);
                } else if (params.len == 3) {
                    const arg0 = if (args.len > 0) args[0] else PyValue{ .none = {} };
                    const arg1 = if (args.len > 1) args[1] else PyValue{ .none = {} };
                    const arg2 = if (args.len > 2) args[2] else PyValue{ .none = {} };
                    const converted0 = convertArg(params[0].type.?, arg0);
                    const converted1 = convertArg(params[1].type.?, arg1);
                    const converted2 = convertArg(params[2].type.?, arg2);
                    const result = @call(.auto, func, .{ converted0, converted1, converted2 });
                    return resultToPyValue(ReturnType, result);
                } else {
                    // For functions with more args, just pass the PyValue slice
                    // The callee must handle PyValue args directly
                    @compileError("CallableWrapper only supports functions with 0-3 parameters");
                }
            }

            fn convertArg(comptime T: type, pv: PyValue) T {
                if (T == PyValue) return pv;
                if (T == i64) return if (pv == .int) pv.int else 0;
                if (T == f64) return if (pv == .float) pv.float else 0.0;
                if (T == bool) return if (pv == .bool) pv.bool else false;
                if (T == []const u8) return if (pv == .string) pv.string else "";
                // For other types, return default/zero value
                return std.mem.zeroes(T);
            }

            fn resultToPyValue(comptime T: type, result: anytype) PyValue {
                if (T == void) return .{ .none = {} };
                if (T == PyValue) return result;
                return PyValue.from(result);
            }
        };
    }

    /// Create a PyValue.object wrapping a callable function
    /// Uses thread-local storage for the wrapper to avoid allocation
    pub fn fromCallable(comptime FnType: type, func: *const FnType) PyValue {
        const Wrapper = CallableWrapper(FnType);
        const S = struct {
            threadlocal var wrapper: Wrapper = undefined;
            threadlocal var initialized: bool = false;
        };
        S.wrapper = .{ .fn_ptr = func };
        S.initialized = true;
        return .{
            .object = .{
                .ptr = @ptrCast(@constCast(&S.wrapper)),
                .type_info = null,
                .vtable = &Wrapper.vtable,
            },
        };
    }

    /// Create a PyValue list from a slice (allocates ArrayList on heap)
    pub fn listFromSlice(allocator: std.mem.Allocator, items: []const PyValue) !PyValue {
        const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
        al.* = .{};
        try al.appendSlice(allocator, items);
        return .{ .list = al };
    }

    /// Create an empty PyValue list
    pub fn emptyList(allocator: std.mem.Allocator) !PyValue {
        const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
        al.* = .{};
        return .{ .list = al };
    }

    /// Static empty list for compile-time defaults (threadlocal, no allocation needed)
    /// Use this for default initializers where allocator isn't available
    const StaticEmpty = struct {
        threadlocal var empty_list: std.ArrayListUnmanaged(PyValue) = .{};
    };

    pub fn staticEmptyList() PyValue {
        return .{ .list = &StaticEmpty.empty_list };
    }

    /// Set element at index in list (for list[i] = val)
    pub fn pyListSet(self: PyValue, idx: usize, value: PyValue) void {
        if (self == .list) {
            self.list.items[idx] = value;
        }
    }

    /// Set element at index with Python semantics (negative indices from end)
    /// Used for dynamic attribute subscript assignment like self.a[-12] = val
    pub fn pyListSetPy(self: PyValue, idx: i64, value: PyValue) void {
        if (self == .list) {
            const len: i64 = @intCast(self.list.items.len);
            const actual_idx: i64 = if (idx < 0) len + idx else idx;
            if (actual_idx >= 0 and actual_idx < len) {
                self.list.items[@intCast(actual_idx)] = value;
            }
        }
    }

    /// Get element at index with Python semantics (negative indices from end)
    /// Used for dynamic attribute subscript access like self.a[-12]
    pub fn pyListGetPy(self: PyValue, idx: i64) PyValue {
        if (self == .list) {
            const len: i64 = @intCast(self.list.items.len);
            const actual_idx: i64 = if (idx < 0) len + idx else idx;
            if (actual_idx >= 0 and actual_idx < len) {
                return self.list.items[@intCast(actual_idx)];
            }
        }
        return .{ .none = {} };
    }

    /// Get list items as slice (for iteration)
    pub fn listItems(self: PyValue) []const PyValue {
        return if (self == .list) self.list.items else &[_]PyValue{};
    }

    /// Get mutable list items (for direct mutation)
    pub fn listItemsMut(self: PyValue) []PyValue {
        return if (self == .list) self.list.items else &[_]PyValue{};
    }

    /// Format value for printing
    pub fn format(
        self: PyValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .string => |v| try writer.print("{s}", .{v}),
            .bytes => |v| try writer.print("{s}", .{v.data}),
            .bool => |v| try writer.print("{}", .{v}),
            .none => try writer.writeAll("None"),
            .list => |list| {
                try writer.writeAll("[");
                for (list.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                try writer.writeAll("]");
            },
            .tuple => |items| {
                try writer.writeAll("(");
                for (items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                if (items.len == 1) try writer.writeAll(",");
                try writer.writeAll(")");
            },
            .bigint => |v| {
                // Avoid type coercion issue in Zig 0.15 with catch returning different types
                if (v.toString(allocator_helper.fast_allocator, 10)) |s| {
                    try writer.print("{s}", .{s});
                } else |_| {
                    try writer.writeAll("<bigint>");
                }
            },
            .complex => |v| {
                if (v.imag >= 0) {
                    try writer.print("({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    try writer.print("({d}{d}j)", .{ v.real, v.imag });
                }
            },
            .type_obj => |t| try writer.print("<class '{s}'>", .{t.name}),
            .ptr => try writer.writeAll("<PyObject>"),
            .not_implemented => try writer.writeAll("NotImplemented"),
            .object => |obj| {
                if (obj.vtable.class_name) |name| {
                    try writer.print("<{s} instance>", .{name});
                } else {
                    try writer.writeAll("<object instance>");
                }
            },
            .pylist => |pylist| {
                // For CPython lists returned from c_interop, use PyObject_Repr
                const size: usize = @intCast(pylist.ob_base.ob_size);
                try writer.print("[<{d} items>]", .{size});
            },
            // VM-specific types - provide reasonable defaults
            .dict => |d| try writer.print("{{<{d} items>}}", .{d.count()}),
            .code => |c| try writer.print("<code object '{s}'>", .{c.name}),
            .function => |f| try writer.print("<function '{s}'>", .{f.code.name}),
            .builtin_fn => try writer.writeAll("<built-in function>"),
            .iterator => try writer.writeAll("<iterator>"),
            .range => |r| try writer.print("range({d}, {d}, {d})", .{ r.start, r.stop, r.step }),
            .exception => |e| try writer.print("{s}('{s}')", .{ e.exc_type, e.message }),
            .generator => try writer.writeAll("<generator object>"),
        }
    }

    /// Convert to integer (if possible)
    pub fn toInt(self: PyValue) ?i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| @intFromFloat(v),
            .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
            .bigint => |v| v.toInt(i64) catch null,
            else => null,
        };
    }

    /// Convert to float (if possible)
    pub fn toFloat(self: PyValue) ?f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            .bigint => |v| v.toFloat(),
            else => null,
        };
    }

    /// Check if value is truthy
    pub fn isTruthy(self: PyValue) bool {
        return switch (self) {
            .bool => |v| v,
            .int => |v| v != 0,
            .float => |v| v != 0.0,
            .string => |v| v.len > 0,
            .bytes => |v| v.data.len > 0,
            .none => false,
            .not_implemented => true, // NotImplemented is truthy
            .list => |list| list.items.len > 0,
            .pylist => |pylist| pylist.ob_base.ob_size > 0, // CPython list
            .tuple => |v| v.len > 0,
            .dict => |d| d.count() > 0,
            .bigint => |v| !v.isZero(),
            .complex => |v| v.real != 0.0 or v.imag != 0.0, // 0j is falsy
            .type_obj => true, // Type objects are always truthy
            .ptr => true, // Objects are truthy by default
            .object => true, // Class instances are truthy by default
            // VM-specific types
            .range => |r| blk: {
                // range is truthy if it has any elements
                if (r.step > 0) break :blk r.start < r.stop;
                if (r.step < 0) break :blk r.start > r.stop;
                break :blk false;
            },
            .code, .function, .builtin_fn, .iterator, .exception, .generator => true,
        };
    }

    /// Convert to boolean (Python truthiness) - alias for isTruthy
    /// This name is used by the VM
    pub fn toBool(self: PyValue) bool {
        return self.isTruthy();
    }

    /// Check if this is an integer
    pub fn isInt(self: PyValue) bool {
        return self == .int;
    }

    /// Check if this is a float
    pub fn isFloat(self: PyValue) bool {
        return self == .float;
    }

    /// Check if this is a string
    pub fn isString(self: PyValue) bool {
        return self == .string;
    }

    /// Check if this value is NaN (for float/complex types)
    /// Used by math.isnan() to support PyValue arguments
    pub fn isNan(self: PyValue) bool {
        return switch (self) {
            .float => |v| std.math.isNan(v),
            .complex => |v| std.math.isNan(v.real) or std.math.isNan(v.imag),
            else => false,
        };
    }

    /// Check if this value is infinite (for float/complex types)
    /// Used by math.isinf() to support PyValue arguments
    pub fn isInf(self: PyValue) bool {
        return switch (self) {
            .float => |v| std.math.isInf(v),
            .complex => |v| std.math.isInf(v.real) or std.math.isInf(v.imag),
            else => false,
        };
    }

    /// Get length for list/tuple/string PyValues
    pub fn pyLen(self: PyValue) usize {
        return switch (self) {
            .list => |list| list.items.len,
            .pylist => |pylist| @intCast(pylist.ob_base.ob_size),
            .tuple => |v| v.len,
            .string => |v| v.len,
            else => 0,
        };
    }

    /// Get Python type name for this value
    /// This is the SINGLE SOURCE OF TRUTH for type names.
    /// All code needing type names should call this method.
    pub fn typeName(self: PyValue) []const u8 {
        return switch (self) {
            .int, .bigint => "int",
            .float => "float",
            .string => "str",
            .bytes => "bytes",
            .bool => "bool",
            .none => "NoneType",
            .not_implemented => "NotImplementedType",
            .list, .pylist => "list",
            .tuple => "tuple",
            .complex => "complex",
            .type_obj => "type",
            .ptr, .object => "object",
            // VM-specific types
            .dict => "dict",
            .code => "code",
            .function => "function",
            .builtin_fn => "builtin_function_or_method",
            .iterator => "iterator",
            .range => "range",
            .exception => "Exception",
            .generator => "generator",
        };
    }

    /// Get error message for "cannot interpret as integer" - SINGLE SOURCE OF TRUTH
    /// Used by pyToInt and similar functions.
    pub fn intErrorMessage(self: PyValue) []const u8 {
        // Pre-computed messages for common types (Zig can't concat runtime strings)
        return switch (self) {
            .string => "'" ++ "str" ++ "' object cannot be interpreted as an integer",
            .bytes => "'" ++ "bytes" ++ "' object cannot be interpreted as an integer",
            .float => "'" ++ "float" ++ "' object cannot be interpreted as an integer",
            .bool => "'" ++ "bool" ++ "' object cannot be interpreted as an integer",
            .none => "'" ++ "NoneType" ++ "' object cannot be interpreted as an integer",
            .list, .pylist => "'" ++ "list" ++ "' object cannot be interpreted as an integer",
            .tuple => "'" ++ "tuple" ++ "' object cannot be interpreted as an integer",
            .complex => "'" ++ "complex" ++ "' object cannot be interpreted as an integer",
            .type_obj => "'" ++ "type" ++ "' object cannot be interpreted as an integer",
            .ptr, .object => "'" ++ "object" ++ "' object cannot be interpreted as an integer",
            .not_implemented => "'" ++ "NotImplementedType" ++ "' object cannot be interpreted as an integer",
            .int, .bigint => "'" ++ "int" ++ "' object cannot be interpreted as an integer",
            .dict => "'" ++ "dict" ++ "' object cannot be interpreted as an integer",
            .code => "'" ++ "code" ++ "' object cannot be interpreted as an integer",
            .function => "'" ++ "function" ++ "' object cannot be interpreted as an integer",
            .builtin_fn => "'" ++ "builtin_function" ++ "' object cannot be interpreted as an integer",
            .iterator => "'" ++ "iterator" ++ "' object cannot be interpreted as an integer",
            .range => "'" ++ "range" ++ "' object cannot be interpreted as an integer",
            .exception => "'" ++ "Exception" ++ "' object cannot be interpreted as an integer",
            .generator => "'" ++ "generator" ++ "' object cannot be interpreted as an integer",
        };
    }

    /// Get repr() string for this value - SINGLE SOURCE OF TRUTH
    /// All code needing repr should call this method.
    pub fn repr(self: PyValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .int => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
            .float => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
            .string => |s| blk: {
                // String repr needs quotes and escaping
                var result = std.ArrayList(u8).init(allocator);
                try result.append(allocator, '\'');
                for (s) |c| {
                    if (c == '\'' or c == '\\') {
                        try result.append(allocator, '\\');
                    }
                    try result.append(allocator, c);
                }
                try result.append(allocator, '\'');
                break :blk result.items;
            },
            .bytes => |b| std.fmt.allocPrint(allocator, "b'{s}'", .{b.data}),
            .bool => |v| if (v) allocator.dupe(u8, "True") else allocator.dupe(u8, "False"),
            .none => allocator.dupe(u8, "None"),
            .not_implemented => allocator.dupe(u8, "NotImplemented"),
            .list => |list| std.fmt.allocPrint(allocator, "[<{d} items>]", .{list.items.len}),
            .pylist => |pylist| std.fmt.allocPrint(allocator, "[<{d} items>]", .{@as(usize, @intCast(pylist.ob_base.ob_size))}),
            .tuple => |tup| std.fmt.allocPrint(allocator, "(<{d} items>)", .{tup.len}),
            .bigint => |v| v.toString(allocator, 10) catch allocator.dupe(u8, "<bigint>"),
            .complex => |c| if (c.real == 0)
                std.fmt.allocPrint(allocator, "{d}j", .{c.imag})
            else
                std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ c.real, c.imag }),
            .type_obj => |t| std.fmt.allocPrint(allocator, "<class '{s}'>", .{t.name}),
            .ptr => allocator.dupe(u8, "<PyObject>"),
            .object => |obj| if (obj.vtable.class_name) |name|
                std.fmt.allocPrint(allocator, "<{s} instance>", .{name})
            else
                allocator.dupe(u8, "<object instance>"),
            // VM-specific types
            .dict => |d| std.fmt.allocPrint(allocator, "{{<{d} items>}}", .{d.count()}),
            .code => |c| std.fmt.allocPrint(allocator, "<code object '{s}'>", .{c.name}),
            .function => |f| std.fmt.allocPrint(allocator, "<function '{s}'>", .{f.code.name}),
            .builtin_fn => allocator.dupe(u8, "<built-in function>"),
            .iterator => allocator.dupe(u8, "<iterator>"),
            .range => |r| std.fmt.allocPrint(allocator, "range({d}, {d}, {d})", .{ r.start, r.stop, r.step }),
            .exception => |e| std.fmt.allocPrint(allocator, "{s}('{s}')", .{ e.exc_type, e.message }),
            .generator => allocator.dupe(u8, "<generator object>"),
        };
    }

    /// Index into list/tuple PyValue
    pub fn pyAt(self: PyValue, idx: usize) PyValue {
        return switch (self) {
            .list => |list| list.items[idx],
            .tuple => |v| v[idx],
            else => .{ .none = {} },
        };
    }

    /// Get from dict-wrapped PyValue (ptr to StringHashMap)
    /// For fmtdict['@'][fmt] where fmtdict['@'] is a PyValue wrapping a dict
    pub fn pyDictGet(self: PyValue, key: []const u8) ?PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("utils.hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.get(key);
    }

    /// Get mutable ptr from dict-wrapped PyValue (ptr to StringHashMap)
    /// For assigning to fmtdict['@'][fmt]
    pub fn pyDictGetPtr(self: PyValue, key: []const u8) ?*PyValue {
        if (self != .ptr) return null;
        const hashmap_helper = @import("utils.hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        return map_ptr.getPtr(key);
    }

    /// Put into dict-wrapped PyValue (ptr to StringHashMap)
    pub fn pyDictPut(self: PyValue, allocator: std.mem.Allocator, key: []const u8, value: PyValue) !void {
        _ = allocator; // Allocator kept for API compatibility but not used for in-place put
        if (self != .ptr) return;
        const hashmap_helper = @import("utils.hashmap_helper");
        const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(self.ptr));
        try map_ptr.put(key, value);
    }

    /// Unwrap to string (for code that expects []const u8)
    pub fn asString(self: PyValue) []const u8 {
        return switch (self) {
            .string => |v| v,
            else => "",
        };
    }

    /// Unwrap to int (for code that expects i64)
    pub fn asInt(self: PyValue) i64 {
        return switch (self) {
            .int => |v| v,
            else => 0,
        };
    }

    /// Unwrap to float (for code that expects f64)
    pub fn asFloat(self: PyValue) f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            else => 0.0,
        };
    }

    /// Unwrap to bool (for code that expects bool)
    pub fn asBool(self: PyValue) bool {
        return self.isTruthy();
    }

    /// Get underlying pointer for c_interop method calls
    /// Returns *anyopaque that can be cast to *cpython.PyObject for C extension calls
    pub fn toPtr(self: PyValue) *anyopaque {
        return switch (self) {
            .ptr => |p| p,
            .object => |o| o.ptr,
            .pylist => |p| @ptrCast(@alignCast(p)),
            .list => |l| @ptrCast(@alignCast(l)),
            .type_obj => |t| @ptrCast(@alignCast(t)),
            // For other types, return null pointer (will fail at runtime if used incorrectly)
            else => @ptrFromInt(0),
        };
    }

    /// Create PyValue from any type (runtime version)
    /// Only supports simple types that don't need allocation for tuples/structs
    /// For tuples/structs, use fromAlloc() which properly allocates
    pub fn from(value: anytype) PyValue {
        const T = @TypeOf(value);
        const info = @typeInfo(T);

        // Handle error unions - unwrap and convert the payload
        if (info == .error_union) {
            if (value) |payload| {
                return from(payload);
            } else |_| {
                return .{ .none = {} }; // Error becomes None
            }
        }

        // Handle optional types (?T) - unwrap if present, None if null
        if (info == .optional) {
            if (value) |v| {
                return from(v);
            }
            return .{ .none = {} };
        }

        // Handle unions generically (IntResult, UnifiedInt, FloorCeilResult, etc.)
        // This automatically converts the active variant to PyValue
        if (info == .@"union") {
            return switch (value) {
                inline else => |v| {
                    const VT = @TypeOf(v);
                    // Skip types that would cause compile errors
                    if (VT == []const PyValue or VT == []PyValue) {
                        return .{ .none = {} };
                    }
                    return from(v);
                },
            };
        }

        // Handle BigInt explicitly (before general struct handling)
        if (T == bigint.BigInt) {
            return .{ .bigint = value };
        }

        // Handle *BigInt and *const BigInt pointers (from UnifiedInt.big)
        if (T == *bigint.BigInt or T == *const bigint.BigInt) {
            return .{ .bigint = value.* };
        }

        // Handle PyPowResult explicitly - convert to float or complex
        const builtins_pow = @import("../runtime/builtins/pow.zig");
        if (T == builtins_pow.PyPowResult) {
            return switch (value) {
                .float_val => |f| .{ .float = f },
                .complex_val => |c| .{ .complex = .{ .real = c.real, .imag = c.imag } },
            };
        }

        // Handle PyBytes explicitly (before general struct handling)
        const builtins_repr = @import("../runtime/builtins/repr.zig");
        if (T == builtins_repr.PyBytes) {
            return .{ .bytes = value };
        }

        if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize or T == comptime_int) {
            return .{ .int = @intCast(value) };
        } else if (T == f64 or T == f32 or T == comptime_float) {
            return .{ .float = @floatCast(value) };
        } else if (T == bool) {
            return .{ .bool = value };
        } else if (T == []const u8 or T == []u8) {
            return .{ .string = value };
        } else if (T == PyValue) {
            return value;
        } else if (T == []const PyValue or T == []PyValue) {
            @compileError("Cannot convert []PyValue to PyValue.list without allocator. Use PyValue.listFromSlice(allocator, slice) instead.");
        } else if (info == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            // Check for sentinel-terminated pointer to u8 (C strings)
            if (ptr_info.child == u8 and ptr_info.sentinel() != null) {
                return .{ .string = std.mem.span(value) };
            }
            // Handle pointer to fixed-size array of u8 (string literals)
            if (@typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    // Convert array pointer to slice
                    return .{ .string = value[0..arr_info.len] };
                }
            }
            // Handle *cpython.PyObject (or any PyObject-like struct from c_interop)
            // Check by layout: struct with ob_refcnt and ob_type fields
            const is_pyobject_like = blk: {
                if (ptr_info.child == cpython.PyObject) break :blk true;
                // Also check for c_interop's PyObject (same layout, different type)
                if (@typeInfo(ptr_info.child) == .@"struct") {
                    const ChildT = ptr_info.child;
                    if (@hasField(ChildT, "ob_refcnt") and @hasField(ChildT, "ob_type")) {
                        break :blk true;
                    }
                }
                break :blk false;
            };
            if (is_pyobject_like) {
                // Cast to runtime's PyObject type (same layout, safe cast)
                const obj: *cpython.PyObject = @ptrCast(@alignCast(value));
                // Check bool BEFORE int (PyBoolObject inherits from PyLongObject)
                if (cpython.PyBool_Check(obj)) {
                    const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(obj));
                    return .{ .bool = bool_obj.ob_digit != 0 };
                }
                if (cpython.PyLong_Check(obj)) {
                    const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(obj));
                    return .{ .int = @intCast(long_obj.ob_digit) };
                }
                if (cpython.PyFloat_Check(obj)) {
                    const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(obj));
                    return .{ .float = float_obj.ob_fval };
                }
                // Check for PyUnicode by type name (cross-module compatible)
                const type_obj = obj.ob_type;
                const type_name = std.mem.span(type_obj.tp_name);
                if (std.mem.eql(u8, type_name, "str")) {
                    // CPython-style compact ASCII: data follows PyASCIIObject struct
                    // PyASCIIObject = { ob_base(16) + length(8) + hash(8) + state(4) } = 36 bytes
                    // But with alignment, it's 40 bytes. String data starts at offset 40.
                    const obj_ptr: [*]const u8 = @ptrCast(obj);
                    // Read length from offset 16 (after ob_base)
                    const length_ptr: *const isize = @ptrCast(@alignCast(obj_ptr + 16));
                    const length: usize = @intCast(length_ptr.*);
                    // Data follows at offset 40 (sizeof PyASCIIObject rounded to alignment)
                    const data_ptr = obj_ptr + 40;
                    return .{ .string = data_ptr[0..length] };
                }
                if (cpython.PyList_Check(obj)) {
                    // Store the PyList as a PyObject with list semantics
                    // This allows len() and other operations to work
                    return .{ .pylist = @ptrCast(@alignCast(obj)) };
                }
                // Unknown PyObject type - store as ptr
                return .{ .ptr = @ptrCast(@constCast(value)) };
            }
            // Handle pointer to class instance (struct with __vtable__ or dunder methods)
            if (@typeInfo(ptr_info.child) == .@"struct") {
                const ChildT = ptr_info.child;
                const child_has_vtable = @hasDecl(ChildT, "__vtable__");
                const child_has_dunders = @hasDecl(ChildT, "__call__") or @hasDecl(ChildT, "__eq__") or
                    @hasDecl(ChildT, "__ne__") or @hasDecl(ChildT, "__lt__") or @hasDecl(ChildT, "__le__") or
                    @hasDecl(ChildT, "__gt__") or @hasDecl(ChildT, "__ge__");
                if (child_has_vtable or child_has_dunders) {
                    const vtable_ptr: *const PyObjectVTable = if (@hasDecl(ChildT, "__vtable__"))
                        &@field(ChildT, "__vtable__")
                    else blk: {
                        const VTableForT = struct {
                            const vtable: PyObjectVTable = generateVTable(ChildT);
                        };
                        break :blk &VTableForT.vtable;
                    };
                    return .{
                        .object = .{
                            .ptr = @ptrCast(@constCast(value)),
                            .type_info = null,
                            .vtable = vtable_ptr,
                        },
                    };
                }
            }
            // Store as ptr for unknown pointer types
            return .{ .ptr = @ptrCast(@constCast(value)) };
        } else if (@typeInfo(T) == .@"struct") {
            const struct_info = @typeInfo(T).@"struct";
            // Handle tuples (anonymous structs with is_tuple = true)
            // Use rotating static storage to avoid allocation while supporting
            // comparisons like: PyValue.from(.{a, b}).eql(PyValue.from(.{c, d}))
            // where we need two different buffers in the same expression
            if (struct_info.is_tuple) {
                const TupleStorage = struct {
                    // 4 rotating buffers for small tuples (up to 8 elements each)
                    // This handles comparisons and nested tuple operations
                    threadlocal var buffers: [4][8]PyValue = undefined;
                    threadlocal var next_buffer: u2 = 0;
                };
                const len = struct_info.fields.len;
                if (len <= 8) {
                    const buf_idx = TupleStorage.next_buffer;
                    TupleStorage.next_buffer +%= 1;
                    inline for (0..len) |i| {
                        TupleStorage.buffers[buf_idx][i] = from(value[i]);
                    }
                    return .{ .tuple = TupleStorage.buffers[buf_idx][0..len] };
                }
                // Tuple too large for static storage - return none
                return .{ .none = {} };
            }
            // Handle Complex numbers (PyComplex has .real and .imag fields)
            if (@hasField(T, "real") and @hasField(T, "imag")) {
                return .{ .complex = .{ .real = value.real, .imag = value.imag } };
            }
            // Handle float/int/str subclasses with __base_value__ field
            if (@hasField(T, "__base_value__")) {
                const base = value.__base_value__;
                const base_info = @typeInfo(@TypeOf(base));
                if (base_info == .float or base_info == .comptime_float) {
                    return .{ .float = @floatCast(base) };
                }
                if (base_info == .int or base_info == .comptime_int) {
                    return .{ .int = @intCast(base) };
                }
            }
            // Handle class instances with dunder methods (__call__, __eq__, __lt__, etc.)
            const has_vtable = @hasDecl(T, "__vtable__");
            const has_dunders = @hasDecl(T, "__call__") or @hasDecl(T, "__eq__") or
                @hasDecl(T, "__ne__") or @hasDecl(T, "__lt__") or @hasDecl(T, "__le__") or
                @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__");
            if (has_vtable or has_dunders) {
                // Use thread-local storage to store the struct value
                // This avoids allocation but limits to one callable per type at a time
                const Storage = struct {
                    threadlocal var stored: T = undefined;
                };
                Storage.stored = value;
                // Use the class's pre-generated __vtable__ if available (includes bases info),
                // otherwise generate a new vtable at comptime
                const vtable_ptr: *const PyObjectVTable = if (@hasDecl(T, "__vtable__"))
                    &@field(T, "__vtable__")
                else blk: {
                    const VTableForT = struct {
                        const vtable: PyObjectVTable = generateVTable(T);
                    };
                    break :blk &VTableForT.vtable;
                };
                return .{
                    .object = .{
                        .ptr = @ptrCast(&Storage.stored),
                        .type_info = null,
                        .vtable = vtable_ptr,
                    },
                };
            }
            // Handle ArrayListUnmanaged(PyValue) - structs with items and capacity
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                const ItemsType = @TypeOf(value.items);
                // Check if items is a slice of PyValue
                if (@typeInfo(ItemsType) == .pointer and @typeInfo(ItemsType).pointer.size == .slice) {
                    const ItemType = @typeInfo(ItemsType).pointer.child;
                    if (ItemType == PyValue) {
                        // Store the ArrayList in thread-local storage and return as tuple
                        // (can't allocate a list without allocator, so use tuple representation)
                        const len = value.items.len;
                        if (len <= 8) {
                            const TupleStorage = struct {
                                threadlocal var buffers: [4][8]PyValue = undefined;
                                threadlocal var next_buffer: u2 = 0;
                            };
                            const buf_idx = TupleStorage.next_buffer;
                            TupleStorage.next_buffer +%= 1;
                            for (0..len) |i| {
                                TupleStorage.buffers[buf_idx][i] = value.items[i];
                            }
                            return .{ .tuple = TupleStorage.buffers[buf_idx][0..len] };
                        }
                        // Too large - fallback to none
                        return .{ .none = {} };
                    }
                }
            }
            return .{ .none = {} };
        } else if (info == .array) {
            // Handle fixed-size arrays [N]T
            const array_info = @typeInfo(T).array;
            if (array_info.child == PyValue) {
                const len = array_info.len;
                if (len <= 8) {
                    const TupleStorage = struct {
                        threadlocal var buffers: [4][8]PyValue = undefined;
                        threadlocal var next_buffer: u2 = 0;
                    };
                    const buf_idx = TupleStorage.next_buffer;
                    TupleStorage.next_buffer +%= 1;
                    for (0..len) |i| {
                        TupleStorage.buffers[buf_idx][i] = value[i];
                    }
                    return .{ .tuple = TupleStorage.buffers[buf_idx][0..len] };
                }
                return .{ .none = {} };
            }
            return .{ .none = {} };
        } else if (info == .@"fn") {
            // Function type - wrap as callable object
            // Note: This requires the function to be passed as a pointer
            // Use PyValue.fromCallable(&func) for direct function values
            return .{ .none = {} }; // Can't wrap bare function - need pointer
        } else if (info == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn") {
            // Pointer to function - wrap as callable
            return fromCallable(@typeInfo(T).pointer.child, value);
        } else {
            return .{ .none = {} };
        }
    }

    /// Allocating version of from() for runtime tuples/structs
    /// Use this when you need to convert runtime values to PyValue
    pub fn fromAlloc(allocator: std.mem.Allocator, value: anytype) !PyValue {
        const T = @TypeOf(value);
        // Handle BigInt first (before general struct handling)
        if (T == bigint.BigInt) {
            return .{ .bigint = value };
        }
        // Handle PyBytes explicitly (before general struct handling)
        const builtins_repr = @import("../runtime/builtins/repr.zig");
        if (T == builtins_repr.PyBytes) {
            return .{ .bytes = value };
        }
        if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize) {
            return .{ .int = @intCast(value) };
        } else if (@typeInfo(T) == .comptime_int) {
            // Handle comptime_int values
            return .{ .int = @as(i64, value) };
        } else if (T == f64 or T == f32) {
            return .{ .float = @floatCast(value) };
        } else if (T == bool) {
            return .{ .bool = value };
        } else if (T == []const u8 or T == []u8) {
            return .{ .string = value };
        } else if (T == PyValue) {
            return value;
        } else if (T == []const PyValue or T == []PyValue) {
            @compileError("Cannot convert []PyValue to PyValue.list without allocator. Use PyValue.listFromSlice(allocator, slice) instead.");
        } else if (@typeInfo(T) == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            // Check for sentinel-terminated pointer to u8 (C strings)
            if (ptr_info.child == u8 and ptr_info.sentinel() != null) {
                return .{ .string = std.mem.span(value) };
            }
            // Handle pointer to fixed-size array of u8 (string literals)
            if (@typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    // Convert array pointer to slice
                    return .{ .string = value[0..arr_info.len] };
                }
            }
            if (ptr_info.size == .slice) {
                // Allocate and convert slice elements
                const result = try allocator.alloc(PyValue, value.len);
                for (value, 0..) |item, i| {
                    result[i] = try fromAlloc(allocator, item);
                }
                return try PyValue.listFromSlice(allocator, result);
            }
            return .{ .ptr = @ptrCast(@constCast(value)) };
        } else if (@typeInfo(T) == .array) {
            // Handle fixed-size arrays - convert to tuple
            const arr_info = @typeInfo(T).array;
            const result = try allocator.alloc(PyValue, arr_info.len);
            for (0..arr_info.len) |i| {
                result[i] = try fromAlloc(allocator, value[i]);
            }
            return .{ .tuple = result };
        } else if (@typeInfo(T) == .@"struct") {
            const info = @typeInfo(T).@"struct";
            // Handle float/int/str subclasses with __base_value__ field
            if (@hasField(T, "__base_value__")) {
                const base = value.__base_value__;
                const base_info = @typeInfo(@TypeOf(base));
                if (base_info == .float or base_info == .comptime_float) {
                    return .{ .float = @floatCast(base) };
                }
                if (base_info == .int or base_info == .comptime_int) {
                    return .{ .int = @intCast(base) };
                }
            }
            // Handle StringHashMap/AutoHashMap - store as pointer
            // These have unmanaged and entries fields
            if (@hasField(T, "unmanaged") and @hasField(T, "entries")) {
                // HashMap - store pointer to the map
                // We allocate a copy of the struct on heap so it survives
                const ptr = try allocator.create(T);
                ptr.* = value;
                return .{ .ptr = @ptrCast(ptr) };
            }
            // Handle ArrayList - convert to list using items
            if (@hasField(T, "items") and @hasField(T, "capacity")) {
                const items_slice = value.items;
                const result = try allocator.alloc(PyValue, items_slice.len);
                for (items_slice, 0..) |item, i| {
                    result[i] = try fromAlloc(allocator, item);
                }
                return try PyValue.listFromSlice(allocator, result);
            }
            // Handle tuples
            if (info.is_tuple) {
                const result = try allocator.alloc(PyValue, info.fields.len);
                inline for (0..info.fields.len) |i| {
                    result[i] = try fromAlloc(allocator, value[i]);
                }
                return .{ .tuple = result };
            }
            // Detect Python class instances (structs with __name__ or dunder methods)
            // Store as .object with vtable for dynamic method dispatch
            const is_class_instance = @hasDecl(T, "__name__") or
                                      @hasDecl(T, "__eq__") or
                                      @hasDecl(T, "__lt__") or
                                      @hasDecl(T, "__le__") or
                                      @hasDecl(T, "__init__") or
                                      @hasDecl(T, "__str__") or
                                      @hasDecl(T, "__repr__");

            if (is_class_instance) {
                // Use the class's pre-generated __vtable__ if available (includes bases info),
                // otherwise generate a new vtable at comptime
                const vtable_ptr: *const PyObjectVTable = if (@hasDecl(T, "__vtable__"))
                    &@field(T, "__vtable__")
                else blk: {
                    // Fallback: generate vtable at comptime for this type
                    const VTableForT = struct {
                        const vtable: PyObjectVTable = generateVTable(T);
                    };
                    break :blk &VTableForT.vtable;
                };

                // Allocate class instance on heap and store as .object with vtable
                const ptr = try allocator.create(T);
                ptr.* = value;

                // Get PyType if available (for MRO-based method lookup)
                const type_info: ?*pytype.PyType = if (@hasDecl(T, "__type__")) @field(T, "__type__") else null;

                return .{ .object = .{
                    .ptr = @ptrCast(ptr),
                    .type_info = type_info,
                    .vtable = vtable_ptr,
                } };
            }

            // Non-tuple, non-class struct - convert to tuple of fields
            const result = try allocator.alloc(PyValue, info.fields.len);
            inline for (0..info.fields.len) |i| {
                result[i] = try fromAlloc(allocator, @field(value, info.fields[i].name));
            }
            return .{ .tuple = result };
        } else {
            return .{ .none = {} };
        }
    }

    // ============================================================================
    // PyValue → PyObject* Bridge (for external library interop)
    // ============================================================================

    /// Convert PyValue to CPython-compatible *PyObject
    /// This is the critical bridge for passing values TO external Python libs (numpy, pandas, etc.)
    /// Allocates CPython-compatible objects with proper refcount and type pointers.
    ///
    /// Usage:
    ///   const py_obj = try my_pyvalue.toPyObject(allocator);
    ///   defer cpython.Py_DECREF(py_obj);  // Caller owns the reference
    ///   numpy_function(py_obj);
    ///
    pub fn toPyObject(self: PyValue, allocator: std.mem.Allocator) !*cpython.PyObject {
        const PyInt = @import("intobject.zig").PyInt;
        const PyFloat = @import("floatobject.zig").PyFloat;
        const PyBool = @import("boolobject.zig").PyBool;
        const PyString = @import("unicodeobject.zig").PyString;
        const listobject = @import("listobject.zig");
        const tupleobject = @import("tupleobject.zig");

        return switch (self) {
            .int => |v| try PyInt.create(allocator, v),
            .float => |v| try PyFloat.create(allocator, v),
            .bool => |v| try PyBool.create(allocator, v),
            .string => |v| try PyString.create(allocator, v),
            .none => cpython.Py_None,

            .list => |list_ptr| blk: {
                // Convert PyValue list to PyListObject
                const py_list = try listobject.PyList.create(allocator);
                for (list_ptr.items) |item| {
                    const py_item = try item.toPyObject(allocator);
                    try listobject.PyList.append(py_list, py_item);
                }
                break :blk @ptrCast(py_list);
            },

            .tuple => |items| blk: {
                // Convert PyValue tuple to PyTupleObject
                const py_tuple = try tupleobject.PyTuple.create(allocator, items.len);
                for (items, 0..) |item, i| {
                    const py_item = try item.toPyObject(allocator);
                    tupleobject.PyTuple.setItem(py_tuple, i, py_item);
                }
                break :blk @ptrCast(py_tuple);
            },

            .pylist => |py_list| blk: {
                // Already a PyListObject - just increment refcount and return
                cpython.Py_INCREF(@ptrCast(py_list));
                break :blk @ptrCast(py_list);
            },

            .bigint => |big| blk: {
                // BigInt → PyLongObject (simplified: convert to string, then parse)
                // For full support, would need multi-digit PyLongObject
                if (big.toInt64()) |small_val| {
                    break :blk try PyInt.create(allocator, small_val);
                }
                // TODO: Create multi-digit PyLongObject for large BigInt
                // For now, return None for values that don't fit in i64
                break :blk cpython.Py_None;
            },

            .complex => |c| blk: {
                // Create PyComplexObject
                const complex_obj = try allocator.create(cpython.PyComplexObject);
                complex_obj.* = cpython.PyComplexObject{
                    .ob_base = .{
                        .ob_refcnt = 1,
                        .ob_type = &cpython.PyComplex_Type,
                    },
                    .cval_real = c.real,
                    .cval_imag = c.imag,
                };
                break :blk @ptrCast(complex_obj);
            },

            .bytes => |b| blk: {
                // Create PyBytesObject
                const total_size = @sizeOf(cpython.PyBytesObject) + b.data.len;
                const mem = try allocator.alignedAlloc(u8, @alignOf(cpython.PyBytesObject), total_size);
                const bytes_obj: *cpython.PyBytesObject = @ptrCast(@alignCast(mem.ptr));
                bytes_obj.ob_base = .{
                    .ob_base = .{
                        .ob_refcnt = 1,
                        .ob_type = &cpython.PyBytes_Type,
                    },
                    .ob_size = @intCast(b.data.len),
                };
                bytes_obj.ob_shash = -1; // Not computed
                // Copy bytes data after the struct
                const data_ptr: [*]u8 = @ptrCast(&bytes_obj.ob_sval);
                @memcpy(data_ptr[0..b.data.len], b.data);
                break :blk @ptrCast(bytes_obj);
            },

            .object => |obj| blk: {
                // Class instance - wrap as opaque PyObject
                // External libs won't understand our vtable, so this is limited
                // For full interop, would need to create proper Python class wrapper
                _ = obj;
                // Return None for now - proper interop needs class registration
                break :blk cpython.Py_None;
            },

            .ptr => |p| blk: {
                // Already a pointer - assume it's a PyObject*
                // This handles values that came from eval() or external sources
                cpython.Py_INCREF(@ptrCast(p));
                break :blk @ptrCast(p);
            },

            .type_obj => cpython.Py_None, // Type objects need special handling
            .not_implemented => cpython.Py_None, // TODO: Return actual Py_NotImplemented
        };
    }

    /// Convert to string representation
    pub fn toString(self: PyValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .int => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .float => |v| blk: {
                // Python convention: nan never has sign, inf shows sign
                if (std.math.isNan(v)) break :blk try allocator.dupe(u8, "nan");
                if (std.math.isInf(v)) break :blk try allocator.dupe(u8, if (v < 0) "-inf" else "inf");
                break :blk try std.fmt.allocPrint(allocator, "{d}", .{v});
            },
            .string => |v| v,
            .bool => |v| if (v) "True" else "False",
            .none => "None",
            .complex => |v| blk: {
                if (v.imag >= 0) {
                    break :blk try std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    break :blk try std.fmt.allocPrint(allocator, "({d}{d}j)", .{ v.real, v.imag });
                }
            },
            .list, .pylist, .tuple, .bigint, .bytes, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
            else => try std.fmt.allocPrint(allocator, "{}", .{self}),
        };
    }

    /// Convert to repr representation (with quotes for strings)
    pub fn toRepr(self: PyValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .int => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .float => |v| blk: {
                // Python convention: nan never has sign, inf shows sign
                if (std.math.isNan(v)) break :blk try allocator.dupe(u8, "nan");
                if (std.math.isInf(v)) break :blk try allocator.dupe(u8, if (v < 0) "-inf" else "inf");
                break :blk try std.fmt.allocPrint(allocator, "{d}", .{v});
            },
            .string => |v| try std.fmt.allocPrint(allocator, "'{s}'", .{v}),
            .bool => |v| if (v) "True" else "False",
            .none => "None",
            .complex => |v| blk: {
                if (v.imag >= 0) {
                    break :blk try std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ v.real, v.imag });
                } else {
                    break :blk try std.fmt.allocPrint(allocator, "({d}{d}j)", .{ v.real, v.imag });
                }
            },
            .list, .pylist, .tuple, .bigint, .bytes, .ptr => try std.fmt.allocPrint(allocator, "{}", .{self}),
            else => try std.fmt.allocPrint(allocator, "{}", .{self}),
        };
    }

    // ============================================================================
    // Arithmetic Operations (for uncertain type safety)
    // ============================================================================

    /// Add two PyValues (returns PyValue to handle mixed types safely)
    pub fn add(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a +% b }, // Wrapping add for safety
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) + b },
                .bool => |b| .{ .int = a +% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a + @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a + b },
                .bool => |b| .{ .float = a + @as(f64, if (b) 1.0 else 0.0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                // Bool arithmetic - Python treats bool as subtype of int
                .int => |b| .{ .int = @as(i64, @intFromBool(a)) +% b },
                .float => |b| .{ .float = @as(f64, if (a) 1.0 else 0.0) + b },
                .bool => |b| .{ .int = @as(i64, @intFromBool(a)) +% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            .string => |a| switch (other) {
                .string => |b| blk: {
                    // String concat - needs allocator, return none for now
                    // Callers should use addAlloc for strings
                    _ = a;
                    _ = b;
                    break :blk .{ .none = {} };
                },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Subtract two PyValues
    pub fn sub(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a -% b },
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) - b },
                .bool => |b| .{ .int = a -% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a - @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a - b },
                .bool => |b| .{ .float = a - @as(f64, if (b) 1.0 else 0.0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, @intFromBool(a)) -% b },
                .float => |b| .{ .float = @as(f64, if (a) 1.0 else 0.0) - b },
                .bool => |b| .{ .int = @as(i64, @intFromBool(a)) -% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Multiply two PyValues
    pub fn mul(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a *% b },
                .float => |b| .{ .float = @as(f64, @floatFromInt(a)) * b },
                .bool => |b| .{ .int = a *% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = a * @as(f64, @floatFromInt(b)) },
                .float => |b| .{ .float = a * b },
                .bool => |b| .{ .float = a * @as(f64, if (b) 1.0 else 0.0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, @intFromBool(a)) *% b },
                .float => |b| .{ .float = @as(f64, if (a) 1.0 else 0.0) * b },
                .bool => |b| .{ .int = @as(i64, @intFromBool(a)) *% @as(i64, @intFromBool(b)) },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Divide two PyValues (Python 3 true division - always returns float)
    pub fn div(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b)) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @as(f64, @floatFromInt(a)) / b } else .{ .none = {} },
                .bool => |b| if (b) .{ .float = @as(f64, @floatFromInt(a)) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = a / @as(f64, @floatFromInt(b)) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = a / b } else .{ .none = {} },
                .bool => |b| if (b) .{ .float = a } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @as(f64, if (a) 1.0 else 0.0) / @as(f64, @floatFromInt(b)) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @as(f64, if (a) 1.0 else 0.0) / b } else .{ .none = {} },
                .bool => |b| if (b) .{ .float = if (a) 1.0 else 0.0 } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Floor divide two PyValues (Python //)
    pub fn floordiv(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @divFloor(a, b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @floor(@as(f64, @floatFromInt(a)) / b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .int = a } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @floor(a / @as(f64, @floatFromInt(b))) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @floor(a / b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .float = @floor(a) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @divFloor(@as(i64, @intFromBool(a)), b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @floor(@as(f64, if (a) 1.0 else 0.0) / b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .int = @as(i64, @intFromBool(a)) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Modulo two PyValues (Python %)
    pub fn mod(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @mod(a, b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @mod(@as(f64, @floatFromInt(a)), b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .int = 0 } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| if (b != 0) .{ .float = @mod(a, @as(f64, @floatFromInt(b))) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @mod(a, b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .float = @mod(a, 1.0) } else .{ .none = {} },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| if (b != 0) .{ .int = @mod(@as(i64, @intFromBool(a)), b) } else .{ .none = {} },
                .float => |b| if (b != 0.0) .{ .float = @mod(@as(f64, if (a) 1.0 else 0.0), b) } else .{ .none = {} },
                .bool => |b| if (b) .{ .int = 0 } else .{ .none = {} },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Power: self ** other
    pub fn pow(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0) {
                        // Negative exponent - return float
                        break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))) };
                    }
                    if (b > 63) {
                        // Would overflow i64 - return float
                        break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))) };
                    }
                    break :blk .{ .int = std.math.powi(i64, a, @intCast(b)) catch {
                        // Overflow - fall back to float
                        return .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))) };
                    } };
                },
                .float => |b| .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), b) },
                .bool => |b| .{ .int = if (b) a else 1 },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = std.math.pow(f64, a, @as(f64, @floatFromInt(b))) },
                .float => |b| .{ .float = std.math.pow(f64, a, b) },
                .bool => |b| .{ .float = if (b) a else 1.0 },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    const base: i64 = if (a) 1 else 0;
                    if (b < 0) break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(base)), @as(f64, @floatFromInt(b))) };
                    if (b > 63) break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(base)), @as(f64, @floatFromInt(b))) };
                    break :blk .{ .int = std.math.powi(i64, base, @intCast(b)) catch 1 };
                },
                .float => |b| .{ .float = std.math.pow(f64, @as(f64, if (a) 1.0 else 0.0), b) },
                .bool => |b| .{ .int = if (b) @as(i64, @intFromBool(a)) else 1 },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Negate a PyValue
    pub fn neg(self: PyValue) PyValue {
        return switch (self) {
            .int => |a| .{ .int = -%a },
            .float => |a| .{ .float = -a },
            .bool => |a| .{ .int = if (a) -1 else 0 },
            else => .{ .none = {} },
        };
    }

    // ============================================================================
    // Bitwise Operations (for Two-Flow uncertain operands)
    // ============================================================================

    /// Bitwise AND of two PyValues (a & b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitAnd(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a & b },
                .bool => |b| .{ .int = a & @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) & b },
                .bool => |b| .{ .bool = a and b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise OR of two PyValues (a | b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitOr(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a | b },
                .bool => |b| .{ .int = a | @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) | b },
                .bool => |b| .{ .bool = a or b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise XOR of two PyValues (a ^ b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyBitXor(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| .{ .int = a ^ b },
                .bool => |b| .{ .int = a ^ @as(i64, if (b) 1 else 0) },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| .{ .int = @as(i64, if (a) 1 else 0) ^ b },
                .bool => |b| .{ .bool = a != b },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise left shift of two PyValues (a << b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyLShift(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = a << @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (b) a << 1 else a },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = @as(i64, if (a) 1 else 0) << @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (a) (if (b) @as(i64, 2) else @as(i64, 1)) else 0 },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise right shift of two PyValues (a >> b)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyRShift(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = a >> @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (b) a >> 1 else a },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0 or b >= 64) break :blk .{ .none = {} };
                    break :blk .{ .int = @as(i64, if (a) 1 else 0) >> @as(u6, @intCast(b)) };
                },
                .bool => |b| .{ .int = if (a) (if (b) @as(i64, 0) else @as(i64, 1)) else 0 },
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Bitwise invert of a PyValue (~a)
    /// For Two-Flow: handles uncertain integer types at runtime
    pub fn pyInvert(self: PyValue) PyValue {
        return switch (self) {
            .int => |a| .{ .int = ~a },
            .bool => |a| .{ .int = if (a) -2 else -1 }, // ~True=-2, ~False=-1
            else => .{ .none = {} },
        };
    }

    /// Power of two PyValues (a ** b)
    /// For Two-Flow: handles uncertain numeric types at runtime
    pub fn pyPow(self: PyValue, other: PyValue) PyValue {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b < 0) {
                        // Negative exponent returns float
                        break :blk .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), @as(f64, @floatFromInt(b))) };
                    }
                    // Positive exponent returns int (with overflow)
                    var result: i64 = 1;
                    var base = a;
                    var exp = b;
                    while (exp > 0) {
                        if (exp & 1 == 1) result *%= base;
                        base *%= base;
                        exp >>= 1;
                    }
                    break :blk .{ .int = result };
                },
                .float => |b| .{ .float = std.math.pow(f64, @as(f64, @floatFromInt(a)), b) },
                .bool => |b| .{ .int = if (b) a else 1 },
                else => .{ .none = {} },
            },
            .float => |a| switch (other) {
                .int => |b| .{ .float = std.math.pow(f64, a, @as(f64, @floatFromInt(b))) },
                .float => |b| .{ .float = std.math.pow(f64, a, b) },
                .bool => |b| .{ .float = if (b) a else 1.0 },
                else => .{ .none = {} },
            },
            .bool => |a| switch (other) {
                .int => |b| blk: {
                    const base: i64 = if (a) 1 else 0;
                    if (b < 0) {
                        if (base == 0) break :blk .{ .none = {} }; // 0**-n is undefined
                        break :blk .{ .float = 1.0 }; // 1**-n = 1.0
                    }
                    break :blk .{ .int = if (a) 1 else (if (b == 0) @as(i64, 1) else @as(i64, 0)) };
                },
                .float => |b| .{ .float = std.math.pow(f64, if (a) 1.0 else 0.0, b) },
                .bool => |b| .{ .int = if (a) 1 else (if (b) 0 else 1) }, // 0**0=1, 0**1=0, 1**x=1
                else => .{ .none = {} },
            },
            else => .{ .none = {} },
        };
    }

    /// Compare two PyValues (less than)
    pub fn lt(self: PyValue, other: PyValue) bool {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| a < b,
                .float => |b| @as(f64, @floatFromInt(a)) < b,
                else => false,
            },
            .float => |a| switch (other) {
                .int => |b| a < @as(f64, @floatFromInt(b)),
                .float => |b| a < b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.order(u8, a, b) == .lt,
                else => false,
            },
            .object => |self_obj| blk: {
                // Python rich comparison protocol with subclass priority
                // For lt, the reflected operation is __gt__
                if (other == .object) {
                    const other_obj = other.object;
                    const other_is_subclass = other_obj.isProperSubclassOf(self_obj);

                    if (other_is_subclass) {
                        // Other is a subclass - try other.__gt__(self) first (reflected)
                        const other_result = callDunderMethod(other_obj, "__gt__", self);
                        if (other_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                        // Fallback to self.__lt__(other)
                        const self_result = callDunderMethod(self_obj, "__lt__", other);
                        if (self_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                    } else {
                        // Normal case - try self.__lt__(other) first
                        const self_result = callDunderMethod(self_obj, "__lt__", other);
                        if (self_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                        // Fallback to other.__gt__(self)
                        const other_result = callDunderMethod(other_obj, "__gt__", self);
                        if (other_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                    }
                } else {
                    // Other is not an object, just try self.__lt__(other)
                    const self_result = callDunderMethod(self_obj, "__lt__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) break :blk result.bool;
                            break :blk !isFalsy(result);
                        }
                    }
                }
                // Both returned NotImplemented, no ordering defined
                break :blk false;
            },
            else => false,
        };
    }

    /// Compare two PyValues (less than or equal)
    pub fn le(self: PyValue, other: PyValue) bool {
        // For .object instances, try __le__ first via vtable with subclass priority
        if (self == .object) {
            const self_obj = self.object;
            if (other == .object) {
                const other_obj = other.object;
                const other_is_subclass = other_obj.isProperSubclassOf(self_obj);

                if (other_is_subclass) {
                    // Other is a subclass - try other.__ge__(self) first (reflected)
                    const other_result = callDunderMethod(other_obj, "__ge__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to self.__le__(other)
                    const self_result = callDunderMethod(self_obj, "__le__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                } else {
                    // Normal case - try self.__le__(other) first
                    const self_result = callDunderMethod(self_obj, "__le__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to other.__ge__(self)
                    const other_result = callDunderMethod(other_obj, "__ge__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                }
            } else {
                // Other is not an object, just try self.__le__(other)
                const self_result = callDunderMethod(self_obj, "__le__", other);
                if (self_result) |result| {
                    if (result != .not_implemented) {
                        if (result == .bool) return result.bool;
                        return !isFalsy(result);
                    }
                }
            }
            // Both returned NotImplemented - Python would raise TypeError
            // For comparison purposes, return false (no ordering)
            return false;
        }
        // Fallback for non-object: __lt__ or __eq__
        return self.lt(other) or self.eql(other);
    }

    /// Compare two PyValues (greater than)
    pub fn gt(self: PyValue, other: PyValue) bool {
        // For .object instances, try __gt__ first via vtable with subclass priority
        if (self == .object) {
            const self_obj = self.object;
            if (other == .object) {
                const other_obj = other.object;
                const other_is_subclass = other_obj.isProperSubclassOf(self_obj);

                if (other_is_subclass) {
                    // Other is a subclass - try other.__lt__(self) first (reflected)
                    const other_result = callDunderMethod(other_obj, "__lt__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to self.__gt__(other)
                    const self_result = callDunderMethod(self_obj, "__gt__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                } else {
                    // Normal case - try self.__gt__(other) first
                    const self_result = callDunderMethod(self_obj, "__gt__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to other.__lt__(self)
                    const other_result = callDunderMethod(other_obj, "__lt__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                }
            } else {
                // Other is not an object, just try self.__gt__(other)
                const self_result = callDunderMethod(self_obj, "__gt__", other);
                if (self_result) |result| {
                    if (result != .not_implemented) {
                        if (result == .bool) return result.bool;
                        return !isFalsy(result);
                    }
                }
            }
            // Both returned NotImplemented, no ordering defined
            return false;
        }
        return other.lt(self);
    }

    /// Compare two PyValues (greater than or equal)
    pub fn ge(self: PyValue, other: PyValue) bool {
        // For .object instances, try __ge__ first via vtable with subclass priority
        if (self == .object) {
            const self_obj = self.object;
            if (other == .object) {
                const other_obj = other.object;
                const other_is_subclass = other_obj.isProperSubclassOf(self_obj);

                if (other_is_subclass) {
                    // Other is a subclass - try other.__le__(self) first (reflected)
                    const other_result = callDunderMethod(other_obj, "__le__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to self.__ge__(other)
                    const self_result = callDunderMethod(self_obj, "__ge__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                } else {
                    // Normal case - try self.__ge__(other) first
                    const self_result = callDunderMethod(self_obj, "__ge__", other);
                    if (self_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                    // Fallback to other.__le__(self)
                    const other_result = callDunderMethod(other_obj, "__le__", self);
                    if (other_result) |result| {
                        if (result != .not_implemented) {
                            if (result == .bool) return result.bool;
                            return !isFalsy(result);
                        }
                    }
                }
            } else {
                // Other is not an object, just try self.__ge__(other)
                const self_result = callDunderMethod(self_obj, "__ge__", other);
                if (self_result) |result| {
                    if (result != .not_implemented) {
                        if (result == .bool) return result.bool;
                        return !isFalsy(result);
                    }
                }
            }
            // Both returned NotImplemented - Python would raise TypeError
            // For comparison purposes, return false (no ordering)
            return false;
        }
        return other.lt(self) or self.eql(other);
    }

    /// Check if a PyValue is falsy (for truthiness testing)
    pub fn isFalsy(value: PyValue) bool {
        return switch (value) {
            .bool => |v| !v,
            .int => |v| v == 0,
            .float => |v| v == 0.0,
            .none => true,
            .not_implemented => false, // NotImplemented is truthy
            .string => |v| v.len == 0,
            .bytes => |v| v.data.len == 0,
            .list => |v| v.items.len == 0,
            .pylist => |v| v.ob_base.ob_size == 0,
            .tuple => |v| v.len == 0,
            .bigint => |v| v.isZero(),
            .complex => |v| v.real == 0.0 and v.imag == 0.0,
            .ptr, .type_obj, .object => false, // Objects are truthy by default
            // VM-specific types
            .dict => |d| d.count() == 0,
            .range => |r| blk: {
                // range is falsy if it's empty
                if (r.step > 0) break :blk r.start >= r.stop;
                if (r.step < 0) break :blk r.start <= r.stop;
                break :blk true; // step == 0 would be an error, treat as falsy
            },
            .code, .function, .builtin_fn, .iterator, .exception, .generator => false, // These are truthy by default
        };
    }

    /// Call a PyValue (callable protocol via __call__ dunder method)
    /// Returns error if the value is not callable
    pub fn call(self: PyValue, args: []const PyValue) !PyValue {
        return switch (self) {
            .object => |obj| {
                if (obj.vtable.__call__) |call_fn| {
                    return try call_fn(obj.ptr, args);
                }
                // Fallback: not callable
                @panic("PyValue object is not callable (no __call__ method)");
            },
            else => @panic("PyValue is not callable"),
        };
    }

    /// Try to call a dunder method on an object instance
    /// Returns null if the method doesn't exist, or the PyValue result if it does
    /// Uses vtable for dynamic dispatch
    fn callDunderMethod(obj: ObjectInstance, comptime method_name: []const u8, arg: PyValue) ?PyValue {
        const vtable = obj.vtable;

        if (std.mem.eql(u8, method_name, "__eq__")) {
            if (vtable.eq) |eq_fn| {
                return eq_fn(obj.ptr, arg);
            }
        } else if (std.mem.eql(u8, method_name, "__ne__")) {
            if (vtable.ne) |ne_fn| {
                return ne_fn(obj.ptr, arg);
            }
        } else if (std.mem.eql(u8, method_name, "__lt__")) {
            if (vtable.lt) |lt_fn| {
                return lt_fn(obj.ptr, arg);
            }
        } else if (std.mem.eql(u8, method_name, "__le__")) {
            if (vtable.le) |le_fn| {
                return le_fn(obj.ptr, arg);
            }
        } else if (std.mem.eql(u8, method_name, "__gt__")) {
            if (vtable.gt) |gt_fn| {
                return gt_fn(obj.ptr, arg);
            }
        } else if (std.mem.eql(u8, method_name, "__ge__")) {
            if (vtable.ge) |ge_fn| {
                return ge_fn(obj.ptr, arg);
            }
        }

        return null;
    }

    /// Helper to call __eq__ on PyValue.object instances
    /// This uses a function pointer approach for dynamic dispatch
    pub fn callObjectEq(a_obj: ObjectInstance, b_obj: ObjectInstance, b_pyval: PyValue) ?PyValue {
        // Check if we have a vtable-style eq function pointer
        // For now, return null to indicate we can't dispatch
        // Generated code should provide type-specific implementations
        _ = a_obj;
        _ = b_obj;
        _ = b_pyval;
        return null;
    }

    /// Check equality with another PyValue (single concrete function - no anytype)
    /// Implements Python's rich comparison semantics:
    /// - bool is subtype of int (True=1, False=0)
    /// - int and float are comparable
    /// - complex with zero imaginary part is comparable to real numbers
    pub fn eql(self: PyValue, other: PyValue) bool {
        const self_tag = std.meta.activeTag(self);
        const other_tag = std.meta.activeTag(other);

        // Same type - direct comparison
        if (self_tag == other_tag) {
            return switch (self) {
                .int => |v| v == other.int,
                // Use bit-level comparison for NaN identity semantics
                // In Python containers, nan == nan returns True (same object identity)
                .float => |v| @as(u64, @bitCast(v)) == @as(u64, @bitCast(other.float)),
                .string => |v| std.mem.eql(u8, v, other.string),
                .bytes => |v| std.mem.eql(u8, v.data, other.bytes.data),
                .bool => |v| v == other.bool,
                .none => true,
                .not_implemented => false, // NotImplemented is never equal to anything
                .list => |list| blk: {
                    const other_list = other.list;
                    if (list.items.len != other_list.items.len) break :blk false;
                    for (list.items, other_list.items) |a, b| {
                        if (!a.eql(b)) break :blk false;
                    }
                    break :blk true;
                },
                .pylist => |v| v == other.pylist, // CPython list identity comparison
                .tuple => |v| blk: {
                    const w = other.tuple;
                    if (v.len != w.len) break :blk false;
                    for (v, w) |a, b| {
                        if (!a.eql(b)) break :blk false;
                    }
                    break :blk true;
                },
                .bigint => |v| v.eql(&other.bigint),
                .complex => |v| v.real == other.complex.real and v.imag == other.complex.imag,
                .type_obj => |v| v == other.type_obj,
                .ptr => |self_ptr| blk: {
                    const other_ptr = other.ptr;
                    // No type information available for .ptr - use identity comparison
                    // For typed class instances, use .object variant instead
                    break :blk self_ptr == other_ptr;
                },
                .object => |self_obj| blk: {
                    const other_obj = other.object;
                    // Python rich comparison protocol with subclass priority
                    // If other is a proper subclass of self, try other's method FIRST
                    // This implements Python's rule: subclass __eq__ takes priority
                    const other_is_subclass = other_obj.isProperSubclassOf(self_obj);

                    if (other_is_subclass) {
                        // Other is a subclass - try other.__eq__(self) first
                        const other_result = callDunderMethod(other_obj, "__eq__", self);
                        if (other_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                        // Fallback to self.__eq__(other)
                        const self_result = callDunderMethod(self_obj, "__eq__", other);
                        if (self_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                    } else {
                        // Normal case - try self.__eq__(other) first
                        const self_result = callDunderMethod(self_obj, "__eq__", other);
                        if (self_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                        // Fallback to other.__eq__(self)
                        const other_result = callDunderMethod(other_obj, "__eq__", self);
                        if (other_result) |result| {
                            if (result != .not_implemented) {
                                if (result == .bool) break :blk result.bool;
                                break :blk !isFalsy(result);
                            }
                        }
                    }

                    // Both returned NotImplemented, fall back to identity
                    break :blk self_obj.ptr == other_obj.ptr;
                },
                // VM-specific types - use identity comparison
                .dict => |d| d == other.dict,
                .code => |c| c == other.code,
                .function => |f| f == other.function,
                .builtin_fn => |b| b == other.builtin_fn,
                .iterator => |i| i == other.iterator,
                .range => |r| r.start == other.range.start and r.stop == other.range.stop and r.step == other.range.step,
                .exception => |e| e == other.exception,
                .generator => |g| g == other.generator,
            };
        }

        // Python numeric coercion: bool < int < float < complex < bigint
        // Convert both to the "higher" type and compare

        // Special case: BigInt vs int - compare as BigInt for precision
        if (self_tag == .bigint and other_tag == .int) {
            return self.bigint.eqlInt(other.int);
        }
        if (self_tag == .int and other_tag == .bigint) {
            return other.bigint.eqlInt(self.int);
        }

        // Helper to get numeric value as complex (real, imag)
        // NOTE: BigInt.toFloat() may lose precision for very large numbers
        const self_num: ?struct { real: f64, imag: f64 } = switch (self) {
            .bool => |v| .{ .real = if (v) 1.0 else 0.0, .imag = 0.0 },
            .int => |v| .{ .real = @floatFromInt(v), .imag = 0.0 },
            .float => |v| .{ .real = v, .imag = 0.0 },
            .complex => |v| .{ .real = v.real, .imag = v.imag },
            .bigint => |v| .{ .real = v.toFloat(), .imag = 0.0 },
            else => null,
        };

        const other_num: ?struct { real: f64, imag: f64 } = switch (other) {
            .bool => |v| .{ .real = if (v) 1.0 else 0.0, .imag = 0.0 },
            .int => |v| .{ .real = @floatFromInt(v), .imag = 0.0 },
            .float => |v| .{ .real = v, .imag = 0.0 },
            .complex => |v| .{ .real = v.real, .imag = v.imag },
            .bigint => |v| .{ .real = v.toFloat(), .imag = 0.0 },
            else => null,
        };

        // If both are numeric types, compare as complex
        if (self_num != null and other_num != null) {
            return self_num.?.real == other_num.?.real and self_num.?.imag == other_num.?.imag;
        }

        // Handle .object vs primitive types - call object's __eq__ method
        if (self_tag == .object) {
            const self_obj = self.object;
            const result = callDunderMethod(self_obj, "__eq__", other);
            if (result) |res| {
                if (res != .not_implemented) {
                    if (res == .bool) return res.bool;
                    return !isFalsy(res);
                }
            }
            // __eq__ returned NotImplemented - try reflected comparison
            // (Other primitive types don't have __eq__ so fall through to false)
        }

        // Handle primitive vs .object - call object's __eq__ method (reflected)
        if (other_tag == .object) {
            const other_obj = other.object;
            const result = callDunderMethod(other_obj, "__eq__", self);
            if (result) |res| {
                if (res != .not_implemented) {
                    if (res == .bool) return res.bool;
                    return !isFalsy(res);
                }
            }
            // __eq__ returned NotImplemented - fall through to false
        }

        // Non-numeric different types are not equal
        return false;
    }

    // ============================================================================
    // Aggregate Operations (for Two-Flow uncertain iterables)
    // ============================================================================

    /// Sum all values in a PyValue list
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pySum(self: PyValue) PyValue {
        return switch (self) {
            .list => |list| {
                var total: PyValue = .{ .int = 0 };
                for (list.items) |item| {
                    total = total.add(item);
                }
                return total;
            },
            .tuple => |items| {
                var total: PyValue = .{ .int = 0 };
                for (items) |item| {
                    total = total.add(item);
                }
                return total;
            },
            // Single numeric value - return as is
            .int, .float => self,
            else => .{ .int = 0 },
        };
    }

    /// Check if all values in a PyValue list are truthy
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pyAll(self: PyValue) bool {
        return switch (self) {
            .list => |list| {
                for (list.items) |item| {
                    if (!item.isTruthy()) return false;
                }
                return true;
            },
            .tuple => |items| {
                for (items) |item| {
                    if (!item.isTruthy()) return false;
                }
                return true;
            },
            // Single value - return its truthiness
            else => self.isTruthy(),
        };
    }

    /// Check if any value in a PyValue list is truthy
    /// For Two-Flow: handles uncertain iterables at runtime
    pub fn pyAny(self: PyValue) bool {
        return switch (self) {
            .list => |list| {
                for (list.items) |item| {
                    if (item.isTruthy()) return true;
                }
                return false;
            },
            .tuple => |items| {
                for (items) |item| {
                    if (item.isTruthy()) return true;
                }
                return false;
            },
            // Single value - return its truthiness
            else => self.isTruthy(),
        };
    }

    // ============================================================================
    // Math Operations (for Two-Flow uncertain operands)
    // ============================================================================

    /// Absolute value of a PyValue
    /// For Two-Flow: handles uncertain numeric types at runtime
    pub fn pyAbs(self: PyValue) PyValue {
        return switch (self) {
            .int => |v| .{ .int = if (v < 0) -v else v },
            .float => |v| .{ .float = @abs(v) },
            .bool => |v| .{ .int = if (v) 1 else 0 },
            else => .{ .int = 0 },
        };
    }

    /// Minimum of two PyValues
    /// For Two-Flow: handles uncertain operands at runtime
    pub fn pyMin(self: PyValue, other: PyValue) PyValue {
        // Use lt() for comparison
        if (self.lt(other)) {
            return self;
        } else {
            return other;
        }
    }

    /// Maximum of two PyValues
    /// For Two-Flow: handles uncertain operands at runtime
    pub fn pyMax(self: PyValue, other: PyValue) PyValue {
        // Use gt() for comparison
        if (self.gt(other)) {
            return self;
        } else {
            return other;
        }
    }

    /// Hash value of a PyValue
    /// For Two-Flow: handles uncertain types at runtime
    pub fn pyHash(self: PyValue) i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| blk: {
                // Python's float hash - if it's a whole number, use the int hash
                const int_val = @as(i64, @intFromFloat(v));
                if (@as(f64, @floatFromInt(int_val)) == v) {
                    break :blk int_val;
                }
                // Otherwise use bit cast
                break :blk @as(i64, @bitCast(v));
            },
            .bool => |v| if (v) 1 else 0,
            .string => |v| @as(i64, @bitCast(std.hash.Wyhash.hash(0, v))),
            .none => 0,
            else => 0,
        };
    }

    // ============================================================================
    // Context Manager Protocol (__enter__ / __exit__)
    // ============================================================================

    /// Context manager __enter__ - returns self for simple context managers
    /// For VM fallback results, this provides minimal context manager support
    pub fn __enter__(self: PyValue, allocator: std.mem.Allocator) !PyValue {
        _ = allocator;
        // For most PyValue types, __enter__ just returns self
        // Object types may have custom __enter__ methods via vtable
        switch (self) {
            .object => |obj| {
                // Try to call __enter__ on the underlying object if it exists
                if (obj.vtable.__call__) |call_fn| {
                    _ = call_fn;
                    // Context managers typically just return self
                }
                return self;
            },
            else => return self,
        }
    }

    /// Context manager __exit__ - cleanup method
    /// For VM fallback results, this provides minimal context manager support
    pub fn __exit__(self: PyValue, allocator: std.mem.Allocator, exc_type: ?PyValue, exc_val: ?PyValue, exc_tb: ?PyValue) !bool {
        _ = allocator;
        _ = exc_type;
        _ = exc_val;
        _ = exc_tb;
        // For most PyValue types, __exit__ does nothing and returns false
        // (meaning exceptions should propagate)
        switch (self) {
            .object => |_| {
                // Object types may have custom __exit__ methods
                return false;
            },
            else => return false,
        }
    }
};

/// Convert any value to PyValue (single-anytype function, O(n) instantiations)
/// This is the foundation for PyValue.from() - unified comparison via PyValue.eql()
pub fn toPyValue(allocator: std.mem.Allocator, value: anytype) !PyValue {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Direct matches
    if (T == PyValue) return value;
    if (T == bigint.BigInt) return .{ .bigint = value };
    if (T == i64 or T == i32 or T == i16 or T == i8) return .{ .int = @intCast(value) };
    // Unsigned integers - check if they fit in i64, otherwise use BigInt
    if (T == u64 or T == usize) {
        if (value <= std.math.maxInt(i64)) {
            return .{ .int = @intCast(value) };
        } else {
            // Value exceeds i64 max, convert to BigInt
            return .{ .bigint = try bigint.BigInt.fromInt128(allocator, @as(i128, value)) };
        }
    }
    if (T == u32 or T == u16 or T == u8) return .{ .int = @intCast(value) };
    if (T == f64 or T == f32) return .{ .float = @floatCast(value) };
    if (T == bool) return .{ .bool = value };
    if (info == .comptime_int) return .{ .int = @intCast(value) };
    if (info == .comptime_float) return .{ .float = @floatCast(value) };

    // Complex numbers (PyComplex struct has .real and .imag fields)
    if (info == .@"struct" and @hasField(T, "real") and @hasField(T, "imag")) {
        return .{ .complex = .{ .real = value.real, .imag = value.imag } };
    }

    // PyObject pointer - extract the actual value from CPython-style object
    // This handles results from BytecodeVM.execute() which returns *PyObject
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const runtime = @import("../runtime.zig");
        // Check if it's a *PyObject (the base type) or compatible pointer
        if (Child == runtime.PyObject or
            (@typeInfo(Child) == .@"struct" and @hasField(Child, "ob_base")))
        {
            // Cast to *PyObject and extract value based on type
            const obj: *runtime.PyObject = @ptrCast(@alignCast(value));
            if (runtime.PyLong_Check(obj)) {
                const PyInt = @import("intobject.zig").PyInt;
                return .{ .int = PyInt.getValue(obj) };
            }
            if (runtime.PyFloat_Check(obj)) {
                const PyFloat = @import("floatobject.zig").PyFloat;
                return .{ .float = PyFloat.getValue(obj) };
            }
            if (runtime.PyBool_Check(obj)) {
                const PyBool = @import("boolobject.zig").PyBool;
                return .{ .bool = PyBool.getValue(obj) };
            }
            if (runtime.PyUnicode_Check(obj)) {
                const PyString = @import("stringlib/core.zig").PyString;
                return .{ .string = PyString.getValue(obj) };
            }
            // Fall through to ptr for other PyObject types
        }
    }

    // String slices
    if (T == []const u8) return .{ .string = value };
    if (T == []u8) return .{ .string = value };

    // String literals: *const [N:0]u8 - pointer to null-terminated array
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            // Convert *const [N]u8 or *const [N:0]u8 to []const u8
            return .{ .string = value[0..child_info.array.len] };
        }
    }

    // Fixed arrays of u8 (strings)
    if (info == .array and info.array.child == u8) {
        return .{ .string = &value };
    }

    // NativeList - special handling (has .items which is ArrayListUnmanaged)
    // NativeList.items contains PyValue items, so just return them directly
    if (info == .@"struct" and @hasDecl(T, "init") and @hasField(T, "items")) {
        // Check if items field is an ArrayListUnmanaged by checking for items.items
        const ItemsT = @TypeOf(value.items);
        if (@typeInfo(ItemsT) == .@"struct" and @hasField(ItemsT, "items")) {
            // This is NativeList or similar wrapper - items.items is the slice
            return try PyValue.listFromSlice(allocator, value.items.items);
        }
    }

    // ArrayLists - convert items to PyValue list
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        const ElemT = std.meta.Elem(@TypeOf(value.items));
        var list = try allocator.alloc(PyValue, value.items.len);
        for (value.items, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
            _ = ElemT; // Reference to avoid unused warning
        }
        return try PyValue.listFromSlice(allocator, list);
    }

    // Fixed arrays
    if (info == .array) {
        var list = try allocator.alloc(PyValue, info.array.len);
        for (value, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
        }
        return try PyValue.listFromSlice(allocator, list);
    }

    // Slices of non-u8
    if (info == .pointer and info.pointer.size == .slice and info.pointer.child != u8) {
        var list = try allocator.alloc(PyValue, value.len);
        for (value, 0..) |item, i| {
            list[i] = try toPyValue(allocator, item);
        }
        // Use listFromSlice to properly allocate ArrayList on heap
        return try PyValue.listFromSlice(allocator, list);
    }

    // Tagged unions (IntResult, PyPowResult, etc.) - extract active field and convert
    // This handles unions like IntResult{ .small = 5 } -> PyValue{ .int = 5 }
    if (info == .@"union" and info.@"union".tag_type != null) {
        // Get the active tag and extract the value
        const tag = std.meta.activeTag(value);
        inline for (info.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(T), field.name)) {
                const field_value = @field(value, field.name);
                return try toPyValue(allocator, field_value);
            }
        }
    }

    // Fallback: store as opaque pointer
    return .{ .ptr = @ptrCast(@constCast(&value)) };
}

/// Optimized string comparison using comptime SIMD if available
/// Falls back to std.mem.eql for smaller strings
pub fn eqlString(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len == 0) return true;

    // Use comptime to select best comparison method
    const use_simd = comptime blk: {
        // SIMD is beneficial for strings >= 16 bytes on most platforms
        const min_simd_len = 16;
        // Check if platform supports SIMD
        const has_simd = @import("builtin").cpu.arch.endian() == .little;
        break :blk has_simd and a.len >= min_simd_len;
    };

    if (use_simd) {
        // For longer strings, use vectorized comparison
        return simdEql(a, b);
    } else {
        // For short strings, use standard comparison
        return std.mem.eql(u8, a, b);
    }
}

/// SIMD-optimized string equality check
fn simdEql(a: []const u8, b: []const u8) bool {
    const len = a.len;

    // Process 16 bytes at a time using @Vector
    const vec_len = 16;
    const Vec = @Vector(vec_len, u8);

    var i: usize = 0;
    while (i + vec_len <= len) : (i += vec_len) {
        const va: Vec = a[i..][0..vec_len].*;
        const vb: Vec = b[i..][0..vec_len].*;

        // Compare vectors element-wise
        if (!@reduce(.And, va == vb)) {
            return false;
        }
    }

    // Handle remaining bytes
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }

    return true;
}

test "PyValue basic operations" {
    const testing = std.testing;

    const v_int = PyValue{ .int = 42 };
    const v_float = PyValue{ .float = 3.14 };
    const v_bool = PyValue{ .bool = true };
    const v_none = PyValue{ .none = {} };

    try testing.expectEqual(@as(i64, 42), v_int.toInt().?);
    try testing.expectEqual(@as(f64, 3.14), v_float.toFloat().?);
    try testing.expect(v_bool.isTruthy());
    try testing.expect(!v_none.isTruthy());
}

test "SIMD string comparison" {
    const testing = std.testing;

    const str1 = "hello world from metal0 compiler!";
    const str2 = "hello world from metal0 compiler!";
    const str3 = "hello world from metal0 compiler?";

    try testing.expect(eqlString(str1, str2));
    try testing.expect(!eqlString(str1, str3));
    try testing.expect(eqlString("", ""));
    try testing.expect(!eqlString("a", ""));
}

// =============================================================================
// PyValue HashMap Support
// =============================================================================

/// Hash context for PyValue keys in ArrayHashMap
/// Enables non-string dict keys (tuples, ints, bools, etc.)
/// Uses PyValue.pyHash() for hashing and PyValue.eql() for equality
pub const PyValueHashContext = struct {
    pub fn hash(_: @This(), key: PyValue) u32 {
        // Use PyValue's pyHash which handles all types
        const h = key.pyHash();
        // Truncate i64 hash to u32 for ArrayHashMap
        return @truncate(@as(u64, @bitCast(h)));
    }

    pub fn eql(_: @This(), a: PyValue, b: PyValue, _: usize) bool {
        // Use PyValue's eql which handles all type combinations
        return a.eql(b);
    }
};

/// HashMap with PyValue keys - for Python dicts with non-string keys
/// Uses ArrayHashMap for O(n) iteration and better cache locality
/// Example:
///   var dict: runtime.PyValueHashMap(runtime.PyValue) = .{};
///   dict.put(allocator, .{ .int = 42 }, .{ .string = "value" });
///   dict.put(allocator, .{ .tuple = &[_]PyValue{.{ .int = 1 }, .{ .int = 2 }} }, .{ .string = "tuple key" });
pub fn PyValueHashMap(comptime V: type) type {
    return std.ArrayHashMap(PyValue, V, PyValueHashContext, true);
}
