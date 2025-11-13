# Agent Task Assignments

**Context:** We're migrating Zyth from Python to pure Zig for a single-binary compiler with zero dependencies.

## Agent 1: Implement Python Lexer (lexer.zig)

**File:** `src/lexer.zig`
**Current:** 140 lines (stub)
**Target:** 300-400 lines (full implementation)

**Task:** Implement `Lexer.tokenize()` method to convert Python source code into tokens.

**Requirements:**
1. **Tokenize all Python keywords:** def, class, if, elif, else, for, while, return, break, continue, pass, import, from, as, in, not, and, or, True, False, None
2. **Tokenize literals:** identifiers, numbers (int/float), strings (single/double quotes, triple quotes)
3. **Tokenize operators:** +, -, *, /, //, %, **, ==, !=, <, <=, >, >=, =
4. **Tokenize delimiters:** (), [], {}, ,, :, ., ->
5. **Handle indentation:** Track indent stack, emit Indent/Dedent tokens
6. **Handle newlines:** Significant newlines (end of statement) vs ignored (inside parens)
7. **Handle comments:** Skip # comments
8. **Track position:** Line and column numbers for error reporting

**Implementation hints:**
- Use `peek()` to look ahead without consuming
- Use `advance()` to consume and move forward
- Maintain `indent_stack` for Python's significant whitespace
- At start of line, compare indentation to stack top
- Emit multiple Dedent tokens when unindenting multiple levels

**Test cases to support:**
```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

numbers = [1, 2, 3]
total = 0
for i in range(len(numbers)):
    total = total + numbers[i]
print(total)
```

**Deliverables:**
1. Fully implemented `tokenize()` method
2. Handle all token types in TokenType enum
3. Correct indentation tracking
4. Pass basic Python examples (fibonacci, loops, lists)

---

## Agent 2: Implement Python Parser (parser.zig + ast.zig)

**Files:** `src/parser.zig`, `src/ast.zig`
**Current:** 50 + 100 lines (stubs)
**Target:** 600-800 + 200-300 lines

**Task:** Implement `Parser.parse()` to build AST from tokens.

**Requirements:**
1. **Parse statements:**
   - Assignments: `x = 5`, `x = y + z`
   - If/elif/else: `if x > 5: ... elif: ... else: ...`
   - For loops: `for i in range(10): ...`
   - While loops: `while x < 10: ...`
   - Function definitions: `def foo(a, b): ...`
   - Class definitions: `class Foo: ...`
   - Return: `return x + y`

2. **Parse expressions:**
   - Binary ops: `a + b`, `x * y`, `n ** 2`
   - Comparisons: `a == b`, `x < y`
   - Function calls: `print(x)`, `foo(1, 2)`
   - List literals: `[1, 2, 3]`
   - Subscripts: `list[0]`, `list[1:3]`
   - Attributes: `obj.method()`

3. **Build AST nodes:**
   - Create proper `ast.Node` instances
   - Link parent/child relationships
   - Allocate memory correctly (use arena allocator)

**Parser structure:**
```zig
fn parseStatement() !Node
fn parseExpression() !Node
fn parsePrimary() !Node
fn expectToken(type: TokenType) !Token
```

**Deliverables:**
1. Recursive descent parser for Python subset
2. Support all AST node types in `ast.zig`
3. Proper error handling with line/column info
4. Pass the same test cases as Agent 1

---

## Agent 3: Port Codegen to Zig (codegen.zig)

**File:** `src/codegen.zig`
**Current:** 120 lines (stub)
**Target:** 1500-2000 lines

**Task:** Port Python codegen logic from `packages/core/codegen/generator.py` to Zig.

**Requirements:**
1. **Port these visitor methods:**
   - `visitAssign()` - Variable assignments
   - `visitBinOp()` - Binary operations (from expressions.py)
   - `visitCall()` - Function/method calls
   - `visitFor()` - For loops
   - `visitIf()` - If statements
   - `visitFunctionDef()` - Function definitions
   - `visitClassDef()` - Class definitions

2. **Track state:**
   - `var_types: StringHashMap` - Variable type tracking
   - `declared_vars: HashSet` - Declared variables
   - `indent_level: usize` - Current indentation

3. **Generate Zig code:**
   - Map Python int → Zig i64
   - Map Python string → PyString.create()
   - Map Python list → PyList.create()
   - Handle method calls: `list.append(x)` → `PyList.append(list, x)`
   - Handle operators: `a + b` → `a + b` (primitives) or `PyInt.add(a, b)` (PyObjects)

**Key logic to port:**
- **Type inference** (lines 1434-1437 in generator.py)
- **Binary operations** (expressions.py:123-180)
- **Method calls** (uses method_registry.py)
- **For loops** (generator.py:945-1125)
- **Assignments** (generator.py:1414-2205)

**Reference files:**
- `packages/core/codegen/generator.py` - Main codegen (2559 lines)
- `packages/core/codegen/expressions.py` - Expression handling (808 lines)
- `packages/core/method_registry.py` - Method metadata (460 lines)

**Deliverables:**
1. Port core visitor methods to Zig
2. Implement type tracking system
3. Generate correct Zig code for test cases
4. Pass regression tests (examples/fibonacci.py, etc.)

---

## Coordination

**Order of completion:**
1. Agent 1 (Lexer) - Must finish first
2. Agent 2 (Parser) - Needs Agent 1's tokens
3. Agent 3 (Codegen) - Can work in parallel with Agent 2

**Testing strategy:**
- Agent 1: Test tokenization output matches expected tokens
- Agent 2: Test AST structure matches Python's ast.dump()
- Agent 3: Test generated Zig code compiles and runs correctly

**Communication:**
- All agents report back with code + test results
- If blocked, specify what's needed to unblock
- If Agent 2 needs AST changes, coordinate with Agent 1

---

## Success Criteria

**Phase 1 Complete** when:
1. ✅ Lexer tokenizes all test cases
2. ✅ Parser builds correct AST
3. ✅ Codegen generates working Zig code
4. ✅ `zyth examples/fibonacci.py` compiles and runs
5. ✅ All regression tests pass

**Result:** Pure Zig compiler, 19x faster codegen, zero Python dependency.
