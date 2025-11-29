/// String/List/Dict/File methods - Re-export hub for method implementations
const string = @import("methods/string.zig");
const list = @import("methods/list.zig");
const dict = @import("methods/dict.zig");
const file = @import("methods/file.zig");

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
pub const genIsdigit = string.genIsdigit;
pub const genIsalpha = string.genIsalpha;
pub const genIsalnum = string.genIsalnum;
pub const genIsspace = string.genIsspace;
pub const genIslower = string.genIslower;
pub const genIsupper = string.genIsupper;
pub const genLstrip = string.genLstrip;
pub const genRstrip = string.genRstrip;
pub const genCapitalize = string.genCapitalize;
pub const genTitle = string.genTitle;
pub const genSwapcase = string.genSwapcase;
pub const genStrIndex = string.genIndex;
pub const genRfind = string.genRfind;
pub const genRindex = string.genRindex;
pub const genLjust = string.genLjust;
pub const genRjust = string.genRjust;
pub const genCenter = string.genCenter;
pub const genZfill = string.genZfill;
pub const genIsascii = string.genIsascii;
pub const genIstitle = string.genIstitle;
pub const genIsprintable = string.genIsprintable;
pub const genEncode = string.genEncode;

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

// Deque methods (using ArrayList as underlying type)
pub const genAppendleft = list.genAppendleft;
pub const genPopleft = list.genPopleft;
pub const genExtendleft = list.genExtendleft;
pub const genRotate = list.genRotate;

// Dict methods
pub const genGet = dict.genGet;
pub const genKeys = dict.genKeys;
pub const genValues = dict.genValues;
pub const genItems = dict.genItems;

// File methods
pub const genFileRead = file.genFileRead;
pub const genFileWrite = file.genFileWrite;
pub const genFileClose = file.genFileClose;
