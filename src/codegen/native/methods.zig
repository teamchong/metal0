/// String/List/Dict methods - Re-export hub for method implementations
const string = @import("methods/string.zig");
const list = @import("methods/list.zig");
const dict = @import("methods/dict.zig");

// String methods
pub const genSplit = string.genSplit;
pub const genUpper = string.genUpper;
pub const genLower = string.genLower;
pub const genStrip = string.genStrip;
pub const genReplace = string.genReplace;
pub const genJoin = string.genJoin;
pub const genStartswith = string.genStartswith;
pub const genEndswith = string.genEndswith;
pub const genFind = string.genFind;
pub const genCount = string.genCount;

// List methods
pub const genAppend = list.genAppend;
pub const genPop = list.genPop;
pub const genExtend = list.genExtend;
pub const genInsert = list.genInsert;
pub const genRemove = list.genRemove;
pub const genReverse = list.genReverse;
pub const genSort = list.genSort;
pub const genClear = list.genClear;
pub const genCopy = list.genCopy;
pub const genIndex = list.genIndex;

// Dict methods
pub const genGet = dict.genGet;
pub const genKeys = dict.genKeys;
pub const genValues = dict.genValues;
pub const genItems = dict.genItems;
