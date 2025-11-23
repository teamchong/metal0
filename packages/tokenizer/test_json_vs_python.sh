#!/usr/bin/env bash
set -euo pipefail

echo "🧪 JSON Correctness Test: PyAOT vs Python"
echo "=========================================="
echo ""

# Test cases
declare -a tests=(
    'null'
    'true'
    'false'
    '0'
    '42'
    '-123'
    '""'
    '"hello"'
    '"hello world"'
    '"hello\nworld"'
    '[]'
    '[1,2,3]'
    '[1,"two",true,null]'
    '{}'
    '{"name":"test"}'
    '{"name":"test","value":123}'
    '{"a":1,"b":[2,3],"c":{"d":4}}'
)

pass_count=0
fail_count=0

for json_input in "${tests[@]}"; do
    # Python: parse and stringify
    python_output=$(python3 -c "import json; print(json.dumps(json.loads('$json_input'), separators=(',',':')))")

    # PyAOT: parse and stringify (using our test program)
    cat > /tmp/test_input.json <<EOF
$json_input
EOF

    # Create simple PyAOT test
    cat > /tmp/test_pyaot_json.zig <<'ZIGEOF'
const std = @import("std");
const runtime = @import("src/runtime.zig");
const json_module = @import("src/json.zig");
const allocator_helper = @import("src/allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const json_data = try std.fs.cwd().readFileAlloc(allocator, "/tmp/test_input.json", 1024 * 1024);
    defer allocator.free(json_data);

    // Parse
    const json_str = try runtime.PyString.create(allocator, json_data);
    defer runtime.decref(json_str, allocator);

    const parsed = try json_module.loads(json_str, allocator);
    defer runtime.decref(parsed, allocator);

    // Stringify
    const result = try json_module.dumps(parsed, allocator);
    defer runtime.decref(result, allocator);

    const result_data: *runtime.PyString = @ptrCast(@alignCast(result.data));
    std.debug.print("{s}", .{result_data.data});
}
ZIGEOF

    # Build and run PyAOT test
    if zig build-exe /tmp/test_pyaot_json.zig -O ReleaseFast -lc -femit-bin=/tmp/test_pyaot_json 2>/dev/null; then
        if pyaot_output=$(/tmp/test_pyaot_json 2>/dev/null); then
            # Compare outputs
            if [ "$python_output" = "$pyaot_output" ]; then
                echo "✅ PASS: $json_input"
                ((pass_count++))
            else
                echo "❌ FAIL: $json_input"
                echo "   Python:  $python_output"
                echo "   PyAOT:   $pyaot_output"
                ((fail_count++))
            fi
        else
            echo "❌ CRASH: $json_input (PyAOT crashed)"
            ((fail_count++))
        fi
    else
        echo "❌ BUILD FAIL: $json_input"
        ((fail_count++))
    fi
done

echo ""
echo "=========================================="
echo "Results: $pass_count passed, $fail_count failed"

if [ $fail_count -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
