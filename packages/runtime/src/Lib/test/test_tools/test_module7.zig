//! test.test_tools.test_c_analyzer - C code analysis testing
//! Tests for Python's C code analysis tools used for extension modules
//! and CPython internals analysis.

const std = @import("std");

/// C type representation
pub const CType = struct {
    base_type: BaseType,
    qualifiers: Qualifiers = .{},
    pointer_depth: u8 = 0,
    array_size: ?usize = null,

    pub const BaseType = enum {
        void,
        char,
        short,
        int,
        long,
        long_long,
        float_type,
        double,
        long_double,
        bool_type,
        size_t,
        ssize_t,
        ptrdiff_t,
        py_object,
        py_object_ptr,
        py_ssize_t,
        custom,
    };

    pub const Qualifiers = struct {
        is_const: bool = false,
        is_volatile: bool = false,
        is_restrict: bool = false,
        is_unsigned: bool = false,
        is_signed: bool = false,
    };

    pub fn isPointer(self: CType) bool {
        return self.pointer_depth > 0;
    }

    pub fn isArray(self: CType) bool {
        return self.array_size != null;
    }

    pub fn isNumeric(self: CType) bool {
        return switch (self.base_type) {
            .char, .short, .int, .long, .long_long, .float_type, .double, .long_double => true,
            else => false,
        };
    }

    pub fn isPyObject(self: CType) bool {
        return self.base_type == .py_object or self.base_type == .py_object_ptr;
    }

    pub fn sizeBytes(self: CType) ?usize {
        if (self.isPointer()) return 8; // 64-bit
        return switch (self.base_type) {
            .void => 0,
            .bool_type, .char => 1,
            .short => 2,
            .int, .float_type => 4,
            .long, .double, .size_t, .ssize_t, .ptrdiff_t, .py_ssize_t => 8,
            .long_long => 8,
            .long_double => 16,
            .py_object, .py_object_ptr => 8,
            .custom => null,
        };
    }
};

/// C function declaration
pub const CFunction = struct {
    name: []const u8,
    return_type: CType,
    parameters: []const Parameter,
    is_static: bool = false,
    is_inline: bool = false,
    is_variadic: bool = false,
    calling_convention: CallingConvention = .cdecl,

    pub const Parameter = struct {
        name: ?[]const u8,
        param_type: CType,
    };

    pub const CallingConvention = enum {
        cdecl,
        stdcall,
        fastcall,
        vectorcall,
    };

    pub fn parameterCount(self: CFunction) usize {
        return self.parameters.len;
    }

    pub fn hasVarArgs(self: CFunction) bool {
        return self.is_variadic;
    }

    pub fn isPyMethod(self: CFunction) bool {
        // Check if this looks like a Python method
        if (self.parameters.len == 0) return false;
        return self.parameters[0].param_type.isPyObject();
    }

    pub fn isNoReturn(self: CFunction) bool {
        return self.return_type.base_type == .void and !self.return_type.isPointer();
    }
};

/// C struct definition
pub const CStruct = struct {
    name: []const u8,
    fields: []const Field,
    is_packed: bool = false,
    is_union: bool = false,
    alignment: ?usize = null,

    pub const Field = struct {
        name: []const u8,
        field_type: CType,
        bit_width: ?u8 = null,
        offset: ?usize = null,
    };

    pub fn fieldCount(self: CStruct) usize {
        return self.fields.len;
    }

    pub fn getField(self: CStruct, name: []const u8) ?Field {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field;
            }
        }
        return null;
    }

    pub fn hasField(self: CStruct, name: []const u8) bool {
        return self.getField(name) != null;
    }

    pub fn estimateSize(self: CStruct) usize {
        var size: usize = 0;
        for (self.fields) |field| {
            if (field.field_type.sizeBytes()) |field_size| {
                size += field_size;
            }
        }
        return size;
    }
};

/// C preprocessor definition
pub const Preprocessor = struct {
    allocator: std.mem.Allocator,
    defines: std.StringHashMap(Define),
    includes: std.ArrayList([]const u8),

    pub const Define = struct {
        name: []const u8,
        value: ?[]const u8,
        parameters: ?[]const []const u8 = null, // For function-like macros
        is_builtin: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Preprocessor {
        return .{
            .allocator = allocator,
            .defines = std.StringHashMap(Define).init(allocator),
            .includes = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Preprocessor) void {
        self.defines.deinit();
        self.includes.deinit();
    }

    pub fn define(self: *Preprocessor, name: []const u8, value: ?[]const u8) !void {
        try self.defines.put(name, .{ .name = name, .value = value });
    }

    pub fn undef(self: *Preprocessor, name: []const u8) void {
        _ = self.defines.remove(name);
    }

    pub fn isDefined(self: Preprocessor, name: []const u8) bool {
        return self.defines.contains(name);
    }

    pub fn getValue(self: Preprocessor, name: []const u8) ?[]const u8 {
        if (self.defines.get(name)) |def| {
            return def.value;
        }
        return null;
    }

    pub fn addInclude(self: *Preprocessor, path: []const u8) !void {
        try self.includes.append(path);
    }

    pub fn isFunctionMacro(self: Preprocessor, name: []const u8) bool {
        if (self.defines.get(name)) |def| {
            return def.parameters != null;
        }
        return false;
    }
};

/// C symbol table for analysis
pub const CSymbolTable = struct {
    allocator: std.mem.Allocator,
    functions: std.StringHashMap(CFunction),
    structs: std.StringHashMap(CStruct),
    typedefs: std.StringHashMap(CType),
    enums: std.StringHashMap(CEnum),
    globals: std.StringHashMap(GlobalVar),

    pub const CEnum = struct {
        name: []const u8,
        values: []const EnumValue,

        pub const EnumValue = struct {
            name: []const u8,
            value: ?i64 = null,
        };
    };

    pub const GlobalVar = struct {
        name: []const u8,
        var_type: CType,
        is_extern: bool = false,
        is_static: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) CSymbolTable {
        return .{
            .allocator = allocator,
            .functions = std.StringHashMap(CFunction).init(allocator),
            .structs = std.StringHashMap(CStruct).init(allocator),
            .typedefs = std.StringHashMap(CType).init(allocator),
            .enums = std.StringHashMap(CEnum).init(allocator),
            .globals = std.StringHashMap(GlobalVar).init(allocator),
        };
    }

    pub fn deinit(self: *CSymbolTable) void {
        self.functions.deinit();
        self.structs.deinit();
        self.typedefs.deinit();
        self.enums.deinit();
        self.globals.deinit();
    }

    pub fn addFunction(self: *CSymbolTable, func: CFunction) !void {
        try self.functions.put(func.name, func);
    }

    pub fn addStruct(self: *CSymbolTable, s: CStruct) !void {
        try self.structs.put(s.name, s);
    }

    pub fn addTypedef(self: *CSymbolTable, name: []const u8, t: CType) !void {
        try self.typedefs.put(name, t);
    }

    pub fn addEnum(self: *CSymbolTable, e: CEnum) !void {
        try self.enums.put(e.name, e);
    }

    pub fn getFunction(self: CSymbolTable, name: []const u8) ?CFunction {
        return self.functions.get(name);
    }

    pub fn getStruct(self: CSymbolTable, name: []const u8) ?CStruct {
        return self.structs.get(name);
    }

    pub fn resolveTypedef(self: CSymbolTable, name: []const u8) ?CType {
        return self.typedefs.get(name);
    }
};

/// C API slot analyzer for Python extension modules
pub const SlotAnalyzer = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayList(Slot),

    pub const Slot = struct {
        name: []const u8,
        slot_type: SlotType,
        function: ?[]const u8 = null,
        offset: ?usize = null,

        pub const SlotType = enum {
            // Number protocol
            nb_add,
            nb_subtract,
            nb_multiply,
            nb_true_divide,
            nb_floor_divide,
            nb_remainder,
            nb_power,
            nb_negative,
            nb_positive,
            nb_absolute,
            nb_bool,
            nb_invert,
            nb_lshift,
            nb_rshift,
            nb_and,
            nb_xor,
            nb_or,
            nb_int,
            nb_float,
            // Sequence protocol
            sq_length,
            sq_concat,
            sq_repeat,
            sq_item,
            sq_ass_item,
            sq_contains,
            sq_inplace_concat,
            sq_inplace_repeat,
            // Mapping protocol
            mp_length,
            mp_subscript,
            mp_ass_subscript,
            // Type slots
            tp_new,
            tp_init,
            tp_dealloc,
            tp_repr,
            tp_str,
            tp_hash,
            tp_call,
            tp_getattr,
            tp_setattr,
            tp_getattro,
            tp_setattro,
            tp_richcompare,
            tp_iter,
            tp_iternext,
            // Buffer protocol
            bf_getbuffer,
            bf_releasebuffer,
        };
    };

    pub fn init(allocator: std.mem.Allocator) SlotAnalyzer {
        return .{
            .allocator = allocator,
            .slots = std.ArrayList(Slot).init(allocator),
        };
    }

    pub fn deinit(self: *SlotAnalyzer) void {
        self.slots.deinit();
    }

    pub fn addSlot(self: *SlotAnalyzer, slot: Slot) !void {
        try self.slots.append(slot);
    }

    pub fn getSlot(self: SlotAnalyzer, slot_type: Slot.SlotType) ?Slot {
        for (self.slots.items) |slot| {
            if (slot.slot_type == slot_type) return slot;
        }
        return null;
    }

    pub fn hasSlot(self: SlotAnalyzer, slot_type: Slot.SlotType) bool {
        return self.getSlot(slot_type) != null;
    }

    pub fn slotCount(self: SlotAnalyzer) usize {
        return self.slots.items.len;
    }
};

/// Reference counting analyzer
pub const RefCountAnalyzer = struct {
    allocator: std.mem.Allocator,
    issues: std.ArrayList(Issue),

    pub const Issue = struct {
        kind: Kind,
        location: []const u8,
        variable: []const u8,
        message: []const u8,

        pub const Kind = enum {
            missing_incref,
            missing_decref,
            double_decref,
            use_after_decref,
            borrowed_ref_leak,
            new_ref_leak,
        };
    };

    pub fn init(allocator: std.mem.Allocator) RefCountAnalyzer {
        return .{
            .allocator = allocator,
            .issues = std.ArrayList(Issue).init(allocator),
        };
    }

    pub fn deinit(self: *RefCountAnalyzer) void {
        self.issues.deinit();
    }

    pub fn addIssue(self: *RefCountAnalyzer, issue: Issue) !void {
        try self.issues.append(issue);
    }

    pub fn hasIssues(self: RefCountAnalyzer) bool {
        return self.issues.items.len > 0;
    }

    pub fn countByKind(self: RefCountAnalyzer, kind: Issue.Kind) usize {
        var count: usize = 0;
        for (self.issues.items) |issue| {
            if (issue.kind == kind) count += 1;
        }
        return count;
    }
};

/// ABI compatibility checker
pub const ABIChecker = struct {
    allocator: std.mem.Allocator,
    stable_abi_version: []const u8,
    warnings: std.ArrayList(Warning),

    pub const Warning = struct {
        symbol: []const u8,
        kind: Kind,
        message: []const u8,

        pub const Kind = enum {
            not_in_stable_abi,
            abi_version_mismatch,
            deprecated_symbol,
            internal_use_only,
        };
    };

    pub fn init(allocator: std.mem.Allocator, version: []const u8) ABIChecker {
        return .{
            .allocator = allocator,
            .stable_abi_version = version,
            .warnings = std.ArrayList(Warning).init(allocator),
        };
    }

    pub fn deinit(self: *ABIChecker) void {
        self.warnings.deinit();
    }

    pub fn checkSymbol(self: *ABIChecker, symbol: []const u8) !void {
        // Check if symbol starts with underscore (internal)
        if (std.mem.startsWith(u8, symbol, "_Py") or std.mem.startsWith(u8, symbol, "_PyCFunction")) {
            try self.warnings.append(.{
                .symbol = symbol,
                .kind = .internal_use_only,
                .message = "Symbol is internal and not part of stable ABI",
            });
        }
    }

    pub fn hasWarnings(self: ABIChecker) bool {
        return self.warnings.items.len > 0;
    }
};

// Tests
test "ctype_basic" {
    const int_type = CType{
        .base_type = .int,
    };
    try std.testing.expect(int_type.isNumeric());
    try std.testing.expect(!int_type.isPointer());
    try std.testing.expectEqual(@as(?usize, 4), int_type.sizeBytes());
}

test "ctype_pointer" {
    const ptr_type = CType{
        .base_type = .char,
        .pointer_depth = 1,
    };
    try std.testing.expect(ptr_type.isPointer());
    try std.testing.expectEqual(@as(?usize, 8), ptr_type.sizeBytes());
}

test "ctype_pyobject" {
    const py_type = CType{
        .base_type = .py_object_ptr,
    };
    try std.testing.expect(py_type.isPyObject());
}

test "ctype_const" {
    const const_char = CType{
        .base_type = .char,
        .qualifiers = .{ .is_const = true },
        .pointer_depth = 1,
    };
    try std.testing.expect(const_char.qualifiers.is_const);
    try std.testing.expect(const_char.isPointer());
}

test "cfunction_basic" {
    const func = CFunction{
        .name = "my_func",
        .return_type = .{ .base_type = .int },
        .parameters = &[_]CFunction.Parameter{
            .{ .name = "a", .param_type = .{ .base_type = .int } },
            .{ .name = "b", .param_type = .{ .base_type = .int } },
        },
    };
    try std.testing.expectEqual(@as(usize, 2), func.parameterCount());
    try std.testing.expect(!func.hasVarArgs());
    try std.testing.expect(!func.isPyMethod());
}

test "cfunction_pymethod" {
    const method = CFunction{
        .name = "mytype_method",
        .return_type = .{ .base_type = .py_object_ptr },
        .parameters = &[_]CFunction.Parameter{
            .{ .name = "self", .param_type = .{ .base_type = .py_object_ptr } },
            .{ .name = "args", .param_type = .{ .base_type = .py_object_ptr } },
        },
    };
    try std.testing.expect(method.isPyMethod());
}

test "cstruct_basic" {
    const s = CStruct{
        .name = "MyStruct",
        .fields = &[_]CStruct.Field{
            .{ .name = "x", .field_type = .{ .base_type = .int } },
            .{ .name = "y", .field_type = .{ .base_type = .int } },
            .{ .name = "name", .field_type = .{ .base_type = .char, .pointer_depth = 1 } },
        },
    };
    try std.testing.expectEqual(@as(usize, 3), s.fieldCount());
    try std.testing.expect(s.hasField("x"));
    try std.testing.expect(!s.hasField("z"));
}

test "preprocessor" {
    var pp = Preprocessor.init(std.testing.allocator);
    defer pp.deinit();

    try pp.define("DEBUG", "1");
    try pp.define("VERSION", "\"1.0\"");
    try pp.define("NDEBUG", null);

    try std.testing.expect(pp.isDefined("DEBUG"));
    try std.testing.expect(pp.isDefined("NDEBUG"));
    try std.testing.expectEqualStrings("1", pp.getValue("DEBUG").?);

    pp.undef("DEBUG");
    try std.testing.expect(!pp.isDefined("DEBUG"));
}

test "csymboltable" {
    var table = CSymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.addFunction(.{
        .name = "my_func",
        .return_type = .{ .base_type = .int },
        .parameters = &.{},
    });

    try table.addStruct(.{
        .name = "MyStruct",
        .fields = &[_]CStruct.Field{
            .{ .name = "value", .field_type = .{ .base_type = .int } },
        },
    });

    try table.addTypedef("myint", .{ .base_type = .int });

    const func = table.getFunction("my_func");
    try std.testing.expect(func != null);

    const s = table.getStruct("MyStruct");
    try std.testing.expect(s != null);

    const t = table.resolveTypedef("myint");
    try std.testing.expect(t != null);
    try std.testing.expectEqual(CType.BaseType.int, t.?.base_type);
}

test "slot_analyzer" {
    var analyzer = SlotAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    try analyzer.addSlot(.{
        .name = "nb_add",
        .slot_type = .nb_add,
        .function = "mytype_add",
    });

    try analyzer.addSlot(.{
        .name = "tp_repr",
        .slot_type = .tp_repr,
        .function = "mytype_repr",
    });

    try std.testing.expectEqual(@as(usize, 2), analyzer.slotCount());
    try std.testing.expect(analyzer.hasSlot(.nb_add));
    try std.testing.expect(analyzer.hasSlot(.tp_repr));
    try std.testing.expect(!analyzer.hasSlot(.tp_str));
}

test "refcount_analyzer" {
    var analyzer = RefCountAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    try analyzer.addIssue(.{
        .kind = .missing_decref,
        .location = "file.c:42",
        .variable = "obj",
        .message = "Object may leak",
    });

    try analyzer.addIssue(.{
        .kind = .missing_decref,
        .location = "file.c:100",
        .variable = "result",
        .message = "Result not decreffed on error path",
    });

    try std.testing.expect(analyzer.hasIssues());
    try std.testing.expectEqual(@as(usize, 2), analyzer.countByKind(.missing_decref));
    try std.testing.expectEqual(@as(usize, 0), analyzer.countByKind(.double_decref));
}

test "abi_checker" {
    var checker = ABIChecker.init(std.testing.allocator, "3.11");
    defer checker.deinit();

    try checker.checkSymbol("_PyObject_GC_TRACK");
    try std.testing.expect(checker.hasWarnings());
    try std.testing.expectEqual(@as(usize, 1), checker.warnings.items.len);
}
