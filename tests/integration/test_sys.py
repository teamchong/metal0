"""Test sys module"""
import pytest
import subprocess
import tempfile
from pathlib import Path


def run_example(code: str) -> str:
    """Compile and run code, return output"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(code)
        source_file = f.name

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        output_path = tmp.name

    try:
        # Compile
        result = subprocess.run(
            ["uv", "run", "python", "-m", "core.compiler", source_file, output_path],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            pytest.fail(f"Compilation failed:\n{result.stderr}")

        # Run
        result = subprocess.run(
            [output_path],
            capture_output=True,
            text=True
        )

        return result.stderr.strip()
    finally:
        Path(source_file).unlink(missing_ok=True)
        Path(output_path).unlink(missing_ok=True)


def test_sys_platform():
    """Test sys.platform returns darwin/linux/win32"""
    code = """
import sys
print(sys.platform)
"""
    output = run_example(code)
    # Should be one of the supported platforms
    assert output in ["darwin", "linux", "win32", "unknown"]


def test_sys_version_info():
    """Test sys.version_info tuple access"""
    code = """
import sys
print(sys.version_info.major)
print(sys.version_info.minor)
"""
    output = run_example(code)
    lines = output.split('\n')
    assert lines[0] == "3"
    assert lines[1] == "12"


def test_sys_exit():
    """Test sys.exit(0) terminates successfully"""
    code = """
import sys
print("before")
sys.exit(0)
print("after")
"""
    # This should exit before printing "after"
    output = run_example(code)
    assert "before" in output
    assert "after" not in output
