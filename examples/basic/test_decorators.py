"""
Basic decorator syntax test
Tests that @decorator syntax parses correctly

NOTE: Decorators are parsed but not yet applied.
- AST correctly stores decorator information
- Parser handles @decorator syntax
- Codegen adds TODO comments showing where decorators would be applied

Current limitation: Decorator APPLICATION requires:
1. Nested functions (closures) - not yet supported
2. Function pointers/reassignment in Zig - not straightforward
3. Scope-aware decorator application - needs refactoring

This test shows that the SYNTAX is supported.
"""

# Simple decorator (would need to return a function)
def log_decorator(func):
    print("Decorator called!")
    return func

# Test simple decorator syntax
@log_decorator
def hello():
    print("Hello from decorated function!")

# Test that function still works
print("=== Testing decorated function ===")
hello()
print("Function executed successfully!")

# Note: For decorators with arguments like @route("/path"),
# we would need nested functions which aren't supported yet.
# But the @decorator syntax itself is now recognized!
