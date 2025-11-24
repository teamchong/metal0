/// Built-in functions dispatcher - delegates to specialized modules
const conversions = @import("builtins/conversions.zig");
const math = @import("builtins/math.zig");
const collections = @import("builtins/collections.zig");
const eval_exec = @import("builtins/eval.zig");

// Re-export all functions
pub const genLen = conversions.genLen;
pub const genStr = conversions.genStr;
pub const genInt = conversions.genInt;
pub const genFloat = conversions.genFloat;
pub const genBool = conversions.genBool;
pub const genType = conversions.genType;
pub const genIsinstance = conversions.genIsinstance;

// Dynamic execution
pub const genEval = eval_exec.genEval;
pub const genExec = eval_exec.genExec;

pub const genAbs = math.genAbs;
pub const genMin = math.genMin;
pub const genMax = math.genMax;
pub const genRound = math.genRound;
pub const genPow = math.genPow;
pub const genChr = math.genChr;
pub const genOrd = math.genOrd;

pub const genEnumerate = collections.genEnumerate;
pub const genZip = collections.genZip;
pub const genSum = collections.genSum;
pub const genAll = collections.genAll;
pub const genAny = collections.genAny;
pub const genSorted = collections.genSorted;
pub const genReversed = collections.genReversed;
pub const genMap = collections.genMap;
pub const genFilter = collections.genFilter;
