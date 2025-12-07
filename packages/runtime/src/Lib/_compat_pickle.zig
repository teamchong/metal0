/// _compat_pickle - Pickle Compatibility Module
/// Mirrors cpython/Lib/_compat_pickle.py
///
/// Provides name mappings for pickle compatibility between
/// Python 2 and Python 3. Used by the pickle module for
/// cross-version compatibility.

const std = @import("std");

// ============================================================================
// Module Name Mappings (Python 2 -> Python 3)
// ============================================================================

/// Mapping of Python 2 module names to Python 3
pub const NAME_MAPPING = std.StaticStringMap([]const u8).initComptime(.{
    // Standard library renames
    .{ "__builtin__", "builtins" },
    .{ "copy_reg", "copyreg" },
    .{ "Queue", "queue" },
    .{ "SocketServer", "socketserver" },
    .{ "ConfigParser", "configparser" },
    .{ "repr", "reprlib" },
    .{ "FileDialog", "tkinter.filedialog" },
    .{ "tkFileDialog", "tkinter.filedialog" },
    .{ "SimpleDialog", "tkinter.simpledialog" },
    .{ "tkSimpleDialog", "tkinter.simpledialog" },
    .{ "tkColorChooser", "tkinter.colorchooser" },
    .{ "tkCommonDialog", "tkinter.commondialog" },
    .{ "Dialog", "tkinter.dialog" },
    .{ "Tkdnd", "tkinter.dnd" },
    .{ "tkFont", "tkinter.font" },
    .{ "tkMessageBox", "tkinter.messagebox" },
    .{ "ScrolledText", "tkinter.scrolledtext" },
    .{ "Tkconstants", "tkinter.constants" },
    .{ "Tix", "tkinter.tix" },
    .{ "ttk", "tkinter.ttk" },
    .{ "Tkinter", "tkinter" },
    .{ "markupbase", "_markupbase" },
    .{ "_winreg", "winreg" },
    .{ "thread", "_thread" },
    .{ "dummy_thread", "_dummy_thread" },
    .{ "dbhash", "dbm.bsd" },
    .{ "dumbdbm", "dbm.dumb" },
    .{ "dbm", "dbm.ndbm" },
    .{ "gdbm", "dbm.gnu" },
    .{ "xmlrpclib", "xmlrpc.client" },
    .{ "DocXMLRPCServer", "xmlrpc.server" },
    .{ "SimpleXMLRPCServer", "xmlrpc.server" },
    .{ "httplib", "http.client" },
    .{ "htmlentitydefs", "html.entities" },
    .{ "HTMLParser", "html.parser" },
    .{ "Cookie", "http.cookies" },
    .{ "cookielib", "http.cookiejar" },
    .{ "BaseHTTPServer", "http.server" },
    .{ "SimpleHTTPServer", "http.server" },
    .{ "CGIHTTPServer", "http.server" },
    .{ "test.test_support", "test.support" },
    .{ "commands", "subprocess" },
    .{ "UserString", "collections" },
    .{ "UserList", "collections" },
    .{ "urlparse", "urllib.parse" },
    .{ "robotparser", "urllib.robotparser" },
    .{ "email.Parser", "email.parser" },
    .{ "email.Utils", "email.utils" },
    .{ "email.Errors", "email.errors" },
    .{ "email.Header", "email.header" },
    .{ "email.Charset", "email.charset" },
    .{ "email.Encoders", "email.encoders" },
    .{ "email.MIMEText", "email.mime.text" },
    .{ "email.MIMEMultipart", "email.mime.multipart" },
    .{ "email.MIMEBase", "email.mime.base" },
    .{ "email.MIMEAudio", "email.mime.audio" },
    .{ "email.MIMEImage", "email.mime.image" },
    .{ "email.MIMEMessage", "email.mime.message" },
    .{ "email.MIMENonMultipart", "email.mime.nonmultipart" },
});

/// Mapping of Python 3 module names back to Python 2
pub const REVERSE_NAME_MAPPING = std.StaticStringMap([]const u8).initComptime(.{
    .{ "builtins", "__builtin__" },
    .{ "copyreg", "copy_reg" },
    .{ "queue", "Queue" },
    .{ "socketserver", "SocketServer" },
    .{ "configparser", "ConfigParser" },
    .{ "reprlib", "repr" },
    .{ "_markupbase", "markupbase" },
    .{ "winreg", "_winreg" },
    .{ "_thread", "thread" },
    .{ "xmlrpc.client", "xmlrpclib" },
    .{ "http.client", "httplib" },
    .{ "html.entities", "htmlentitydefs" },
    .{ "html.parser", "HTMLParser" },
    .{ "http.cookies", "Cookie" },
    .{ "http.cookiejar", "cookielib" },
    .{ "urllib.parse", "urlparse" },
    .{ "urllib.robotparser", "robotparser" },
});

// ============================================================================
// Import Name Mappings (module.name -> module.name)
// ============================================================================

/// Mapping of Python 2 import names to Python 3
pub const IMPORT_MAPPING = std.StaticStringMap(struct { module: []const u8, name: []const u8 }).initComptime(.{
    // __builtin__ -> builtins
    .{ "__builtin__.xrange", .{ .module = "builtins", .name = "range" } },
    .{ "__builtin__.reduce", .{ .module = "functools", .name = "reduce" } },
    .{ "__builtin__.intern", .{ .module = "sys", .name = "intern" } },
    .{ "__builtin__.unichr", .{ .module = "builtins", .name = "chr" } },
    .{ "__builtin__.basestring", .{ .module = "builtins", .name = "str" } },
    .{ "__builtin__.long", .{ .module = "builtins", .name = "int" } },
    .{ "__builtin__.unicode", .{ .module = "builtins", .name = "str" } },
    // itertools
    .{ "itertools.imap", .{ .module = "builtins", .name = "map" } },
    .{ "itertools.ifilter", .{ .module = "builtins", .name = "filter" } },
    .{ "itertools.izip", .{ .module = "builtins", .name = "zip" } },
    .{ "itertools.ifilterfalse", .{ .module = "itertools", .name = "filterfalse" } },
    .{ "itertools.izip_longest", .{ .module = "itertools", .name = "zip_longest" } },
    // StringIO/cStringIO
    .{ "StringIO.StringIO", .{ .module = "io", .name = "StringIO" } },
    .{ "cStringIO.StringIO", .{ .module = "io", .name = "StringIO" } },
    // UserDict
    .{ "UserDict.UserDict", .{ .module = "collections", .name = "UserDict" } },
    .{ "UserDict.IterableUserDict", .{ .module = "collections", .name = "UserDict" } },
});

/// Mapping of Python 3 import names back to Python 2
pub const REVERSE_IMPORT_MAPPING = std.StaticStringMap(struct { module: []const u8, name: []const u8 }).initComptime(.{
    .{ "builtins.range", .{ .module = "__builtin__", .name = "xrange" } },
    .{ "functools.reduce", .{ .module = "__builtin__", .name = "reduce" } },
    .{ "io.StringIO", .{ .module = "StringIO", .name = "StringIO" } },
    .{ "collections.UserDict", .{ .module = "UserDict", .name = "UserDict" } },
});

// ============================================================================
// Lookup Functions
// ============================================================================

/// Translate Python 2 module name to Python 3
pub fn translateModule2to3(name: []const u8) []const u8 {
    return NAME_MAPPING.get(name) orelse name;
}

/// Translate Python 3 module name to Python 2
pub fn translateModule3to2(name: []const u8) []const u8 {
    return REVERSE_NAME_MAPPING.get(name) orelse name;
}

/// Translate Python 2 import to Python 3
pub fn translateImport2to3(
    module: []const u8,
    name: []const u8,
) struct { module: []const u8, name: []const u8 } {
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}.{s}", .{ module, name }) catch return .{ .module = module, .name = name };

    if (IMPORT_MAPPING.get(key)) |mapping| {
        return mapping;
    }

    // Check for module rename only
    const new_module = translateModule2to3(module);
    return .{ .module = new_module, .name = name };
}

/// Translate Python 3 import to Python 2
pub fn translateImport3to2(
    module: []const u8,
    name: []const u8,
) struct { module: []const u8, name: []const u8 } {
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}.{s}", .{ module, name }) catch return .{ .module = module, .name = name };

    if (REVERSE_IMPORT_MAPPING.get(key)) |mapping| {
        return mapping;
    }

    const new_module = translateModule3to2(module);
    return .{ .module = new_module, .name = name };
}

// ============================================================================
// Exception Mappings
// ============================================================================

/// Python 2 exception names that moved
pub const EXCEPTION_MAPPING = std.StaticStringMap([]const u8).initComptime(.{
    .{ "exceptions.StandardError", "builtins.Exception" },
    .{ "exceptions.Exception", "builtins.Exception" },
    .{ "exceptions.BaseException", "builtins.BaseException" },
    .{ "exceptions.KeyboardInterrupt", "builtins.KeyboardInterrupt" },
    .{ "exceptions.SystemExit", "builtins.SystemExit" },
});

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _compat_pickle module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "module name mapping py2 to py3" {
    try std.testing.expectEqualStrings("builtins", translateModule2to3("__builtin__"));
    try std.testing.expectEqualStrings("copyreg", translateModule2to3("copy_reg"));
    try std.testing.expectEqualStrings("queue", translateModule2to3("Queue"));
    try std.testing.expectEqualStrings("configparser", translateModule2to3("ConfigParser"));
}

test "module name mapping py3 to py2" {
    try std.testing.expectEqualStrings("__builtin__", translateModule3to2("builtins"));
    try std.testing.expectEqualStrings("copy_reg", translateModule3to2("copyreg"));
    try std.testing.expectEqualStrings("Queue", translateModule3to2("queue"));
}

test "unknown module unchanged" {
    try std.testing.expectEqualStrings("mymodule", translateModule2to3("mymodule"));
    try std.testing.expectEqualStrings("mymodule", translateModule3to2("mymodule"));
}

test "import mapping" {
    const result = translateImport2to3("__builtin__", "xrange");
    try std.testing.expectEqualStrings("builtins", result.module);
    try std.testing.expectEqualStrings("range", result.name);
}

test "import mapping module only" {
    const result = translateImport2to3("__builtin__", "print");
    try std.testing.expectEqualStrings("builtins", result.module);
    try std.testing.expectEqualStrings("print", result.name);
}

test "reverse import mapping" {
    const result = translateImport3to2("builtins", "range");
    try std.testing.expectEqualStrings("__builtin__", result.module);
    try std.testing.expectEqualStrings("xrange", result.name);
}

test "tkinter mappings" {
    try std.testing.expectEqualStrings("tkinter", translateModule2to3("Tkinter"));
    try std.testing.expectEqualStrings("tkinter.filedialog", translateModule2to3("tkFileDialog"));
    try std.testing.expectEqualStrings("tkinter.messagebox", translateModule2to3("tkMessageBox"));
}

test "http mappings" {
    try std.testing.expectEqualStrings("http.client", translateModule2to3("httplib"));
    try std.testing.expectEqualStrings("http.cookies", translateModule2to3("Cookie"));
    try std.testing.expectEqualStrings("http.cookiejar", translateModule2to3("cookielib"));
}
