/// Cleanup and deinitialization for NativeCodegen
const std = @import("std");
const NativeCodegen = @import("core.zig").NativeCodegen;

/// Clean up all resources owned by NativeCodegen
pub fn deinit(self: *NativeCodegen) void {
    self.output.deinit(self.allocator);

    // Clean up symbol table and class registry
    self.symbol_table.deinit();
    self.allocator.destroy(self.symbol_table);
    self.class_registry.deinit();
    self.allocator.destroy(self.class_registry);

    // Clean up lambda functions
    for (self.lambda_functions.items) |lambda_code| {
        self.allocator.free(lambda_code);
    }
    self.lambda_functions.deinit(self.allocator);

    // Clean up closure tracking HashMaps (free keys)
    freeMapKeys(self.allocator, &self.closure_vars);
    self.closure_vars.deinit();

    freeMapKeys(self.allocator, &self.closure_factories);
    self.closure_factories.deinit();

    freeMapKeys(self.allocator, &self.lambda_vars);
    self.lambda_vars.deinit();

    // Clean up variable renames
    self.var_renames.deinit();

    // Clean up array vars tracking
    freeMapKeys(self.allocator, &self.array_vars);
    self.array_vars.deinit();

    // Clean up array slice vars tracking
    freeMapKeys(self.allocator, &self.array_slice_vars);
    self.array_slice_vars.deinit();

    // Clean up arraylist vars tracking
    freeMapKeys(self.allocator, &self.arraylist_vars);
    self.arraylist_vars.deinit();

    // Clean up decorated functions tracking
    self.decorated_functions.deinit(self.allocator);

    // Clean up unittest classes tracking
    // Note: class_name is an AST slice (not owned), only test_methods is allocated
    for (self.unittest_classes.items) |class_info| {
        self.allocator.free(class_info.test_methods);
    }
    self.unittest_classes.deinit(self.allocator);

    // Clean up functions_needing_allocator tracking
    freeMapKeys(self.allocator, &self.functions_needing_allocator);
    self.functions_needing_allocator.deinit();

    // Clean up async_functions tracking
    freeMapKeys(self.allocator, &self.async_functions);
    self.async_functions.deinit();

    // Clean up vararg_functions tracking
    freeMapKeys(self.allocator, &self.vararg_functions);
    self.vararg_functions.deinit();

    // Clean up vararg_params tracking
    freeMapKeys(self.allocator, &self.vararg_params);
    self.vararg_params.deinit();

    // Clean up kwarg_functions tracking
    freeMapKeys(self.allocator, &self.kwarg_functions);
    self.kwarg_functions.deinit();

    // Clean up kwarg_params tracking
    freeMapKeys(self.allocator, &self.kwarg_params);
    self.kwarg_params.deinit();

    // Clean up function_signatures tracking
    freeMapKeys(self.allocator, &self.function_signatures);
    self.function_signatures.deinit();

    // Clean up global_vars tracking
    freeMapKeys(self.allocator, &self.global_vars);
    self.global_vars.deinit();

    // Clean up async_function_defs tracking
    freeMapKeys(self.allocator, &self.async_function_defs);
    self.async_function_defs.deinit();

    // Clean up imported_modules tracking
    freeMapKeys(self.allocator, &self.imported_modules);
    self.imported_modules.deinit();

    // Clean up import registry
    self.import_registry.deinit();
    self.allocator.destroy(self.import_registry);

    // Clean up c_libraries list (strings are not owned, just references)
    self.c_libraries.deinit(self.allocator);

    // Clean up from_imports list (references AST data, not owned)
    self.from_imports.deinit(self.allocator);

    // Clean up from_import_needs_allocator tracking
    // Note: Keys are references to AST data, not owned - don't free
    self.from_import_needs_allocator.deinit();

    // Clean up func_local_mutations tracking
    // Note: Keys are references to AST data, not owned - don't free
    self.func_local_mutations.deinit();

    // Clean up comptime_evals tracking
    freeMapKeys(self.allocator, &self.comptime_evals);
    self.comptime_evals.deinit();

    // Clean up hoisted vars (not owned - AST references)
    self.hoisted_vars.deinit();

    // Clean up mutable_classes (not owned - AST references)
    self.mutable_classes.deinit();

    // Clean up skipped_modules tracking
    freeMapKeys(self.allocator, &self.skipped_modules);
    self.skipped_modules.deinit();

    // Clean up skipped_functions tracking
    freeMapKeys(self.allocator, &self.skipped_functions);
    self.skipped_functions.deinit();

    // Clean up local_var_types tracking
    // Note: Keys are references to AST data or var_name parameters, not owned - don't free
    self.local_var_types.deinit();

    self.allocator.destroy(self);
}

/// Helper: free all keys in a hashmap
fn freeMapKeys(allocator: std.mem.Allocator, map: anytype) void {
    for (map.keys()) |key| {
        allocator.free(key);
    }
}

/// Clear global vars (call when exiting function scope)
pub fn clearGlobalVars(self: *NativeCodegen) void {
    for (self.global_vars.keys()) |key| {
        self.allocator.free(key);
    }
    self.global_vars.clearRetainingCapacity();
}
