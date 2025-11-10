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
    return [
        Path(__file__),  # compiler.py
        base / "codegen.py",
        base / "method_registry.py",
        base / "parser.py",
        base.parent.parent / "runtime" / "src" / "runtime.zig",
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

        # Read runtime code and inline it
        runtime_code = runtime_source.read_text()

        # Remove imports from generated code since runtime has them
        zig_code_lines = zig_code.split("\n")
        new_lines = []
        for line in zig_code_lines:
            # Skip import lines - runtime already has them
            if '@import("runtime")' in line or (line.strip().startswith('const std = @import("std")') and new_lines == []):
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
    from zyth_core.parser import parse_file, load_all_modules
    from zyth_core.codegen import generate_code

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
