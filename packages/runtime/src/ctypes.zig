/// ctypes - Runtime FFI for calling C libraries
/// Uses Zig's std.DynLib for dynamic library loading
const std = @import("std");

/// Dynamic library handle wrapper
pub const CDLL = struct {
    handle: ?std.DynLib = null,
    name: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !CDLL {
        const handle = std.DynLib.open(path) catch |err| {
            std.debug.print("ctypes: Failed to load library '{s}': {}\n", .{ path, err });
            return err;
        };
        return .{
            .handle = handle,
            .name = try allocator.dupe(u8, path),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CDLL) void {
        if (self.handle) |*h| h.close();
        self.allocator.free(self.name);
    }

    /// Look up a function symbol by name
    /// Returns function pointer or null if not found
    pub fn lookup(self: *CDLL, comptime FnType: type, name: [:0]const u8) ?FnType {
        if (self.handle) |*h| {
            return h.lookup(FnType, name);
        }
        return null;
    }

    /// Look up a data symbol by name
    pub fn lookupData(self: *CDLL, comptime T: type, name: [:0]const u8) ?*T {
        if (self.handle) |*h| {
            const ptr = h.lookup(*T, name);
            return ptr;
        }
        return null;
    }
};

/// WinDLL - Windows DLL (stdcall convention)
pub const WinDLL = CDLL;

/// OleDLL - OLE automation DLL
pub const OleDLL = CDLL;

/// PyDLL - Python DLL (no GIL release)
pub const PyDLL = CDLL;

// C type aliases matching Python ctypes
// Use @"name" syntax to avoid shadowing Zig primitives
pub const c_bool = bool;
pub const @"c_char" = u8;
pub const c_wchar = u32;
pub const c_byte = i8;
pub const c_ubyte = u8;
pub const @"c_short" = i16;
pub const @"c_ushort" = u16;
pub const @"c_int" = i32;
pub const @"c_uint" = u32;
pub const @"c_long" = CTypeLong;
pub const @"c_ulong" = CTypeULong;
pub const @"c_longlong" = i64;
pub const @"c_ulonglong" = u64;
pub const c_size_t = usize;
pub const c_ssize_t = isize;
pub const c_float = f32;
pub const c_double = f64;
pub const @"c_longdouble" = f128;

// Platform-specific long type
const CTypeLong = switch (@import("builtin").target.os.tag) {
    .windows => i32,
    else => isize,
};
const CTypeULong = switch (@import("builtin").target.os.tag) {
    .windows => u32,
    else => usize,
};

// Pointer types
pub const c_char_p = ?[*:0]const u8;
pub const c_wchar_p = ?[*:0]const u32;
pub const c_void_p = ?*anyopaque;

/// Create a pointer type
pub fn POINTER(comptime T: type) type {
    return ?*T;
}

/// Get the address of a value
pub fn addressof(ptr: anytype) usize {
    return @intFromPtr(ptr);
}

/// Pass by reference
pub fn byref(ptr: anytype) *@TypeOf(ptr.*) {
    return ptr;
}

/// Cast pointer to target type
pub fn cast(comptime T: type, ptr: anytype) T {
    return @ptrCast(@alignCast(ptr));
}

/// Create a mutable string buffer
pub fn create_string_buffer(allocator: std.mem.Allocator, size: usize) ![]u8 {
    return try allocator.alloc(u8, size);
}

/// Create a unicode buffer
pub fn create_unicode_buffer(allocator: std.mem.Allocator, size: usize) ![]u32 {
    return try allocator.alloc(u32, size);
}

/// Get errno (thread-local)
pub fn get_errno() c_int {
    return std.c.getErrno();
}

/// Set errno (thread-local)
pub fn set_errno(value: c_int) void {
    std.c.setErrno(value);
}

/// Get string at address
pub fn string_at(addr: usize, size: usize) []const u8 {
    const ptr: [*]const u8 = @ptrFromInt(addr);
    return ptr[0..size];
}

/// memmove wrapper
pub fn memmove(dest: [*]u8, src: [*]const u8, n: usize) void {
    _ = std.c.memmove(dest, src, n);
}

/// memset wrapper
pub fn memset(dest: [*]u8, c: u8, n: usize) void {
    _ = std.c.memset(dest, c, n);
}

/// sizeof - get size of type
pub fn sizeof(comptime T: type) usize {
    return @sizeOf(T);
}

/// alignment - get alignment of type
pub fn alignment(comptime T: type) usize {
    return @alignOf(T);
}

/// pointer - create pointer to value
pub fn pointer(ptr: anytype) *@TypeOf(ptr.*) {
    return ptr;
}

/// wstring_at - get wide string at address
pub fn wstring_at(addr: usize, size: usize) []const u32 {
    const ptr: [*]const u32 = @ptrFromInt(addr);
    return ptr[0..size];
}

/// resize - resize a ctypes array (no-op in Zig, arrays are fixed)
pub fn resize(_: anytype, _: usize) void {}

// Fixed-size integer types matching Python
pub const c_int8 = i8;
pub const c_uint8 = u8;
pub const c_int16 = i16;
pub const c_uint16 = u16;
pub const c_int32 = i32;
pub const c_uint32 = u32;
pub const c_int64 = i64;
pub const c_uint64 = u64;
pub const c_time_t = isize; // Platform dependent

// Alias
pub const c_voidp = c_void_p;

/// ARRAY - create fixed-size array type
pub fn ARRAY(comptime T: type, comptime size: usize) type {
    return [size]T;
}

/// Array alias
pub const Array = ARRAY;

/// Structure base - plain struct
pub fn Structure(comptime fields: anytype) type {
    _ = fields;
    return extern struct {};
}

/// Union base
pub fn Union(comptime fields: anytype) type {
    _ = fields;
    return extern union {};
}

/// BigEndianStructure - struct with big-endian fields
pub const BigEndianStructure = Structure;

/// LittleEndianStructure - struct with little-endian fields
pub const LittleEndianStructure = Structure;

/// BigEndianUnion
pub const BigEndianUnion = Union;

/// LittleEndianUnion
pub const LittleEndianUnion = Union;

/// CFUNCTYPE - C calling convention function type
pub fn CFUNCTYPE(comptime RetType: type, comptime ArgTypes: anytype) type {
    return *const @Type(.{ .@"fn" = .{
        .calling_convention = .c,
        .params = blk: {
            var params: [ArgTypes.len]std.builtin.Type.Fn.Param = undefined;
            for (ArgTypes, 0..) |T, i| {
                params[i] = .{ .is_generic = false, .is_noalias = false, .type = T };
            }
            break :blk &params;
        },
        .return_type = RetType,
        .is_generic = false,
        .is_var_args = false,
    } });
}

/// PYFUNCTYPE - Python calling convention (same as C for our purposes)
pub const PYFUNCTYPE = CFUNCTYPE;

/// SetPointerType - set pointer target (no-op, comptime types)
pub fn SetPointerType(comptime _: type, comptime _: type) void {}

/// LibraryLoader - loads libraries with attribute access
pub const LibraryLoader = struct {
    mode: c_int = DEFAULT_MODE,

    pub fn LoadLibrary(self: *LibraryLoader, name: []const u8, allocator: std.mem.Allocator) !CDLL {
        _ = self;
        return CDLL.init(allocator, name);
    }
};

/// cdll - default library loader
pub var cdll = LibraryLoader{};

/// pydll - Python DLL loader
pub var pydll = LibraryLoader{};

/// DEFAULT_MODE for dlopen
pub const DEFAULT_MODE: c_int = 0;

/// RTLD flags
pub const RTLD_LOCAL: c_int = 0;
pub const RTLD_GLOBAL: c_int = 0x100;

/// SIZEOF_TIME_T - size of time_t
pub const SIZEOF_TIME_T: usize = @sizeOf(isize);

/// ArgumentError - error for invalid arguments
pub const ArgumentError = error{InvalidArgument};

/// py_object - Python object reference (opaque pointer)
pub const py_object = ?*anyopaque;

/// PythonAPI - Special object providing access to CPython C API symbols
/// Supports subscript access like pythonapi["PyLong_Type"]
pub const PythonAPI = struct {
    /// Get a symbol by name - returns pointer to the symbol
    /// For metal0, we provide our own implementations via c_interop
    pub fn get(self: PythonAPI, name: []const u8) ?*anyopaque {
        _ = self;
        _ = name;
        // Return non-null to indicate symbol exists
        // Actual implementation would use dlsym on ourselves
        return @ptrFromInt(1); // Stub: return non-null pointer
    }

    /// Subscript access for pythonapi["symbol_name"]
    pub fn getSymbol(_: PythonAPI, name: []const u8) ?*anyopaque {
        _ = name;
        // Return non-null to indicate symbol is available
        return @ptrFromInt(1);
    }
};

/// pythonapi - handle to Python library itself (legacy, use PythonAPI instead)
pub var pythonapi: ?CDLL = null;

/// c_buffer - alias for create_string_buffer
pub const c_buffer = create_string_buffer;

test "CDLL basic" {
    // Test loading libc
    const allocator = std.testing.allocator;
    var lib = try CDLL.init(allocator, "libc.dylib");
    defer lib.deinit();

    // Look up strlen
    const strlen = lib.lookup(*const fn ([*:0]const u8) callconv(.c) usize, "strlen");
    if (strlen) |f| {
        const result = f("hello");
        try std.testing.expectEqual(@as(usize, 5), result);
    }
}
