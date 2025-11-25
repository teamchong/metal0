"""
Regression test suite - runs all example/*.py demo files.

These tests ensure that all user-facing demos continue to work correctly.
Each demo file is compiled with PyAOT and output is compared against Python.

DO NOT delete examples/ - they serve as user documentation!
This test file just automates verification that demos work.
"""
import pytest
import subprocess
import tempfile
from pathlib import Path

PYAOT_ROOT = Path(__file__).parent.parent
EXAMPLES_DIR = PYAOT_ROOT / "examples"
PYAOT_BIN = PYAOT_ROOT / "zig-out" / "bin" / "pyaot"

# PyAOT-only examples that use built-ins not available in Python
# These are compiled and run with PyAOT only (no Python comparison)
PYAOT_ONLY_EXAMPLES = {
    "web_crawler",
    "web_crawler_async",
}


def get_all_examples():
    """Discover all .py files in examples directory"""
    examples = sorted(EXAMPLES_DIR.glob("*.py"))
    return [(ex.stem, ex) for ex in examples]


def run_example(example_path: Path) -> tuple[str, str, int, int]:
    """
    Run example in both Python and PyAOT, return (py_output, zy_output, py_code, zy_code)

    Returns:
        py_output: Python stdout
        zy_output: PyAOT stderr (uses std.debug.print)
        py_code: Python exit code
        zy_code: PyAOT exit code
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        zy_bin = Path(tmpdir) / "test_zy"

        # Run Python
        py_result = subprocess.run(
            ["python", str(example_path)],
            capture_output=True,
            text=True,
            timeout=60
        )

        # Compile PyAOT (use local build, not system install)
        compile_result = subprocess.run(
            [str(PYAOT_BIN), "build", "--binary", str(example_path), str(zy_bin)],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=PYAOT_ROOT
        )

        if compile_result.returncode != 0:
            pytest.fail(
                f"Compilation failed:\n"
                f"STDOUT:\n{compile_result.stdout}\n"
                f"STDERR:\n{compile_result.stderr}"
            )

        # Run PyAOT
        zy_result = subprocess.run(
            [str(zy_bin)],
            capture_output=True,
            text=True,
            timeout=10
        )

        return (
            py_result.stdout,
            zy_result.stderr,  # PyAOT uses std.debug.print (stderr)
            py_result.returncode,
            zy_result.returncode
        )


class TestExamples:
    """Test all example files produce matching output"""

    @pytest.mark.parametrize("name,path", get_all_examples())
    def test_example(self, name, path):
        """Test that example produces same output in Python and PyAOT"""
        # PyAOT-only examples: just verify they compile and run without errors
        if name in PYAOT_ONLY_EXAMPLES:
            with tempfile.TemporaryDirectory() as tmpdir:
                zy_bin = Path(tmpdir) / "test_zy"

                # Compile PyAOT (use local build, not system install)
                compile_result = subprocess.run(
                    [str(PYAOT_BIN), "build", "--binary", str(path), str(zy_bin)],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    cwd=PYAOT_ROOT
                )

                if compile_result.returncode != 0:
                    pytest.fail(
                        f"Compilation failed:\n"
                        f"STDOUT:\n{compile_result.stdout}\n"
                        f"STDERR:\n{compile_result.stderr}"
                    )

                # Run PyAOT (may fail due to network, but shouldn't crash)
                zy_result = subprocess.run(
                    [str(zy_bin)],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                # Just verify it exits (network errors are OK for web_crawler)
                assert zy_result.returncode in [0, 1], (
                    f"PyAOT crashed with exit code {zy_result.returncode}\n"
                    f"STDERR:\n{zy_result.stderr}"
                )
            return

        # Regular examples: compare Python vs PyAOT output
        py_out, zy_out, py_code, zy_code = run_example(path)

        # Both should exit successfully
        assert py_code == 0, f"Python failed with exit code {py_code}"
        assert zy_code == 0, f"PyAOT failed with exit code {zy_code}"

        # Output should match
        assert py_out == zy_out, (
            f"Output mismatch for {name}:\n"
            f"Python output ({len(py_out)} chars):\n{py_out!r}\n\n"
            f"PyAOT output ({len(zy_out)} chars):\n{zy_out!r}"
        )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
