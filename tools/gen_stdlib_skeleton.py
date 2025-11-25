#!/usr/bin/env python3
"""
Generate Zig skeleton for Python stdlib module.

Usage:
    python tools/gen_stdlib_skeleton.py re > packages/runtime/src/stdlib/re.zig
    python tools/gen_stdlib_skeleton.py os > packages/runtime/src/stdlib/os.zig
    python tools/gen_stdlib_skeleton.py --all  # Generate all common modules
    python tools/gen_stdlib_skeleton.py --list # List available modules
"""

import inspect
import sys
import os as os_module
from typing import get_type_hints

# Python type -> Zig type mapping
TYPE_MAP = {
    "str": "[]const u8",
    "int": "i64",
    "float": "f64",
    "bool": "bool",
    "bytes": "[]const u8",
    "list": "*runtime.PyObject",  # Generic list
    "dict": "*runtime.PyObject",  # Generic dict
    "None": "void",
    "NoneType": "void",
    "Any": "*runtime.PyObject",
    "object": "*runtime.PyObject",
    "Pattern": "*runtime.PyObject",
    "Match": "*runtime.PyObject",
}

def python_type_to_zig(annotation) -> str:
    """Convert Python type annotation to Zig type."""
    if annotation is inspect.Parameter.empty:
        return "*runtime.PyObject"  # Default for untyped

    type_str = str(annotation).replace("typing.", "").replace("<class '", "").replace("'>", "")

    # Handle Optional[X] -> ?X
    if "Optional" in type_str or "| None" in type_str:
        inner = type_str.replace("Optional[", "").replace("]", "").replace(" | None", "")
        zig_type = TYPE_MAP.get(inner, "*runtime.PyObject")
        return f"?{zig_type}"

    return TYPE_MAP.get(type_str, "*runtime.PyObject")

def generate_zig_function(name: str, func) -> str:
    """Generate Zig function skeleton from Python function."""
    try:
        sig = inspect.signature(func)
    except (ValueError, TypeError):
        # Can't get signature, generate generic
        return f"""
/// {name}() - TODO: implement
pub fn {name}(args: []*runtime.PyObject) *runtime.PyObject {{
    _ = args;
    @panic("TODO: implement {name}");
}}
"""

    params = []
    param_names = []

    for pname, param in sig.parameters.items():
        if pname == "self":
            continue
        zig_type = python_type_to_zig(param.annotation)

        # Handle default values
        if param.default is not inspect.Parameter.empty:
            # Optional parameter
            params.append(f"{pname}: ?{zig_type}")
        else:
            params.append(f"{pname}: {zig_type}")
        param_names.append(pname)

    # Return type
    try:
        hints = get_type_hints(func)
        return_type = python_type_to_zig(hints.get("return", inspect.Parameter.empty))
    except:
        return_type = "*runtime.PyObject"

    params_str = ", ".join(params) if params else ""
    unused = "\n".join([f"    _ = {p};" for p in param_names]) if param_names else ""

    return f"""
/// {name}({', '.join(param_names)}) -> {return_type}
pub fn {name}({params_str}) {return_type} {{
{unused}
    @panic("TODO: implement {name}");
}}
"""

def generate_dispatch_entry(module_name: str, func_name: str) -> str:
    """Generate dispatch table entry."""
    return f'    "{module_name}.{func_name}" => return stdlib.{module_name}.{func_name}(args),'

def generate_codegen_handler(module_name: str, func_name: str, func) -> str:
    """Generate codegen handler function (generates Zig code at compile time)."""
    try:
        sig = inspect.signature(func)
        params = [p for p in sig.parameters.keys() if p != 'self']
    except:
        params = []

    param_count = len(params)

    return f"""
/// gen{func_name.title().replace('_', '')}() - generates code for {module_name}.{func_name}()
pub fn gen{func_name.title().replace('_', '')}(self: *NativeCodegen, args: []ast.Node) CodegenError!void {{
    // Expected args: {params if params else 'none'}
    if (args.len != {param_count}) {{
        return CodegenError.TypeError;
    }}
    _ = self;
    _ = args;
    @panic("TODO: implement {module_name}.{func_name} codegen");
}}
"""

def get_existing_functions(module_name: str) -> set:
    """Find already-implemented functions by scanning existing .zig file."""
    import glob
    import re as re_mod

    # Look for existing module file
    patterns = [
        f"src/codegen/native/{module_name}.zig",
        f"src/codegen/native/{module_name}/*.zig",
        f"packages/runtime/src/{module_name}.zig",
    ]

    existing = set()
    mod_title = module_name.title()  # "re" -> "Re", "json" -> "Json"

    for pattern in patterns:
        for filepath in glob.glob(pattern):
            try:
                with open(filepath, 'r') as f:
                    content = f.read()
                    # Find "pub fn genXxx" or "pub fn genModXxx" patterns
                    for match in re_mod.finditer(r'pub fn gen(\w+)\s*\(', content):
                        func_name = match.group(1).lower()
                        # Remove module prefix if present (genReSearch -> search)
                        if func_name.startswith(module_name.lower()):
                            func_name = func_name[len(module_name):]
                        existing.add(func_name)
                    # Find function names in dispatch maps: .{ "search", ...
                    for match in re_mod.finditer(r'\.\{\s*"(\w+)"', content):
                        existing.add(match.group(1).lower())
            except:
                pass

    return existing

def generate_module_skeleton(module_name: str, only_missing: bool = False) -> str:
    """Generate complete Zig skeleton for a Python module."""
    try:
        module = __import__(module_name)
    except ImportError:
        print(f"Error: Cannot import module '{module_name}'", file=sys.stderr)
        sys.exit(1)

    # Get existing implementations if --missing flag
    existing = get_existing_functions(module_name) if only_missing else set()

    # Get all public callables
    funcs = [
        (name, obj) for name, obj in inspect.getmembers(module)
        if callable(obj) and not name.startswith("_")
    ]

    # Filter out existing
    if existing:
        original_count = len(funcs)
        funcs = [(name, obj) for name, obj in funcs if name.lower() not in existing]
        skipped = original_count - len(funcs)
        print(f"// Skipped {skipped} already-implemented functions", file=sys.stderr)

    mod_var = f"{module_name}_mod" if module_name in ['re', 'os', 'async'] else module_name

    output = f"""/// Auto-generated Zig skeleton for Python '{module_name}' module
/// Generated by: python tools/gen_stdlib_skeleton.py {module_name}{' --missing' if only_missing else ''}
///
/// Location: src/codegen/native/{module_name}.zig
/// TODO: Implement each codegen handler
/// Functions to implement: {len(funcs)}

const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// =============================================================================
// {module_name.upper()} MODULE CODEGEN HANDLERS ({len(funcs)} functions)
// =============================================================================
"""

    for name, func in sorted(funcs, key=lambda x: x[0]):
        output += generate_codegen_handler(module_name, name, func)

    # Generate StaticStringMap for module_functions.zig
    output += f"""
// =============================================================================
// ADD TO module_functions.zig
// =============================================================================
// 1. Add import at top:
//    const {mod_var} = @import("../{module_name}.zig");
//
// 2. Add FuncMap:
//    const {module_name.title()}Funcs = FuncMap.initComptime(.{{
"""
    for name, _ in sorted(funcs, key=lambda x: x[0]):
        handler_name = f"gen{name.title().replace('_', '')}"
        output += f'//        .{{ "{name}", {mod_var}.{handler_name} }},\n'

    output += f"""//    }});
//
// 3. Add to dispatchModuleFunction switch:
//    "{module_name}" => return dispatch({module_name.title()}Funcs, func_name, self, args),
"""

    return output

def main():
    if len(sys.argv) < 2:
        print("Usage: python tools/gen_stdlib_skeleton.py <module_name> [--missing]", file=sys.stderr)
        print("Example: python tools/gen_stdlib_skeleton.py re", file=sys.stderr)
        print("         python tools/gen_stdlib_skeleton.py re --missing  # Skip already implemented", file=sys.stderr)
        sys.exit(1)

    module_name = sys.argv[1]
    only_missing = "--missing" in sys.argv
    print(generate_module_skeleton(module_name, only_missing))

if __name__ == "__main__":
    main()
