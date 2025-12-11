//! CPython source: Lib/inspect.py
//!
//! Provides functions to get information about live objects such as modules,
//! classes, methods, functions, tracebacks, frame objects, and code objects.
//!
//! Mirrors: CPython Lib/inspect.py
//!
//! This module has been refactored into a modular directory structure:
//! - types.zig: Core data types (Parameter, Signature, FrameInfo, MemberInfo)
//! - predicates.zig: Type checking predicates (isclass, isfunction, callable, etc.)
//! - signature.zig: Function signature inspection (getSignature, formatargspec)
//! - source.zig: Source code inspection (getfile, getsource, getdoc, cleandoc)
//! - members.zig: Member inspection (getmethods, getmro, issubclass)
//! - stack.zig: Stack frame inspection (currentframe, stack, getouterframes)
//! - tests.zig: Unit tests

// Re-export types
pub const types = @import("inspect/types.zig");
pub const Parameter = types.Parameter;
pub const ParameterKind = types.ParameterKind;
pub const Signature = types.Signature;
pub const FrameInfo = types.FrameInfo;
pub const MemberInfo = types.MemberInfo;

// Re-export predicates
pub const predicates = @import("inspect/predicates.zig");
pub const ismodule = predicates.ismodule;
pub const isclass = predicates.isclass;
pub const ismethod = predicates.ismethod;
pub const isfunction = predicates.isfunction;
pub const isgeneratorfunction = predicates.isgeneratorfunction;
pub const isgenerator = predicates.isgenerator;
pub const iscoroutinefunction = predicates.iscoroutinefunction;
pub const iscoroutine = predicates.iscoroutine;
pub const isawaitable = predicates.isawaitable;
pub const isasyncgenfunction = predicates.isasyncgenfunction;
pub const isasyncgen = predicates.isasyncgen;
pub const istraceback = predicates.istraceback;
pub const isframe = predicates.isframe;
pub const iscode = predicates.iscode;
pub const isbuiltin = predicates.isbuiltin;
pub const isroutine = predicates.isroutine;
pub const isabstract = predicates.isabstract;
pub const isdatadescriptor = predicates.isdatadescriptor;
pub const ismemberdescriptor = predicates.ismemberdescriptor;
pub const ismethoddescriptor = predicates.ismethoddescriptor;
pub const hasattr = predicates.hasattr;
pub const callable = predicates.callable;

// Re-export signature functions
pub const signature = @import("inspect/signature.zig");
pub const getSignature = signature.getSignature;
pub const formatargspec = signature.formatargspec;

// Re-export source functions
pub const source = @import("inspect/source.zig");
pub const getfile = source.getfile;
pub const getsourcefile = source.getsourcefile;
pub const getsourceFromFile = source.getsourceFromFile;
pub const getsource = source.getsource;
pub const getsourcelines_from_file = source.getsourcelines_from_file;
pub const getsourcelines = source.getsourcelines;
pub const getdoc = source.getdoc;
pub const getcomments = source.getcomments;
pub const cleandoc = source.cleandoc;

// Re-export member functions
pub const members = @import("inspect/members.zig");
pub const getmethods = members.getmethods;
pub const getmro = members.getmro;
pub const issubclass = members.issubclass;

// Re-export stack functions
pub const stack_module = @import("inspect/stack.zig");
pub const currentframe = stack_module.currentframe;
pub const stack = stack_module.stack;
pub const getouterframes = stack_module.getouterframes;
pub const getinnerframes = stack_module.getinnerframes;

// Include tests
test {
    _ = @import("inspect/tests.zig");
}
