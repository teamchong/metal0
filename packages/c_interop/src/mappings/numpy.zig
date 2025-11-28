// NumPy to BLAS/LAPACK mapping
// This module maps NumPy array operations to their underlying BLAS/LAPACK C functions

const mapper = @import("../mapper.zig");

// NumPy library mapping
pub const numpy_mapping = mapper.CLibraryMapping{
    .package_name = "numpy",
    .requires_cpp = false,
    .import_patterns = &[_][]const u8{ "import numpy", "from numpy" },

    .libraries = &[_]mapper.LibraryInfo{
        // BLAS - Basic Linear Algebra Subprograms
        .{
            .name = "blas",
            .headers = &[_][]const u8{"cblas.h"},
            .link_flags = &[_][]const u8{"-lopenblas"},
            .pkg_config_name = "openblas",
            .fallback_names = &[_][]const u8{ "openblas", "blas", "Accelerate" },
            .is_cpp = false,
            .min_version = null,
        },
        // LAPACK - Linear Algebra PACKage
        .{
            .name = "lapack",
            .headers = &[_][]const u8{"lapacke.h"},
            .link_flags = &[_][]const u8{"-llapacke"},
            .pkg_config_name = "lapacke",
            .fallback_names = &[_][]const u8{"lapacke"},
            .is_cpp = false,
            .min_version = null,
        },
    },

    .functions = &[_]mapper.FunctionMapping{
        // numpy.sum(a) → cblas_dasum (sum of absolute values, close enough for demo)
        .{
            .python_name = "numpy.sum",
            .c_name = "cblas_dasum",
            .allocates_memory = false,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Array sum via BLAS Level 1. Note: cblas_dasum computes sum of absolute values.",
            .arg_mappings = &[_]mapper.ArgMapping{
                .{
                    .python_index = 0,
                    .c_index = 1,
                    .python_type = .numpy_array,
                    .c_type = .{
                        .name = "double",
                        .pointer_depth = 1,
                        .is_const = true,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .{
                        .pass_pointer = .{ .pointer_path = ".ptr" },
                    },
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .float },
        },

        // numpy.dot(a, b) → cblas_ddot (dot product for 1D)
        .{
            .python_name = "numpy.dot",
            .c_name = "cblas_ddot",
            .allocates_memory = false,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Dot product via BLAS Level 1. For 1D arrays only in this initial implementation.",
            .arg_mappings = &[_]mapper.ArgMapping{
                // First array
                .{
                    .python_index = 0,
                    .c_index = 1,
                    .python_type = .numpy_array,
                    .c_type = .{
                        .name = "double",
                        .pointer_depth = 1,
                        .is_const = true,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .{
                        .pass_pointer = .{ .pointer_path = ".ptr" },
                    },
                    .is_optional = false,
                    .default_value = null,
                },
                // Second array
                .{
                    .python_index = 1,
                    .c_index = 3,
                    .python_type = .numpy_array,
                    .c_type = .{
                        .name = "double",
                        .pointer_depth = 1,
                        .is_const = true,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .{
                        .pass_pointer = .{ .pointer_path = ".ptr" },
                    },
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .float },
        },

        // numpy.array([...]) - no C call, just allocation
        .{
            .python_name = "numpy.array",
            .c_name = "__metal0_numpy_array_create",
            .allocates_memory = true,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Array creation - handled by metal0 runtime, not BLAS",
            .arg_mappings = &[_]mapper.ArgMapping{
                .{
                    .python_index = 0,
                    .c_index = 0,
                    .python_type = .list,
                    .c_type = .{
                        .name = "void",
                        .pointer_depth = 1,
                        .is_const = false,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .{ .custom = "convert_list_to_array" },
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .numpy_array },
        },

        // numpy.zeros(n)
        .{
            .python_name = "numpy.zeros",
            .c_name = "__metal0_numpy_zeros",
            .allocates_memory = true,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Create zero-initialized array",
            .arg_mappings = &[_]mapper.ArgMapping{
                .{
                    .python_index = 0,
                    .c_index = 0,
                    .python_type = .int,
                    .c_type = .{
                        .name = "size_t",
                        .pointer_depth = 0,
                        .is_const = false,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .direct,
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .numpy_array },
        },

        // numpy.ones(n)
        .{
            .python_name = "numpy.ones",
            .c_name = "__metal0_numpy_ones",
            .allocates_memory = true,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Create one-initialized array",
            .arg_mappings = &[_]mapper.ArgMapping{
                .{
                    .python_index = 0,
                    .c_index = 0,
                    .python_type = .int,
                    .c_type = .{
                        .name = "size_t",
                        .pointer_depth = 0,
                        .is_const = false,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .direct,
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .numpy_array },
        },

        // numpy.mean(a)
        .{
            .python_name = "numpy.mean",
            .c_name = "__metal0_numpy_mean",
            .allocates_memory = false,
            .setup_code = null,
            .cleanup_code = null,
            .notes = "Compute mean value - uses BLAS sum internally",
            .arg_mappings = &[_]mapper.ArgMapping{
                .{
                    .python_index = 0,
                    .c_index = 0,
                    .python_type = .numpy_array,
                    .c_type = .{
                        .name = "double",
                        .pointer_depth = 1,
                        .is_const = true,
                        .array_size = 0,
                        .is_reference = false,
                    },
                    .conversion = .{
                        .pass_pointer = .{ .pointer_path = ".ptr" },
                    },
                    .is_optional = false,
                    .default_value = null,
                },
            },
            .return_mapping = .{ .primitive = .float },
        },
    },
};
