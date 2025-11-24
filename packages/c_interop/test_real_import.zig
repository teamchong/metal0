/// Test REAL NumPy import attempt
const std = @import("std");
const cpython = @import("src/cpython_object.zig");
const pyimport = @import("src/cpython_import.zig");
const pyerr = @import("src/cpython_errors.zig");

pub fn main() !void {
    std.debug.print("\n=== Testing Real C Extension Import ===\n\n", .{});

    // Initialize Python subsystem
    std.debug.print("Step 1: Initialize Python...\n", .{});

    // Try to import numpy
    std.debug.print("Step 2: Attempting to import numpy...\n", .{});

    const numpy = pyimport.PyImport_ImportModule("numpy");

    if (numpy == null) {
        std.debug.print("❌ FAILED: numpy import returned null\n", .{});

        // Check for error
        const err = pyerr.PyErr_Occurred();
        if (err != null) {
            std.debug.print("Error occurred during import\n", .{});
            pyerr.PyErr_Print();
        }

        std.debug.print("\n=== RESULT: Import Failed ===\n", .{});
        std.debug.print("This tells us what's missing!\n", .{});
        return;
    }

    std.debug.print("✅ SUCCESS: numpy imported!\n", .{});
    std.debug.print("\n=== RESULT: IT WORKS! ===\n", .{});
}
