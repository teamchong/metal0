/// Function and class body generation - Thin facade that re-exports from submodules
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;

// Import submodules
const class_fields = @import("body/class_fields.zig");
const class_methods = @import("body/class_methods.zig");
const mutation_analysis = @import("body/mutation_analysis.zig");
const usage_analysis = @import("body/usage_analysis.zig");
const nested_captures = @import("body/nested_captures.zig");
const function_gen = @import("body/function_gen.zig");

// Re-export class field functions
pub const genClassFields = class_fields.genClassFields;
pub const genClassFieldsNoDict = class_fields.genClassFieldsNoDict;
pub const genClassLevelFields = class_fields.genClassLevelFields;
pub const inferParamType = class_fields.inferParamType;

// Re-export class method functions
pub const genDefaultInitMethod = class_methods.genDefaultInitMethod;
pub const genDefaultInitMethodWithBuiltinBase = class_methods.genDefaultInitMethodWithBuiltinBase;
pub const genInitMethod = class_methods.genInitMethod;
pub const genInitMethodWithBuiltinBase = class_methods.genInitMethodWithBuiltinBase;
pub const genInitMethodFromNew = class_methods.genInitMethodFromNew;
pub const genClassMethods = class_methods.genClassMethods;
pub const genInheritedMethods = class_methods.genInheritedMethods;
pub const genPolymorphicReturnHelpers = class_methods.genPolymorphicReturnHelpers;

// Re-export mutation analysis functions
pub const methodMutatesSelf = mutation_analysis.methodMutatesSelf;
pub const usesTypeAttribute = mutation_analysis.usesTypeAttribute;
pub const usesRegularSelf = mutation_analysis.usesRegularSelf;
pub const analyzeFunctionLocalMutations = mutation_analysis.analyzeFunctionLocalMutations;
pub const analyzeModuleLevelMutations = mutation_analysis.analyzeModuleLevelMutations;
pub const countAssignmentsWithScope = mutation_analysis.countAssignmentsWithScope;

// Re-export usage analysis functions
pub const analyzeFunctionLocalUses = usage_analysis.analyzeFunctionLocalUses;
pub const collectUsesInNode = usage_analysis.collectUsesInNode;

// Re-export nested capture functions
pub const analyzeNestedClassCaptures = nested_captures.analyzeNestedClassCaptures;
pub const collectLocalVarsInStmts = nested_captures.collectLocalVarsInStmts;
pub const findNestedClassCaptures = nested_captures.findNestedClassCaptures;
pub const findCapturedVarsInClass = nested_captures.findCapturedVarsInClass;
pub const findOuterRefsInStmts = nested_captures.findOuterRefsInStmts;
pub const findOuterRefsInNode = nested_captures.findOuterRefsInNode;
pub const isBuiltinName = nested_captures.isBuiltinName;

// Re-export function generation functions
pub const genFunctionBody = function_gen.genFunctionBody;
pub const genAsyncFunctionBody = function_gen.genAsyncFunctionBody;
pub const genMethodBody = function_gen.genMethodBody;
pub const genMethodBodyWithAllocatorInfo = function_gen.genMethodBodyWithAllocatorInfo;
pub const genMethodBodyWithContext = function_gen.genMethodBodyWithContext;
pub const hasSuperCall = function_gen.hasSuperCall;
