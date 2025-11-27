/// Statement parsing - Re-exports from submodules
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

pub const assign = @import("statements/assign.zig");
pub const definitions = @import("statements/definitions.zig");
pub const control = @import("statements/control.zig");
pub const imports = @import("statements/imports.zig");
pub const misc = @import("statements/misc.zig");

// Re-export all public functions for backward compatibility
pub const parseExprOrAssign = assign.parseExprOrAssign;
pub const parseFunctionDef = definitions.parseFunctionDef;
pub const parseClassDef = definitions.parseClassDef;
pub const parseIf = control.parseIf;
pub const parseFor = control.parseFor;
pub const parseWhile = control.parseWhile;
pub const parseReturn = misc.parseReturn;
pub const parseAssert = misc.parseAssert;
pub const parseImport = imports.parseImport;
pub const parseImportFrom = imports.parseImportFrom;
pub const parseBlock = misc.parseBlock;
pub const parseTry = misc.parseTry;
pub const parseRaise = misc.parseRaise;
pub const parsePass = misc.parsePass;
pub const parseBreak = misc.parseBreak;
pub const parseContinue = misc.parseContinue;
pub const parseDecorated = misc.parseDecorated;
pub const parseGlobal = misc.parseGlobal;
pub const parseWith = misc.parseWith;
pub const parseDel = misc.parseDel;
pub const parseEllipsis = misc.parseEllipsis;
pub const parseYield = misc.parseYield;
