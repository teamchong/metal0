// C Library Mapping System - Core Data Structures
// This module defines the data structures for mapping Python packages to C/C++ libraries

const std = @import("std");

/// Represents a Python package that wraps C/C++ libraries
pub const CLibraryMapping = struct {
    /// Python package name (e.g., "sqlite3")
    package_name: []const u8,

    /// Underlying C/C++ libraries
    libraries: []const LibraryInfo,

    /// Function mappings from Python → C
    functions: []const FunctionMapping,

    /// Whether package requires C++ (affects linking/calling)
    requires_cpp: bool,

    /// Import statement detection pattern (e.g., "import sqlite3")
    import_patterns: []const []const u8,
};

/// Information about a C/C++ library dependency
pub const LibraryInfo = struct {
    /// Library name (e.g., "openblas", "sqlite3")
    name: []const u8,

    /// Headers to include via @cImport
    headers: []const []const u8,

    /// Link flags (e.g., "-lopenblas")
    link_flags: []const []const u8,

    /// Optional pkg-config name for auto-detection
    pkg_config_name: ?[]const u8,

    /// Fallback library names to try (e.g., ["openblas", "blas"])
    fallback_names: []const []const u8,

    /// Is this a C++ library? (affects name mangling)
    is_cpp: bool,

    /// Minimum version required (optional)
    min_version: ?[]const u8,
};

/// Maps a Python function to its C equivalent
pub const FunctionMapping = struct {
    /// Full Python function name (e.g., "sqlite3.connect")
    python_name: []const u8,

    /// C/C++ function name (e.g., "cblas_dgemm")
    c_name: []const u8,

    /// Argument conversion strategy
    arg_mappings: []const ArgMapping,

    /// Return value conversion strategy
    return_mapping: ReturnMapping,

    /// Additional setup code needed before call
    setup_code: ?[]const u8,

    /// Cleanup code needed after call
    cleanup_code: ?[]const u8,

    /// Does this function allocate memory that caller must free?
    allocates_memory: bool,

    /// Documentation/notes for developers
    notes: ?[]const u8,
};

/// Describes how to convert a Python argument to C
pub const ArgMapping = struct {
    /// Position in Python call (0-indexed)
    python_index: u32,

    /// Position in C call (may differ due to hidden params)
    c_index: u32,

    /// Python type expected
    python_type: PythonType,

    /// C type required
    c_type: CType,

    /// Conversion strategy
    conversion: ConversionStrategy,

    /// Is this argument optional in Python?
    is_optional: bool,

    /// Default value if optional and not provided
    default_value: ?[]const u8,
};

/// Python type enumeration
pub const PythonType = enum {
    int,
    float,
    str,
    bytes,
    list,
    tuple,
    dict,
    bool_,
    none,
    // Generic
    any,
};

/// C type representation
pub const CType = struct {
    /// Base type name (e.g., "double", "int64_t", "char*")
    name: []const u8,

    /// Pointer depth (0 = value, 1 = *, 2 = **, etc.)
    pointer_depth: u8,

    /// Is const?
    is_const: bool,

    /// Array size (0 = not array, >0 = fixed size)
    array_size: u32,

    /// Is this a reference? (C++ only)
    is_reference: bool,
};

/// How to convert Python value → C value
pub const ConversionStrategy = union(enum) {
    /// Direct cast (e.g., Python int → C int)
    direct: void,

    /// Extract from PyObject* field
    extract_field: []const u8,

    /// Allocate new C array from Python list
    allocate_array: struct {
        element_type: CType,
        length_source: LengthSource,
    },

    /// Wrap in C struct
    wrap_struct: []const u8,

    /// Call conversion function
    call_converter: struct {
        function_name: []const u8,
        needs_allocator: bool,
    },

    /// Pass pointer to existing data (zero-copy)
    pass_pointer: struct {
        /// Where to get pointer from (e.g., ".data.ptr")
        pointer_path: []const u8,
    },

    /// String encoding conversion
    encode_string: StringEncoding,

    /// Custom code snippet
    custom: []const u8,
};

/// Where to get array length from
pub const LengthSource = union(enum) {
    /// From another argument
    from_arg: u32,

    /// From Python len() call
    from_len: void,

    /// Fixed constant
    constant: u32,

    /// Infer from data
    infer: void,
};

/// String encoding type
pub const StringEncoding = enum {
    utf8,
    ascii,
    latin1,
    utf16,
    utf32,
};

/// Return value conversion from C → Python
pub const ReturnMapping = union(enum) {
    /// No return value (void)
    void_: void,

    /// Direct primitive (int, float, etc.)
    primitive: PythonType,

    /// Wrap C pointer in PyObject*
    wrap_pointer: struct {
        wrapper_type: []const u8,
        needs_free: bool,
    },

    /// Convert C array to Python list
    array_to_list: struct {
        element_type: PythonType,
        length_source: LengthSource,
    },

    /// Wrap in custom Python type
    custom_wrapper: []const u8,

    /// C string to Python str
    string: StringEncoding,

    /// Error code (check and raise exception if non-zero)
    error_code: struct {
        success_value: i32,
        exception_type: []const u8,
    },

    /// Custom conversion code
    custom: []const u8,
};

/// Registry of all library mappings
pub const MappingRegistry = struct {
    mappings: []const *const CLibraryMapping,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, mappings: []const *const CLibraryMapping) MappingRegistry {
        return .{
            .mappings = mappings,
            .allocator = allocator,
        };
    }

    /// Find mapping for a Python package
    pub fn findByPackage(self: *const MappingRegistry, package: []const u8) ?*const CLibraryMapping {
        for (self.mappings) |mapping| {
            if (std.mem.eql(u8, mapping.package_name, package)) {
                return mapping;
            }
        }
        return null;
    }

    /// Find function mapping by full Python name
    pub fn findFunction(self: *const MappingRegistry, full_name: []const u8) ?*const FunctionMapping {
        // Split "sqlite3.connect" → "sqlite3" + "connect"
        const dot_pos = std.mem.indexOf(u8, full_name, ".") orelse return null;
        const package = full_name[0..dot_pos];

        const mapping = self.findByPackage(package) orelse return null;

        for (mapping.functions) |*func| {
            if (std.mem.eql(u8, func.python_name, full_name)) {
                return func;
            }
        }

        return null;
    }

    /// Check if import statement requires C library mapping
    pub fn detectImport(self: *const MappingRegistry, import_stmt: []const u8) ?*const CLibraryMapping {
        for (self.mappings) |mapping| {
            for (mapping.import_patterns) |pattern| {
                if (std.mem.indexOf(u8, import_stmt, pattern)) |_| {
                    return mapping;
                }
            }
        }
        return null;
    }

    /// Get all libraries needed for detected imports
    pub fn getRequiredLibraries(self: *const MappingRegistry, allocator: std.mem.Allocator) ![]const LibraryInfo {
        var libs = std.ArrayList(LibraryInfo).init(allocator);
        defer libs.deinit();

        for (self.mappings) |mapping| {
            for (mapping.libraries) |lib| {
                try libs.append(lib);
            }
        }

        return libs.toOwnedSlice();
    }
};

test "MappingRegistry basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a simple test mapping
    const test_lib = LibraryInfo{
        .name = "testlib",
        .headers = &[_][]const u8{"test.h"},
        .link_flags = &[_][]const u8{"-ltest"},
        .pkg_config_name = null,
        .fallback_names = &[_][]const u8{},
        .is_cpp = false,
        .min_version = null,
    };

    const test_func = FunctionMapping{
        .python_name = "test.func",
        .c_name = "test_func",
        .arg_mappings = &[_]ArgMapping{},
        .return_mapping = .void_,
        .setup_code = null,
        .cleanup_code = null,
        .allocates_memory = false,
        .notes = null,
    };

    const test_mapping = CLibraryMapping{
        .package_name = "test",
        .libraries = &[_]LibraryInfo{test_lib},
        .functions = &[_]FunctionMapping{test_func},
        .requires_cpp = false,
        .import_patterns = &[_][]const u8{"import test"},
    };

    const mappings = [_]*const CLibraryMapping{&test_mapping};
    const registry = MappingRegistry.init(allocator, &mappings);

    // Test findByPackage
    const found_mapping = registry.findByPackage("test");
    try testing.expect(found_mapping != null);
    try testing.expectEqualStrings("test", found_mapping.?.package_name);

    // Test findFunction
    const found_func = registry.findFunction("test.func");
    try testing.expect(found_func != null);
    try testing.expectEqualStrings("test_func", found_func.?.c_name);

    // Test detectImport
    const detected = registry.detectImport("import test");
    try testing.expect(detected != null);
    try testing.expectEqualStrings("test", detected.?.package_name);
}
