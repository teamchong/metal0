/// Cleanup and deinitialization for NativeCodegen
/// With arena allocator, cleanup is simplified - arena.deinit() frees all internal strings at once
const std = @import("std");
const NativeCodegen = @import("core.zig").NativeCodegen;

/// Clean up all resources owned by NativeCodegen
/// Arena allocator handles all string key/value cleanup automatically
pub fn deinit(self: *NativeCodegen) void {
    // Output buffer uses backing allocator (we return this data to caller)
    self.output.deinit(self.allocator);

    // Clean up sub-components (they have their own allocators)
    self.symbol_table.deinit();
    self.allocator.destroy(self.symbol_table);
    self.class_registry.deinit();
    self.allocator.destroy(self.class_registry);
    self.import_registry.deinit();
    self.allocator.destroy(self.import_registry);
    self.module_registry.modules.deinit();
    self.allocator.destroy(self.module_registry);

    // Lambda functions ArrayList (items are arena-allocated, but ArrayList struct needs cleanup)
    self.lambda_functions.deinit(self.allocator);

    // Deinit all HashMaps (releases map structure, keys freed by arena)
    self.closure_vars.deinit();
    self.hoisted_dynamic_closures.deinit();
    self.void_closure_vars.deinit();
    self.callable_vars.deinit();
    self.error_callable_vars.deinit();
    self.recursive_closure_vars.deinit();
    self.closure_factories.deinit();
    self.pending_closure_types.deinit();
    self.deferred_closure_instantiations.deinit();
    self.closure_returning_methods.deinit();
    self.lambda_vars.deinit();
    self.var_renames.deinit();
    self.hoisted_vars.deinit();
    self.pending_discards.deinit();
    self.array_vars.deinit();
    self.array_slice_vars.deinit();
    self.closure_list_vars.deinit();
    self.lazy_class_attrs.deinit();
    self.arraylist_vars.deinit();
    self.arraylist_aliases.deinit();
    self.class_instance_aliases.deinit();
    self.dict_vars.deinit();
    self.anytype_params.deinit();
    self.mutable_classes.deinit();
    self.error_init_classes.deinit();
    self.test_factories.deinit();
    self.from_import_needs_allocator.deinit();
    self.functions_needing_allocator.deinit();
    self.async_functions.deinit();
    self.async_function_defs.deinit();
    self.vararg_functions.deinit();
    self.vararg_params.deinit();
    self.vararg_methods.deinit();
    self.kwarg_functions.deinit();
    self.kwarg_params.deinit();
    self.dict_builtin_vars.deinit();
    self.function_signatures.deinit();
    self.imported_modules.deinit();
    self.import_aliases.deinit();
    self.module_alias_map.deinit();
    self.module_level_from_imports.deinit();
    self.comptime_evals.deinit();
    self.interned_strings.deinit();
    self.func_local_mutations.deinit();
    self.func_local_aug_assigns.deinit();
    self.func_local_uses.deinit();
    self.global_vars.deinit();
    self.module_level_funcs.deinit();
    self.module_level_vars.deinit();
    self.func_local_vars.deinit();
    self.nested_class_captures.deinit();
    self.mutated_captures.deinit();
    self.nested_class_instances.deinit();
    self.nested_class_names.deinit();
    self.hoisted_local_classes.deinit();
    self.bigint_vars.deinit();
    self.nested_class_bases.deinit();
    self.nested_class_defs.deinit();
    self.nested_class_method_needs_alloc.deinit();
    self.nested_class_zig_refs.deinit();
    self.class_type_attrs.deinit();
    self.skipped_modules.deinit();
    self.skipped_functions.deinit();
    self.c_extension_modules.deinit();
    self.local_var_types.deinit();
    self.local_from_imports.deinit();
    self.loop_capture_vars.deinit();
    self.callable_global_vars.deinit();
    self.import_module_vars.deinit();
    self.csv_iterators.deinit();
    self.type_alias_vars.deinit();
    self.hoisted_branch_funcs.deinit();
    self.forward_declared_vars.deinit();
    self.generic_type_params.deinit();
    self.generic_classes.deinit();
    self.ctypes_functions.deinit();

    // ArrayLists (structure cleanup, items arena-allocated)
    self.unittest_classes.deinit(self.allocator);
    self.decorated_functions.deinit(self.allocator);
    self.from_imports.deinit(self.allocator);
    self.c_libraries.deinit(self.allocator);
    self.intern_list.deinit(self.allocator);

    // Optional fields
    if (self.token_lines) |*tl| tl.deinit();
    if (self.call_graph) |*cg| cg.deinit();

    // Builder (Phase 1 migration - lazily initialized)
    if (self.builder) |b| {
        b.deinit();
        self.allocator.destroy(b);
    }

    // Free arena (frees ALL internal strings at once - O(1) cleanup)
    const backing = self.allocator;
    self.arena.deinit();
    backing.destroy(self.arena);

    // Finally destroy self
    backing.destroy(self);
}

/// Clear global vars (call when exiting function scope)
/// With arena, we just clear the map - keys are freed when arena is freed
pub fn clearGlobalVars(self: *NativeCodegen) void {
    self.global_vars.clearRetainingCapacity();
}

/// Clear deferred closure instantiations (call at function boundaries)
/// This prevents closures from one function leaking into another function's scope
/// With arena, we just clear the map - keys are freed when arena is freed
pub fn clearDeferredClosureInstantiations(self: *NativeCodegen) void {
    // Clear the ArrayLists inside (they still need to release their structure)
    var iter = self.deferred_closure_instantiations.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.arena.allocator());
    }
    self.deferred_closure_instantiations.clearRetainingCapacity();
}
