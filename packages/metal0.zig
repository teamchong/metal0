/// metal0 - Unified module for Python-like imports
///
/// Usage in Zig code (mirrors Python's import style):
///
///   const metal0 = @import("metal0");
///   const runtime = metal0.runtime;      // Python builtins, types
///   const wasmedge = metal0.wasmedge;    // WASM runtime for eval()
///   const collections = metal0.collections;
///
/// Equivalent Python:
///   from metal0 import runtime, wasmedge, collections
///

// Core runtime - Python types, builtins, string methods, etc.
pub const runtime = @import("runtime");

// Collections - list, dict, tuple, set implementations
pub const collections = @import("collections");

// WasmEdge bindings for eval()/exec() in WASM
pub const wasmedge = @import("wasmedge");

// C interop for extension modules (numpy, pandas, etc.)
pub const c_interop = @import("c_interop");

// JSON with SIMD acceleration
pub const json = @import("json");

// HTTP/2 + TLS 1.3
pub const h2 = @import("h2");

// Regex for re module
pub const regex = @import("regex");

// BigInt for arbitrary precision
pub const bigint = @import("bigint");

// BPE tokenizer
pub const tokenizer = @import("tokenizer");

// Package manager
pub const pkg = @import("pkg");

// Data structures
pub const ds = @import("ds");

// Glob pattern matching
pub const glob = @import("glob");
