# Vector operations for @logic_table benchmark
# Compiled by metal0: metal0 build --emit-logic-table benchmarks/vector_ops.py -o lib/vector_ops.a
#
# HONEST BENCHMARK: These are ACTUAL Python for loops that get compiled to Zig.
# No built-in functions - pure Python code that metal0 compiles.

from logic_table import logic_table


@logic_table
class VectorOps:
    """Core vector operations - REAL Python code compiled to native Zig.

    These for loops are what metal0 compiles. No cheating with built-in SIMD.
    """

    def dot_product(self, a: list, b: list) -> float:
        """Compute dot product of two vectors.

        This Python for loop is compiled to Zig by metal0.
        """
        result = 0.0
        for i in range(len(a)):
            result = result + a[i] * b[i]
        return result

    def sum_squares(self, a: list) -> float:
        """Compute sum of squares of a vector.

        This Python for loop is compiled to Zig by metal0.
        """
        result = 0.0
        for i in range(len(a)):
            result = result + a[i] * a[i]
        return result

