"""
Method registry for Python runtime methods.

This module defines metadata for all supported Python methods and provides
a clean interface for code generation.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class ArgType(Enum):
    """Argument type for method calls"""
    ANY = "any"  # Accept any type (primitive or PyObject)
    PYOBJECT = "pyobject"  # Requires PyObject
    PRIMITIVE = "primitive"  # Requires primitive (int, str literal)


class ReturnType(Enum):
    """Return type from method calls"""
    PYOBJECT = "pyobject"  # Returns !*PyObject (error union, needs try)
    PYOBJECT_DIRECT = "pyobject_direct"  # Returns *PyObject (no error union, no try)
    PRIMITIVE_INT = "int"  # Returns i64
    VOID = "void"  # Returns nothing (like append)


@dataclass
class MethodInfo:
    """Metadata for a Python method"""
    name: str  # Method name (e.g., "upper", "append")
    runtime_type: str  # Runtime type (e.g., "PyString", "PyList")
    runtime_fn: str  # Runtime function name (e.g., "upper", "append")
    needs_allocator: bool  # Whether to pass allocator argument
    return_type: ReturnType  # What the method returns
    arg_types: list[ArgType]  # Expected argument types
    wrap_primitive_args: bool = False  # Wrap primitives in PyInt
    is_statement: bool = False  # True for methods like append() that don't return values

    def generate_call(
        self,
        obj_code: str,
        args: list[tuple[str, bool]],
        allocator: str = "allocator"
    ) -> tuple[str, bool]:
        """
        Generate Zig code for this method call.

        Args:
            obj_code: Code for the object being called on
            args: List of (arg_code, needs_try) tuples
            allocator: Allocator variable name

        Returns:
            (generated_code, needs_try) tuple
        """
        # Build argument list
        # For string methods, allocator comes first: (allocator, obj)
        # For list methods, obj comes first: (obj, [allocator])
        arg_list = []

        if self.runtime_type == "PyString" and self.needs_allocator:
            # String methods: allocator, obj, ...args
            arg_list.append(allocator)
            arg_list.append(obj_code)
        else:
            # List/Dict methods: obj, [allocator], ...args
            arg_list.append(obj_code)
            if self.needs_allocator:
                arg_list.append(allocator)

        # Add method arguments
        for i, (arg_code, arg_try) in enumerate(args):
            if i < len(self.arg_types):
                arg_type = self.arg_types[i]

                # If we need to wrap primitives and this is a primitive
                if self.wrap_primitive_args and not arg_try:
                    # This will be handled specially - return a marker
                    arg_list.append(f"__WRAP_PRIMITIVE__{arg_code}")
                elif arg_try:
                    # Argument needs try - wrap it
                    arg_list.append(f"try {arg_code}")
                else:
                    arg_list.append(arg_code)
            else:
                # Handle generic arguments
                if arg_try:
                    arg_list.append(f"try {arg_code}")
                else:
                    arg_list.append(arg_code)

        args_str = ", ".join(arg_list)
        call_code = f"runtime.{self.runtime_type}.{self.runtime_fn}({args_str})"

        # Determine if this needs try
        # Only PYOBJECT (error unions) need try, not PYOBJECT_DIRECT
        needs_try = self.return_type == ReturnType.PYOBJECT

        return (call_code, needs_try)


# Method Registry
METHOD_REGISTRY: dict[str, MethodInfo] = {
    # String methods
    "upper": MethodInfo(
        name="upper",
        runtime_type="PyString",
        runtime_fn="upper",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[],
    ),
    "lower": MethodInfo(
        name="lower",
        runtime_type="PyString",
        runtime_fn="lower",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[],
    ),
    "split": MethodInfo(
        name="split",
        runtime_type="PyString",
        runtime_fn="split",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[ArgType.PYOBJECT],  # Separator string
    ),
    "strip": MethodInfo(
        name="strip",
        runtime_type="PyString",
        runtime_fn="strip",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[],
    ),
    "replace": MethodInfo(
        name="replace",
        runtime_type="PyString",
        runtime_fn="replace",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[ArgType.PYOBJECT, ArgType.PYOBJECT],  # old, new
    ),
    "startswith": MethodInfo(
        name="startswith",
        runtime_type="PyString",
        runtime_fn="startswith",
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,  # Returns bool, but we use int
        arg_types=[ArgType.PYOBJECT],
    ),
    "endswith": MethodInfo(
        name="endswith",
        runtime_type="PyString",
        runtime_fn="endswith",
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,  # Returns bool, but we use int
        arg_types=[ArgType.PYOBJECT],
    ),
    "find": MethodInfo(
        name="find",
        runtime_type="PyString",
        runtime_fn="find",
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,
        arg_types=[ArgType.PYOBJECT],
    ),
    "count": MethodInfo(
        name="count",
        runtime_type="PyString",
        runtime_fn="count_substr",  # Different name to avoid conflict with list.count
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,
        arg_types=[ArgType.PYOBJECT],
    ),

    # List methods
    "append": MethodInfo(
        name="append",
        runtime_type="PyList",
        runtime_fn="append",
        needs_allocator=False,
        return_type=ReturnType.VOID,
        arg_types=[ArgType.ANY],
        wrap_primitive_args=True,
        is_statement=True,
    ),
    "pop": MethodInfo(
        name="pop",
        runtime_type="PyList",
        runtime_fn="pop",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT_DIRECT,  # Returns *PyObject, no error union
        arg_types=[],
    ),
    "extend": MethodInfo(
        name="extend",
        runtime_type="PyList",
        runtime_fn="extend",
        needs_allocator=False,
        return_type=ReturnType.VOID,
        arg_types=[ArgType.PYOBJECT],  # Another list
        is_statement=True,
    ),
    "remove": MethodInfo(
        name="remove",
        runtime_type="PyList",
        runtime_fn="remove",
        needs_allocator=True,
        return_type=ReturnType.VOID,
        arg_types=[ArgType.ANY],
        wrap_primitive_args=True,
        is_statement=True,
    ),
    "reverse": MethodInfo(
        name="reverse",
        runtime_type="PyList",
        runtime_fn="reverse",
        needs_allocator=False,
        return_type=ReturnType.VOID,
        arg_types=[],
        is_statement=True,
    ),
    "count": MethodInfo(
        name="count",
        runtime_type="PyList",
        runtime_fn="count",
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,
        arg_types=[ArgType.ANY],
        wrap_primitive_args=True,
    ),
    "index": MethodInfo(
        name="index",
        runtime_type="PyList",
        runtime_fn="index",
        needs_allocator=False,
        return_type=ReturnType.PRIMITIVE_INT,
        arg_types=[ArgType.ANY],
        wrap_primitive_args=True,
    ),
    "insert": MethodInfo(
        name="insert",
        runtime_type="PyList",
        runtime_fn="insert",
        needs_allocator=True,
        return_type=ReturnType.VOID,
        arg_types=[ArgType.PRIMITIVE, ArgType.ANY],  # index, value
        wrap_primitive_args=True,
        is_statement=True,
    ),
    "clear": MethodInfo(
        name="clear",
        runtime_type="PyList",
        runtime_fn="clear",
        needs_allocator=True,
        return_type=ReturnType.VOID,
        arg_types=[],
        is_statement=True,
    ),

    # Dict methods
    "keys": MethodInfo(
        name="keys",
        runtime_type="PyDict",
        runtime_fn="keys",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[],
    ),
    "values": MethodInfo(
        name="values",
        runtime_type="PyDict",
        runtime_fn="values",
        needs_allocator=True,
        return_type=ReturnType.PYOBJECT,
        arg_types=[],
    ),
}


def get_method_info(method_name: str, obj_type: Optional[str] = None) -> Optional[MethodInfo]:
    """
    Get method metadata by name and optionally by object type.

    For methods like 'count' that exist on multiple types, obj_type helps disambiguate.
    obj_type can be "string", "list", etc. from var_types tracking.
    """
    method_info = METHOD_REGISTRY.get(method_name)

    # If no type hint or method not in registry, return what we have
    if not obj_type or not method_info:
        return method_info

    # For "count", check if we need the list or string version
    if method_name == "count":
        if obj_type == "list":
            # Look for PyList.count in registry
            for info in METHOD_REGISTRY.values():
                if info.name == "count" and info.runtime_type == "PyList":
                    return info
        elif obj_type == "string":
            # Look for PyString.count_substr in registry
            for info in METHOD_REGISTRY.values():
                if info.name == "count" and info.runtime_type == "PyString":
                    return info

    return method_info


def register_method(method_info: MethodInfo) -> None:
    """Register a new method"""
    METHOD_REGISTRY[method_info.name] = method_info
