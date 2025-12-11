/// marshal - Python Object Serialization
/// Mirrors cpython/Python/marshal.c
///
/// This module provides:
/// - Serialization of Python objects to binary format
/// - Deserialization of binary format to Python objects
/// - Support for code objects, tuples, lists, dicts, etc.
/// - Version-aware format handling

// Re-export from submodules
pub const types = @import("marshal/types.zig");
pub const writer = @import("marshal/writer.zig");
pub const reader = @import("marshal/reader.zig");
pub const api = @import("marshal/api.zig");

// Re-export commonly used types and functions
pub const VERSION = types.VERSION;
pub const MAX_MARSHAL_STACK_DEPTH = types.MAX_MARSHAL_STACK_DEPTH;
pub const Type = types.Type;
pub const FLAG_REF = types.FLAG_REF;
pub const WriteError = types.WriteError;
pub const ReadError = types.ReadError;
pub const Value = types.Value;
pub const CodeValue = types.CodeValue;

pub const Writer = writer.Writer;
pub const writeInt = writer.writeInt;
pub const writeFloat = writer.writeFloat;
pub const writeNone = writer.writeNone;
pub const writeBool = writer.writeBool;
pub const writeBytes = writer.writeBytes;
pub const writeUnicode = writer.writeUnicode;
pub const writeTuple = writer.writeTuple;
pub const writeList = writer.writeList;
pub const writeValue = writer.writeValue;

pub const Reader = reader.Reader;
pub const readValue = reader.readValue;

pub const dumps = api.dumps;
pub const loads = api.loads;
pub const init = api.init;
pub const fini = api.fini;

// Re-export tests
test {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(types);
    @import("std").testing.refAllDecls(writer);
    @import("std").testing.refAllDecls(reader);
    @import("std").testing.refAllDecls(api);
}
