"""
Helper methods for code generation
Small utility methods extracted from generator.py
"""
import ast


class CodegenHelpers:
    """Mixin class with helper methods for code generation"""

    def visit_compare_op(self, op: ast.cmpop) -> str:
        """Convert comparison operator"""
        op_map = {
            ast.Lt: "<",
            ast.LtE: "<=",
            ast.Gt: ">",
            ast.GtE: ">=",
            ast.Eq: "==",
            ast.NotEq: "!=",
        }
        return op_map.get(type(op), "==")

    def visit_bin_op(self, op: ast.operator) -> str:
        """Convert binary operator"""
        op_map = {
            ast.Add: "+",
            ast.Sub: "-",
            ast.Mult: "*",
            ast.Div: "/",
            ast.Mod: "%",
            ast.FloorDiv: "//",
            ast.Pow: "**",
            ast.BitAnd: "&",
            ast.BitOr: "|",
            ast.BitXor: "^",
            ast.LShift: "<<",
            ast.RShift: ">>",
        }
        return op_map.get(type(op), "+")
