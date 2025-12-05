/// WasmEdge Zig Bindings
///
/// Provides Zig-friendly interface to WasmEdge C API.
/// Link with: -lwasmedge
///
/// Usage:
/// ```zig
/// const wasmedge = @import("wasmedge");
///
/// var vm = try wasmedge.VM.create();
/// defer vm.destroy();
///
/// const result = try vm.runFromFile("module.wasm", "add", &.{
///     wasmedge.Value.i32(1),
///     wasmedge.Value.i32(2),
/// });
/// ```
const std = @import("std");

// C API bindings (from wasmedge.h)
const c = @cImport({
    @cInclude("wasmedge/wasmedge.h");
});

/// WasmEdge error
pub const Error = error{
    ConfigCreateFailed,
    VMCreateFailed,
    LoadFailed,
    ValidateFailed,
    InstantiateFailed,
    ExecuteFailed,
    CompileFailed,
    OutOfMemory,
};

/// WasmEdge value (i32, i64, f32, f64, etc.)
pub const Value = struct {
    inner: c.WasmEdge_Value,

    pub fn i32(v: i32) Value {
        return .{ .inner = c.WasmEdge_ValueGenI32(v) };
    }

    pub fn i64(v: i64) Value {
        return .{ .inner = c.WasmEdge_ValueGenI64(v) };
    }

    pub fn f32(v: f32) Value {
        return .{ .inner = c.WasmEdge_ValueGenF32(v) };
    }

    pub fn f64(v: f64) Value {
        return .{ .inner = c.WasmEdge_ValueGenF64(v) };
    }

    pub fn getI32(self: Value) i32 {
        return c.WasmEdge_ValueGetI32(self.inner);
    }

    pub fn getI64(self: Value) i64 {
        return c.WasmEdge_ValueGetI64(self.inner);
    }

    pub fn getF32(self: Value) f32 {
        return c.WasmEdge_ValueGetF32(self.inner);
    }

    pub fn getF64(self: Value) f64 {
        return c.WasmEdge_ValueGetF64(self.inner);
    }
};

/// WasmEdge Configuration
pub const Config = struct {
    inner: *c.WasmEdge_ConfigureContext,

    pub fn create() Error!Config {
        const ctx = c.WasmEdge_ConfigureCreate();
        if (ctx == null) return Error.ConfigCreateFailed;
        return .{ .inner = ctx.? };
    }

    pub fn destroy(self: *Config) void {
        c.WasmEdge_ConfigureDelete(self.inner);
    }

    /// Enable WASI support
    pub fn enableWASI(self: *Config) void {
        c.WasmEdge_ConfigureAddHostRegistration(
            self.inner,
            c.WasmEdge_HostRegistration_Wasi,
        );
    }

    /// Enable reference types proposal
    pub fn enableRefTypes(self: *Config) void {
        c.WasmEdge_ConfigureAddProposal(
            self.inner,
            c.WasmEdge_Proposal_ReferenceTypes,
        );
    }

    /// Enable SIMD proposal
    pub fn enableSIMD(self: *Config) void {
        c.WasmEdge_ConfigureAddProposal(
            self.inner,
            c.WasmEdge_Proposal_SIMD,
        );
    }
};

/// WasmEdge Virtual Machine
pub const VM = struct {
    inner: *c.WasmEdge_VMContext,

    /// Create VM with default configuration
    pub fn create() Error!VM {
        return createWithConfig(null);
    }

    /// Create VM with custom configuration
    pub fn createWithConfig(config: ?*Config) Error!VM {
        const cfg = if (config) |c| c.inner else null;
        const ctx = c.WasmEdge_VMCreate(cfg, null);
        if (ctx == null) return Error.VMCreateFailed;
        return .{ .inner = ctx.? };
    }

    /// Destroy VM and free resources
    pub fn destroy(self: *VM) void {
        c.WasmEdge_VMDelete(self.inner);
    }

    /// Run WASM function from file
    pub fn runFromFile(
        self: *VM,
        path: [:0]const u8,
        func_name: [:0]const u8,
        params: []const Value,
        results: []Value,
    ) Error!void {
        const func_str = c.WasmEdge_StringCreateByCString(func_name.ptr);
        defer c.WasmEdge_StringDelete(func_str);

        // Convert params to C array
        var c_params: [16]c.WasmEdge_Value = undefined;
        for (params, 0..) |p, i| {
            c_params[i] = p.inner;
        }

        var c_results: [16]c.WasmEdge_Value = undefined;

        const res = c.WasmEdge_VMRunWasmFromFile(
            self.inner,
            path.ptr,
            func_str,
            &c_params,
            @intCast(params.len),
            &c_results,
            @intCast(results.len),
        );

        if (!c.WasmEdge_ResultOK(res)) {
            return Error.ExecuteFailed;
        }

        // Convert results back
        for (results, 0..) |*r, i| {
            r.inner = c_results[i];
        }
    }

    /// Run WASM function from buffer
    pub fn runFromBuffer(
        self: *VM,
        wasm_bytes: []const u8,
        func_name: [:0]const u8,
        params: []const Value,
        results: []Value,
    ) Error!void {
        const func_str = c.WasmEdge_StringCreateByCString(func_name.ptr);
        defer c.WasmEdge_StringDelete(func_str);

        var c_params: [16]c.WasmEdge_Value = undefined;
        for (params, 0..) |p, i| {
            c_params[i] = p.inner;
        }

        var c_results: [16]c.WasmEdge_Value = undefined;

        const res = c.WasmEdge_VMRunWasmFromBuffer(
            self.inner,
            wasm_bytes.ptr,
            @intCast(wasm_bytes.len),
            func_str,
            &c_params,
            @intCast(params.len),
            &c_results,
            @intCast(results.len),
        );

        if (!c.WasmEdge_ResultOK(res)) {
            return Error.ExecuteFailed;
        }

        for (results, 0..) |*r, i| {
            r.inner = c_results[i];
        }
    }

    /// Load WASM module from file (separate step)
    pub fn loadFromFile(self: *VM, path: [:0]const u8) Error!void {
        const res = c.WasmEdge_VMLoadWasmFromFile(self.inner, path.ptr);
        if (!c.WasmEdge_ResultOK(res)) return Error.LoadFailed;
    }

    /// Load WASM module from buffer
    pub fn loadFromBuffer(self: *VM, wasm_bytes: []const u8) Error!void {
        const res = c.WasmEdge_VMLoadWasmFromBuffer(
            self.inner,
            wasm_bytes.ptr,
            @intCast(wasm_bytes.len),
        );
        if (!c.WasmEdge_ResultOK(res)) return Error.LoadFailed;
    }

    /// Validate loaded module
    pub fn validate(self: *VM) Error!void {
        const res = c.WasmEdge_VMValidate(self.inner);
        if (!c.WasmEdge_ResultOK(res)) return Error.ValidateFailed;
    }

    /// Instantiate validated module
    pub fn instantiate(self: *VM) Error!void {
        const res = c.WasmEdge_VMInstantiate(self.inner);
        if (!c.WasmEdge_ResultOK(res)) return Error.InstantiateFailed;
    }

    /// Execute function on instantiated module
    pub fn execute(
        self: *VM,
        func_name: [:0]const u8,
        params: []const Value,
        results: []Value,
    ) Error!void {
        const func_str = c.WasmEdge_StringCreateByCString(func_name.ptr);
        defer c.WasmEdge_StringDelete(func_str);

        var c_params: [16]c.WasmEdge_Value = undefined;
        for (params, 0..) |p, i| {
            c_params[i] = p.inner;
        }

        var c_results: [16]c.WasmEdge_Value = undefined;

        const res = c.WasmEdge_VMExecute(
            self.inner,
            func_str,
            &c_params,
            @intCast(params.len),
            &c_results,
            @intCast(results.len),
        );

        if (!c.WasmEdge_ResultOK(res)) {
            return Error.ExecuteFailed;
        }

        for (results, 0..) |*r, i| {
            r.inner = c_results[i];
        }
    }

    /// Get WASI module for configuration
    pub fn getWasiModule(self: *VM) ?*c.WasmEdge_ModuleInstanceContext {
        return c.WasmEdge_VMGetImportModuleContext(
            self.inner,
            c.WasmEdge_HostRegistration_Wasi,
        );
    }
};

/// WasmEdge AOT Compiler
pub const Compiler = struct {
    inner: *c.WasmEdge_CompilerContext,

    pub fn create(config: ?*Config) Error!Compiler {
        const cfg = if (config) |c| c.inner else null;
        const ctx = c.WasmEdge_CompilerCreate(cfg);
        if (ctx == null) return Error.ConfigCreateFailed;
        return .{ .inner = ctx.? };
    }

    pub fn destroy(self: *Compiler) void {
        c.WasmEdge_CompilerDelete(self.inner);
    }

    /// Compile WASM to native
    pub fn compile(
        self: *Compiler,
        input_path: [:0]const u8,
        output_path: [:0]const u8,
    ) Error!void {
        const res = c.WasmEdge_CompilerCompile(
            self.inner,
            input_path.ptr,
            output_path.ptr,
        );
        if (!c.WasmEdge_ResultOK(res)) return Error.CompileFailed;
    }
};

/// Initialize WASI with args and environment
pub fn initWASI(
    wasi_module: *c.WasmEdge_ModuleInstanceContext,
    args: []const [:0]const u8,
    envs: []const [:0]const u8,
    preopens: []const [:0]const u8,
) void {
    var c_args: [64][*c]const u8 = undefined;
    for (args, 0..) |a, i| {
        c_args[i] = a.ptr;
    }

    var c_envs: [64][*c]const u8 = undefined;
    for (envs, 0..) |e, i| {
        c_envs[i] = e.ptr;
    }

    var c_preopens: [64][*c]const u8 = undefined;
    for (preopens, 0..) |p, i| {
        c_preopens[i] = p.ptr;
    }

    c.WasmEdge_ModuleInstanceInitWASI(
        wasi_module,
        &c_args,
        @intCast(args.len),
        &c_envs,
        @intCast(envs.len),
        &c_preopens,
        @intCast(preopens.len),
    );
}

/// Get WASI exit code after execution
pub fn getWASIExitCode(wasi_module: *c.WasmEdge_ModuleInstanceContext) u32 {
    return c.WasmEdge_ModuleInstanceWASIGetExitCode(wasi_module);
}

// Tests
test "create and destroy VM" {
    var vm = try VM.create();
    defer vm.destroy();
}

test "create config with WASI" {
    var config = try Config.create();
    defer config.destroy();
    config.enableWASI();
}
