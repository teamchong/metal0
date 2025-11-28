/// Python collections module - Counter, defaultdict, deque
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate collections.Counter(iterable?)
/// Counter is a dict subclass for counting hashable objects
pub fn genCounter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Counter() -> empty dict, Counter(iterable) -> count elements
    try self.emit("counter_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _counter = hashmap_helper.StringHashMap(i64).init(allocator);\n");

    if (args.len > 0) {
        try self.emitIndent();
        try self.emit("const _iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        // Use direct iteration - works for both arrays and ArrayList.items
        try self.emit("for (_iterable) |item| {\n");
        self.indent();
        try self.emitIndent();
        // getOrPut for managed ArrayHashMap takes only key (uses internal allocator)
        try self.emit("const entry = _counter.getOrPut(item) catch continue;\n");
        try self.emitIndent();
        try self.emit("if (entry.found_existing) { entry.value_ptr.* += 1; } else { entry.value_ptr.* = 1; }\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.emit("break :counter_blk _counter;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate collections.defaultdict(default_factory)
/// defaultdict returns default value for missing keys
pub fn genDefaultdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // For now, generate a regular dict with a note
    // Full implementation would need runtime type tracking
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(i64).init(allocator)");
}

/// Generate collections.deque(iterable?, maxlen?)
/// deque is a double-ended queue with O(1) append/pop from both ends
pub fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("deque_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _deque = std.ArrayList(i64).init(allocator);\n");

    if (args.len > 0) {
        try self.emitIndent();
        try self.emit("const _iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        // Use direct iteration - works for both arrays and ArrayList.items
        try self.emit("for (_iterable) |item| {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("_deque.append(allocator, item) catch continue;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.emit("break :deque_blk _deque;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate collections.OrderedDict()
/// OrderedDict remembers insertion order (Python 3.7+ dict already does this)
pub fn genOrderedDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // In Python 3.7+, regular dict maintains insertion order
    // So OrderedDict is essentially a regular dict
    _ = args;
    try self.emit("hashmap_helper.StringHashMap(*runtime.PyObject).init(allocator)");
}

/// Generate collections.namedtuple(typename, field_names)
/// namedtuple creates a tuple subclass with named fields
pub fn genNamedtuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // namedtuple is complex - it creates a new type at runtime
    // For AOT, we'd need to generate a struct at compile time
    // For now, just return a struct type placeholder
    _ = args;
    try self.emit("struct {}");
}
