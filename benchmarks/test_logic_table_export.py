@logic_table
class VectorOps:
    """Logic table for vector operations - simplified for testing."""

    def dot_product(self, a: list, b: list) -> float:
        """Compute dot product of two vectors."""
        result = 0.0
        for i in range(len(a)):
            result = result + a[i] * b[i]
        return result

    def sum_squares(self, a: list) -> float:
        """Compute sum of squares."""
        result = 0.0
        for i in range(len(a)):
            result = result + a[i] * a[i]
        return result


# Note: Don't call @logic_table methods from Python - they're for C FFI only
