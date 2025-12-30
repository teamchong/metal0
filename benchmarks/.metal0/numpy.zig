const std = @import("std");
const runtime = @import("runtime");

pub const _array_api_info = struct {

    const __array_namespace_info__ = struct {
        // Python class metadata
        pub const __name__: []const u8 = "__array_namespace_info__";
        pub const __doc__: ?[]const u8 = "    Get the array API inspection namespace for NumPy.\n\n    The array API inspection namespace defines the following functions:\n\n    - capabilities()\n    - default_device()\n    - default_dtypes()\n    - dtypes()\n    - devices()\n\n    See\n    https://data-apis.org/array-api/latest/API_specification/inspection.html\n    for more details.\n\n    Returns\n    -------\n    info : ModuleType\n        The array API inspection namespace for NumPy.\n\n    Examples\n    --------\n    >>> info = np.__array_namespace_info__()\n    >>> info.default_dtypes()\n    {'real floating': numpy.float64,\n     'complex floating': numpy.complex128,\n     'integral': numpy.int64,\n     'indexing': numpy.int64}\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }

        pub fn capabilities(self: *const @This(), _: std.mem.Allocator) !i64 {
            _ = &self;
            _ = &self;
            _ = "\n        Return a dictionary of array API library capabilities.\n\n        The resulting dictionary has the following keys:\n\n        - **\"boolean indexing\"**: boolean indicating whether an array library\n          supports boolean indexing. Always ``True`` for NumPy.\n\n        - **\"data-dependent shapes\"**: boolean indicating whether an array\n          library supports data-dependent output shapes. Always ``True`` for\n          NumPy.\n\n        See\n        https://data-apis.org/array-api/latest/API_specification/generated/array_api.info.capabilities.html\n        for more details.\n\n        See Also\n        --------\n        __array_namespace_info__.default_device,\n        __array_namespace_info__.default_dtypes,\n        __array_namespace_info__.dtypes,\n        __array_namespace_info__.devices\n\n        Returns\n        -------\n        capabilities : dict\n            A dictionary of array API library capabilities.\n\n        Examples\n        --------\n        >>> info = np.__array_namespace_info__()\n        >>> info.capabilities()\n        {'boolean indexing': True,\n         'data-dependent shapes': True,\n         'max dimensions': 64}\n\n        ";
            return (__m0_dict: { 
                var __m1_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                try __m1_t.put("boolean indexing", try runtime.PyValue.fromAlloc(__global_allocator, true));
                try __m1_t.put("data-dependent shapes", try runtime.PyValue.fromAlloc(__global_allocator, true));
                try __m1_t.put("max dimensions", try runtime.PyValue.fromAlloc(__global_allocator, 64));
                break :__m0_dict __m1_t;
            });
        }

        pub fn default_device(self: *const @This()) []const u8 {
            _ = &self;
            _ = &self;
            _ = "\n        The default device used for new NumPy arrays.\n\n        For NumPy, this always returns ``'cpu'``.\n\n        See Also\n        --------\n        __array_namespace_info__.capabilities,\n        __array_namespace_info__.default_dtypes,\n        __array_namespace_info__.dtypes,\n        __array_namespace_info__.devices\n\n        Returns\n        -------\n        device : str\n            The default device used for new NumPy arrays.\n\n        Examples\n        --------\n        >>> info = np.__array_namespace_info__()\n        >>> info.default_device()\n        'cpu'\n\n        ";
            return "cpu";
        }

        pub fn default_dtypes(self: *const @This(), _: std.mem.Allocator, device: anytype) !i64 {
            _ = &self;
            _ = &self;
            _ = &device;
            _ = "\n        The default data types used for new NumPy arrays.\n\n        For NumPy, this always returns the following dictionary:\n\n        - **\"real floating\"**: ``numpy.float64``\n        - **\"complex floating\"**: ``numpy.complex128``\n        - **\"integral\"**: ``numpy.intp``\n        - **\"indexing\"**: ``numpy.intp``\n\n        Parameters\n        ----------\n        device : str, optional\n            The device to get the default data types for. For NumPy, only\n            ``'cpu'`` is allowed.\n\n        Returns\n        -------\n        dtypes : dict\n            A dictionary describing the default data types used for new NumPy\n            arrays.\n\n        See Also\n        --------\n        __array_namespace_info__.capabilities,\n        __array_namespace_info__.default_device,\n        __array_namespace_info__.dtypes,\n        __array_namespace_info__.devices\n\n        Examples\n        --------\n        >>> info = np.__array_namespace_info__()\n        >>> info.default_dtypes()\n        {'real floating': numpy.float64,\n         'complex floating': numpy.complex128,\n         'integral': numpy.int64,\n         'indexing': numpy.int64}\n\n        ";
            if ((!(inline_blk: { inline for (__list_blk_2: {
                const __values_2 = .{ "cpu", null };
                const __T_2 = comptime runtime.InferListType(@TypeOf(__values_2));
                var __list_2 = std.ArrayListUnmanaged(__T_2){};
                inline for (__values_2) |val| {
                    try runtime.list_ops.appendCast(__T_2, &__list_2, __global_allocator, val);
                }
                break :__list_blk_2 __list_2;
            }) |__item| { if (runtime.pyAnyEql(__item, device)) break :inline_blk true; } break :inline_blk false; }))) {
                runtime.exceptions.setException("ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "Device not understood. Only \"cpu\" is allowed, but received: {any}", .{ device })))));
                runtime.debug_reader.printPythonError(__global_allocator, "ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "Device not understood. Only \"cpu\" is allowed, but received: {any}", .{ device })))), @src().line);
                return error.ValueError;
            }
            return (__m3_dict: { 
                var __m4_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                try __m4_t.put("real floating", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float64)")));
                try __m4_t.put("complex floating", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex128)")));
                try __m4_t.put("integral", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(intp)")));
                try __m4_t.put("indexing", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(intp)")));
                break :__m3_dict __m4_t;
            });
        }

        pub fn dtypes(self: *const @This(), _: std.mem.Allocator, device: anytype, kind: anytype) !i64 {
            _ = &self;
            _ = &self;
            _ = &device;
            _ = &kind;
            _ = "\n        The array API data types supported by NumPy.\n\n        Note that this function only returns data types that are defined by\n        the array API.\n\n        Parameters\n        ----------\n        device : str, optional\n            The device to get the data types for. For NumPy, only ``'cpu'`` is\n            allowed.\n        kind : str or tuple of str, optional\n            The kind of data types to return. If ``None``, all data types are\n            returned. If a string, only data types of that kind are returned.\n            If a tuple, a dictionary containing the union of the given kinds\n            is returned. The following kinds are supported:\n\n            - ``'bool'``: boolean data types (i.e., ``bool``).\n            - ``'signed integer'``: signed integer data types (i.e., ``int8``,\n              ``int16``, ``int32``, ``int64``).\n            - ``'unsigned integer'``: unsigned integer data types (i.e.,\n              ``uint8``, ``uint16``, ``uint32``, ``uint64``).\n            - ``'integral'``: integer data types. Shorthand for ``('signed\n              integer', 'unsigned integer')``.\n            - ``'real floating'``: real-valued floating-point data types\n              (i.e., ``float32``, ``float64``).\n            - ``'complex floating'``: complex floating-point data types (i.e.,\n              ``complex64``, ``complex128``).\n            - ``'numeric'``: numeric data types. Shorthand for ``('integral',\n              'real floating', 'complex floating')``.\n\n        Returns\n        -------\n        dtypes : dict\n            A dictionary mapping the names of data types to the corresponding\n            NumPy data types.\n\n        See Also\n        --------\n        __array_namespace_info__.capabilities,\n        __array_namespace_info__.default_device,\n        __array_namespace_info__.default_dtypes,\n        __array_namespace_info__.devices\n\n        Examples\n        --------\n        >>> info = np.__array_namespace_info__()\n        >>> info.dtypes(kind='signed integer')\n        {'int8': numpy.int8,\n         'int16': numpy.int16,\n         'int32': numpy.int32,\n         'int64': numpy.int64}\n\n        ";
            if ((!(inline_blk: { inline for (__list_blk_5: {
                const __values_5 = .{ "cpu", null };
                const __T_5 = comptime runtime.InferListType(@TypeOf(__values_5));
                var __list_5 = std.ArrayListUnmanaged(__T_5){};
                inline for (__values_5) |val| {
                    try runtime.list_ops.appendCast(__T_5, &__list_5, __global_allocator, val);
                }
                break :__list_blk_5 __list_5;
            }) |__item| { if (runtime.pyAnyEql(__item, device)) break :inline_blk true; } break :inline_blk false; }))) {
                runtime.exceptions.setException("ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "Device not understood. Only \"cpu\" is allowed, but received: {any}", .{ device })))));
                runtime.debug_reader.printPythonError(__global_allocator, "ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "Device not understood. Only \"cpu\" is allowed, but received: {any}", .{ device })))), @src().line);
                return error.ValueError;
            }
            if (((@TypeOf(kind) == @TypeOf(null)))) {
                return (__m6_dict: { 
                    var __m7_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m7_t.put("bool", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(bool)")));
                    try __m7_t.put("int8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int8)")));
                    try __m7_t.put("int16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int16)")));
                    try __m7_t.put("int32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int32)")));
                    try __m7_t.put("int64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int64)")));
                    try __m7_t.put("uint8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint8)")));
                    try __m7_t.put("uint16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint16)")));
                    try __m7_t.put("uint32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint32)")));
                    try __m7_t.put("uint64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint64)")));
                    try __m7_t.put("float32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float32)")));
                    try __m7_t.put("float64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float64)")));
                    try __m7_t.put("complex64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex64)")));
                    try __m7_t.put("complex128", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex128)")));
                    break :__m6_dict __m7_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "bool"))) {
                return (__m8_dict: { 
                    var __m9_t = hashmap_helper.StringHashMap(runtime.builtins.PyCallable).init(__global_allocator);
                    try __m9_t.put("bool", bool);
                    break :__m8_dict __m9_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "signed integer"))) {
                return (__m10_dict: { 
                    var __m11_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m11_t.put("int8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int8)")));
                    try __m11_t.put("int16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int16)")));
                    try __m11_t.put("int32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int32)")));
                    try __m11_t.put("int64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int64)")));
                    break :__m10_dict __m11_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "unsigned integer"))) {
                return (__m12_dict: { 
                    var __m13_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m13_t.put("uint8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint8)")));
                    try __m13_t.put("uint16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint16)")));
                    try __m13_t.put("uint32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint32)")));
                    try __m13_t.put("uint64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint64)")));
                    break :__m12_dict __m13_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "integral"))) {
                return (__m14_dict: { 
                    var __m15_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m15_t.put("int8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int8)")));
                    try __m15_t.put("int16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int16)")));
                    try __m15_t.put("int32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int32)")));
                    try __m15_t.put("int64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int64)")));
                    try __m15_t.put("uint8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint8)")));
                    try __m15_t.put("uint16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint16)")));
                    try __m15_t.put("uint32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint32)")));
                    try __m15_t.put("uint64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint64)")));
                    break :__m14_dict __m15_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "real floating"))) {
                return (__m16_dict: { 
                    var __m17_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m17_t.put("float32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float32)")));
                    try __m17_t.put("float64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float64)")));
                    break :__m16_dict __m17_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "complex floating"))) {
                return (__m18_dict: { 
                    var __m19_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m19_t.put("complex64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex64)")));
                    try __m19_t.put("complex128", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex128)")));
                    break :__m18_dict __m19_t;
                });
            }
            if ((runtime.pyAnyEql(kind, "numeric"))) {
                return (__m20_dict: { 
                    var __m21_t = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);
                    try __m21_t.put("int8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int8)")));
                    try __m21_t.put("int16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int16)")));
                    try __m21_t.put("int32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int32)")));
                    try __m21_t.put("int64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(int64)")));
                    try __m21_t.put("uint8", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint8)")));
                    try __m21_t.put("uint16", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint16)")));
                    try __m21_t.put("uint32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint32)")));
                    try __m21_t.put("uint64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(uint64)")));
                    try __m21_t.put("float32", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float32)")));
                    try __m21_t.put("float64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(float64)")));
                    try __m21_t.put("complex64", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex64)")));
                    try __m21_t.put("complex128", runtime.PyValue.from(try runtime.eval(__global_allocator, "dtype(complex128)")));
                    break :__m20_dict __m21_t;
                });
            }
            var res: hashmap_helper.StringHashMap(runtime.PyValue) = undefined;
            if (__m22_blk: { _ = @TypeOf(kind); break :__m22_blk true; }) {
                res = runtime.PyValueHashMap(runtime.PyValue).init(__global_allocator);
                {
                    const __pylist_raw_0 = kind;
                    const __pylist_0 = if (@typeInfo(@TypeOf(__pylist_raw_0)) == .error_union) try __pylist_raw_0 else __pylist_raw_0;
                    const __pylist_len_0 = runtime.container_dispatch.getLen(@TypeOf(__pylist_0), __pylist_0);
                    var __pylist_i_0: usize = 0;
                    while (__pylist_i_0 < __pylist_len_0) : (__pylist_i_0 += 1) {
                        const k = runtime.container_dispatch.getAt(@TypeOf(__pylist_0), __pylist_0, __pylist_i_0);
                        (dupdate_1: {
                            var __target_dict = &res;
                            const __other_dict = try self.dtypes(__global_allocator, k, null);
                            var __other_iter = __other_dict.iterator();
                            while (__other_iter.next()) |entry| {
                                try __target_dict.put(entry.key_ptr.*, entry.value_ptr.*);
                            }
                            break :dupdate_1 {};
                        });
                    }
                }
                return res;
            }
            runtime.exceptions.setException("ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "unsupported kind: {any}", .{ kind })))));
            runtime.debug_reader.printPythonError(__global_allocator, "ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "unsupported kind: {any}", .{ kind })))), @src().line);
            return error.ValueError;
        }

        pub fn devices(self: *const @This(), _: std.mem.Allocator) !i64 {
            _ = &self;
            _ = &self;
            _ = "\n        The devices supported by NumPy.\n\n        For NumPy, this always returns ``['cpu']``.\n\n        Returns\n        -------\n        devices : list of str\n            The devices supported by NumPy.\n\n        See Also\n        --------\n        __array_namespace_info__.capabilities,\n        __array_namespace_info__.default_device,\n        __array_namespace_info__.default_dtypes,\n        __array_namespace_info__.dtypes\n\n        Examples\n        --------\n        >>> info = np.__array_namespace_info__()\n        >>> info.devices()\n        ['cpu']\n\n        ";
            return [_][]const u8{"cpu"};
        }
    };

    };

    pub const conftest = struct {

    pub const _old_fpu_mode = null;
    pub const _collect_results = runtime.PyValueHashMap(runtime.PyValue).init(__global_allocator);
    pub const _pytest_ini = (__m0_path_join: { const _paths = [_][]const u8{ (__m1_path_dirname: { const _path = runtime.container_dispatch.toPathStr(@TypeOf(__file__), __file__); break :__m1_path_dirname std.fs.path.dirname(_path) orelse ""; }), "..", "pytest.ini" }; break :__m0_path_join std.fs.path.join(__global_allocator, &_paths) catch ""; });
    pub fn pytest_configure(_: std.mem.Allocator, config: i64) !void {
        _ = &config;
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "config.addinivalue_line(\"markers\", \"valgrind_error: Tests that are known to error under valgrind.\")"));
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "config.addinivalue_line(\"markers\", \"leaks_references: Tests that are known to leak references.\")"));
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "config.addinivalue_line(\"markers\", \"slow: Tests that are very slow.\")"));
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "config.addinivalue_line(\"markers\", \"slow_pypy: Tests that are very slow on pypy.\")"));
    }

    pub fn pytest_addoption(_: std.mem.Allocator, parser: i64) !void {
        _ = &parser;
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.addoption(\"--available-memory\", action=\"store\", default=None, help=\"Set amount of memory available for running the test suite. This can result to tests requiring especially large amounts of memory to be skipped. Equivalent to setting environment variable NPY_AVAILABLE_MEM. Default: determinedautomatically.\")"));
    }

    pub const gil_enabled_at_start = true;
    pub fn pytest_sessionstart(_: std.mem.Allocator, session: i64) !void {
        _ = &session;
        const available_mem: runtime.PyValue = runtime.PyValue.from((mcall_0: { const __obj = session.config; break :mcall_0 __obj.getoption("available_memory"); }));
        if (((@TypeOf(available_mem) != @TypeOf(null)))) {
            hashmap_helper.StringHashMap([]const u8).init(__global_allocator)[@as(usize, @intCast("NPY_AVAILABLE_MEM"))] = available_mem;
        }
    }

    pub fn pytest_terminal_summary(_: std.mem.Allocator, terminalreporter: i64, _: i64, _: i64) !void {
        _ = &terminalreporter;
        var tr: i64 = undefined;
        if (runtime.pyTruthy((boolop_1: { const _a = (boolop_2: { const _a = NOGIL_BUILD; const _b = !runtime.toBool(gil_enabled_at_start); break :boolop_2 if (!(runtime.toBool(_a))) _a else _b; }); const _b = try runtime.builtins.sys._is_gil_enabled(__global_allocator); break :boolop_1 if (!(runtime.toBool(_a))) _a else _b; }))) {
            tr = terminalreporter;
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.ensure_newline()"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.section(\"GIL re-enabled\", sep=\"=\", red=True, bold=True)"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"The GIL was re-enabled at runtime during the tests.\")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"This can happen with no test failures if the RuntimeWarning\")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"raised by Python when this happens is filtered by a test.\")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"\")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"Please ensure all new C modules declare support for running\")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"without the GIL. Any new tests that intentionally imports \")"));
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "tr.line(\"code that re-enables the GIL should do so in a subprocess.\")"));
            try pytest.exit(__global_allocator, "GIL re-enabled during tests", 1);
        }
    }

    pub fn pytest_itemcollected(_: std.mem.Allocator, item: i64) !void {
        _ = &item;
        _ = "\n    Check FPU precision mode was not changed during test collection.\n\n    The clumsy way we do it here is mainly necessary because numpy\n    still uses yield tests, which can execute code at test collection\n    time.\n    ";
        const mode: runtime.PyValue = runtime.PyValue.from(runtime.PyValue.from(try runtime.eval(__global_allocator, "get_fpu_mode()")));
        if (((@TypeOf(_old_fpu_mode) == @TypeOf(null)))) {
            _old_fpu_mode = mode;
        } else if ((!runtime.pyAnyEql(mode, _old_fpu_mode))) {
            try _collect_results.put(item, .{ _old_fpu_mode, mode });
            _old_fpu_mode = mode;
        }
    }

    pub fn check_fpu_mode(_: std.mem.Allocator, request: i64) ![]runtime.PyValue {
        _ = &request;
        var __gen_result = std.ArrayListUnmanaged(runtime.PyValue){};
        _ = &__gen_result;
        _ = "\n    Check FPU precision mode was not changed during the test.\n    ";
        var old_mode: runtime.PyValue = runtime.PyValue.from(runtime.PyValue.from(try runtime.eval(__global_allocator, "get_fpu_mode()")));
        _ = &old_mode;
        try __gen_result.append(__global_allocator, runtime.PyValue.from(null));
        var new_mode: runtime.PyValue = runtime.PyValue.from(runtime.PyValue.from(try runtime.eval(__global_allocator, "get_fpu_mode()")));
        _ = &new_mode;
        if ((!runtime.pyAnyEql(old_mode, new_mode))) {
            runtime.exceptions.setException("AssertionError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "FPU precision mode changed from {s} to {s} during the test", .{ (try runtime.pyFormat(__global_allocator, old_mode, "#x")), (try runtime.pyFormat(__global_allocator, new_mode, "#x")) })))));
            runtime.debug_reader.printPythonError(__global_allocator, "AssertionError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "FPU precision mode changed from {s} to {s} during the test", .{ (try runtime.pyFormat(__global_allocator, old_mode, "#x")), (try runtime.pyFormat(__global_allocator, new_mode, "#x")) })))), @src().line);
            return error.AssertionError;
        }
        const collect_result: runtime.PyValue = runtime.PyValue.from(_collect_results.get(request.node).?);
        if (((@TypeOf(collect_result) != @TypeOf(null)))) {
            const __m2_unpack_tmp = collect_result;
            old_mode = __m2_unpack_tmp.listItems()[0];
            new_mode = __m2_unpack_tmp.listItems()[1];
            runtime.exceptions.setException("AssertionError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "FPU precision mode changed from {s} to {s} when collecting the test", .{ (try runtime.pyFormat(__global_allocator, old_mode, "#x")), (try runtime.pyFormat(__global_allocator, new_mode, "#x")) })))));
            runtime.debug_reader.printPythonError(__global_allocator, "AssertionError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "FPU precision mode changed from {s} to {s} when collecting the test", .{ (try runtime.pyFormat(__global_allocator, old_mode, "#x")), (try runtime.pyFormat(__global_allocator, new_mode, "#x")) })))), @src().line);
            return error.AssertionError;
        }
        return __gen_result.items;
    }

    pub fn add_np(_: std.mem.Allocator, doctest_namespace: i64) !void {
        _ = &doctest_namespace;
        doctest_namespace[@as(usize, @intCast("np"))] = numpy;
    }

    pub fn env_setup(_: std.mem.Allocator, monkeypatch: i64) !void {
        _ = &monkeypatch;
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "monkeypatch.setenv(\"PYTHONHASHSEED\", \"0\")"));
    }

    pub fn random_string_list(_: std.mem.Allocator) !i64 {
        var chars = runtime.listFromString(__global_allocator, try std.mem.concat(__global_allocator, u8, &[_][]const u8{ "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", "0123456789" }));
        _ = &chars;
        chars = @as(*runtime.PyObject, @ptrCast(c_interop.callModuleFunction("numpy", "array", .{chars}).?));
        const ret: runtime.PyValue = runtime.PyValue.from(@as(*runtime.PyObject, @ptrCast(c_interop.callModuleFunction("numpy.random", "choice", .{chars}).?)));
        _ = &ret;
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "ret.view(\"U100\")"));
    }

    pub fn coerce(_: std.mem.Allocator, request: i64) !i64 {
        _ = &request;
        return request.param;
    }

    pub fn na_object(_: std.mem.Allocator, request: i64) !i64 {
        _ = &request;
        return request.param;
    }

    pub fn dtype(_: std.mem.Allocator, __m3_p_na_object: i64, __m4_p_coerce: i64) !i64 {
        _ = &na_object__shadow;
        _ = &coerce__shadow;
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "get_stringdtype_dtype(na_object, coerce)"));
    }

    };

    pub const version = struct {

    pub const version = "2.3.4";
    pub const __version__ = version;
    pub const full_version = version;
    pub const git_revision = "1458b9e79d1a5755eae9adcb346758f449b6b430";
    pub const release = ((std.mem.indexOf(u8, version, "dev") == null)) and ((std.mem.indexOf(u8, version, "+") == null));
    pub const short_version = (sub_0: { const __base = split_1: {
    var _split_result = std.ArrayListUnmanaged([]const u8){};
    var _split_iter = std.mem.splitSequence(u8, version, "+");
    while (_split_iter.next()) |part| {
        try _split_result.append(__global_allocator, part);
    }
    break :split_1 _split_result;
}; break :sub_0 __base.items[@as(usize, @intCast(0))]; });
    };

    pub const _globals = struct {

    pub const __all__ = [_][]const u8{"_NoValue", "_CopyMode"};
    pub const _is_loaded = true;
    const _NoValueType = struct {
        // Python class metadata
        pub const __name__: []const u8 = "_NoValueType";
        pub const __doc__: ?[]const u8 = "pecial keyword value.\n\n    The instance of this class may be used as the default value assigned to a\n    keyword if no other obvious default (e.g., `None`) is suitable,\n\n    Common reasons for using this keyword are:\n\n    - A new keyword is added to a function, and that function forwards its\n      inputs to another function or method which can be defined outside of\n      NumPy. For example, ``np.std(x)`` calls ``x.std``, so when a ``keepdims``\n      keyword was added that could only be forwarded if the user explicitly\n      specified ``keepdims``; downstream array libraries may not have added\n      the same keyword, so adding ``x.std(..., keepdims=keepdims)``\n      unconditionally could have broken previously working code.\n    - A keyword is being deprecated, and a deprecation warning must only be\n      emitted when the keyword is used.\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());


        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            if (!runtime.toBool(runtime.PyValue.from(runtime.eval(__global_allocator, "cls.__instance") catch unreachable))) {
                runtime.PyValue.from(runtime.eval(__global_allocator, "cls.__instance = super().__new__(cls)") catch unreachable);
            }
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }

        pub fn __repr__(self: *const @This()) []const u8 {
            _ = &self;
            _ = &self;
            return "<no value>";
        }

        pub fn __instance(_: *const @This(), _: std.mem.Allocator, _: anytype) !@This() {
            return error.TypeError; // 'NoneType' object is not callable
        }
    };

    pub const _NoValue = (try _NoValueType.init(__global_allocator));
    const _CopyMode = struct {
        // Python class metadata
        pub const __name__: []const u8 = "_CopyMode";
        pub const __doc__: ?[]const u8 = "    An enumeration for the copy modes supported\n    by numpy.copy() and numpy.array(). The following three modes are supported,\n\n    - ALWAYS: This means that a deep copy of the input\n              array will always be taken.\n    - IF_NEEDED: This means that a deep copy of the input\n                 array will be taken only if necessary.\n    - NEVER: This means that the deep copy will never be taken.\n             If a copy cannot be avoided then a `ValueError` will be\n             raised.\n\n    Note that the buffer-protocol could in theory do copies.  NumPy currently\n    assumes an object exporting the buffer protocol will never do this.\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }

        pub fn __bool__(self: *const @This()) runtime.PythonError!bool {
            _ = &self;
            _ = &self;
            if ((runtime.pyAnyEql(self, runtime.PyValue.from(try runtime.eval(__global_allocator, "_CopyMode.ALWAYS"))))) {
                return runtime.validateBoolReturn(true);
            }
            if ((runtime.pyAnyEql(self, runtime.PyValue.from(try runtime.eval(__global_allocator, "_CopyMode.NEVER"))))) {
                return runtime.validateBoolReturn(false);
            }
            runtime.exceptions.setException("ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "{any} is neither True nor False.", .{ self })))));
            runtime.debug_reader.printPythonError(__global_allocator, "ValueError", (try runtime.builtins.pyStr(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "{any} is neither True nor False.", .{ self })))), @src().line);
            return error.ValueError;
        }

        // Class-level attribute
        pub const ALWAYS = true;

        // Class-level attribute
        pub const NEVER = false;

        // Class-level attribute
        pub const IF_NEEDED = 2;
    };

    };

    pub const _configtool = struct {

    pub fn __user_main(_: std.mem.Allocator) !null {
        const parser: runtime.PyValue = runtime.PyValue.from(struct { description: ?[]const u8 = null, prog: ?[]const u8 = null, arguments: std.ArrayList(Argument), parsed: hashmap_helper.StringHashMap([]const u8), positional_args: std.ArrayList([]const u8), const Argument = struct { name: []const u8, short: ?[]const u8 = null, help: ?[]const u8 = null, default: ?[]const u8 = null, required: bool = false, is_flag: bool = false, action: ?[]const u8 = null }; pub fn init() @This() { return @This(){ .arguments = .{}, .parsed = .{}, .positional_args = .{} }; } pub fn add_argument(__self: *@This(), name: []const u8) void { const is_optional = name.len > 0 and name[0] == '-'; __self.arguments.append(__global_allocator, Argument{ .name = name, .is_flag = is_optional }) catch unreachable; } pub fn parse_args(__self: *@This()) *@This() { const args_arr = std.process.argsAlloc(__global_allocator) catch return __self; var i: usize = 1; while (i < args_arr.len) : (i += 1) { const arg = args_arr[i]; if (arg.len > 2 and std.mem.startsWith(u8, arg, "--")) { if (std.mem.indexOfScalar(u8, arg, '=')) |eq| { __self.parsed.put(arg[2..eq], arg[eq + 1 ..]) catch unreachable; } else if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], "-")) { __self.parsed.put(arg[2..], args_arr[i + 1]) catch unreachable; i += 1; } else { __self.parsed.put(arg[2..], "true") catch unreachable; } } else if (arg.len > 1 and arg[0] == '-') { if (i + 1 < args_arr.len and !std.mem.startsWith(u8, args_arr[i + 1], "-")) { __self.parsed.put(arg[1..], args_arr[i + 1]) catch unreachable; i += 1; } else { __self.parsed.put(arg[1..], "true") catch unreachable; } } else { __self.positional_args.append(__global_allocator, arg) catch unreachable; } } return __self; } pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.parsed.get(name); } pub fn get_positional(__self: *@This(), index: usize) ?[]const u8 { if (index < __self.positional_args.items.len) return __self.positional_args.items[index]; return null; } pub fn print_help(__self: *@This()) void { _ = __self; const stdout = std.io.getStdOut().writer(); stdout.print("usage: program [options]\n", .{}) catch unreachable; } }.init());
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.add_argument(\"--version\", action=\"version\", version=__version__, help=\"Print the version and exit.\")"));
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.add_argument(\"--cflags\", action=\"store_true\", help=\"Compile flag needed when using the NumPy headers.\")"));
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.add_argument(\"--pkgconfigdir\", action=\"store_true\", help=\"Print the pkgconfig directory in which `numpy.pc` is stored (useful for setting $PKG_CONFIG_PATH).\")"));
        const args: runtime.PyValue = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.parse_args()"));
        _ = &args;
        _ = &parser;
        if (!runtime.toBool((sub_0: { const __base = __sys_argv; break :sub_0 __base[@as(usize, @intCast(1))..__base.len]; }))) {
            _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "parser.print_help()"));
        }
        if (runtime.pyTruthy(args.cflags)) {
            runtime.builtins.print(__global_allocator, &.{try std.mem.concat(__global_allocator, u8, &[_][]const u8{ "-I", get_include() })});
        }
        var _path: *pathlib.Path = undefined;
        if (runtime.pyTruthy(args.pkgconfigdir)) {
            _path = get_include().join("..").join("lib").join("pkgconfig");
            runtime.builtins.print(__global_allocator, &.{_path.resolve()});
        }
    }

    };

    pub const dtypes = struct {

    pub const __all__ = std.ArrayListUnmanaged(i64){};
    pub fn _add_dtype_helper(_: std.mem.Allocator, DType: i64, alias: i64) !void {
        _ = &DType;
        _ = &alias;
        var __m0_m_alias = alias;
        __m1_setattr: { const __sa_obj = dtypes; const __sa_name = DType.__; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), "__base_value__")) __sa_name.__base_value__ else __sa_name; const __sa_val = DType; const __sa_obj_type = @TypeOf(__sa_obj); const __is_pytype = @typeInfo(__sa_obj_type) == .pointer and @hasDecl(@typeInfo(__sa_obj_type).pointer.child, "setattr"); if (__is_pytype) { try @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)); } else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, "__dict__")) { try @constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); } break :__m1_setattr; }
        try __all__.append(__global_allocator, DType.__);
        if ((__m0_m_alias) != 0) {
            __m0_m_alias = runtime.PyValue.from(try runtime.eval(__global_allocator, "alias.removeprefix(\"numpy.dtypes.\")"));
            __m2_setattr: { const __sa_obj = dtypes; const __sa_name = __m0_m_alias; const __sa_name_str: []const u8 = if (@hasField(@TypeOf(__sa_name), "__base_value__")) __sa_name.__base_value__ else __sa_name; const __sa_val = DType; const __sa_obj_type = @TypeOf(__sa_obj); const __is_pytype = @typeInfo(__sa_obj_type) == .pointer and @hasDecl(@typeInfo(__sa_obj_type).pointer.child, "setattr"); if (__is_pytype) { try @constCast(__sa_obj).setattr(__sa_name_str, runtime.PyValue.from(__sa_val)); } else if (@hasField(@typeInfo(__sa_obj_type).pointer.child, "__dict__")) { try @constCast(&__sa_obj.__dict__).put(__sa_name_str, runtime.PyValue.from(__sa_val)); } break :__m2_setattr; }
            try __all__.append(__global_allocator, __m0_m_alias);
        }
    }

    };

    pub const _distributor_init = struct {

    };

    pub const matlib = struct {

    pub const __version__ = np.__;
    pub const __all__ = [_][]const u8{"rand", "randn", "repmat"};
    pub fn empty(_: std.mem.Allocator, shape: struct { runtime.PyValue, runtime.PyValue, }, dtype_param: ?i64, order_param: ?[]const u8) !i64 {
        _ = &shape;
        const dtype = dtype_param;
        const order = order_param orelse "C";
        _ = "Return a new matrix of given shape and type, without initializing entries.\n\n    Parameters\n    ----------\n    shape : int or tuple of int\n        Shape of the empty matrix.\n    dtype : data-type, optional\n        Desired output data-type.\n    order : {'C', 'F'}, optional\n        Whether to store multi-dimensional data in row-major\n        (C-style) or column-major (Fortran-style) order in\n        memory.\n\n    See Also\n    --------\n    numpy.empty : Equivalent array function.\n    matlib.zeros : Return a matrix of zeros.\n    matlib.ones : Return a matrix of ones.\n\n    Notes\n    -----\n    Unlike other matrix creation functions (e.g. `matlib.zeros`,\n    `matlib.ones`), `matlib.empty` does not initialize the values of the\n    matrix, and may therefore be marginally faster. However, the values\n    stored in the newly allocated matrix are arbitrary. For reproducible\n    behavior, be sure to set each element of the matrix before reading.\n\n    Examples\n    --------\n    >>> import numpy.matlib\n    >>> np.matlib.empty((2, 2))    # filled with random data\n    matrix([[  6.76425276e-320,   9.79033856e-307], # random\n            [  7.39337286e-309,   3.22135945e-309]])\n    >>> np.matlib.empty((2, 2), dtype=int)\n    matrix([[ 6600475,        0], # random\n            [ 6586976, 22740995]])\n\n    ";
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "ndarray.__new__(matrix, shape, dtype, order=order)"));
    }

    pub fn ones(_: std.mem.Allocator, shape: i64, dtype_param: ?i64, order_param: ?[]const u8) !i64 {
        _ = &shape;
        const dtype = dtype_param;
        const order = order_param orelse "C";
        _ = "\n    Matrix of ones.\n\n    Return a matrix of given shape and type, filled with ones.\n\n    Parameters\n    ----------\n    shape : {sequence of ints, int}\n        Shape of the matrix\n    dtype : data-type, optional\n        The desired data-type for the matrix, default is np.float64.\n    order : {'C', 'F'}, optional\n        Whether to store matrix in C- or Fortran-contiguous order,\n        default is 'C'.\n\n    Returns\n    -------\n    out : matrix\n        Matrix of ones of given shape, dtype, and order.\n\n    See Also\n    --------\n    ones : Array of ones.\n    matlib.zeros : Zero matrix.\n\n    Notes\n    -----\n    If `shape` has length one i.e. ``(N,)``, or is a scalar ``N``,\n    `out` becomes a single row matrix of shape ``(1,N)``.\n\n    Examples\n    --------\n    >>> np.matlib.ones((2,3))\n    matrix([[1.,  1.,  1.],\n            [1.,  1.,  1.]])\n\n    >>> np.matlib.ones(2)\n    matrix([[1.,  1.]])\n\n    ";
        const a: runtime.PyValue = runtime.PyValue.from(try runtime.eval(__global_allocator, "ndarray.__new__(matrix, shape, dtype, order=order)"));
        _ = &a;
        _ = &shape;
        _ = &dtype;
        _ = &order;
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "a.fill(1)"));
        return a;
    }

    pub fn zeros(_: std.mem.Allocator, shape: i64, dtype_param: ?i64, order_param: ?[]const u8) !i64 {
        _ = &shape;
        const dtype = dtype_param;
        const order = order_param orelse "C";
        _ = "\n    Return a matrix of given shape and type, filled with zeros.\n\n    Parameters\n    ----------\n    shape : int or sequence of ints\n        Shape of the matrix\n    dtype : data-type, optional\n        The desired data-type for the matrix, default is float.\n    order : {'C', 'F'}, optional\n        Whether to store the result in C- or Fortran-contiguous order,\n        default is 'C'.\n\n    Returns\n    -------\n    out : matrix\n        Zero matrix of given shape, dtype, and order.\n\n    See Also\n    --------\n    numpy.zeros : Equivalent array function.\n    matlib.ones : Return a matrix of ones.\n\n    Notes\n    -----\n    If `shape` has length one i.e. ``(N,)``, or is a scalar ``N``,\n    `out` becomes a single row matrix of shape ``(1,N)``.\n\n    Examples\n    --------\n    >>> import numpy.matlib\n    >>> np.matlib.zeros((2, 3))\n    matrix([[0.,  0.,  0.],\n            [0.,  0.,  0.]])\n\n    >>> np.matlib.zeros(2)\n    matrix([[0.,  0.]])\n\n    ";
        const a: runtime.PyValue = runtime.PyValue.from(try runtime.eval(__global_allocator, "ndarray.__new__(matrix, shape, dtype, order=order)"));
        _ = &a;
        _ = &shape;
        _ = &dtype;
        _ = &order;
        _ = runtime.PyValue.from(try runtime.eval(__global_allocator, "a.fill(0)"));
        return a;
    }

    pub fn identity(_: std.mem.Allocator, n: i64, dtype_param: ?i64) !i64 {
        _ = &n;
        const dtype = dtype_param;
        _ = "\n    Returns the square identity matrix of given size.\n\n    Parameters\n    ----------\n    n : int\n        Size of the returned identity matrix.\n    dtype : data-type, optional\n        Data-type of the output. Defaults to ``float``.\n\n    Returns\n    -------\n    out : matrix\n        `n` x `n` matrix with its main diagonal set to one,\n        and all other elements zero.\n\n    See Also\n    --------\n    numpy.identity : Equivalent array function.\n    matlib.eye : More general matrix identity function.\n\n    Examples\n    --------\n    >>> import numpy.matlib\n    >>> np.matlib.identity(3, dtype=int)\n    matrix([[1, 0, 0],\n            [0, 1, 0],\n            [0, 0, 1]])\n\n    ";
        const a: runtime.PyValue = runtime.PyValue.from("");
        const b: runtime.PyValue = runtime.PyValue.from(try empty(__global_allocator, .{ n, n }, dtype, null));
        b.flat = a;
        return b;
    }

    pub fn eye(_: std.mem.Allocator, n: i64, M_param: ?i64, k_param: ?i64, dtype_param: ?runtime.builtins.PyCallable, order_param: ?[]const u8) !i64 {
        _ = &n;
        const M = M_param;
        const k = k_param orelse 0;
        const dtype = dtype_param orelse f64;
        const order = order_param orelse "C";
        _ = "\n    Return a matrix with ones on the diagonal and zeros elsewhere.\n\n    Parameters\n    ----------\n    n : int\n        Number of rows in the output.\n    M : int, optional\n        Number of columns in the output, defaults to `n`.\n    k : int, optional\n        Index of the diagonal: 0 refers to the main diagonal,\n        a positive value refers to an upper diagonal,\n        and a negative value to a lower diagonal.\n    dtype : dtype, optional\n        Data-type of the returned matrix.\n    order : {'C', 'F'}, optional\n        Whether the output should be stored in row-major (C-style) or\n        column-major (Fortran-style) order in memory.\n\n    Returns\n    -------\n    I : matrix\n        A `n` x `M` matrix where all elements are equal to zero,\n        except for the `k`-th diagonal, whose values are equal to one.\n\n    See Also\n    --------\n    numpy.eye : Equivalent array function.\n    identity : Square identity matrix.\n\n    Examples\n    --------\n    >>> import numpy.matlib\n    >>> np.matlib.eye(3, k=1, dtype=float)\n    matrix([[0.,  1.,  0.],\n            [0.,  0.,  1.],\n            [0.,  0.,  0.]])\n\n    ";
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "asmatrix(np.eye(n, M=M, k=k, dtype=dtype, order=order))"));
    }

    pub fn rand(_: std.mem.Allocator, args: anytype) !i64 {
        _ = &args;
        _ = "\n    Return a matrix of random values with given shape.\n\n    Create a matrix of the given shape and propagate it with\n    random samples from a uniform distribution over ``[0, 1)``.\n\n    Parameters\n    ----------\n    \\*args : Arguments\n        Shape of the output.\n        If given as N integers, each integer specifies the size of one\n        dimension.\n        If given as a tuple, this tuple gives the complete shape.\n\n    Returns\n    -------\n    out : ndarray\n        The matrix of random values with shape given by `\\*args`.\n\n    See Also\n    --------\n    randn, numpy.random.RandomState.rand\n\n    Examples\n    --------\n    >>> np.random.seed(123)\n    >>> import numpy.matlib\n    >>> np.matlib.rand(2, 3)\n    matrix([[0.69646919, 0.28613933, 0.22685145],\n            [0.55131477, 0.71946897, 0.42310646]])\n    >>> np.matlib.rand((2, 3))\n    matrix([[0.9807642 , 0.68482974, 0.4809319 ],\n            [0.39211752, 0.34317802, 0.72904971]])\n\n    If the first argument is a tuple, other arguments are ignored:\n\n    >>> np.matlib.rand((2, 3), 4)\n    matrix([[0.43857224, 0.0596779 , 0.39804426],\n            [0.73799541, 0.18249173, 0.17545176]])\n\n    ";
        _ = __m0_blk: { _ = @TypeOf(runtime.PyValue.from(try runtime.eval(__global_allocator, "args[0]"))); break :__m0_blk true; };
        const args: runtime.PyValue = runtime.PyValue.from(try runtime.eval(__global_allocator, "args[0]"));
        _ = &args;
        _ = &args;
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "asmatrix(np.random.rand(*args))"));
    }

    pub fn randn(_: std.mem.Allocator, args: anytype) !i64 {
        _ = &args;
        _ = "\n    Return a random matrix with data from the \"standard normal\" distribution.\n\n    `randn` generates a matrix filled with random floats sampled from a\n    univariate \"normal\" (Gaussian) distribution of mean 0 and variance 1.\n\n    Parameters\n    ----------\n    \\*args : Arguments\n        Shape of the output.\n        If given as N integers, each integer specifies the size of one\n        dimension. If given as a tuple, this tuple gives the complete shape.\n\n    Returns\n    -------\n    Z : matrix of floats\n        A matrix of floating-point samples drawn from the standard normal\n        distribution.\n\n    See Also\n    --------\n    rand, numpy.random.RandomState.randn\n\n    Notes\n    -----\n    For random samples from the normal distribution with mean ``mu`` and\n    standard deviation ``sigma``, use::\n\n        sigma * np.matlib.randn(...) + mu\n\n    Examples\n    --------\n    >>> np.random.seed(123)\n    >>> import numpy.matlib\n    >>> np.matlib.randn(1)\n    matrix([[-1.0856306]])\n    >>> np.matlib.randn(1, 2, 3)\n    matrix([[ 0.99734545,  0.2829785 , -1.50629471],\n            [-0.57860025,  1.65143654, -2.42667924]])\n\n    Two-by-four matrix of samples from the normal distribution with\n    mean 3 and standard deviation 2.5:\n\n    >>> 2.5 * np.matlib.randn((2, 4)) + 3\n    matrix([[1.92771843, 6.16484065, 0.83314899, 1.30278462],\n            [2.76322758, 6.72847407, 1.40274501, 1.8900451 ]])\n\n    ";
        _ = __m1_blk: { _ = @TypeOf(runtime.PyValue.from(try runtime.eval(__global_allocator, "args[0]"))); break :__m1_blk true; };
        const args: runtime.PyValue = runtime.PyValue.from(try runtime.eval(__global_allocator, "args[0]"));
        _ = &args;
        _ = &args;
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "asmatrix(np.random.randn(*args))"));
    }

    pub fn repmat(_: std.mem.Allocator, a: i64, m: i64, n: i64) !i64 {
        var origrows: @TypeOf(.{ @as(i64, 1), @as(i64, 1) }) = undefined;
        _ = &origrows;
        var origcols: @TypeOf(.{ @as(i64, 1), @as(i64, 1) }) = undefined;
        _ = &origcols;
        _ = &a;
        _ = &m;
        _ = &n;
        var __m2_m_a = a;
        _ = "\n    Repeat a 0-D to 2-D array or matrix MxN times.\n\n    Parameters\n    ----------\n    a : array_like\n        The array or matrix to be repeated.\n    m, n : int\n        The number of times `a` is repeated along the first and second axes.\n\n    Returns\n    -------\n    out : ndarray\n        The result of repeating `a`.\n\n    Examples\n    --------\n    >>> import numpy.matlib\n    >>> a0 = np.array(1)\n    >>> np.matlib.repmat(a0, 2, 3)\n    array([[1, 1, 1],\n           [1, 1, 1]])\n\n    >>> a1 = np.arange(4)\n    >>> np.matlib.repmat(a1, 2, 2)\n    array([[0, 1, 2, 3, 0, 1, 2, 3],\n           [0, 1, 2, 3, 0, 1, 2, 3]])\n\n    >>> a2 = np.asmatrix(np.arange(6).reshape(2, 3))\n    >>> np.matlib.repmat(a2, 2, 3)\n    matrix([[0, 1, 2, 0, 1, 2, 0, 1, 2],\n            [3, 4, 5, 3, 4, 5, 3, 4, 5],\n            [0, 1, 2, 0, 1, 2, 0, 1, 2],\n            [3, 4, 5, 3, 4, 5, 3, 4, 5]])\n\n    ";
        __m2_m_a = asanyarray(__m2_m_a);
        const ndim: runtime.PyValue = runtime.PyValue.from(__m2_m_a.ndim);
        if ((runtime.pyAnyEql(ndim, 0))) {
            const __m3_unpack_tmp = .{ @as(i64, 1), @as(i64, 1) };
            origrows = runtime.tuple_ops.getField(__m3_unpack_tmp, 0);
            origcols = runtime.tuple_ops.getField(__m3_unpack_tmp, 1);
        } else if ((runtime.pyAnyEql(ndim, 1))) {
            const __m4_unpack_tmp = .{ @as(i64, 1), (sub_0: { const __base = __m2_m_a.shape; break :sub_0 if (@TypeOf(__base) == runtime.PyValue) __base.pyAt(@as(usize, @intCast(0))) else __base[@as(usize, @intCast(0))]; }) };
            origrows = runtime.tuple_ops.getField(__m4_unpack_tmp, 0);
            origcols = runtime.tuple_ops.getField(__m4_unpack_tmp, 1);
        } else {
            const __m5_unpack_tmp = __m2_m_a.shape;
            origrows = runtime.tuple_ops.getField(__m5_unpack_tmp, 0);
            origcols = runtime.tuple_ops.getField(__m5_unpack_tmp, 1);
        }
        const rows: runtime.PyValue = runtime.PyValue.from((origrows * m));
        const cols: runtime.PyValue = (runtime.PyValue.from(origcols)).mul(runtime.PyValue.from(n));
        const c: runtime.PyValue = runtime.PyValue.from((mcall_1: { const __obj = (mcall_2: { const __obj = (mcall_3: { const __obj = runtime.PyValue.from(try runtime.eval(__global_allocator, "a.reshape(1, a.size)")); break :mcall_3 __obj.repeat(m, 0); }); break :mcall_2 __obj.reshape(rows, origcols); }); break :mcall_1 __obj.repeat(n, 0); }));
        _ = &cols;
        _ = &c;
        return runtime.PyValue.from(try runtime.eval(__global_allocator, "c.reshape(rows, cols)"));
    }

    };

    pub const exceptions = struct {

    pub const __all__ = [_][]const u8{"ComplexWarning", "VisibleDeprecationWarning", "ModuleDeprecationWarning", "TooHardError", "AxisError", "DTypePromotionError"};
    pub const _is_loaded = true;
    const ComplexWarning = struct {
        // Python class metadata
        pub const __name__: []const u8 = "ComplexWarning";
        pub const __doc__: ?[]const u8 = "    The warning raised when casting a complex dtype to a real dtype.\n\n    As implemented, casting a complex number to a real discards its imaginary\n    part, but this behavior may not be what the user actually wants.\n\n   ";
        pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{&RuntimeWarning.__vtable__};
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    const ModuleDeprecationWarning = struct {
        // Python class metadata
        pub const __name__: []const u8 = "ModuleDeprecationWarning";
        pub const __doc__: ?[]const u8 = "odule deprecation warning.\n\n    .. warning::\n\n        This warning should not be used, since nose testing is not relevant\n        anymore.\n\n    The nose tester turns ordinary Deprecation warnings into test failures.\n    That makes it hard to deprecate whole modules, because they get\n    imported by default. So this is a special Deprecation warning that the\n    nose tester will let pass without making tests fail.\n\n   ";
        pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{&DeprecationWarning.__vtable__};
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    const VisibleDeprecationWarning = struct {
        // Python class metadata
        pub const __name__: []const u8 = "VisibleDeprecationWarning";
        pub const __doc__: ?[]const u8 = "isible deprecation warning.\n\n    By default, python will not show deprecation warnings, so this class\n    can be used when a very visible warning is helpful, for example because\n    the usage is most likely a user bug.\n\n   ";
        pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{&UserWarning.__vtable__};
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    const RankWarning = struct {
        // Python class metadata
        pub const __name__: []const u8 = "RankWarning";
        pub const __doc__: ?[]const u8 = "atrix rank warning.\n\n    Issued by polynomial functions when the design matrix is rank deficient.\n\n   ";
        pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{&RuntimeWarning.__vtable__};
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    const TooHardError = struct {
        // Python class metadata
        pub const __name__: []const u8 = "TooHardError";
        pub const __doc__: ?[]const u8 = "`max_work`` was exceeded.\n\n    This is raised whenever the maximum number of candidate solutions\n    to consider specified by the ``max_work`` parameter is exceeded.\n    Assigning a finite number to ``max_work`` may have caused the operation\n    to fail.\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    const AxisError = struct {
        // Python class metadata
        pub const __name__: []const u8 = "AxisError";
        pub const __doc__: ?[]const u8 = "xis supplied was invalid.\n\n    This is raised whenever an ``axis`` parameter is specified that is larger\n    than the number of array dimensions.\n    For compatibility with code written against older numpy versions, which\n    raised a mixture of :exc:`ValueError` and :exc:`IndexError` for this\n    situation, this exception subclasses both to ensure that\n    ``except ValueError`` and ``except IndexError`` statements continue\n    to catch ``AxisError``.\n\n    Parameters\n    ----------\n    axis : int or str\n        The out of bounds axis or a custom exception message.\n        If an axis is provided, then `ndim` should be specified as well.\n    ndim : int, optional\n        The number of array dimensions.\n    msg_prefix : str, optional\n        A prefix for the exception message.\n\n    Attributes\n    ----------\n    axis : int, optional\n        The out of bounds axis or ``None`` if a custom exception\n        message was provided. This should be the axis as passed by\n        the user, before any normalization to resolve negative indices.\n\n        .. versionadded:: 1.22\n    ndim : int, optional\n        The number of array dimensions or ``None`` if a custom exception\n        message was provided.\n\n        .. versionadded:: 1.22\n\n\n    Examples\n    --------\n    >>> import numpy as np\n    >>> array_1d = np.arange(10)\n    >>> np.cumsum(array_1d, axis=1)\n    Traceback (most recent call last):\n      ...\n    numpy.exceptions.AxisError: axis 1 is out of bounds for array of dimension 1\n\n    Negative axes are preserved:\n\n    >>> np.cumsum(array_1d, axis=-2)\n    Traceback (most recent call last):\n      ...\n    numpy.exceptions.AxisError: axis -2 is out of bounds for array of dimension 1\n\n    The class constructor generally takes the axis and arrays'\n    dimensionality as arguments:\n\n    >>> print(np.exceptions.AxisError(2, 1, msg_prefix='error'))\n    error: axis 2 is out of bounds for array of dimension 1\n\n    Alternatively, a custom exception message can be passed:\n\n    >>> print(np.exceptions.AxisError('Custom error message'))\n    Custom error message\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());


        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator, axis: anytype, ndim: anytype, msg_prefix: anytype) !@This() {
            if ((((runtime.pyIdentical(ndim, msg_prefix)) and ((@TypeOf(msg_prefix) == @TypeOf(null)))))) {
                try @constCast(&runtime.builtins.self.__dict__).put("_msg", runtime.PyValue.from(axis));
                try @constCast(&runtime.builtins.self.__dict__).put("axis", runtime.PyValue.from(null));
                try @constCast(&runtime.builtins.self.__dict__).put("ndim", runtime.PyValue.from(null));
            } else {
                try @constCast(&runtime.builtins.self.__dict__).put("_msg", runtime.PyValue.from(msg_prefix));
                try @constCast(&runtime.builtins.self.__dict__).put("axis", runtime.PyValue.from(axis));
                try @constCast(&runtime.builtins.self.__dict__).put("ndim", runtime.PyValue.from(ndim));
            }
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }

        pub fn __str__(self: *const @This(), _: std.mem.Allocator) []const u8 {
            _ = &self;
            _ = &self;
            const axis: runtime.PyValue = runtime.PyValue.from(self.__dict__.get("axis").?.int);
            const ndim: runtime.PyValue = runtime.PyValue.from(self.__dict__.get("ndim").?.int);
            var msg: []const u8 = undefined;
            if ((((runtime.pyIdentical(axis, ndim)) and ((@TypeOf(ndim) == @TypeOf(null)))))) {
                return self.__dict__.get("_msg").?.int;
            } else {
                msg = (try std.fmt.allocPrint(__global_allocator, "axis {any} is out of bounds for array of dimension {any}", .{ axis, ndim }));
                if (((@TypeOf(self.__dict__.get("_msg").?.int) != @TypeOf(null)))) {
                    msg = (try std.fmt.allocPrint(__global_allocator, "{any}: {s}", .{ self.__dict__.get("_msg").?.int, msg }));
                }
                return msg;
            }
        }
    };

    const DTypePromotionError = struct {
        // Python class metadata
        pub const __name__: []const u8 = "DTypePromotionError";
        pub const __doc__: ?[]const u8 = "ultiple DTypes could not be converted to a common one.\n\n    This exception derives from ``TypeError`` and is raised whenever dtypes\n    cannot be converted to a single common one.  This can be because they\n    are of a different category/class or incompatible instances of the same\n    one (see Examples).\n\n    Notes\n    -----\n    Many functions will use promotion to find the correct result and\n    implementation.  For these functions the error will typically be chained\n    with a more specific error indicating that no implementation was found\n    for the input dtypes.\n\n    Typically promotion should be considered \"invalid\" between the dtypes of\n    two arrays when `arr1 == arr2` can safely return all ``False`` because the\n    dtypes are fundamentally different.\n\n    Examples\n    --------\n    Datetimes and complex numbers are incompatible classes and cannot be\n    promoted:\n\n    >>> import numpy as np\n    >>> np.result_type(np.dtype(\"M8[s]\"), np.complex128)  # doctest: +IGNORE_EXCEPTION_DETAIL\n    Traceback (most recent call last):\n     ...\n    DTypePromotionError: The DType <class 'numpy.dtype[datetime64]'> could not\n    be promoted by <class 'numpy.dtype[complex128]'>. This means that no common\n    DType exists for the given inputs. For example they cannot be stored in a\n    single array unless the dtype is `object`. The full list of DTypes is:\n    (<class 'numpy.dtype[datetime64]'>, <class 'numpy.dtype[complex128]'>)\n\n    For example for structured dtypes, the structure can mismatch and the\n    same ``DTypePromotionError`` is given when two structured dtypes with\n    a mismatch in their number of fields is given:\n\n    >>> dtype1 = np.dtype([(\"field1\", np.float64), (\"field2\", np.int64)])\n    >>> dtype2 = np.dtype([(\"field1\", np.float64)])\n    >>> np.promote_types(dtype1, dtype2)  # doctest: +IGNORE_EXCEPTION_DETAIL\n    Traceback (most recent call last):\n     ...\n    DTypePromotionError: field names `('field1', 'field2')` and `('field1',)`\n    mismatch.\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator) !@This() {
            return @This(){
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }
    };

    };

    pub const _expired_attrs_2_0 = struct {

    pub const __expired_attributes__ = (__m0_dict: { 
        const _kvs = .{
            .{ "geterrobj", "Use the np.errstate context manager instead." },
            .{ "seterrobj", "Use the np.errstate context manager instead." },
            .{ "cast", "Use `np.asarray(arr, dtype=dtype)` instead." },
            .{ "source", "Use `inspect.getsource` instead." },
            .{ "lookfor", "Search NumPy's documentation directly." },
            .{ "who", "Use an IDE variable explorer or `locals()` instead." },
            .{ "fastCopyAndTranspose", "Use `arr.T.copy()` instead." },
            .{ "set_numeric_ops", "For the general case, use `PyUFunc_ReplaceLoopBySignature`. For ndarray subclasses, define the ``__array_ufunc__`` method and override the relevant ufunc." },
            .{ "NINF", "Use `-np.inf` instead." },
            .{ "PINF", "Use `np.inf` instead." },
            .{ "NZERO", "Use `-0.0` instead." },
            .{ "PZERO", "Use `0.0` instead." },
            .{ "add_newdoc", "It's still available as `np.lib.add_newdoc`." },
            .{ "add_docstring", "It's still available as `np.lib.add_docstring`." },
            .{ "add_newdoc_ufunc", "It's an internal function and doesn't have a replacement." },
            .{ "safe_eval", "Use `ast.literal_eval` instead." },
            .{ "float_", "Use `np.float64` instead." },
            .{ "complex_", "Use `np.complex128` instead." },
            .{ "longfloat", "Use `np.longdouble` instead." },
            .{ "singlecomplex", "Use `np.complex64` instead." },
            .{ "cfloat", "Use `np.complex128` instead." },
            .{ "longcomplex", "Use `np.clongdouble` instead." },
            .{ "clongfloat", "Use `np.clongdouble` instead." },
            .{ "string_", "Use `np.bytes_` instead." },
            .{ "unicode_", "Use `np.str_` instead." },
            .{ "Inf", "Use `np.inf` instead." },
            .{ "Infinity", "Use `np.inf` instead." },
            .{ "NaN", "Use `np.nan` instead." },
            .{ "infty", "Use `np.inf` instead." },
            .{ "issctype", "Use `issubclass(rep, np.generic)` instead." },
            .{ "maximum_sctype", "Use a specific dtype instead. You should avoid relying on any implicit mechanism and select the largest dtype of a kind explicitly in the code." },
            .{ "obj2sctype", "Use `np.dtype(obj).type` instead." },
            .{ "sctype2char", "Use `np.dtype(obj).char` instead." },
            .{ "sctypes", "Access dtypes explicitly instead." },
            .{ "issubsctype", "Use `np.issubdtype` instead." },
            .{ "set_string_function", "Use `np.set_printoptions` instead with a formatter for custom printing of NumPy objects." },
            .{ "asfarray", "Use `np.asarray` with a proper dtype instead." },
            .{ "issubclass_", "Use `issubclass` builtin instead." },
            .{ "tracemalloc_domain", "It's now available from `np.lib`." },
            .{ "mat", "Use `np.asmatrix` instead." },
            .{ "recfromcsv", "Use `np.genfromtxt` with comma delimiter instead." },
            .{ "recfromtxt", "Use `np.genfromtxt` instead." },
            .{ "deprecate", "Emit `DeprecationWarning` with `warnings.warn` directly, or use `typing.deprecated`." },
            .{ "deprecate_with_doc", "Emit `DeprecationWarning` with `warnings.warn` directly, or use `typing.deprecated`." },
            .{ "disp", "Use your own printing function instead." },
            .{ "find_common_type", "Use `numpy.promote_types` or `numpy.result_type` instead. To achieve semantics for the `scalar_types` argument, use `numpy.result_type` and pass the Python values `0`, `0.0`, or `0j`." },
            .{ "round_", "Use `np.round` instead." },
            .{ "get_array_wrap", "" },
            .{ "DataSource", "It's still available as `np.lib.npyio.DataSource`." },
            .{ "nbytes", "Use `np.dtype(<dtype>).itemsize` instead." },
            .{ "byte_bounds", "Now it's available under `np.lib.array_utils.byte_bounds`" },
            .{ "compare_chararrays", "It's still available as `np.char.compare_chararrays`." },
            .{ "format_parser", "It's still available as `np.rec.format_parser`." },
            .{ "alltrue", "Use `np.all` instead." },
            .{ "sometrue", "Use `np.any` instead." },
        };
        const V = comptime runtime.InferDictValueType(@TypeOf(_kvs));
        var _dict = hashmap_helper.StringHashMap(V).init(__global_allocator);
        inline for (_kvs) |kv| {
            const cast_val = if (@TypeOf(kv[1]) != V) (__m1_cast: {
                if (V == f64 and (@TypeOf(kv[1]) == i64 or @TypeOf(kv[1]) == comptime_int)) {
                    break :__m1_cast @as(f64, @floatFromInt(kv[1]));
                }
                if (V == f64 and @TypeOf(kv[1]) == comptime_float) {
                    break :__m1_cast @as(f64, kv[1]);
                }
                if (V == []const u8) {
                    const kv_type_info = @typeInfo(@TypeOf(kv[1]));
                    if (kv_type_info == .pointer and kv_type_info.pointer.size == .one) {
                        const child = @typeInfo(kv_type_info.pointer.child);
                        if (child == .array and child.array.child == u8) {
                            break :__m1_cast @as([]const u8, kv[1]);
                        }
                    }
                }
                if (V == ?void and @TypeOf(kv[1]) == @TypeOf(null)) {
                    break :__m1_cast null;
                }
                if (V == runtime.PyValue) {
                    break :__m1_cast try runtime.toPyValue(__global_allocator, kv[1]);
                }
                break :__m1_cast kv[1];
            }) else kv[1];
            try _dict.put(kv[0], cast_val);
        }
        break :__m0_dict _dict;
    });
    };

    pub const _pytesttester = struct {

    pub const __all__ = [_][]const u8{"PytestTester"};
    pub fn _show_numpy_info(_: std.mem.Allocator) !void {
        const np = runtime.PyValue.from(try runtime.eval(__global_allocator, "import numpy; numpy"));
        _ = &np;
        runtime.builtins.print(__global_allocator, &.{(try std.fmt.allocPrint(__global_allocator, "NumPy version {any}", .{ runtime.PyValue.from(try runtime.eval(__global_allocator, "np.__version__")) }))});
        const info: runtime.PyValue = runtime.PyValue.from((mcall_0: { const __obj = (attr_1: { const __obj = runtime.PyValue.from(try runtime.eval(__global_allocator, "np.lib")); break :attr_1 __obj._utils_impl; }); break :mcall_0 __obj._opt_info(); }));
        runtime.builtins.print(__global_allocator, &.{"NumPy CPU features: ", runtime.toBool(try runtime.pyOr(__global_allocator, info, "nothing enabled"))});
    }

    const PytestTester = struct {
        // Python class metadata
        pub const __name__: []const u8 = "PytestTester";
        pub const __doc__: ?[]const u8 = "    Pytest test runner.\n\n    A test function is typically added to a package's __init__.py like so::\n\n      from numpy._pytesttester import PytestTester\n      test = PytestTester(__name__).test\n      del PytestTester\n\n    Calling this test function finds and runs all tests associated with the\n    module and all its sub-modules.\n\n    Attributes\n    ----------\n    module_name : str\n        Full path to the package to test.\n\n    Parameters\n    ----------\n    module_name : module name\n        The name of the module to test.\n\n    Notes\n    -----\n    Unlike the previous ``nose``-based implementation, this class is not\n    publicly exposed as it performs some ``numpy``-specific warning\n    suppression.\n\n   ";
        pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;
        pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());

        module_name: runtime.PyValue,
        __module__: runtime.PyValue,

        // Dynamic attributes dictionary
        __dict__: hashmap_helper.StringHashMap(runtime.PyValue),

        pub fn init(__alloc: std.mem.Allocator, module_name: anytype) !@This() {
            return @This(){
                .module_name = runtime.PyValue.from(module_name),
                .__module__ = runtime.PyValue.from(module_name),
                .__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(__alloc),
            };
        }

        pub fn __call__(self: *const @This(), _: std.mem.Allocator, label: anytype, verbose: anytype, extra_argv: anytype, doctests: anytype, coverage: anytype, durations: anytype, tests: ?std.ArrayListUnmanaged(runtime.PyValue)) !bool {
            _ = &self;
            _ = &self;
            _ = &label;
            _ = &verbose;
            _ = &extra_argv;
            _ = &doctests;
            _ = &coverage;
            _ = &durations;
            _ = &tests;
            var code: runtime.PyValue = undefined;
            _ = &code;
            var pytest_args: i64 = undefined;
            _ = &pytest_args;
            var __m0_m_tests: runtime.PyValue = runtime.PyValue.from(tests);
            _ = "\n        Run tests for module using pytest.\n\n        Parameters\n        ----------\n        label : {'fast', 'full'}, optional\n            Identifies the tests to run. When set to 'fast', tests decorated\n            with `pytest.mark.slow` are skipped, when 'full', the slow marker\n            is ignored.\n        verbose : int, optional\n            Verbosity value for test outputs, in the range 1-3. Default is 1.\n        extra_argv : list, optional\n            List with any extra arguments to pass to pytests.\n        doctests : bool, optional\n            .. note:: Not supported\n        coverage : bool, optional\n            If True, report coverage of NumPy code. Default is False.\n            Requires installation of (pip) pytest-cov.\n        durations : int, optional\n            If < 0, do nothing, If 0, report time of all tests, if > 0,\n            report the time of the slowest `timer` tests. Default is -1.\n        tests : test or list of tests\n            Tests to be executed with pytest '--pyargs'\n\n        Returns\n        -------\n        result : bool\n            Return True on success, false otherwise.\n\n        Notes\n        -----\n        Each NumPy module exposes `test` in its namespace to run all tests for\n        it. For example, to run all tests for numpy.lib:\n\n        >>> np.lib.test() #doctest: +SKIP\n\n        Examples\n        --------\n        >>> result = np.lib.test() #doctest: +SKIP\n        ...\n        1023 passed, 2 skipped, 6 deselected, 1 xfailed in 10.39 seconds\n        >>> result\n        True\n\n        ";
            const pytest = runtime.PyValue.from(try runtime.eval(__global_allocator, "import pytest; pytest"));
            _ = &pytest;
            const module: runtime.PyValue = runtime.PyValue.from((sub_2: { const __base = hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator); break :sub_2 __base[self.module_name]; }));
            const module_path: []const u8 = (__m1_path_abspath: { const _path = (sub_3: { const __base = module.__; break :sub_3 if (@TypeOf(__base) == runtime.PyValue) __base.pyAt(@as(usize, @intCast(0))) else __base[@as(usize, @intCast(0))]; }); const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :__m1_path_abspath _path; break :__m1_path_abspath std.fs.path.join(__global_allocator, &[_][]const u8{_cwd, _path}) catch _path; });
            pytest_args = std.ArrayListUnmanaged([]const u8){};
            try pytest_args.append(__global_allocator, "-l");
            try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"-q"});
            if ((runtime.PyValue.from(sys.version_info).lt(runtime.PyValue.from(.{ @as(i64, 3), @as(i64, 12) })))) {
                {
                    var __m2_ctx = struct { record: bool = false, log: std.ArrayList([]const u8) = .{}, pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { _ = __self; } pub fn close(_: @This()) void {} }{};
                    defer { _ = __m2_ctx.__exit__(__global_allocator, null, null, null) catch {}; }
                    _ = try __m2_ctx.__enter__(__global_allocator);
                }
                }
                try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"-W ignore:Not importing directory", "-W ignore:numpy.dtype size changed", "-W ignore:numpy.ufunc size changed", "-W ignore::UserWarning:cpuinfo"});
                try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"-W ignore:the matrix subclass is not", "-W ignore:Importing from numpy.matlib is"});
                if (runtime.pyTruthy(doctests)) {
                    try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"--doctest-modules"});
                }
                if (runtime.pyTruthy(extra_argv)) {
                    {
                        const __ext_src = runtime.listFromAny(__global_allocator, extra_argv);
                        for (runtime.iterSlice(__ext_src)) |__ext_item| {
                            const __ListElemType = @typeInfo(@TypeOf(pytest_args.items)).pointer.child;
                            const __ItemType = @TypeOf(__ext_item);
                            if (__ListElemType == __ItemType) {
                                pytest_args.append(__global_allocator, __ext_item) catch unreachable;
                            } else if (__ListElemType == runtime.PyValue) {
                                pytest_args.append(__global_allocator, try runtime.PyValue.fromAlloc(__global_allocator, __ext_item)) catch unreachable;
                            }
                        }
                    }
                }
                if ((runtime.PyValue.from(verbose).gt(runtime.PyValue.from(1)))) {
                    try pytest_args.appendSlice(__global_allocator, &__list_rt_3: {
                        var __list_var_3 = std.ArrayListUnmanaged([]const u8){};
                        try __list_var_3.append(__global_allocator, try std.mem.concat(__global_allocator, u8, &[_][]const u8{ "-", runtime.strRepeat(__global_allocator, "v", @as(usize, @intCast(runtime.subtractNum(verbose, 1)))) }));
                        break :__list_rt_3 __list_var_3;
                    });
                }
                if (runtime.pyTruthy(coverage)) {
                    try pytest_args.appendSlice(__global_allocator, &__list_rt_4: {
                        var __list_var_4 = std.ArrayListUnmanaged([]const u8){};
                        try __list_var_4.append(__global_allocator, (runtime.PyValue.from("--cov=")).add(runtime.PyValue.from(module_path)));
                        break :__list_rt_4 __list_var_4;
                    });
                }
                if ((runtime.pyAnyEql(label, "fast"))) {
                    if (runtime.pyTruthy(IS_PYPY)) {
                        try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"-m", "not slow and not slow_pypy"});
                    } else {
                        try pytest_args.appendSlice(__global_allocator, &[_][]const u8{"-m", "not slow"});
                    }
                } else if ((!runtime.pyAnyEql(label, "full"))) {
                    try pytest_args.appendSlice(__global_allocator, &__list_rt_5: {
                        var __list_var_5 = std.ArrayListUnmanaged([]const u8){};
                        try __list_var_5.append(__global_allocator, "-m");
                        try __list_var_5.append(__global_allocator, label);
                        break :__list_rt_5 __list_var_5;
                    });
                }
                if ((runtime.PyValue.from(durations).ge(runtime.PyValue.from(0)))) {
                    try pytest_args.appendSlice(__global_allocator, &__list_rt_6: {
                        var __list_var_6 = std.ArrayListUnmanaged([]const u8){};
                        try __list_var_6.append(__global_allocator, (try std.fmt.allocPrint(__global_allocator, "--durations={any}", .{ durations })));
                        break :__list_rt_6 __list_var_6;
                    });
                }
                if (((@TypeOf(__m0_m_tests) == @TypeOf(null)))) {
                    __m0_m_tests = std.ArrayListUnmanaged(runtime.PyValue){};
                    try __m0_m_tests.append(__global_allocator, self.module_name);
                }
                {
                    const __ext_src = try runtime.concatRuntime(__global_allocator, [_][]const u8{"--pyargs"}, __m0_m_tests);
                    for (runtime.iterSlice(__ext_src)) |__ext_item| {
                        const __ListElemType = @typeInfo(@TypeOf(pytest_args.items)).pointer.child;
                        const __ItemType = @TypeOf(__ext_item);
                        if (__ListElemType == __ItemType) {
                            pytest_args.append(__global_allocator, __ext_item) catch unreachable;
                        } else if (__ListElemType == runtime.PyValue) {
                            pytest_args.append(__global_allocator, try runtime.PyValue.fromAlloc(__global_allocator, __ext_item)) catch unreachable;
                        }
                    }
                }
                _ = try _show_numpy_info(__global_allocator);
                var exc: runtime.PyException = undefined;
                _ = &exc;
                {
                    const __TryHelper_0 = struct {
                        fn run(p_pytest_args_0: anytype, p_code_0: *runtime.PyValue, p_exc_0: *runtime.PyException) !void {
                            const __local_pytest_args_0: @TypeOf(p_pytest_args_0) = p_pytest_args_0;
                            _ = &__local_pytest_args_0;
                            runtime.discard(p_exc_0);
                            p_code_0.* = runtime.PyValue.from(try runtime.eval(__global_allocator, "pytest.main(pytest_args)"));
                        }
                    };
                    __TryHelper_0.run(pytest_args, &code, &exc) catch |__err_0| {
                        if (__err_0 == error.SystemExit) {
                            exc = runtime.getExceptionFull();
                            code = runtime.PyValue.from(try runtime.eval(__global_allocator, "exc.code"));
                        } else {
                            return __err_0;
                        }
                    };
                }
                return (runtime.pyAnyEql(code, 0));
            }
        };

    };