//! CPython source: Lib/weakref.py
//!
//! Provides tools for creating weak references to objects.
//!
//! Mirrors: CPython Lib/weakref.py

// Re-export all submodules
pub const types = @import("weakref/types.zig");
pub const weakdict = @import("weakref/weakdict.zig");
pub const weakset = @import("weakref/weakset.zig");
pub const proxy = @import("weakref/proxy.zig");
pub const finalize = @import("weakref/finalize.zig");
pub const helpers = @import("weakref/helpers.zig");

// Re-export core types at top level
pub const WeakRef = types.WeakRef;
pub const WeakKeyDictionary = weakdict.WeakKeyDictionary;
pub const WeakValueDictionary = weakdict.WeakValueDictionary;
pub const WeakSet = weakset.WeakSet;
pub const Finalizer = finalize.Finalizer;
pub const Proxy = proxy.Proxy;
pub const CallableProxy = proxy.CallableProxy;

// Re-export helper functions
pub const ref = helpers.ref;
pub const proxy_fn = helpers.proxy;
pub const getweakrefcount = helpers.getweakrefcount;
pub const getweakrefs = helpers.getweakrefs;

// Backwards compatibility aliases
pub const ReferenceType = WeakRef;
pub const ProxyType = Proxy;
