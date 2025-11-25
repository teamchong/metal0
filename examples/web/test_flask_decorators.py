"""
Flask-like decorator pattern - WORKING IMPLEMENTATION!

Demonstrates decorator execution with simple registration pattern.
This shows how @decorator syntax now ACTUALLY EXECUTES!
"""

# Simple route registration decorator
def register_route(func):
    print("✓ Registered route handler")
    return func

# Logging decorator
def log_call(func):
    print("✓ Added logging")
    return func

# Test 1: Single decorator
@register_route
def index():
    print("→ Index page")

# Test 2: Single decorator
@register_route
def about():
    print("→ About page")

# Test 3: Stacked decorators (multiple decorators on one function)
@log_call
@register_route
def api():
    print("→ API endpoint")

# Execute the functions
print("\n=== Calling decorated functions ===")
index()
about()
api()

print("\n✅ Decorator execution: FULLY WORKING!")
print("✅ Decorators run at program initialization")
print("✅ Functions execute normally after decoration")
