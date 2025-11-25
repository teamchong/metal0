# Python Feature Coverage Matrix

Based on CPython test categories. Run `make test-features` to verify.

## Syntax & Grammar

| Feature | Test File | Status |
|---------|-----------|--------|
| Integers | test_integers.py | ? |
| Floats | test_floats.py | ? |
| Strings | test_strings.py | ? |
| Lists | test_lists.py | ? |
| Dicts | test_dicts.py | ? |
| Tuples | test_tuples.py | ? |
| Sets | test_sets.py | ? |

## Operators

| Feature | Test File | Status |
|---------|-----------|--------|
| Arithmetic (+,-,*,//,%) | test_arithmetic.py | ? |
| Division (/) | test_division.py | ❌ |
| Power (**) | test_power.py | ? |
| Comparison (==,!=,<,>) | test_comparison.py | ? |
| Boolean (and,or,not) | test_boolean.py | ? |
| Bitwise (&,|,^,~) | test_bitwise.py | ? |
| Assignment (=,+=,-=) | test_assignment.py | ? |

## Control Flow

| Feature | Test File | Status |
|---------|-----------|--------|
| if/elif/else | test_if.py | ✅ |
| for loop | test_for.py | ✅ |
| while loop | test_while.py | ✅ |
| break/continue | test_break_continue.py | ? |
| try/except | test_try_except.py | ⏳ Not implemented |
| with statement | test_with.py | ? |

## Functions

| Feature | Test File | Status |
|---------|-----------|--------|
| def | test_def.py | ✅ |
| return | test_return.py | ✅ |
| recursion | test_recursion.py | ✅ |
| default args | test_default_args.py | ? |
| *args | test_args.py | ? |
| **kwargs | test_kwargs.py | ? |
| lambda | test_lambda.py | ? |
| global | test_global.py | ❌ |
| nonlocal | test_nonlocal.py | ? |

## Classes

| Feature | Test File | Status |
|---------|-----------|--------|
| class def | test_class.py | ✅ |
| __init__ | test_init.py | ✅ |
| self | test_self.py | ✅ |
| inheritance | test_inheritance.py | ? |
| methods | test_methods.py | ? |

## Comprehensions

| Feature | Test File | Status |
|---------|-----------|--------|
| list comp | test_listcomp.py | ❌ |
| dict comp | test_dictcomp.py | ? |
| set comp | test_setcomp.py | ? |
| generator | test_generator.py | ? |

## Async

| Feature | Test File | Status |
|---------|-----------|--------|
| async def | test_async.py | ✅ |
| await | test_await.py | ? |
| async for | test_async_for.py | ? |
| async with | test_async_with.py | ? |

## Misc

| Feature | Test File | Status |
|---------|-----------|--------|
| import | test_import.py | ? |
| f-strings | test_fstring.py | ✅ |
| print | test_print.py | ✅ |
| input | test_input.py | ? |
| type hints | test_typehints.py | ? |

---
✅ = Working | ❌ = Broken | ⏳ = Not implemented (planned) | ? = Not tested
