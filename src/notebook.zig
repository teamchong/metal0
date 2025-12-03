const std = @import("std");
const runtime = @import("runtime");
const json = @import("runtime").json;
const JsonValue = json.JsonValue;

/// Represents a single cell in a Jupyter notebook
pub const Cell = struct {
    cell_type: []const u8, // "code" or "markdown"
    source: std.ArrayList([]const u8), // Lines of code/markdown
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cell_type: []const u8) Cell {
        return Cell{
            .cell_type = cell_type,
            .source = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Cell) void {
        for (self.source.items) |line| {
            self.allocator.free(line);
        }
        self.source.deinit(self.allocator);
    }

    /// Join all source lines into a single string
    pub fn joinSource(self: *const Cell, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        for (self.source.items) |line| {
            try result.appendSlice(allocator, line);
        }

        return try result.toOwnedSlice(allocator);
    }
};

/// Represents a Jupyter notebook
pub const Notebook = struct {
    cells: std.ArrayList(Cell),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Notebook {
        return Notebook{
            .cells = std.ArrayList(Cell){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Notebook) void {
        for (self.cells.items) |*cell| {
            cell.deinit();
        }
        self.cells.deinit(self.allocator);
    }

    /// Parse .ipynb JSON file
    pub fn parse(json_path: []const u8, allocator: std.mem.Allocator) !Notebook {
        // Read file
        const file_content = try std.fs.cwd().readFileAlloc(allocator, json_path, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(file_content);

        // Parse JSON
        var notebook = Notebook.init(allocator);
        errdefer notebook.deinit();

        var root = try json.parse(allocator, file_content);
        defer root.deinit(allocator);

        // Get cells array
        const cells_array = root.object.get("cells") orelse return error.NoCellsFound;

        for (cells_array.array.items) |*cell_value| {
            const cell_obj = cell_value.object;

            // Get cell_type
            const cell_type_value = cell_obj.get("cell_type") orelse continue;
            const cell_type = cell_type_value.string;
            const cell_type_copy = try allocator.dupe(u8, cell_type);

            var cell = Cell.init(allocator, cell_type_copy);
            errdefer cell.deinit();

            // Get source (can be string or array of strings)
            if (cell_obj.get("source")) |*source_value| {
                switch (source_value.*) {
                    .string => |str| {
                        const line_copy = try allocator.dupe(u8, str);
                        try cell.source.append(allocator, line_copy);
                    },
                    .array => |arr| {
                        for (arr.items) |*line_value| {
                            if (line_value.* == .string) {
                                const line_copy = try allocator.dupe(u8, line_value.string);
                                try cell.source.append(allocator, line_copy);
                            }
                        }
                    },
                    else => {},
                }
            }

            try notebook.cells.append(allocator, cell);
        }

        return notebook;
    }

    /// Extract only code cells and join their source
    pub fn extractCodeCells(self: *const Notebook, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var code_blocks = std.ArrayList([]const u8){};
        errdefer {
            for (code_blocks.items) |block| {
                allocator.free(block);
            }
            code_blocks.deinit(allocator);
        }

        for (self.cells.items) |*cell| {
            if (std.mem.eql(u8, cell.cell_type, "code")) {
                const joined = try cell.joinSource(allocator);
                try code_blocks.append(allocator, joined);
            }
        }

        return code_blocks;
    }

    /// Process cell source to remove IPython-specific syntax
    fn processSourceLine(line: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        // Trim whitespace
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        // Skip magic commands (%, %%)
        if (trimmed.len > 0 and trimmed[0] == '%') {
            return null; // Skip this line
        }

        // Skip IPython.display imports
        if (std.mem.indexOf(u8, trimmed, "from IPython") != null or
            std.mem.indexOf(u8, trimmed, "import IPython") != null or
            std.mem.indexOf(u8, trimmed, "from IPython.display") != null)
        {
            return null; // Skip this line
        }

        // Skip display() calls
        if (std.mem.indexOf(u8, trimmed, "display(") != null) {
            // Replace display(x) with print(x)
            var new_line = std.ArrayList(u8){};
            defer new_line.deinit(allocator);

            var i: usize = 0;
            while (i < line.len) : (i += 1) {
                if (i + 7 < line.len and std.mem.eql(u8, line[i .. i + 7], "display")) {
                    try new_line.appendSlice(allocator, "print");
                    i += 6; // Skip "display" (will increment by 1 in loop)
                } else {
                    try new_line.append(allocator, line[i]);
                }
            }

            return try new_line.toOwnedSlice(allocator);
        }

        // Return original line
        return try allocator.dupe(u8, line);
    }

    /// Combine all code cells into a single Python module (for state sharing)
    pub fn combineCodeCells(self: *const Notebook, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        for (self.cells.items, 0..) |*cell, i| {
            if (std.mem.eql(u8, cell.cell_type, "code")) {
                // Add cell marker comment
                try result.writer(allocator).print("# Cell {d}\n", .{i});

                // Process each source line
                for (cell.source.items) |line| {
                    const processed = try processSourceLine(line, allocator);
                    if (processed) |p| {
                        defer allocator.free(p);
                        try result.appendSlice(allocator, p);
                    }
                }

                // Add newlines between cells
                try result.appendSlice(allocator, "\n\n");
            }
        }

        return try result.toOwnedSlice(allocator);
    }
};

test "parse simple notebook" {
    const allocator = std.testing.allocator;

    // Create a simple test notebook JSON
    const test_json =
        \\{
        \\  "cells": [
        \\    {
        \\      "cell_type": "code",
        \\      "source": ["x = 10\n", "print(x)\n"]
        \\    },
        \\    {
        \\      "cell_type": "markdown",
        \\      "source": ["# Header\n"]
        \\    },
        \\    {
        \\      "cell_type": "code",
        \\      "source": ["y = 20\n", "print(y)\n"]
        \\    }
        \\  ]
        \\}
    ;

    // Write to temp file
    const temp_file = "/tmp/test_notebook.ipynb";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_json });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    // Parse notebook
    var notebook = try Notebook.parse(temp_file, allocator);
    defer notebook.deinit();

    // Check number of cells
    try std.testing.expectEqual(@as(usize, 3), notebook.cells.items.len);

    // Check first cell is code
    try std.testing.expect(std.mem.eql(u8, notebook.cells.items[0].cell_type, "code"));

    // Check second cell is markdown
    try std.testing.expect(std.mem.eql(u8, notebook.cells.items[1].cell_type, "markdown"));

    // Extract code cells
    var code_cells = try notebook.extractCodeCells(allocator);
    defer {
        for (code_cells.items) |block| {
            allocator.free(block);
        }
        code_cells.deinit(allocator);
    }

    // Should have 2 code cells
    try std.testing.expectEqual(@as(usize, 2), code_cells.items.len);
}

test "combine code cells" {
    const allocator = std.testing.allocator;

    const test_json =
        \\{
        \\  "cells": [
        \\    {
        \\      "cell_type": "code",
        \\      "source": ["x = 10\n"]
        \\    },
        \\    {
        \\      "cell_type": "code",
        \\      "source": ["print(x)\n"]
        \\    }
        \\  ]
        \\}
    ;

    const temp_file = "/tmp/test_combine.ipynb";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_file, .data = test_json });
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    var notebook = try Notebook.parse(temp_file, allocator);
    defer notebook.deinit();

    const combined = try notebook.combineCodeCells(allocator);
    defer allocator.free(combined);

    // Check combined code contains both cells
    try std.testing.expect(std.mem.indexOf(u8, combined, "x = 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "print(x)") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "# Cell 0") != null);
}
