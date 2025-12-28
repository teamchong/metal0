/// Structured Zig Code Generation Builder
///
/// This module provides a type-safe, scope-aware alternative to string-based
/// emit()/emitFmt() code generation. Inspired by Zig's C backend architecture.
///
/// ## Overview
///
/// The builder system replaces:
/// ```zig
/// try self.emit("const ");
/// try self.emit(var_name);
/// try self.emit(": i64 = ");
/// try self.emit(value);
/// try self.emit(";\n");
/// ```
///
/// With:
/// ```zig
/// _ = try builder.declareConst(var_name, pool.i64_(), ZigValue.int(value));
/// ```
///
/// ## Core Abstractions
///
/// - **ZigValue**: Type-safe representation of values (certain/uncertain types)
/// - **ZigType**: Unified type system with pooling for deduplication
/// - **ZigBuilder**: Main code generation API with scope management
/// - **EmitContext**: Context-aware emission (statement, expression, etc.)
/// - **LocalAllocator**: Local variable pool with type-based reuse
///
/// ## Integration with Two-Flow TypeSystem
///
/// Values know their confidence level (certain/uncertain), which determines
/// whether they use raw Zig types or runtime.PyValue wrappers:
///
/// ```zig
/// // Certain type - uses i64 directly
/// const x = ZigValue.int(42);
///
/// // Uncertain type - wraps in PyValue
/// const y = ZigValue.pyvalue(.unknown);
/// ```
///
/// ## Usage Example
///
/// ```zig
/// const builder_mod = @import("codegen.builder");
/// const ZigBuilder = builder_mod.ZigBuilder;
/// const ZigValue = builder_mod.ZigValue;
///
/// var builder = try ZigBuilder.init(allocator);
/// defer builder.deinit();
///
/// // Get type pool for type references
/// const pool = builder.getTypePool();
///
/// // Add imports
/// try builder.addImport("std", "std");
/// try builder.addImport("runtime", "runtime");
///
/// // Declare variables
/// _ = try builder.declareConst("x", pool.i64_(), ZigValue.int(42));
/// _ = try builder.declareVar("y", pool.f64_(), ZigValue.float(3.14));
///
/// // Control flow
/// const if_handle = try builder.beginIf(ZigValue.boolean(true));
/// try builder.assign("result", ZigValue.int(1));
/// try builder.beginElse();
/// try builder.assign("result", ZigValue.int(0));
/// try builder.endIf(if_handle);
///
/// // Loops
/// const for_handle = try builder.beginFor(ZigValue.fromName("items"), "item");
/// try builder.emitCall("process", &.{ZigValue.fromName("item")});
/// try builder.endFor(for_handle);
///
/// // Functions
/// const func_handle = try builder.beginFunction("add", &.{
///     .{ .name = "a", .type_ = .i64 },
///     .{ .name = "b", .type_ = .i64 },
/// }, pool.i64_());
/// try builder.emitReturn(ZigValue.raw("a + b"));
/// try builder.endFunction(func_handle);
///
/// // Get final output
/// const code = try builder.finish();
/// ```
///
/// ## Migration Strategy
///
/// The builder is designed to coexist with existing emit() calls during migration:
///
/// 1. **Phase 0**: Create builder abstractions (this module)
/// 2. **Phase 1**: Migrate pilot file (arithmetic.zig)
/// 3. **Phase 2-N**: Migrate remaining files incrementally
///
/// Each file can be migrated independently. The builder produces identical
/// output to manual emit() calls, ensuring byte-for-byte compatibility.
///
pub const ZigValue = @import("zig_value.zig").ZigValue;
pub const LocalIndex = @import("zig_value.zig").LocalIndex;
pub const ParamIndex = @import("zig_value.zig").ParamIndex;
pub const TypeConfidence = @import("zig_value.zig").TypeConfidence;
pub const TypeHint = @import("zig_value.zig").TypeHint;
pub const BinOp = @import("zig_value.zig").BinOp;
pub const BigIntValue = @import("zig_value.zig").BigIntValue;
pub const UnifiedIntValue = @import("zig_value.zig").UnifiedIntValue;
pub const ArrayValue = @import("zig_value.zig").ArrayValue;
pub const StructLiteralValue = @import("zig_value.zig").StructLiteralValue;
pub const MethodResultValue = @import("zig_value.zig").MethodResultValue;
pub const BinOpResultValue = @import("zig_value.zig").BinOpResultValue;
pub const UnaryOpResultValue = @import("zig_value.zig").UnaryOpResultValue;
pub const FieldAccessValue = @import("zig_value.zig").FieldAccessValue;
pub const SubscriptValue = @import("zig_value.zig").SubscriptValue;
pub const CallResultValue = @import("zig_value.zig").CallResultValue;

pub const ZigType = @import("zig_type.zig").ZigType;
pub const TypePool = @import("zig_type.zig").TypePool;
pub const ArrayType = @import("zig_type.zig").ArrayType;
pub const SliceType = @import("zig_type.zig").SliceType;
pub const PointerType = @import("zig_type.zig").PointerType;
pub const OptionalType = @import("zig_type.zig").OptionalType;
pub const ErrorUnionType = @import("zig_type.zig").ErrorUnionType;
pub const TupleType = @import("zig_type.zig").TupleType;
pub const ArrayListType = @import("zig_type.zig").ArrayListType;
pub const HashMapType = @import("zig_type.zig").HashMapType;

pub const EmitContext = @import("emit_context.zig").EmitContext;
pub const EmitConfig = @import("emit_context.zig").EmitConfig;
pub const ErrorMode = @import("emit_context.zig").ErrorMode;
pub const ScopeKind = @import("emit_context.zig").ScopeKind;
pub const ScopeContext = @import("emit_context.zig").ScopeContext;
pub const ScopeHandle = @import("emit_context.zig").ScopeHandle;

pub const LocalAllocator = @import("local_allocator.zig").LocalAllocator;
pub const Local = @import("local_allocator.zig").Local;

pub const ZigBuilder = @import("zig_builder.zig").ZigBuilder;
pub const FuncParam = @import("zig_builder.zig").FuncParam;
pub const NameGen = @import("zig_builder.zig").NameGen;

// Structured statement and expression types
pub const ZigStatement = @import("zig_statement.zig").ZigStatement;
pub const ConstDecl = @import("zig_statement.zig").ConstDecl;
pub const VarDecl = @import("zig_statement.zig").VarDecl;
pub const VarUndef = @import("zig_statement.zig").VarUndef;
pub const Assign = @import("zig_statement.zig").Assign;
pub const AugAssign = @import("zig_statement.zig").AugAssign;
pub const AugOp = @import("zig_statement.zig").AugOp;
pub const IfStmt = @import("zig_statement.zig").IfStmt;
pub const WhileLoop = @import("zig_statement.zig").WhileLoop;
pub const ForLoop = @import("zig_statement.zig").ForLoop;
pub const Break = @import("zig_statement.zig").Break;
pub const Continue = @import("zig_statement.zig").Continue;
pub const Return = @import("zig_statement.zig").Return;
pub const Block = @import("zig_statement.zig").Block;

pub const ZigExpr = @import("zig_expr.zig").ZigExpr;
pub const Binary = @import("zig_expr.zig").Binary;
pub const Unary = @import("zig_expr.zig").Unary;
pub const UnaryOp = @import("zig_expr.zig").UnaryOp;
pub const BinaryOpKind = @import("zig_expr.zig").BinaryOpKind;
pub const ResultType = @import("zig_expr.zig").ResultType;
pub const Field = @import("zig_expr.zig").Field;
pub const Subscript = @import("zig_expr.zig").Subscript;
pub const Call = @import("zig_expr.zig").Call;
pub const MethodCall = @import("zig_expr.zig").MethodCall;
pub const Ternary = @import("zig_expr.zig").Ternary;
pub const CompOp = @import("zig_value.zig").CompOp;
pub const CertainType = @import("zig_value.zig").CertainType;

// StatementBuilder - high-level API for structured codegen
pub const StatementBuilder = @import("statement_builder.zig").StatementBuilder;

// AstBridge - AST to ZigValue conversion with type confidence
pub const AstBridge = @import("ast_bridge.zig").AstBridge;

// ============================================
// Convenience functions
// ============================================

/// Create a new builder
pub fn init(allocator: @import("std").mem.Allocator) !ZigBuilder {
    return ZigBuilder.init(allocator);
}

// ============================================
// Tests
// ============================================

test {
    // Run all module tests
    @import("std").testing.refAllDecls(@This());
}

test "builder integration" {
    const std = @import("std");

    var builder = try init(std.testing.allocator);
    defer builder.deinit();

    // Test basic workflow
    try builder.addImport("std", "std");

    const pool = builder.getTypePool();
    _ = try builder.declareConst("x", pool.i64_(), ZigValue.int(42));

    const code = try builder.finish();
    defer std.testing.allocator.free(code);

    try std.testing.expect(code.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, code, "const x: i64 = 42;") != null);
}
