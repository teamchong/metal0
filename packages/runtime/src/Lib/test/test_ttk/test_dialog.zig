//! test.test_ttk.test_dialog - Tk dialog tests
const std = @import("std");

/// Dialog button types
pub const DialogButton = enum {
    ok,
    cancel,
    yes,
    no,
    retry,
    abort,
    ignore,

    pub fn toString(self: DialogButton) []const u8 {
        return switch (self) {
            .ok => "OK",
            .cancel => "Cancel",
            .yes => "Yes",
            .no => "No",
            .retry => "Retry",
            .abort => "Abort",
            .ignore => "Ignore",
        };
    }
};

/// Message box icons
pub const MessageIcon = enum {
    info,
    warning,
    @"error",
    question,

    pub fn toString(self: MessageIcon) []const u8 {
        return switch (self) {
            .info => "info",
            .warning => "warning",
            .@"error" => "error",
            .question => "question",
        };
    }
};

/// Message box button configurations
pub const MessageBoxType = enum {
    ok,
    okcancel,
    yesno,
    yesnocancel,
    retrycancel,
    abortretryignore,

    pub fn buttons(self: MessageBoxType) []const DialogButton {
        return switch (self) {
            .ok => &[_]DialogButton{.ok},
            .okcancel => &[_]DialogButton{ .ok, .cancel },
            .yesno => &[_]DialogButton{ .yes, .no },
            .yesnocancel => &[_]DialogButton{ .yes, .no, .cancel },
            .retrycancel => &[_]DialogButton{ .retry, .cancel },
            .abortretryignore => &[_]DialogButton{ .abort, .retry, .ignore },
        };
    }
};

/// Message box configuration
pub const MessageBoxOptions = struct {
    title: []const u8 = "",
    message: []const u8 = "",
    detail: ?[]const u8 = null,
    icon: MessageIcon = .info,
    box_type: MessageBoxType = .ok,
    default: ?DialogButton = null,
    parent: ?u32 = null,
};

/// Message box result
pub const MessageBoxResult = struct {
    button: DialogButton,

    pub fn isOk(self: MessageBoxResult) bool {
        return self.button == .ok;
    }

    pub fn isYes(self: MessageBoxResult) bool {
        return self.button == .yes;
    }

    pub fn isCancelled(self: MessageBoxResult) bool {
        return self.button == .cancel;
    }
};

/// File dialog file type filter
pub const FileType = struct {
    name: []const u8,
    patterns: []const []const u8,

    pub fn init(name: []const u8, patterns: []const []const u8) FileType {
        return .{ .name = name, .patterns = patterns };
    }
};

/// Open file dialog options
pub const OpenFileOptions = struct {
    title: []const u8 = "Open",
    initial_dir: ?[]const u8 = null,
    initial_file: ?[]const u8 = null,
    file_types: ?[]const FileType = null,
    default_extension: ?[]const u8 = null,
    multiple: bool = false,
    parent: ?u32 = null,
};

/// Save file dialog options
pub const SaveFileOptions = struct {
    title: []const u8 = "Save As",
    initial_dir: ?[]const u8 = null,
    initial_file: ?[]const u8 = null,
    file_types: ?[]const FileType = null,
    default_extension: ?[]const u8 = null,
    confirm_overwrite: bool = true,
    parent: ?u32 = null,
};

/// Directory chooser options
pub const DirectoryOptions = struct {
    title: []const u8 = "Select Directory",
    initial_dir: ?[]const u8 = null,
    must_exist: bool = true,
    parent: ?u32 = null,
};

/// Color chooser options
pub const ColorOptions = struct {
    title: []const u8 = "Select Color",
    initial_color: ?[]const u8 = null,
    parent: ?u32 = null,
};

/// Color chooser result
pub const ColorResult = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toHex(self: ColorResult) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn toString(self: ColorResult, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
    }
};

/// Dialog base
pub const Dialog = struct {
    title: []const u8,
    width: u32 = 300,
    height: u32 = 200,
    modal: bool = true,
    resizable: bool = false,
    result: ?DialogButton = null,

    pub fn init(title: []const u8) Dialog {
        return .{ .title = title };
    }

    pub fn show(self: *Dialog) void {
        // Simulated dialog display
        _ = self;
    }

    pub fn close(self: *Dialog, button: DialogButton) void {
        self.result = button;
    }

    pub fn getResult(self: *const Dialog) ?DialogButton {
        return self.result;
    }
};

/// Input dialog
pub const InputDialog = struct {
    title: []const u8,
    prompt: []const u8,
    default_value: []const u8 = "",
    show_chars: bool = true,
    result: ?[]const u8 = null,

    pub fn init(title: []const u8, prompt: []const u8) InputDialog {
        return .{ .title = title, .prompt = prompt };
    }

    pub fn getValue(self: *const InputDialog) ?[]const u8 {
        return self.result;
    }
};

/// Simulate showing message box (returns default button)
pub fn showMessageBox(options: MessageBoxOptions) MessageBoxResult {
    const buttons = options.box_type.buttons();
    const default = options.default orelse buttons[0];
    return .{ .button = default };
}

test "DialogButton toString" {
    try std.testing.expectEqualStrings("OK", DialogButton.ok.toString());
    try std.testing.expectEqualStrings("Cancel", DialogButton.cancel.toString());
    try std.testing.expectEqualStrings("Yes", DialogButton.yes.toString());
}

test "MessageIcon toString" {
    try std.testing.expectEqualStrings("info", MessageIcon.info.toString());
    try std.testing.expectEqualStrings("warning", MessageIcon.warning.toString());
}

test "MessageBoxType buttons" {
    const okcancel = MessageBoxType.okcancel.buttons();
    try std.testing.expectEqual(@as(usize, 2), okcancel.len);
    try std.testing.expectEqual(DialogButton.ok, okcancel[0]);
    try std.testing.expectEqual(DialogButton.cancel, okcancel[1]);

    const yesnocancel = MessageBoxType.yesnocancel.buttons();
    try std.testing.expectEqual(@as(usize, 3), yesnocancel.len);
}

test "MessageBoxResult" {
    const ok_result = MessageBoxResult{ .button = .ok };
    try std.testing.expect(ok_result.isOk());
    try std.testing.expect(!ok_result.isYes());

    const yes_result = MessageBoxResult{ .button = .yes };
    try std.testing.expect(yes_result.isYes());

    const cancel_result = MessageBoxResult{ .button = .cancel };
    try std.testing.expect(cancel_result.isCancelled());
}

test "FileType" {
    const patterns = [_][]const u8{ "*.txt", "*.text" };
    const ft = FileType.init("Text Files", &patterns);
    try std.testing.expectEqualStrings("Text Files", ft.name);
    try std.testing.expectEqual(@as(usize, 2), ft.patterns.len);
}

test "ColorResult" {
    const color = ColorResult{ .r = 255, .g = 128, .b = 64 };
    try std.testing.expectEqual(@as(u32, 0xFF8040), color.toHex());

    var buf: [8]u8 = undefined;
    const hex = try color.toString(&buf);
    try std.testing.expectEqualStrings("#ff8040", hex);
}

test "Dialog" {
    var dialog = Dialog.init("Test Dialog");
    try std.testing.expectEqualStrings("Test Dialog", dialog.title);
    try std.testing.expect(dialog.modal);
    try std.testing.expect(dialog.getResult() == null);

    dialog.close(.ok);
    try std.testing.expectEqual(DialogButton.ok, dialog.getResult().?);
}

test "InputDialog" {
    const input = InputDialog.init("Input", "Enter value:");
    try std.testing.expectEqualStrings("Input", input.title);
    try std.testing.expectEqualStrings("Enter value:", input.prompt);
    try std.testing.expect(input.getValue() == null);
}

test "showMessageBox" {
    const result = showMessageBox(.{
        .title = "Test",
        .message = "Hello",
        .box_type = .yesno,
    });
    try std.testing.expectEqual(DialogButton.yes, result.button);
}

test "OpenFileOptions defaults" {
    const opts = OpenFileOptions{};
    try std.testing.expectEqualStrings("Open", opts.title);
    try std.testing.expect(!opts.multiple);
}

test "SaveFileOptions defaults" {
    const opts = SaveFileOptions{};
    try std.testing.expectEqualStrings("Save As", opts.title);
    try std.testing.expect(opts.confirm_overwrite);
}
