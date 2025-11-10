"""
Zyth Compiler - Compiles generated Zig code to binary
"""
import subprocess
import tempfile
from pathlib import Path
from typing import Optional
import shutil
import hashlib
import os


class CompilationError(Exception):
    """Raised when Zig compilation fails"""
    pass


# Cache directory setup
CACHE_DIR = Path(tempfile.gettempdir()) / "zyth_cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)


def get_compiler_files() -> list[Path]:
    """
    Get list of all compiler files that affect compilation.

    Used for timestamp-based cache invalidation.

    Returns:
        List of Path objects for all compiler source files
    """
    base = Path(__file__).parent
    runtime_dir = base.parent.parent / "runtime" / "src"
    return [
        Path(__file__),  # compiler.py
        base / "codegen.py",
        base / "method_registry.py",
        base / "parser.py",
        runtime_dir / "runtime.zig",
        runtime_dir / "pyint.zig",
        runtime_dir / "pylist.zig",
        runtime_dir / "pytuple.zig",
        runtime_dir / "dict.zig",
        runtime_dir / "pystring.zig",
    ]


def is_cache_valid(cache_file: Path, source_file: Path) -> bool:
    """
    Check if cached binary is up-to-date using timestamp comparison.

    Cache is valid if the cached binary is newer than both:
    - The source file
    - All compiler files

    This is the standard approach used by Make, Ninja, and most build systems.

    Args:
        cache_file: Path to cached binary
        source_file: Path to source Python file

    Returns:
        True if cache is valid and can be reused
    """
    if not cache_file.exists():
        return False

    cache_mtime = cache_file.stat().st_mtime

    # Check if source file is newer than cache
    if source_file.stat().st_mtime > cache_mtime:
        return False

    # Check if any compiler file is newer than cache
    for compiler_file in get_compiler_files():
        if compiler_file.exists() and compiler_file.stat().st_mtime > cache_mtime:
            return False

    return True


def compile_zig(zig_code: str, output_path: Optional[str] = None) -> str:
    """
    Compile Zig code to executable binary

    Args:
        zig_code: Zig source code
        output_path: Optional output path for binary

    Returns:
        Path to compiled binary

    Raises:
        CompilationError: If compilation fails
    """
    # Inline runtime if needed
    if '@import("runtime")' in zig_code:
        # Find runtime.zig - try multiple locations
        possible_paths = [
            Path(__file__).parent.parent.parent / "runtime" / "src" / "runtime.zig",  # Development
            Path.cwd() / "packages" / "runtime" / "src" / "runtime.zig",  # Monorepo root
        ]

        runtime_source = None
        for path in possible_paths:
            if path.exists():
                runtime_source = path
                break

        if not runtime_source:
            raise CompilationError(
                f"Runtime library not found. Searched:\n" +
                "\n".join(f"  - {p}" for p in possible_paths)
            )

        # Read runtime code
        runtime_code = runtime_source.read_text()

        # Check if runtime imports pylist and inline it
        if '@import("pylist.zig")' in runtime_code:
            pylist_source = runtime_source.parent / "pylist.zig"
            if not pylist_source.exists():
                raise CompilationError(f"pylist.zig not found at {pylist_source}")

            pylist_code = pylist_source.read_text()

            # Remove pylist's runtime import and adjust it to use inline code
            pylist_lines = []
            for line in pylist_code.split("\n"):
                # Skip the runtime import line and std import
                if '@import("runtime.zig")' in line or 'const runtime = @import("runtime.zig")' in line:
                    continue
                if 'const std = @import("std")' in line:
                    continue
                # Skip const declarations that reference runtime types (will be self-referential after prefix removal)
                if line.strip().startswith("const ") and "= runtime." in line:
                    continue
                # Remove runtime. prefix from pylist code
                line = line.replace("runtime.", "")
                pylist_lines.append(line)

            # Remove pylist import from runtime and adjust runtime code
            runtime_lines = []
            skip_next_blank = False
            for line in runtime_code.split("\n"):
                # Skip pylist import lines
                if '@import("pylist.zig")' in line:
                    continue
                # Remove the re-export line and the comment before it
                if 'PyList = pylist.PyList' in line:
                    # Also remove the previous line if it's a comment about re-export
                    if runtime_lines and runtime_lines[-1].strip().startswith("///") and "re-exported" in runtime_lines[-1]:
                        runtime_lines.pop()
                    skip_next_blank = True
                    continue
                # Skip one blank line after the re-export to clean up spacing
                if skip_next_blank and line.strip() == "":
                    skip_next_blank = False
                    continue
                skip_next_blank = False
                runtime_lines.append(line)

            # Combine: runtime first (without pylist import), then pylist structs
            runtime_code = "\n".join(runtime_lines) + "\n\n" + "\n".join(pylist_lines)

        # Check if runtime imports dict and inline it
        if '@import("dict.zig")' in runtime_code:
            dict_source = runtime_source.parent / "dict.zig"
            if not dict_source.exists():
                raise CompilationError(f"dict.zig not found at {dict_source}")

            dict_code = dict_source.read_text()

            # Remove dict's runtime import and adjust it to use inline code
            dict_lines = []
            for line in dict_code.split("\n"):
                # Skip the runtime import line and std import
                if '@import("runtime.zig")' in line or 'const runtime = @import("runtime.zig")' in line:
                    continue
                if 'const std = @import("std")' in line:
                    continue
                # Skip const declarations that reference runtime types (will be self-referential after prefix removal)
                if line.strip().startswith("const ") and "= runtime." in line:
                    continue
                # Remove runtime. prefix from dict code
                line = line.replace("runtime.", "")
                dict_lines.append(line)

            # Remove dict import from runtime and adjust runtime code
            runtime_lines = []
            skip_next_blank = False
            for line in runtime_code.split("\n"):
                # Skip dict import lines
                if '@import("dict.zig")' in line or 'const dict_module = @import("dict.zig")' in line:
                    continue
                # Remove the re-export line and any comment before it
                if 'PyDict = dict_module.PyDict' in line:
                    # Check if previous line is a comment and remove it
                    if runtime_lines and runtime_lines[-1].strip().startswith("//"):
                        runtime_lines.pop()
                    skip_next_blank = True
                    continue
                # Skip one blank line after the re-export to clean up spacing
                if skip_next_blank and line.strip() == "":
                    skip_next_blank = False
                    continue
                skip_next_blank = False
                runtime_lines.append(line)

            # Combine: runtime first (without dict import), then dict structs
            runtime_code = "\n".join(runtime_lines) + "\n\n" + "\n".join(dict_lines)

        # Check if runtime imports pystring and inline it
        if '@import("pystring.zig")' in runtime_code:
            pystring_source = runtime_source.parent / "pystring.zig"
            if not pystring_source.exists():
                raise CompilationError(f"pystring.zig not found at {pystring_source}")

            pystring_code = pystring_source.read_text()

            # Remove pystring's runtime and pylist imports and adjust it to use inline code
            pystring_lines = []
            for line in pystring_code.split("\n"):
                # Skip the runtime import line and std import
                if '@import("runtime.zig")' in line or 'const runtime = @import("runtime.zig")' in line:
                    continue
                # Skip the pylist import line
                if '@import("pylist.zig")' in line or 'const pylist = @import("pylist.zig")' in line:
                    continue
                if 'const std = @import("std")' in line:
                    continue
                # Skip const declarations that reference runtime or pylist types (will be self-referential after prefix removal)
                if line.strip().startswith("const ") and ("= runtime." in line or "= pylist." in line):
                    continue
                # Remove runtime. and pylist. prefixes from pystring code
                line = line.replace("runtime.", "")
                line = line.replace("pylist.", "")
                pystring_lines.append(line)

            # Remove pystring import from runtime and adjust runtime code
            runtime_lines = []
            skip_next_blank = False
            for i, line in enumerate(runtime_code.split("\n")):
                # Skip pystring import lines
                if '@import("pystring.zig")' in line:
                    continue
                # Remove the re-export line and the comment before it
                if 'PyString = pystring.PyString' in line:
                    # Also remove the previous line if it's a comment about re-export
                    if runtime_lines and runtime_lines[-1].strip().startswith("///") and "re-exported" in runtime_lines[-1]:
                        runtime_lines.pop()
                    skip_next_blank = True
                    continue
                # Skip one blank line after the re-export to clean up spacing
                if skip_next_blank and line.strip() == "":
                    skip_next_blank = False
                    continue
                skip_next_blank = False
                runtime_lines.append(line)

            # Combine: runtime first (without pystring import), then pystring structs
            runtime_code = "\n".join(runtime_lines) + "\n\n" + "\n".join(pystring_lines)

        # Check if runtime imports pyint and inline it
        if '@import("pyint.zig")' in runtime_code:
            pyint_source = runtime_source.parent / "pyint.zig"
            if not pyint_source.exists():
                raise CompilationError(f"pyint.zig not found at {pyint_source}")

            pyint_code = pyint_source.read_text()

            # Remove pyint's runtime import and adjust it to use inline code
            pyint_lines = []
            for line in pyint_code.split("\n"):
                # Skip the runtime import line and std import
                if '@import("runtime.zig")' in line or 'const runtime = @import("runtime.zig")' in line:
                    continue
                if 'const std = @import("std")' in line:
                    continue
                # Skip const declarations that reference runtime types (will be self-referential after prefix removal)
                if line.strip().startswith("const ") and "= runtime." in line:
                    continue
                # Remove runtime. prefix from pyint code
                line = line.replace("runtime.", "")
                pyint_lines.append(line)

            # Remove pyint import from runtime and adjust runtime code
            runtime_lines = []
            skip_next_blank = False
            for i, line in enumerate(runtime_code.split("\n")):
                # Skip pyint import lines
                if '@import("pyint.zig")' in line:
                    continue
                # Remove the re-export line and the comment before it
                if 'PyInt = pyint.PyInt' in line:
                    # Also remove the previous line if it's a comment about re-export
                    if runtime_lines and runtime_lines[-1].strip().startswith("///") and "re-exported" in runtime_lines[-1]:
                        runtime_lines.pop()
                    skip_next_blank = True
                    continue
                # Skip one blank line after the re-export to clean up spacing
                if skip_next_blank and line.strip() == "":
                    skip_next_blank = False
                    continue
                skip_next_blank = False
                runtime_lines.append(line)

            # Combine: runtime first (without pyint import), then pyint structs
            runtime_code = "\n".join(runtime_lines) + "\n\n" + "\n".join(pyint_lines)

        # Check if runtime imports pytuple and inline it
        if '@import("pytuple.zig")' in runtime_code:
            pytuple_source = runtime_source.parent / "pytuple.zig"
            if not pytuple_source.exists():
                raise CompilationError(f"pytuple.zig not found at {pytuple_source}")

            pytuple_code = pytuple_source.read_text()

            # Remove pytuple's runtime import and adjust it to use inline code
            pytuple_lines = []
            for line in pytuple_code.split("\n"):
                # Skip the runtime import line and std import
                if '@import("runtime.zig")' in line or 'const runtime = @import("runtime.zig")' in line:
                    continue
                if 'const std = @import("std")' in line:
                    continue
                # Skip const declarations that reference runtime types (will be self-referential after prefix removal)
                if line.strip().startswith("const ") and "= runtime." in line:
                    continue
                # Remove runtime. prefix from pytuple code
                line = line.replace("runtime.", "")
                pytuple_lines.append(line)

            # Remove pytuple import from runtime and adjust runtime code
            runtime_lines = []
            skip_next_blank = False
            for i, line in enumerate(runtime_code.split("\n")):
                # Skip pytuple import lines
                if '@import("pytuple.zig")' in line:
                    continue
                # Remove the re-export line and the comment before it
                if 'PyTuple = pytuple.PyTuple' in line:
                    # Also remove the previous line if it's a comment about re-export
                    if runtime_lines and runtime_lines[-1].strip().startswith("///") and "re-exported" in runtime_lines[-1]:
                        runtime_lines.pop()
                    skip_next_blank = True
                    continue
                # Skip one blank line after the re-export to clean up spacing
                if skip_next_blank and line.strip() == "":
                    skip_next_blank = False
                    continue
                skip_next_blank = False
                runtime_lines.append(line)

            # Combine: runtime first (without pytuple import), then pytuple structs
            runtime_code = "\n".join(runtime_lines) + "\n\n" + "\n".join(pytuple_lines)

        # Remove imports from generated code since runtime has them
        zig_code_lines = zig_code.split("\n")
        new_lines = []
        for line in zig_code_lines:
            # Skip import lines - runtime already has them
            if '@import("runtime")' in line or (line.strip().startswith('const std = @import("std")') and new_lines == []):
                continue
            # Skip pyint, pytuple, pylist, pystring, dict imports - they're inlined in runtime
            if any(x in line for x in ['@import("pyint.zig")', '@import("pytuple.zig")',
                                       '@import("pylist.zig")', '@import("pystring.zig")',
                                       '@import("dict.zig")']):
                continue
            # Remove runtime. prefix since we're inlining
            line = line.replace("runtime.", "")
            new_lines.append(line)

        # Prepend runtime code
        zig_code = runtime_code + "\n\n" + "\n".join(new_lines)

    # Create temporary directory for compilation
    with tempfile.TemporaryDirectory() as tmpdir:
        # Write Zig code to file
        zig_file = Path(tmpdir) / "main.zig"
        zig_file.write_text(zig_code)

        # Determine output path
        if output_path is None:
            output_path = str(Path(tmpdir) / "output")

        # Compile with Zig
        # Use Debug to catch memory leaks and bugs during development
        # Use ZYTH_RELEASE=1 for production builds
        optimize = "ReleaseFast" if os.getenv("ZYTH_RELEASE") == "1" else "Debug"

        try:
            subprocess.run(
                ["zig", "build-exe", str(zig_file), "-O", optimize],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                check=True
            )

            # Zig places the binary in the same directory as the source
            compiled_binary = Path(tmpdir) / "main"

            if not compiled_binary.exists():
                raise CompilationError("Compilation succeeded but binary not found")

            # Move binary to desired location if specified
            if output_path:
                output_dest = Path(output_path)
                output_dest.parent.mkdir(parents=True, exist_ok=True)

                # Copy instead of move since we're in temp dir
                shutil.copy2(str(compiled_binary), str(output_dest))
                return str(output_dest)

            return str(compiled_binary)

        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if e.stderr else e.stdout
            raise CompilationError(f"Zig compilation failed:\n{error_msg}") from e


def compile_file(source_file: str, output_path: Optional[str] = None, use_cache: bool = True) -> str:
    """
    Compile Python source file to binary with caching

    Args:
        source_file: Path to Python source file
        output_path: Optional output path for binary
                    If None: places binary in same directory as source (industry standard)
                    Example: fibonacci.py → ./fibonacci
        use_cache: Enable build caching (default: True)

    Returns:
        Path to compiled binary

    Raises:
        CompilationError: If compilation fails
    """
    from core.parser import parse_file, load_all_modules
    from core.codegen import generate_code

    # Generate cache key from absolute source path
    # This ensures same source file always maps to same cache entry
    source_path = Path(source_file).absolute()
    cache_key = hashlib.md5(source_path.as_posix().encode()).hexdigest()
    cache_file = CACHE_DIR / cache_key

    # Default output location: same directory as source (without .py extension)
    if output_path is None:
        output_path = str(source_path.parent / source_path.stem)

    # Check cache using timestamp comparison (fast!)
    if use_cache and is_cache_valid(cache_file, source_path):
        # Cache hit - reuse binary
        if output_path:
            output_dest = Path(output_path)
            output_dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(cache_file), str(output_dest))
            return str(output_dest)
        else:
            # Return path to cached binary
            return str(cache_file)

    # Cache miss or caching disabled - compile fresh
    # Parse Python file
    parsed = parse_file(source_file)

    # Load imported modules
    imported_modules = {}
    if parsed.imports:
        imported_modules = load_all_modules(parsed)

    # Generate Zig code
    zig_code = generate_code(parsed, imported_modules)

    # Compile to binary
    binary_path = compile_zig(zig_code, output_path)

    # Cache the result if enabled
    if use_cache:
        shutil.copy2(binary_path, str(cache_file))

    return binary_path


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python -m zyth_core.compiler <file.py> [output]")
        sys.exit(1)

    filepath = sys.argv[1]
    output_path_arg = sys.argv[2] if len(sys.argv) > 2 else None

    # Check for cache control via environment variable
    use_cache = os.getenv("ZYTH_CACHE", "1") == "1"

    # Compile with caching
    binary_path = compile_file(filepath, output_path_arg, use_cache=use_cache)

    print(f"✓ Compiled successfully to: {binary_path}")
