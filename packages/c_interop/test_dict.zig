/// Test PyDictObject implementation
const std = @import("std");
const cpython = @import("src/cpython_object.zig");
const pydict = @import("src/pyobject_dict.zig");
const pylong = @import("src/pyobject_long.zig");
const pyunicode = @import("src/pyobject_unicode.zig");

pub fn main() !void {
    std.debug.print("\n=== Testing PyDictObject (Comptime Version) ===\n\n", .{});

    // Test 1: Create empty dict
    std.debug.print("Test 1: Create empty dict\n", .{});
    const dict = pydict.PyDict_New();
    if (dict == null) {
        std.debug.print("❌ FAILED: PyDict_New returned null\n", .{});
        return error.CreationFailed;
    }
    std.debug.print("✓ Dict created\n", .{});

    const size = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Initial size: {d}\n", .{size});

    // Test 2: Set/Get with PyLong keys
    std.debug.print("\nTest 2: Set/Get with PyLong\n", .{});

    const key1 = pylong.PyLong_FromLong(42);
    const val1 = pylong.PyLong_FromLong(100);

    if (key1 == null or val1 == null) {
        std.debug.print("❌ FAILED: Could not create PyLong objects\n", .{});
        return error.CreationFailed;
    }

    const set_result = pydict.PyDict_SetItem(dict.?, key1.?, val1.?);
    if (set_result != 0) {
        std.debug.print("❌ FAILED: PyDict_SetItem returned {d}\n", .{set_result});
        return error.SetFailed;
    }
    std.debug.print("✓ Set item (42 -> 100)\n", .{});

    const get_result = pydict.PyDict_GetItem(dict.?, key1.?);
    if (get_result == null) {
        std.debug.print("❌ FAILED: PyDict_GetItem returned null\n", .{});
        return error.GetFailed;
    }

    const retrieved_val = pylong.PyLong_AsLong(get_result.?);
    std.debug.print("✓ Get item: {d}\n", .{retrieved_val});

    if (retrieved_val != 100) {
        std.debug.print("❌ FAILED: Expected 100, got {d}\n", .{retrieved_val});
        return error.ValueMismatch;
    }

    // Test 3: Multiple items
    std.debug.print("\nTest 3: Multiple items\n", .{});

    const key2 = pylong.PyLong_FromLong(43);
    const val2 = pylong.PyLong_FromLong(200);
    _ = pydict.PyDict_SetItem(dict.?, key2.?, val2.?);

    const key3 = pylong.PyLong_FromLong(44);
    const val3 = pylong.PyLong_FromLong(300);
    _ = pydict.PyDict_SetItem(dict.?, key3.?, val3.?);

    const size2 = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Dict size after 3 inserts: {d}\n", .{size2});

    if (size2 != 3) {
        std.debug.print("❌ FAILED: Expected size 3, got {d}\n", .{size2});
        return error.SizeMismatch;
    }

    // Test 4: Update existing key
    std.debug.print("\nTest 4: Update existing key\n", .{});

    const val1_new = pylong.PyLong_FromLong(999);
    _ = pydict.PyDict_SetItem(dict.?, key1.?, val1_new.?);

    const get_result2 = pydict.PyDict_GetItem(dict.?, key1.?);
    const updated_val = pylong.PyLong_AsLong(get_result2.?);
    std.debug.print("✓ Updated value: {d}\n", .{updated_val});

    if (updated_val != 999) {
        std.debug.print("❌ FAILED: Expected 999, got {d}\n", .{updated_val});
        return error.UpdateFailed;
    }

    const size3 = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Size after update (should be 3): {d}\n", .{size3});

    // Test 5: Delete item
    std.debug.print("\nTest 5: Delete item\n", .{});

    const del_result = pydict.PyDict_DelItem(dict.?, key2.?);
    if (del_result != 0) {
        std.debug.print("❌ FAILED: PyDict_DelItem returned {d}\n", .{del_result});
        return error.DeleteFailed;
    }
    std.debug.print("✓ Deleted key 43\n", .{});

    const size4 = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Size after delete: {d}\n", .{size4});

    if (size4 != 2) {
        std.debug.print("❌ FAILED: Expected size 2, got {d}\n", .{size4});
        return error.SizeMismatch;
    }

    // Test 6: Contains check
    std.debug.print("\nTest 6: Contains check\n", .{});

    const contains1 = pydict.PyDict_Contains(dict.?, key1.?);
    const contains2 = pydict.PyDict_Contains(dict.?, key2.?);
    const contains3 = pydict.PyDict_Contains(dict.?, key3.?);

    std.debug.print("✓ Contains key 42: {d}\n", .{contains1});
    std.debug.print("✓ Contains key 43 (deleted): {d}\n", .{contains2});
    std.debug.print("✓ Contains key 44: {d}\n", .{contains3});

    if (contains1 != 1 or contains2 != 0 or contains3 != 1) {
        std.debug.print("❌ FAILED: Contains check failed\n", .{});
        return error.ContainsFailed;
    }

    // Test 7: Clear dict
    std.debug.print("\nTest 7: Clear dict\n", .{});

    pydict.PyDict_Clear(dict.?);
    const size5 = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Size after clear: {d}\n", .{size5});

    if (size5 != 0) {
        std.debug.print("❌ FAILED: Expected size 0, got {d}\n", .{size5});
        return error.ClearFailed;
    }

    // Test 8: Many items (trigger resize)
    std.debug.print("\nTest 8: Resize test (20 items)\n", .{});

    var i: i64 = 0;
    while (i < 20) : (i += 1) {
        const k = pylong.PyLong_FromLong(i);
        const v = pylong.PyLong_FromLong(i * 10);
        _ = pydict.PyDict_SetItem(dict.?, k.?, v.?);
    }

    const size6 = pydict.PyDict_Size(dict.?);
    std.debug.print("✓ Size after 20 inserts: {d}\n", .{size6});

    if (size6 != 20) {
        std.debug.print("❌ FAILED: Expected size 20, got {d}\n", .{size6});
        return error.ResizeFailed;
    }

    // Verify all items accessible
    i = 0;
    while (i < 20) : (i += 1) {
        const k = pylong.PyLong_FromLong(i);
        const v = pydict.PyDict_GetItem(dict.?, k.?);
        if (v == null) {
            std.debug.print("❌ FAILED: Key {d} not found after resize\n", .{i});
            return error.ResizeFailed;
        }
        const val = pylong.PyLong_AsLong(v.?);
        if (val != i * 10) {
            std.debug.print("❌ FAILED: Key {d} has wrong value {d}\n", .{ i, val });
            return error.ResizeFailed;
        }
    }
    std.debug.print("✓ All 20 items accessible after resize\n", .{});

    std.debug.print("\n=== All Tests Passed! ===\n", .{});
    std.debug.print("\nComptime Benefits:\n", .{});
    std.debug.print("  - Reuses generic dict_impl.zig\n", .{});
    std.debug.print("  - Same optimizations as native dicts\n", .{});
    std.debug.print("  - Less code to maintain\n", .{});
    std.debug.print("  - Zero runtime cost (comptime specialization)\n", .{});
}
