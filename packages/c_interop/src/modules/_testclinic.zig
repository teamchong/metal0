/// _testclinic Module - Test Argument Clinic
const cpython = @import("../include/object.zig");
pub export var _testclinicmodule: cpython.PyModuleDef = .{ .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null }, .m_name = "_testclinic", .m_doc = "Argument Clinic tests.", .m_size = -1, .m_methods = null, .m_slots = null, .m_traverse = null, .m_clear = null, .m_free = null };
pub export fn PyInit__testclinic() ?*cpython.PyObject { return @import("../objects/moduleobject.zig").PyModule_Create(&_testclinicmodule); }
