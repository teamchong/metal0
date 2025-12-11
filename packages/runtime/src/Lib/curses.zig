//! Python 'curses' module - Terminal handling for character-cell displays
//!
//! Provides an interface to the curses library for terminal control.
//!
//! Mirrors: CPython Lib/curses/
//!
//! Module Structure:
//! - types.zig - Error types and constants (colors, attributes, keys)
//! - window.zig - Window struct and operations
//! - screen.zig - Screen initialization and management
//! - terminal.zig - Terminal mode control (echo, cbreak, raw)
//! - color.zig - Color support functions
//! - utils.zig - Utility functions (cursor, beep, flash)

// Re-export all public APIs
pub const types = @import("curses/types.zig");
pub const window = @import("curses/window.zig");
pub const screen = @import("curses/screen.zig");
pub const terminal = @import("curses/terminal.zig");
pub const color = @import("curses/color.zig");
pub const utils = @import("curses/utils.zig");

// Re-export commonly used types and constants
pub const CursesError = types.CursesError;
pub const Window = window.Window;

// Color constants
pub const COLOR_BLACK = types.COLOR_BLACK;
pub const COLOR_RED = types.COLOR_RED;
pub const COLOR_GREEN = types.COLOR_GREEN;
pub const COLOR_YELLOW = types.COLOR_YELLOW;
pub const COLOR_BLUE = types.COLOR_BLUE;
pub const COLOR_MAGENTA = types.COLOR_MAGENTA;
pub const COLOR_CYAN = types.COLOR_CYAN;
pub const COLOR_WHITE = types.COLOR_WHITE;

// Attribute constants
pub const A_NORMAL = types.A_NORMAL;
pub const A_STANDOUT = types.A_STANDOUT;
pub const A_UNDERLINE = types.A_UNDERLINE;
pub const A_REVERSE = types.A_REVERSE;
pub const A_BLINK = types.A_BLINK;
pub const A_DIM = types.A_DIM;
pub const A_BOLD = types.A_BOLD;
pub const A_ALTCHARSET = types.A_ALTCHARSET;
pub const A_INVIS = types.A_INVIS;
pub const A_PROTECT = types.A_PROTECT;

// Key constants
pub const KEY_DOWN = types.KEY_DOWN;
pub const KEY_UP = types.KEY_UP;
pub const KEY_LEFT = types.KEY_LEFT;
pub const KEY_RIGHT = types.KEY_RIGHT;
pub const KEY_HOME = types.KEY_HOME;
pub const KEY_BACKSPACE = types.KEY_BACKSPACE;
pub const KEY_F0 = types.KEY_F0;
pub const KEY_DC = types.KEY_DC;
pub const KEY_IC = types.KEY_IC;
pub const KEY_NPAGE = types.KEY_NPAGE;
pub const KEY_PPAGE = types.KEY_PPAGE;
pub const KEY_END = types.KEY_END;
pub const KEY_ENTER = types.KEY_ENTER;
pub const KEY_F = types.KEY_F;

// Screen management
pub const initscr = screen.initscr;
pub const endwin = screen.endwin;
pub const isendwin = screen.isendwin;
pub const newwin = screen.newwin;
pub const delwin = screen.delwin;

// Terminal modes
pub const echo = terminal.echo;
pub const noecho = terminal.noecho;
pub const cbreak = terminal.cbreak;
pub const nocbreak = terminal.nocbreak;
pub const raw = terminal.raw;
pub const noraw = terminal.noraw;

// Color support
pub const has_colors = color.has_colors;
pub const start_color = color.start_color;
pub const init_pair = color.init_pair;
pub const color_pair = color.color_pair;

// Utilities
pub const curs_set = utils.curs_set;
pub const beep = utils.beep;
pub const flash = utils.flash;

// Module lifecycle
pub const init = screen.init;
pub const reset = screen.reset;
