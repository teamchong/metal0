//! Python 'tkinter' module - Tk GUI toolkit interface
//!
//! Python interface to Tcl/Tk for building graphical user interfaces.
//!
//! Mirrors: CPython Lib/tkinter/
//!
//! Module structure:
//! - types: Error types, constants, and option values
//! - widget: Base Widget class with configuration and geometry management
//! - root: Tk root window with event loop
//! - basic_widgets: Label, Button, Entry
//! - container_widgets: Frame, Text, Canvas
//! - dialogs: messagebox and filedialog
//! - state: Module initialization and availability

const std = @import("std");

// Re-export submodules
pub const types = @import("tkinter/types.zig");
pub const widget = @import("tkinter/widget.zig");
pub const root = @import("tkinter/root.zig");
pub const basic_widgets = @import("tkinter/basic_widgets.zig");
pub const container_widgets = @import("tkinter/container_widgets.zig");
pub const dialogs = @import("tkinter/dialogs.zig");
pub const state = @import("tkinter/state.zig");

// Re-export types for convenience
pub const TkError = types.TkError;
pub const OptionValue = types.OptionValue;
pub const Widget = widget.Widget;
pub const Tk = root.Tk;
pub const Label = basic_widgets.Label;
pub const Button = basic_widgets.Button;
pub const Entry = basic_widgets.Entry;
pub const Frame = container_widgets.Frame;
pub const Text = container_widgets.Text;
pub const Canvas = container_widgets.Canvas;
pub const messagebox = dialogs.messagebox;
pub const filedialog = dialogs.filedialog;

// Re-export constants
pub const YES = types.YES;
pub const NO = types.NO;
pub const TRUE = types.TRUE;
pub const FALSE = types.FALSE;
pub const ON = types.ON;
pub const OFF = types.OFF;
pub const N = types.N;
pub const NE = types.NE;
pub const E = types.E;
pub const SE = types.SE;
pub const S = types.S;
pub const SW = types.SW;
pub const W = types.W;
pub const NW = types.NW;
pub const CENTER = types.CENTER;
pub const NONE = types.NONE;
pub const X = types.X;
pub const Y = types.Y;
pub const BOTH = types.BOTH;
pub const LEFT = types.LEFT;
pub const TOP = types.TOP;
pub const RIGHT = types.RIGHT;
pub const BOTTOM = types.BOTTOM;
pub const RAISED = types.RAISED;
pub const SUNKEN = types.SUNKEN;
pub const FLAT = types.FLAT;
pub const RIDGE = types.RIDGE;
pub const GROOVE = types.GROOVE;
pub const SOLID = types.SOLID;
pub const NORMAL = types.NORMAL;
pub const DISABLED = types.DISABLED;
pub const ACTIVE = types.ACTIVE;
pub const HIDDEN = types.HIDDEN;
pub const SINGLE = types.SINGLE;
pub const BROWSE = types.BROWSE;
pub const MULTIPLE = types.MULTIPLE;
pub const EXTENDED = types.EXTENDED;
pub const CHAR = types.CHAR;
pub const WORD = types.WORD;
pub const INSERT = types.INSERT;
pub const CURRENT = types.CURRENT;
pub const END = types.END;
pub const SEL = types.SEL;
pub const SEL_FIRST = types.SEL_FIRST;
pub const SEL_LAST = types.SEL_LAST;

// Re-export state functions
pub const init = state.init;
pub const reset = state.reset;
pub const isTkAvailable = state.isTkAvailable;

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqualStrings("n", N);
    try std.testing.expectEqualStrings("center", CENTER);
    try std.testing.expectEqualStrings("raised", RAISED);
    try std.testing.expectEqualStrings("normal", NORMAL);
}

test "Widget init" {
    const allocator = std.testing.allocator;
    var w = Widget.init(allocator, "test");
    defer w.deinit();

    try std.testing.expectEqualStrings("test", w.name);
}

test "Tk init" {
    const allocator = std.testing.allocator;
    var tk = Tk.init(allocator);
    defer tk.deinit();

    tk.title("Test Window");
    try std.testing.expectEqualStrings("Test Window", tk.title_text);
}

test "Entry" {
    const allocator = std.testing.allocator;
    var entry = Entry.init(allocator, null);
    defer entry.deinit();

    try entry.insert(0, "hello");
    try std.testing.expectEqualStrings("hello", entry.get());
}

test "isTkAvailable" {
    try std.testing.expect(!isTkAvailable());
}
