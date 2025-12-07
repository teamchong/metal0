//! isIterable - Check if type supports "for x in obj"
//! USE: Before emitting for loops or list(), set() constructors
//! RETURNS: true for sequences, mappings, iterator, generator

const std = @import("std");
const NativeType = @import("../../native_types/core.zig").NativeType;
const isSequence = @import("isSequence.zig").isSequence;
const isMapping = @import("isMapping.zig").isMapping;

pub fn isIterable(t: NativeType) bool {
    return isSequence(t) or isMapping(t) or t == .iterator or t == .generator;
}
