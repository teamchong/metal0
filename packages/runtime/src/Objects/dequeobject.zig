/// PyDeque implementation - Python collections.deque type
const std = @import("std");
const runtime = @import("../runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyDequeObject = runtime.PyDequeObject;
pub const DequeBlock = runtime.DequeBlock;
pub const PyDeque_Type = &runtime.PyDeque_Type;
pub const DEQUE_BLOCKLEN = runtime.DEQUE_BLOCKLEN;

const incref = runtime.incref;
const decref = runtime.decref;
const PythonError = runtime.PythonError;
const Py_ssize_t = runtime.Py_ssize_t;

/// Python deque type - double-ended queue
pub const PyDeque = struct {
    /// Create a new empty deque with optional maxlen
    pub fn create(allocator: std.mem.Allocator, maxlen: ?Py_ssize_t) !*PyObject {
        const deque_obj = try allocator.create(PyDequeObject);

        // Allocate initial block
        const block = try allocator.create(DequeBlock);
        block.* = .{
            .data = [_]?*PyObject{null} ** DEQUE_BLOCKLEN,
            .prev = null,
            .next = null,
        };

        deque_obj.* = PyDequeObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyDeque_Type,
            },
            .leftblock = block,
            .rightblock = block,
            .leftindex = DEQUE_BLOCKLEN / 2,
            .rightindex = DEQUE_BLOCKLEN / 2 - 1,
            .len = 0,
            .maxlen = maxlen orelse -1,
            .weakreflist = null,
        };

        return @ptrCast(deque_obj);
    }

    /// Append item to the right side of the deque
    pub fn append(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        const allocator = std.heap.c_allocator;

        // Check maxlen - pop from left if at capacity
        if (deque.maxlen >= 0 and deque.len >= deque.maxlen) {
            _ = try popleft(obj);
        }

        deque.rightindex += 1;

        // Check if we need a new block
        if (deque.rightindex >= DEQUE_BLOCKLEN) {
            const new_block = try allocator.create(DequeBlock);
            new_block.* = .{
                .data = [_]?*PyObject{null} ** DEQUE_BLOCKLEN,
                .prev = deque.rightblock,
                .next = null,
            };
            if (deque.rightblock) |rb| {
                rb.next = new_block;
            }
            deque.rightblock = new_block;
            deque.rightindex = 0;
        }

        incref(item);
        if (deque.rightblock) |rb| {
            rb.data[deque.rightindex] = item;
        }
        deque.len += 1;
    }

    /// Append item to the left side of the deque
    pub fn appendleft(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        const allocator = std.heap.c_allocator;

        // Check maxlen - pop from right if at capacity
        if (deque.maxlen >= 0 and deque.len >= deque.maxlen) {
            _ = try pop(obj);
        }

        if (deque.leftindex == 0) {
            const new_block = try allocator.create(DequeBlock);
            new_block.* = .{
                .data = [_]?*PyObject{null} ** DEQUE_BLOCKLEN,
                .prev = null,
                .next = deque.leftblock,
            };
            if (deque.leftblock) |lb| {
                lb.prev = new_block;
            }
            deque.leftblock = new_block;
            deque.leftindex = DEQUE_BLOCKLEN;
        }

        deque.leftindex -= 1;
        incref(item);
        if (deque.leftblock) |lb| {
            lb.data[deque.leftindex] = item;
        }
        deque.len += 1;
    }

    /// Pop item from the right side of the deque
    pub fn pop(obj: *PyObject) PythonError!*PyObject {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        const allocator = std.heap.c_allocator;

        if (deque.len == 0) return PythonError.IndexError;

        var item: ?*PyObject = null;
        if (deque.rightblock) |rb| {
            item = rb.data[deque.rightindex];
            rb.data[deque.rightindex] = null;
        }

        deque.len -= 1;

        if (deque.rightindex == 0) {
            // Move to previous block
            if (deque.rightblock) |rb| {
                const prev = rb.prev;
                if (prev != null and rb != deque.leftblock) {
                    allocator.destroy(rb);
                    deque.rightblock = prev;
                    if (prev) |p| p.next = null;
                    deque.rightindex = DEQUE_BLOCKLEN - 1;
                }
            }
        } else {
            deque.rightindex -= 1;
        }

        // Don't decref - transferring ownership to caller
        return item orelse return PythonError.IndexError;
    }

    /// Pop item from the left side of the deque
    pub fn popleft(obj: *PyObject) PythonError!*PyObject {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        const allocator = std.heap.c_allocator;

        if (deque.len == 0) return PythonError.IndexError;

        var item: ?*PyObject = null;
        if (deque.leftblock) |lb| {
            item = lb.data[deque.leftindex];
            lb.data[deque.leftindex] = null;
        }

        deque.len -= 1;
        deque.leftindex += 1;

        if (deque.leftindex >= DEQUE_BLOCKLEN) {
            if (deque.leftblock) |lb| {
                const next = lb.next;
                if (next != null and lb != deque.rightblock) {
                    allocator.destroy(lb);
                    deque.leftblock = next;
                    if (next) |n| n.prev = null;
                    deque.leftindex = 0;
                }
            }
        }

        return item orelse return PythonError.IndexError;
    }

    /// Get item at index
    pub fn get(obj: *PyObject, index: Py_ssize_t) PythonError!*PyObject {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));

        // Handle negative indices
        var idx = index;
        if (idx < 0) {
            idx += deque.len;
        }

        if (idx < 0 or idx >= deque.len) {
            return PythonError.IndexError;
        }

        // Navigate to the right block and index
        const abs_idx: usize = @intCast(idx);
        const pos = deque.leftindex + abs_idx;
        const block_num = pos / DEQUE_BLOCKLEN;
        const block_idx = pos % DEQUE_BLOCKLEN;

        var block = deque.leftblock;
        var i: usize = 0;
        while (i < block_num and block != null) : (i += 1) {
            block = block.?.next;
        }

        if (block) |b| {
            if (b.data[block_idx]) |item| {
                incref(item);
                return item;
            }
        }

        return PythonError.IndexError;
    }

    /// Get length of deque
    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        return @intCast(deque.len);
    }

    /// Clear all items from the deque
    pub fn clear(obj: *PyObject) void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));
        const allocator = std.heap.c_allocator;

        // Pop all items and decref them
        while (deque.len > 0) {
            if (pop(obj)) |item| {
                decref(item, allocator);
            } else |_| break;
        }
    }

    /// Extend deque from iterable (list) on the right
    pub fn extend(obj: *PyObject, list_obj: *PyObject) !void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        std.debug.assert(runtime.PyList_Check(list_obj));

        const list: *runtime.PyListObject = @ptrCast(@alignCast(list_obj));
        const size: usize = @intCast(list.ob_base.ob_size);

        var i: usize = 0;
        while (i < size) : (i += 1) {
            try append(obj, list.ob_item[i]);
        }
    }

    /// Extend deque from iterable (list) on the left
    pub fn extendleft(obj: *PyObject, list_obj: *PyObject) !void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        std.debug.assert(runtime.PyList_Check(list_obj));

        const list: *runtime.PyListObject = @ptrCast(@alignCast(list_obj));
        const size: usize = @intCast(list.ob_base.ob_size);

        // Items are added in reverse order (like CPython)
        var i: usize = 0;
        while (i < size) : (i += 1) {
            try appendleft(obj, list.ob_item[i]);
        }
    }

    /// Rotate deque by n steps (positive = right, negative = left)
    pub fn rotate(obj: *PyObject, n: Py_ssize_t) !void {
        std.debug.assert(runtime.PyDeque_Check(obj));
        const deque: *PyDequeObject = @ptrCast(@alignCast(obj));

        if (deque.len <= 1 or n == 0) return;

        // Normalize n to be within length
        var steps = @mod(n, deque.len);
        if (steps == 0) return;

        if (steps > 0) {
            // Rotate right - pop from right, push to left
            var i: Py_ssize_t = 0;
            while (i < steps) : (i += 1) {
                const item = try pop(obj);
                try appendleft(obj, item);
                decref(item, std.heap.c_allocator); // appendleft increfs
            }
        } else {
            // Rotate left - pop from left, push to right
            steps = -steps;
            var i: Py_ssize_t = 0;
            while (i < steps) : (i += 1) {
                const item = try popleft(obj);
                try append(obj, item);
                decref(item, std.heap.c_allocator); // append increfs
            }
        }
    }

    /// Create deque from list
    pub fn fromList(allocator: std.mem.Allocator, list_obj: *PyObject, maxlen: ?Py_ssize_t) !*PyObject {
        std.debug.assert(runtime.PyList_Check(list_obj));
        const list: *runtime.PyListObject = @ptrCast(@alignCast(list_obj));

        const result = try create(allocator, maxlen);
        const size: usize = @intCast(list.ob_base.ob_size);

        var i: usize = 0;
        while (i < size) : (i += 1) {
            try append(result, list.ob_item[i]);
        }

        return result;
    }
};
