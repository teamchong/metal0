"""
Simple @logic_table for benchmark demonstration.

These are pure numeric functions that compile cleanly without numpy dependencies.
Compiled by metal0: metal0 build --emit-logic-table benchmarks/simple_logic_table.py -o lib/simple_logic_table.a
"""

from logic_table import logic_table


@logic_table
class MathOps:
    """Basic mathematical operations."""

    def add(self, x: float, y: float) -> float:
        """Add two numbers."""
        return x + y

    def multiply(self, x: float, y: float) -> float:
        """Multiply two numbers."""
        return x * y

    def subtract(self, x: float, y: float) -> float:
        """Subtract two numbers."""
        return x - y


@logic_table
class ScoreOps:
    """Scoring and ranking operations."""

    def weighted_score(self, a: float, b: float, w: float) -> float:
        """Weighted combination of two scores."""
        return a * w + b * (1.0 - w)
