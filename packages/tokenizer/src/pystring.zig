/// Python string type implementation - index file
/// Re-exports all string methods from subdirectory modules

// Import pystring modules
const core = @import("pystring/core.zig");
const transform = @import("pystring/transform.zig");
const search = @import("pystring/search.zig");
const manipulate = @import("pystring/manipulate.zig");

// Re-export PyString struct type
pub const PyString = struct {
    data: []const u8,

    // Core operations
    pub const create = core.PyString.create;
    pub const createOwned = core.PyString.createOwned;
    pub const getValue = core.PyString.getValue;
    pub const len = core.PyString.len;
    pub const getItem = core.PyString.getItem;
    pub const charAt = core.PyString.charAt;
    pub const concat = core.PyString.concat;
    pub const concatMulti = core.PyString.concatMulti;
    pub const toInt = core.PyString.toInt;

    // Transform operations
    pub const upper = transform.upper;
    pub const lower = transform.lower;
    pub const capitalize = transform.capitalize;
    pub const swapcase = transform.swapcase;
    pub const title = transform.title;
    pub const center = transform.center;

    // Search operations
    pub const contains = search.contains;
    pub const startswith = search.startswith;
    pub const endswith = search.endswith;
    pub const find = search.find;
    pub const count_substr = search.count_substr;
    pub const isdigit = search.isdigit;
    pub const isalpha = search.isalpha;

    // Manipulation operations
    pub const slice = manipulate.slice;
    pub const sliceWithStep = manipulate.sliceWithStep;
    pub const split = manipulate.split;
    pub const strip = manipulate.strip;
    pub const lstrip = manipulate.lstrip;
    pub const rstrip = manipulate.rstrip;
    pub const replace = manipulate.replace;
    pub const join = manipulate.join;
};
