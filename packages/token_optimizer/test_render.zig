const std = @import("std");
const render = @import("src/render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Simple text
    {
        var rendered = try render.renderText(allocator, "Hi");
        defer rendered.deinit();

        std.debug.print("\n=== Test 1: 'Hi' ===\n", .{});
        render.printAsciiArt(&rendered);
        std.debug.print("Size: {d}x{d} (expected: 12x7)\n\n", .{ rendered.width, rendered.height });

        if (rendered.height != 7) {
            std.debug.print("ERROR: Expected height 7, got {d}\n", .{rendered.height});
            return error.TestFailed;
        }
    }

    // Test 2: Text with newline (now renders as ↵ symbol, not blank row)
    {
        var rendered = try render.renderText(allocator, "Hi\n");
        defer rendered.deinit();

        std.debug.print("=== Test 2: 'Hi\\n' (newline as ↵ symbol) ===\n", .{});
        render.printAsciiArt(&rendered);
        std.debug.print("Size: {d}x{d} (expected: 18x7)\n", .{ rendered.width, rendered.height });
        std.debug.print("Note: Newline now rendered as gray ↵ symbol\n\n", .{});

        if (rendered.height != 7) {
            std.debug.print("ERROR: Expected height 7, got {d}\n", .{rendered.height});
            return error.TestFailed;
        }

        // Width should be 3 chars * 6 pixels = 18
        if (rendered.width != 18) {
            std.debug.print("ERROR: Expected width 18 (3 chars), got {d}\n", .{rendered.width});
            return error.TestFailed;
        }
    }

    // Test 3: Text with spaces (rendered as · dots)
    {
        var rendered = try render.renderText(allocator, "a b");
        defer rendered.deinit();

        std.debug.print("=== Test 3: 'a b' (spaces as · dots) ===\n", .{});
        render.printAsciiArt(&rendered);
        std.debug.print("Size: {d}x{d}\n", .{ rendered.width, rendered.height });
        std.debug.print("Note: Spaces rendered as gray · symbols\n\n", .{});

        if (rendered.height != 7) {
            std.debug.print("ERROR: Expected height 7, got {d}\n", .{rendered.height});
            return error.TestFailed;
        }
    }

    // Test 4: Tab character
    {
        var rendered = try render.renderText(allocator, "x\ty");
        defer rendered.deinit();

        std.debug.print("=== Test 4: 'x\\ty' (tab as → arrow) ===\n", .{});
        render.printAsciiArt(&rendered);
        std.debug.print("Size: {d}x{d}\n", .{ rendered.width, rendered.height });
        std.debug.print("Note: Tab rendered as gray → symbol\n\n", .{});
    }

    // Test 5: Multiline text
    {
        var rendered = try render.renderText(allocator, "def\n    x");
        defer rendered.deinit();

        std.debug.print("=== Test 5: 'def\\n    x' (Python code with indent) ===\n", .{});
        render.printAsciiArt(&rendered);
        std.debug.print("Size: {d}x{d}\n", .{ rendered.width, rendered.height });
        std.debug.print("Note: \\n and spaces all visible\n\n", .{});
    }

    // Test 6: Color enum values
    {
        const white = @intFromEnum(render.RenderColor.white);
        const black = @intFromEnum(render.RenderColor.black);
        const gray = @intFromEnum(render.RenderColor.gray);

        std.debug.print("=== Test 6: Color values ===\n", .{});
        std.debug.print("White: {d}, Black: {d}, Gray: {d}\n", .{ white, black, gray });

        if (white != 0 or black != 1 or gray != 2) {
            std.debug.print("ERROR: Unexpected color values\n", .{});
            return error.TestFailed;
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("✓ All tests passed!\n", .{});
}
