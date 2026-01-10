//! test.test_tkinter.test_dialog - Tk dialog tests
//!
//! Tests for Tkinter dialog boxes including message boxes, file dialogs,
//! color choosers, and custom dialog implementations.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Icon types for message dialogs
pub const IconType = enum {
    info,
    warning,
    @"error",
    question,

    pub fn toTclString(self: IconType) []const u8 {
        return switch (self) {
            .info => "info",
            .warning => "warning",
            .@"error" => "error",
            .question => "question",
        };
    }
};

/// Button types for message dialogs
pub const ButtonType = enum {
    ok,
    ok_cancel,
    yes_no,
    yes_no_cancel,
    retry_cancel,
    abort_retry_ignore,

    pub fn toTclString(self: ButtonType) []const u8 {
        return switch (self) {
            .ok => "ok",
            .ok_cancel => "okcancel",
            .yes_no => "yesno",
            .yes_no_cancel => "yesnocancel",
            .retry_cancel => "retrycancel",
            .abort_retry_ignore => "abortretryignore",
        };
    }

    pub fn buttonCount(self: ButtonType) usize {
        return switch (self) {
            .ok => 1,
            .ok_cancel, .yes_no, .retry_cancel => 2,
            .yes_no_cancel, .abort_retry_ignore => 3,
        };
    }
};

/// Dialog result codes
pub const DialogResult = enum {
    ok,
    cancel,
    yes,
    no,
    retry,
    abort,
    ignore,
    none,

    pub fn fromString(s: []const u8) DialogResult {
        if (std.mem.eql(u8, s, "ok")) return .ok;
        if (std.mem.eql(u8, s, "cancel")) return .cancel;
        if (std.mem.eql(u8, s, "yes")) return .yes;
        if (std.mem.eql(u8, s, "no")) return .no;
        if (std.mem.eql(u8, s, "retry")) return .retry;
        if (std.mem.eql(u8, s, "abort")) return .abort;
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        return .none;
    }
};

/// Message box configuration
pub const MessageBoxConfig = struct {
    title: []const u8 = "Message",
    message: []const u8 = "",
    detail: []const u8 = "",
    icon: IconType = .info,
    buttons: ButtonType = .ok,
    default_button: ?usize = null,
    parent: ?*anyopaque = null,

    pub fn toTclArgs(self: *const MessageBoxConfig, allocator: Allocator) ![]const u8 {
        var args = std.ArrayList(u8).init(allocator);
        errdefer args.deinit();

        try args.appendSlice("-title {");
        try args.appendSlice(self.title);
        try args.appendSlice("} -message {");
        try args.appendSlice(self.message);
        try args.appendSlice("} -icon ");
        try args.appendSlice(self.icon.toTclString());
        try args.appendSlice(" -type ");
        try args.appendSlice(self.buttons.toTclString());

        if (self.detail.len > 0) {
            try args.appendSlice(" -detail {");
            try args.appendSlice(self.detail);
            try args.append('}');
        }

        if (self.default_button) |def| {
            var buf: [16]u8 = undefined;
            const num_str = std.fmt.bufPrint(&buf, " -default {d}", .{def}) catch "";
            try args.appendSlice(num_str);
        }

        return args.toOwnedSlice();
    }
};

/// Message box dialog
pub const MessageBox = struct {
    config: MessageBoxConfig,
    result: DialogResult = .none,
    is_shown: bool = false,

    pub fn init(config: MessageBoxConfig) MessageBox {
        return .{ .config = config };
    }

    pub fn show(self: *MessageBox) DialogResult {
        self.is_shown = true;
        // In real implementation, this would call tk_messageBox
        // For testing, we simulate based on button type
        self.result = switch (self.config.buttons) {
            .ok => .ok,
            .ok_cancel => .ok,
            .yes_no => .yes,
            .yes_no_cancel => .yes,
            .retry_cancel => .retry,
            .abort_retry_ignore => .retry,
        };
        return self.result;
    }

    pub fn showInfo(title: []const u8, message: []const u8) DialogResult {
        var box = MessageBox.init(.{
            .title = title,
            .message = message,
            .icon = .info,
            .buttons = .ok,
        });
        return box.show();
    }

    pub fn showWarning(title: []const u8, message: []const u8) DialogResult {
        var box = MessageBox.init(.{
            .title = title,
            .message = message,
            .icon = .warning,
            .buttons = .ok,
        });
        return box.show();
    }

    pub fn showError(title: []const u8, message: []const u8) DialogResult {
        var box = MessageBox.init(.{
            .title = title,
            .message = message,
            .icon = .@"error",
            .buttons = .ok,
        });
        return box.show();
    }

    pub fn askQuestion(title: []const u8, message: []const u8) DialogResult {
        var box = MessageBox.init(.{
            .title = title,
            .message = message,
            .icon = .question,
            .buttons = .yes_no,
        });
        return box.show();
    }

    pub fn askOkCancel(title: []const u8, message: []const u8) DialogResult {
        var box = MessageBox.init(.{
            .title = title,
            .message = message,
            .icon = .question,
            .buttons = .ok_cancel,
        });
        return box.show();
    }
};

/// File type filter for file dialogs
pub const FileType = struct {
    name: []const u8,
    patterns: []const []const u8,

    pub fn toTclList(self: *const FileType, allocator: Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice("{{");
        try result.appendSlice(self.name);
        try result.appendSlice("} {");
        for (self.patterns, 0..) |pattern, i| {
            if (i > 0) try result.append(' ');
            try result.appendSlice(pattern);
        }
        try result.appendSlice("}}");

        return result.toOwnedSlice();
    }
};

/// File dialog configuration
pub const FileDialogConfig = struct {
    title: []const u8 = "Select File",
    initial_dir: []const u8 = "",
    initial_file: []const u8 = "",
    default_extension: []const u8 = "",
    file_types: []const FileType = &.{},
    multiple: bool = false,
    parent: ?*anyopaque = null,

    pub fn defaultFileTypes() []const FileType {
        return &.{
            .{ .name = "All Files", .patterns = &.{"*"} },
            .{ .name = "Text Files", .patterns = &.{ "*.txt", "*.text" } },
            .{ .name = "Python Files", .patterns = &.{"*.py"} },
        };
    }
};

/// Open file dialog
pub const OpenFileDialog = struct {
    config: FileDialogConfig,
    selected_files: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: FileDialogConfig) OpenFileDialog {
        return .{
            .config = config,
            .selected_files = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OpenFileDialog) void {
        self.selected_files.deinit();
    }

    pub fn show(self: *OpenFileDialog) ?[]const u8 {
        // Simulated for testing
        if (self.config.initial_file.len > 0) {
            return self.config.initial_file;
        }
        return null;
    }

    pub fn showMultiple(self: *OpenFileDialog) []const []const u8 {
        return self.selected_files.items;
    }
};

/// Save file dialog
pub const SaveFileDialog = struct {
    config: FileDialogConfig,
    confirm_overwrite: bool = true,

    pub fn init(config: FileDialogConfig) SaveFileDialog {
        return .{ .config = config };
    }

    pub fn show(self: *SaveFileDialog) ?[]const u8 {
        _ = self;
        // Simulated for testing
        return null;
    }
};

/// Directory dialog
pub const DirectoryDialog = struct {
    title: []const u8 = "Select Directory",
    initial_dir: []const u8 = "",
    must_exist: bool = true,
    parent: ?*anyopaque = null,

    pub fn init() DirectoryDialog {
        return .{};
    }

    pub fn show(self: *DirectoryDialog) ?[]const u8 {
        _ = self;
        return null;
    }
};

/// RGB color value
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toHex(self: RGBColor) [7]u8 {
        var buf: [7]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch unreachable;
        return buf;
    }

    pub fn fromHex(hex: []const u8) ?RGBColor {
        if (hex.len != 7 or hex[0] != '#') return null;
        const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return null;
        const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return null;
        const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return null;
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn toTclString(self: RGBColor, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch "";
    }

    pub fn eql(self: RGBColor, other: RGBColor) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }
};

/// Color chooser dialog
pub const ColorChooser = struct {
    title: []const u8 = "Choose Color",
    initial_color: ?RGBColor = null,
    parent: ?*anyopaque = null,
    selected_color: ?RGBColor = null,

    pub fn init() ColorChooser {
        return .{};
    }

    pub fn withInitialColor(color: RGBColor) ColorChooser {
        return .{ .initial_color = color };
    }

    pub fn show(self: *ColorChooser) ?RGBColor {
        // Simulated - return initial color or a default
        if (self.initial_color) |color| {
            self.selected_color = color;
            return color;
        }
        self.selected_color = .{ .r = 255, .g = 0, .b = 0 };
        return self.selected_color;
    }
};

/// Input dialog for simple text input
pub const InputDialog = struct {
    title: []const u8 = "Input",
    prompt: []const u8 = "Enter value:",
    initial_value: []const u8 = "",
    show_password: bool = false,
    min_length: usize = 0,
    max_length: usize = 1024,
    result: ?[]const u8 = null,

    pub fn init(prompt: []const u8) InputDialog {
        return .{ .prompt = prompt };
    }

    pub fn show(self: *InputDialog) ?[]const u8 {
        if (self.initial_value.len > 0) {
            self.result = self.initial_value;
            return self.initial_value;
        }
        return null;
    }

    pub fn askString(title: []const u8, prompt: []const u8) ?[]const u8 {
        var dialog = InputDialog{
            .title = title,
            .prompt = prompt,
        };
        return dialog.show();
    }

    pub fn askInteger(title: []const u8, prompt: []const u8) ?i64 {
        var dialog = InputDialog{
            .title = title,
            .prompt = prompt,
        };
        const result = dialog.show() orelse return null;
        return std.fmt.parseInt(i64, result, 10) catch null;
    }

    pub fn askFloat(title: []const u8, prompt: []const u8) ?f64 {
        var dialog = InputDialog{
            .title = title,
            .prompt = prompt,
        };
        const result = dialog.show() orelse return null;
        return std.fmt.parseFloat(f64, result) catch null;
    }
};

/// Custom dialog builder
pub const CustomDialog = struct {
    title: []const u8,
    width: u32 = 300,
    height: u32 = 200,
    modal: bool = true,
    resizable: bool = false,
    buttons: std.ArrayList(DialogButton),
    widgets: std.ArrayList(DialogWidget),
    allocator: Allocator,
    result: DialogResult = .none,

    pub const DialogButton = struct {
        text: []const u8,
        result: DialogResult,
        is_default: bool = false,
        is_cancel: bool = false,
    };

    pub const DialogWidget = struct {
        widget_type: WidgetType,
        name: []const u8,
        label: []const u8 = "",
        value: []const u8 = "",

        pub const WidgetType = enum {
            label,
            entry,
            text,
            checkbutton,
            radiobutton,
            combobox,
            spinbox,
            separator,
        };
    };

    pub fn init(allocator: Allocator, title: []const u8) CustomDialog {
        return .{
            .title = title,
            .buttons = std.ArrayList(DialogButton).init(allocator),
            .widgets = std.ArrayList(DialogWidget).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CustomDialog) void {
        self.buttons.deinit();
        self.widgets.deinit();
    }

    pub fn addButton(self: *CustomDialog, text: []const u8, result: DialogResult) !void {
        try self.buttons.append(.{ .text = text, .result = result });
    }

    pub fn addDefaultButton(self: *CustomDialog, text: []const u8, result: DialogResult) !void {
        try self.buttons.append(.{ .text = text, .result = result, .is_default = true });
    }

    pub fn addCancelButton(self: *CustomDialog, text: []const u8) !void {
        try self.buttons.append(.{ .text = text, .result = .cancel, .is_cancel = true });
    }

    pub fn addLabel(self: *CustomDialog, name: []const u8, text: []const u8) !void {
        try self.widgets.append(.{
            .widget_type = .label,
            .name = name,
            .label = text,
        });
    }

    pub fn addEntry(self: *CustomDialog, name: []const u8, label: []const u8) !void {
        try self.widgets.append(.{
            .widget_type = .entry,
            .name = name,
            .label = label,
        });
    }

    pub fn addCheckbutton(self: *CustomDialog, name: []const u8, label: []const u8) !void {
        try self.widgets.append(.{
            .widget_type = .checkbutton,
            .name = name,
            .label = label,
        });
    }

    pub fn setSize(self: *CustomDialog, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
    }

    pub fn setModal(self: *CustomDialog, modal: bool) void {
        self.modal = modal;
    }

    pub fn setResizable(self: *CustomDialog, resizable: bool) void {
        self.resizable = resizable;
    }

    pub fn show(self: *CustomDialog) DialogResult {
        // Simulated - return first button's result or cancel
        if (self.buttons.items.len > 0) {
            self.result = self.buttons.items[0].result;
        } else {
            self.result = .cancel;
        }
        return self.result;
    }

    pub fn getWidgetValue(self: *CustomDialog, name: []const u8) ?[]const u8 {
        for (self.widgets.items) |widget| {
            if (std.mem.eql(u8, widget.name, name)) {
                return widget.value;
            }
        }
        return null;
    }
};

/// Font chooser dialog
pub const FontChooser = struct {
    title: []const u8 = "Select Font",
    initial_font: ?[]const u8 = null,
    selected_font: ?[]const u8 = null,
    preview_text: []const u8 = "AaBbCcDdEeFf",

    pub fn init() FontChooser {
        return .{};
    }

    pub fn withInitialFont(font: []const u8) FontChooser {
        return .{ .initial_font = font };
    }

    pub fn show(self: *FontChooser) ?[]const u8 {
        if (self.initial_font) |font| {
            self.selected_font = font;
            return font;
        }
        self.selected_font = "TkDefaultFont";
        return self.selected_font;
    }
};

/// Progress dialog for long operations
pub const ProgressDialog = struct {
    title: []const u8 = "Progress",
    message: []const u8 = "Please wait...",
    maximum: u32 = 100,
    current: u32 = 0,
    is_determinate: bool = true,
    is_canceled: bool = false,
    cancel_button: bool = true,

    pub fn init(title: []const u8) ProgressDialog {
        return .{ .title = title };
    }

    pub fn update(self: *ProgressDialog, value: u32) void {
        self.current = @min(value, self.maximum);
    }

    pub fn updateMessage(self: *ProgressDialog, message: []const u8) void {
        self.message = message;
    }

    pub fn increment(self: *ProgressDialog, amount: u32) void {
        self.current = @min(self.current + amount, self.maximum);
    }

    pub fn getProgress(self: *ProgressDialog) f64 {
        if (self.maximum == 0) return 0.0;
        return @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.maximum));
    }

    pub fn isComplete(self: *ProgressDialog) bool {
        return self.current >= self.maximum;
    }

    pub fn cancel(self: *ProgressDialog) void {
        self.is_canceled = true;
    }

    pub fn close(self: *ProgressDialog) void {
        self.current = self.maximum;
    }
};

// Tests

test "IconType conversion" {
    try testing.expectEqualStrings("info", IconType.info.toTclString());
    try testing.expectEqualStrings("warning", IconType.warning.toTclString());
    try testing.expectEqualStrings("error", IconType.@"error".toTclString());
    try testing.expectEqualStrings("question", IconType.question.toTclString());
}

test "ButtonType properties" {
    try testing.expectEqual(@as(usize, 1), ButtonType.ok.buttonCount());
    try testing.expectEqual(@as(usize, 2), ButtonType.ok_cancel.buttonCount());
    try testing.expectEqual(@as(usize, 2), ButtonType.yes_no.buttonCount());
    try testing.expectEqual(@as(usize, 3), ButtonType.yes_no_cancel.buttonCount());
    try testing.expectEqualStrings("okcancel", ButtonType.ok_cancel.toTclString());
}

test "DialogResult parsing" {
    try testing.expectEqual(DialogResult.ok, DialogResult.fromString("ok"));
    try testing.expectEqual(DialogResult.cancel, DialogResult.fromString("cancel"));
    try testing.expectEqual(DialogResult.yes, DialogResult.fromString("yes"));
    try testing.expectEqual(DialogResult.no, DialogResult.fromString("no"));
    try testing.expectEqual(DialogResult.none, DialogResult.fromString("unknown"));
}

test "MessageBox creation and show" {
    var box = MessageBox.init(.{
        .title = "Test",
        .message = "Hello",
        .icon = .info,
        .buttons = .ok,
    });
    const result = box.show();
    try testing.expect(box.is_shown);
    try testing.expectEqual(DialogResult.ok, result);
}

test "MessageBox convenience methods" {
    try testing.expectEqual(DialogResult.ok, MessageBox.showInfo("Info", "Test"));
    try testing.expectEqual(DialogResult.ok, MessageBox.showWarning("Warning", "Test"));
    try testing.expectEqual(DialogResult.ok, MessageBox.showError("Error", "Test"));
    try testing.expectEqual(DialogResult.yes, MessageBox.askQuestion("Question", "Test?"));
    try testing.expectEqual(DialogResult.ok, MessageBox.askOkCancel("Confirm", "OK?"));
}

test "MessageBoxConfig Tcl args" {
    const allocator = testing.allocator;
    const config = MessageBoxConfig{
        .title = "Test Title",
        .message = "Test Message",
        .icon = .warning,
        .buttons = .yes_no,
    };
    const args = try config.toTclArgs(allocator);
    defer allocator.free(args);

    try testing.expect(std.mem.indexOf(u8, args, "Test Title") != null);
    try testing.expect(std.mem.indexOf(u8, args, "warning") != null);
    try testing.expect(std.mem.indexOf(u8, args, "yesno") != null);
}

test "FileType Tcl list" {
    const allocator = testing.allocator;
    const file_type = FileType{
        .name = "Python Files",
        .patterns = &.{ "*.py", "*.pyw" },
    };
    const tcl_list = try file_type.toTclList(allocator);
    defer allocator.free(tcl_list);

    try testing.expect(std.mem.indexOf(u8, tcl_list, "Python Files") != null);
    try testing.expect(std.mem.indexOf(u8, tcl_list, "*.py") != null);
}

test "OpenFileDialog basic" {
    const allocator = testing.allocator;
    var dialog = OpenFileDialog.init(allocator, .{
        .title = "Open",
        .initial_file = "test.txt",
    });
    defer dialog.deinit();

    const result = dialog.show();
    try testing.expect(result != null);
    try testing.expectEqualStrings("test.txt", result.?);
}

test "SaveFileDialog basic" {
    var dialog = SaveFileDialog.init(.{
        .title = "Save",
        .default_extension = ".txt",
    });
    try testing.expect(dialog.confirm_overwrite);
}

test "DirectoryDialog basic" {
    var dialog = DirectoryDialog.init();
    try testing.expect(dialog.must_exist);
    try testing.expectEqualStrings("Select Directory", dialog.title);
}

test "RGBColor hex conversion" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const hex = red.toHex();
    try testing.expectEqualStrings("#ff0000", &hex);

    const parsed = RGBColor.fromHex("#00ff00");
    try testing.expect(parsed != null);
    try testing.expectEqual(@as(u8, 0), parsed.?.r);
    try testing.expectEqual(@as(u8, 255), parsed.?.g);
    try testing.expectEqual(@as(u8, 0), parsed.?.b);
}

test "RGBColor equality" {
    const c1 = RGBColor{ .r = 128, .g = 64, .b = 32 };
    const c2 = RGBColor{ .r = 128, .g = 64, .b = 32 };
    const c3 = RGBColor{ .r = 128, .g = 64, .b = 33 };

    try testing.expect(c1.eql(c2));
    try testing.expect(!c1.eql(c3));
}

test "ColorChooser" {
    var chooser = ColorChooser.withInitialColor(.{ .r = 100, .g = 150, .b = 200 });
    const result = chooser.show();

    try testing.expect(result != null);
    try testing.expectEqual(@as(u8, 100), result.?.r);
    try testing.expectEqual(@as(u8, 150), result.?.g);
    try testing.expectEqual(@as(u8, 200), result.?.b);
}

test "InputDialog basic" {
    var dialog = InputDialog.init("Enter name:");
    dialog.initial_value = "test value";
    const result = dialog.show();

    try testing.expect(result != null);
    try testing.expectEqualStrings("test value", result.?);
}

test "CustomDialog builder" {
    const allocator = testing.allocator;
    var dialog = CustomDialog.init(allocator, "Settings");
    defer dialog.deinit();

    try dialog.addLabel("lbl1", "Enter your name:");
    try dialog.addEntry("name", "Name:");
    try dialog.addCheckbutton("remember", "Remember me");
    try dialog.addDefaultButton("OK", .ok);
    try dialog.addCancelButton("Cancel");

    dialog.setSize(400, 300);
    dialog.setModal(true);
    dialog.setResizable(false);

    try testing.expectEqual(@as(u32, 400), dialog.width);
    try testing.expectEqual(@as(u32, 300), dialog.height);
    try testing.expect(dialog.modal);
    try testing.expect(!dialog.resizable);
    try testing.expectEqual(@as(usize, 3), dialog.widgets.items.len);
    try testing.expectEqual(@as(usize, 2), dialog.buttons.items.len);
}

test "CustomDialog show" {
    const allocator = testing.allocator;
    var dialog = CustomDialog.init(allocator, "Test");
    defer dialog.deinit();

    try dialog.addDefaultButton("OK", .ok);
    const result = dialog.show();
    try testing.expectEqual(DialogResult.ok, result);
}

test "FontChooser" {
    var chooser = FontChooser.withInitialFont("Helvetica 12 bold");
    const result = chooser.show();

    try testing.expect(result != null);
    try testing.expectEqualStrings("Helvetica 12 bold", result.?);
}

test "ProgressDialog operations" {
    var dialog = ProgressDialog.init("Loading");
    dialog.maximum = 100;

    dialog.update(25);
    try testing.expectEqual(@as(u32, 25), dialog.current);
    try testing.expect(!dialog.isComplete());

    dialog.increment(25);
    try testing.expectEqual(@as(u32, 50), dialog.current);

    const progress = dialog.getProgress();
    try testing.expect(progress > 0.49 and progress < 0.51);

    dialog.update(100);
    try testing.expect(dialog.isComplete());
}

test "ProgressDialog cancel" {
    var dialog = ProgressDialog.init("Downloading");
    try testing.expect(!dialog.is_canceled);

    dialog.cancel();
    try testing.expect(dialog.is_canceled);
}

test "FileDialogConfig defaults" {
    const types = FileDialogConfig.defaultFileTypes();
    try testing.expectEqual(@as(usize, 3), types.len);
    try testing.expectEqualStrings("All Files", types[0].name);
    try testing.expectEqualStrings("Text Files", types[1].name);
    try testing.expectEqualStrings("Python Files", types[2].name);
}
