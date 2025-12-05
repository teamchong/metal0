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

    // Clean up void closure tracking
    freeMapKeys(self.allocator, &self.void_closure_vars);
    self.void_closure_vars.deinit();

    // Clean up callable vars tracking (for loop variables over PyCallable lists)
    freeMapKeys(self.allocator, &self.callable_vars);
    self.callable_vars.deinit();

    // Clean up error callable vars tracking
    freeMapKeys(self.allocator, &self.error_callable_vars);
    self.error_callable_vars.deinit();

    freeMapKeys(self.allocator, &self.recursive_closure_vars);
    self.recursive_closure_vars.deinit();

    freeMapKeys(self.allocator, &self.closure_factories);
    self.closure_factories.deinit();

    freeStringMapValues(self.allocator, &self.pending_closure_types);
    freeMapKeys(self.allocator, &self.pending_closure_types);
    self.pending_closure_types.deinit();

    // Clean up deferred closure instantiations
    var dci_iter = self.deferred_closure_instantiations.iterator();
    while (dci_iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.deferred_closure_instantiations.deinit();

    freeMapKeys(self.allocator, &self.closure_returning_methods);
    self.closure_returning_methods.deinit();

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

    // Clean up dict vars tracking
    freeMapKeys(self.allocator, &self.dict_vars);
    self.dict_vars.deinit();

    // Clean up anytype params tracking
    self.anytype_params.deinit();

    // Clean up decorated functions tracking
    self.decorated_functions.deinit(self.allocator);

    // Clean up unittest classes tracking
    // Note: class_name is an AST slice (not owned), only test_methods is allocated
    for (self.unittest_classes.items) |class_info| {
        self.allocator.free(class_info.test_methods);
    }
    self.unittest_classes.deinit(self.allocator);

    // Clean up test_factories tracking
    for (self.test_factories.values()) |factory_info| {
        for (factory_info.returned_classes) |class_info| {
            self.allocator.free(class_info.test_methods);
        }
        self.allocator.free(factory_info.returned_classes);
    }
    freeMapKeys(self.allocator, &self.test_factories);
    self.test_factories.deinit();

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

    // Clean up import_aliases tracking
    freeMapKeys(self.allocator, &self.import_aliases);
    self.import_aliases.deinit();

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

    // Clean up func_local_uses tracking
    // Note: Keys are references to AST data, not owned - don't free
    self.func_local_uses.deinit();

    // Clean up func_local_vars tracking
    // Note: Keys are references to AST data, not owned - don't free
    self.func_local_vars.deinit();

    // Clean up nested_class_captures tracking
    // Free the allocated slices (lists of captured vars), keys are AST refs
    var iter = self.nested_class_captures.iterator();
    while (iter.next()) |entry| {
        self.allocator.free(entry.value_ptr.*);
    }
    self.nested_class_captures.deinit();

    // Clean up mutated_captures tracking
    self.mutated_captures.deinit();

    // Clean up nested_class_instances tracking (keys are AST refs, values are AST refs)
    self.nested_class_instances.deinit();

    // Clean up nested_class_bases tracking (keys/values are AST refs)
    self.nested_class_bases.deinit();

    // Clean up nested_class_defs tracking (keys are AST refs)
    self.nested_class_defs.deinit();

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

    // Clean up local_from_imports tracking
    // Note: Keys and values are references to AST data, not owned
    self.local_from_imports.deinit();

    // Clean up callable_global_vars tracking
    freeMapKeys(self.allocator, &self.callable_global_vars);
    self.callable_global_vars.deinit();

    // Clean up call_graph if it was built
    if (self.call_graph) |*cg| {
        cg.deinit();
    }

    // Clean up ctypes_functions tracking
    // Note: Keys are allocated, values have allocated argtypes arrays
    for (self.ctypes_functions.keys()) |key| {
        self.allocator.free(key);
    }
    for (self.ctypes_functions.values()) |info| {
        self.allocator.free(info.library_var);
        self.allocator.free(info.func_name);
        self.allocator.free(info.restype);
        for (info.argtypes) |at| {
            self.allocator.free(at);
        }
        self.allocator.free(info.argtypes);
    }
    self.ctypes_functions.deinit();

    // Clean up token_lines hashmap (if it was built lazily)
    if (self.token_lines) |*tl| {
        tl.deinit();
    }

    self.allocator.destroy(self);
}

/// Helper: free all keys in a hashmap
pub fn freeMapKeys(allocator: std.mem.Allocator, map: anytype) void {
    for (map.keys()) |key| {
        allocator.free(key);
    }
}

/// Helper: free all values in a string->string hashmap
fn freeStringMapValues(allocator: std.mem.Allocator, map: anytype) void {
    for (map.values()) |value| {
        allocator.free(value);
    }
}

/// Clear global vars (call when exiting function scope)
pub fn clearGlobalVars(self: *NativeCodegen) void {
    for (self.global_vars.keys()) |key| {
        self.allocator.free(key);
    }
    self.global_vars.clearRetainingCapacity();
}

/// Clear deferred closure instantiations (call at function boundaries)
/// This prevents closures from one function leaking into another function's scope
pub fn clearDeferredClosureInstantiations(self: *NativeCodegen) void {
    var iter = self.deferred_closure_instantiations.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.deferred_closure_instantiations.clearRetainingCapacity();
}
