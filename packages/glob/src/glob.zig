// Glob Pattern Matching
//
// Portions of this file are derived from works under the MIT License:
//
// Copyright (c) 2023 Devon Govett
// Copyright (c) 2023 Stephen Gregoratto
// Copyright (c) 2024 shulaoda
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

const std = @import("std");
const ds = @import("ds");
const BoundedArray = ds.BoundedArray;

const Brace = struct {
    open_brace_idx: u32,
    branch_idx: u32,
};
const BraceStack = BoundedArray(Brace, 10);

pub const MatchResult = enum {
    no_match,
    match,
    negate_no_match,
    negate_match,

    pub fn matches(this: MatchResult) bool {
        return this == .match or this == .negate_match;
    }
};

const State = struct {
    path_index: u32 = 0,
    glob_index: u32 = 0,
    wildcard: Wildcard = .{},
    globstar: Wildcard = .{},
    brace_depth: u8 = 0,

    inline fn backtrack(self: *State) void {
        self.path_index = self.wildcard.path_index;
        self.glob_index = self.wildcard.glob_index;
        self.brace_depth = self.wildcard.brace_depth;
    }

    inline fn skipToSeparator(self: *State, path: []const u8, is_end_invalid: bool) void {
        if (self.path_index == path.len) {
            self.wildcard.path_index += 1;
            return;
        }

        var path_index = self.path_index;
        while (path_index < path.len and !isSeparator(path[path_index])) {
            path_index += 1;
        }

        if (is_end_invalid or path_index != path.len) {
            path_index += 1;
        }

        self.wildcard.path_index = path_index;
        self.globstar = self.wildcard;
    }
};

const Wildcard = struct {
    glob_index: u32 = 0,
    path_index: u32 = 0,
    brace_depth: u8 = 0,
};

/// Match a path against a glob pattern.
///
/// The supported pattern syntax for `glob` is:
///
/// "?"
///     Matches any single character.
/// "*"
///     Matches zero or more characters, except for path separators ('/' or '\').
/// "**"
///     Matches zero or more characters, including path separators.
///     Must match a complete path segment, i.e. followed by a path separator or
///     at the end of the pattern.
/// "[ab]"
///     Matches one of the characters contained in the brackets.
///     Character ranges (e.g. "[a-z]") are also supported.
///     Use "[!ab]" or "[^ab]" to match any character *except* those contained
///     in the brackets.
/// "{a,b}"
///     Match one of the patterns contained in the braces.
///     Any of the wildcards listed above can be used in the sub patterns.
///     Braces may be nested up to 10 levels deep.
/// "!"
///     Negates the result when at the start of the pattern.
///     Multiple "!" characters negate the pattern multiple times.
/// "\"
///     Used to escape any of the special characters above.
pub fn match(glob: []const u8, path: []const u8) MatchResult {
    var state = State{};

    var negated = false;
    while (state.glob_index < glob.len and glob[state.glob_index] == '!') {
        negated = !negated;
        state.glob_index += 1;
    }

    var brace_stack = BraceStack.init(0) catch unreachable;
    const matched = globMatchImpl(&state, glob, 0, path, &brace_stack);

    if (negated) {
        return if (matched) .negate_no_match else .negate_match;
    } else {
        return if (matched) .match else .no_match;
    }
}

/// Convenience function returning bool
pub fn isMatch(glob: []const u8, path: []const u8) bool {
    return match(glob, path).matches();
}

inline fn globMatchImpl(state: *State, glob: []const u8, glob_start: u32, path: []const u8, brace_stack: *BraceStack) bool {
    main_loop: while (state.glob_index < glob.len or state.path_index < path.len) {
        if (state.glob_index < glob.len) fallthrough: {
            const char = glob[state.glob_index];
            to_else: {
                switch (char) {
                    '*' => {
                        const is_globstar =
                            state.glob_index + 1 < glob.len and glob[state.glob_index + 1] == '*';
                        if (is_globstar) {
                            skipGlobstars(glob, &state.glob_index);
                        }

                        state.wildcard.glob_index = state.glob_index;
                        state.wildcard.path_index = state.path_index + if (state.path_index < path.len) (std.unicode.utf8ByteSequenceLength(path[state.path_index]) catch 1) else 1;
                        state.wildcard.brace_depth = state.brace_depth;

                        var in_globstar = false;
                        if (is_globstar) {
                            state.glob_index += 2;

                            const is_end_invalid = state.glob_index < glob.len;

                            if (is_end_invalid and state.path_index == path.len and glob.len - state.glob_index == 2 and isSeparator(glob[state.glob_index]) and glob[state.glob_index + 1] == '*') {
                                continue;
                            }

                            if ((state.glob_index -| glob_start < 3 or glob[state.glob_index - 3] == '/') and (!is_end_invalid or glob[state.glob_index] == '/')) {
                                if (is_end_invalid) {
                                    state.glob_index += 1;
                                }

                                state.skipToSeparator(path, is_end_invalid);
                                in_globstar = true;
                            }
                        } else {
                            state.glob_index += 1;
                        }

                        if (!in_globstar and state.path_index < path.len and isSeparator(path[state.path_index])) {
                            state.wildcard = state.globstar;
                        }

                        continue;
                    },
                    '?' => if (state.path_index < path.len) {
                        if (!isSeparator(path[state.path_index])) {
                            state.glob_index += 1;
                            state.path_index += std.unicode.utf8ByteSequenceLength(path[state.path_index]) catch 1;
                            continue;
                        }
                        break :fallthrough;
                    } else break :to_else,
                    '[' => if (state.path_index < path.len) {
                        state.glob_index += 1;

                        var negated = false;
                        if (state.glob_index < glob.len and (glob[state.glob_index] == '^' or glob[state.glob_index] == '!')) {
                            negated = true;
                            state.glob_index += 1;
                        }

                        var first = true;
                        var is_match = false;

                        const len = std.unicode.utf8ByteSequenceLength(path[state.path_index]) catch 1;
                        const c = std.unicode.utf8Decode(path[state.path_index..][0..len]) catch 0xFFFD;

                        while (state.glob_index < glob.len and (first or glob[state.glob_index] != ']')) {
                            var low: u32 = glob[state.glob_index];
                            var low_len: u8 = 1;
                            if (!getUnicode(&low, &low_len, glob, &state.glob_index)) {
                                return false;
                            }

                            state.glob_index += low_len;

                            const high = if (state.glob_index + 1 < glob.len and glob[state.glob_index] == '-' and glob[state.glob_index + 1] != ']') blk: {
                                state.glob_index += 1;

                                var high: u32 = glob[state.glob_index];
                                var high_len: u8 = 1;
                                if (!getUnicode(&high, &high_len, glob, &state.glob_index)) {
                                    return false;
                                }

                                state.glob_index += high_len;
                                break :blk high;
                            } else low;

                            if (low <= c and c <= high) {
                                is_match = true;
                            }

                            first = false;
                        }

                        if (state.glob_index >= glob.len) {
                            return false;
                        }

                        state.glob_index += 1;
                        if (is_match != negated) {
                            state.path_index += len;
                            continue;
                        }
                        break :fallthrough;
                    } else break :to_else,
                    '{' => {
                        for (brace_stack.slice()) |brace| {
                            if (brace.open_brace_idx == state.glob_index) {
                                state.glob_index = brace.branch_idx;
                                state.brace_depth += 1;
                                continue :main_loop;
                            }
                        }
                        return matchBrace(state, glob, path, brace_stack);
                    },
                    ',' => if (state.brace_depth > 0) {
                        skipBranch(state, glob);
                        continue;
                    } else break :to_else,
                    '}' => if (state.brace_depth > 0) {
                        skipBranch(state, glob);
                        continue;
                    } else break :to_else,
                    else => break :to_else,
                }
            }
            if (state.path_index < path.len) {
                var cc: u8 = char;
                if (!unescape(&cc, glob, &state.glob_index)) {
                    return false;
                }
                const cc_len = std.unicode.utf8ByteSequenceLength(cc) catch 1;

                const is_match = if (cc == '/')
                    isSeparator(path[state.path_index])
                else if (cc_len > 1)
                    state.path_index + cc_len <= path.len and std.mem.eql(u8, path[state.path_index..][0..cc_len], glob[state.glob_index..][0..cc_len])
                else
                    path[state.path_index] == cc;

                if (is_match) {
                    state.glob_index += cc_len;
                    state.path_index += cc_len;

                    if (cc == '/') {
                        state.wildcard = state.globstar;
                    }

                    continue;
                }
            }
        }

        if (state.wildcard.path_index > 0 and state.wildcard.path_index <= path.len) {
            state.backtrack();
            continue;
        }

        return false;
    }

    return true;
}

fn matchBrace(state: *State, glob: []const u8, path: []const u8, brace_stack: *BraceStack) bool {
    var brace_depth: i16 = 0;
    var in_brackets = false;

    const open_brace_index = state.glob_index;

    var branch_index: u32 = 0;

    while (state.glob_index < glob.len) {
        switch (glob[state.glob_index]) {
            '{' => if (!in_brackets) {
                brace_depth += 1;
                if (brace_depth == 1) {
                    branch_index = state.glob_index + 1;
                }
            },
            '}' => if (!in_brackets) {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    if (matchBraceBranch(state, glob, path, open_brace_index, branch_index, brace_stack)) {
                        return true;
                    }
                    break;
                }
            },
            ',' => if (brace_depth == 1) {
                if (matchBraceBranch(state, glob, path, open_brace_index, branch_index, brace_stack)) {
                    return true;
                }
                branch_index = state.glob_index + 1;
            },
            '[' => if (!in_brackets) {
                in_brackets = true;
            },
            ']' => in_brackets = false,
            '\\' => state.glob_index += 1,
            else => {},
        }
        state.glob_index += 1;
    }

    return false;
}

fn matchBraceBranch(state: *State, glob: []const u8, path: []const u8, open_brace_index: u32, branch_index: u32, brace_stack: *BraceStack) bool {
    brace_stack.append(Brace{ .open_brace_idx = open_brace_index, .branch_idx = branch_index }) catch
        return false;

    var branch_state = state.*;
    branch_state.glob_index = branch_index;
    branch_state.brace_depth = @intCast(brace_stack.len);

    const matched = globMatchImpl(&branch_state, glob, branch_index, path, brace_stack);

    _ = brace_stack.pop();

    return matched;
}

fn skipBranch(state: *State, glob: []const u8) void {
    var in_brackets = false;
    const end_brace_depth = state.brace_depth - 1;
    while (state.glob_index < glob.len) {
        switch (glob[state.glob_index]) {
            '{' => if (!in_brackets) {
                state.brace_depth += 1;
            },
            '}' => if (!in_brackets) {
                state.brace_depth -= 1;
                if (state.brace_depth == end_brace_depth) {
                    state.glob_index += 1;
                    return;
                }
            },
            '[' => if (!in_brackets) {
                in_brackets = true;
            },
            ']' => in_brackets = false,
            '\\' => state.glob_index += 1,
            else => {},
        }
        state.glob_index += 1;
    }
}

inline fn isSeparator(c: u8) bool {
    if (comptime @import("builtin").os.tag == .windows) return c == '/' or c == '\\';
    return c == '/';
}

inline fn unescape(c: *u8, glob: []const u8, glob_index: *u32) bool {
    if (c.* == '\\') {
        glob_index.* += 1;
        if (glob_index.* >= glob.len)
            return false;

        c.* = switch (glob[glob_index.*]) {
            'a' => '\x61',
            'b' => '\x08',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            else => |cc| cc,
        };
    }

    return true;
}

inline fn getUnicode(c: *u32, clen: *u8, glob: []const u8, glob_index: *u32) bool {
    std.debug.assert(clen.* == 1);
    switch (c.*) {
        0x0...('\\' - 1), '\\' + 1...0x7F => {
            return true;
        },
        '\\' => {
            glob_index.* += 1;
            if (glob_index.* >= glob.len)
                return false;

            c.* = switch (glob[glob_index.*]) {
                'a' => '\x61',
                'b' => '\x08',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => |cc| brk: {
                    const len = std.unicode.utf8ByteSequenceLength(cc) catch 1;
                    clen.* = len;
                    if (len == 1) {
                        break :brk cc;
                    }

                    break :brk std.unicode.utf8Decode(glob[glob_index.*..][0..len]) catch 0xFFFD;
                },
            };
        },
        else => {
            const len = std.unicode.utf8ByteSequenceLength(@truncate(c.*)) catch 1;
            clen.* = len;

            c.* = std.unicode.utf8Decode(glob[glob_index.*..][0..len]) catch 0xFFFD;
        },
    }

    return true;
}

inline fn skipGlobstars(glob: []const u8, glob_index: *u32) void {
    glob_index.* += 2;

    while (glob_index.* + 4 <= glob.len and std.mem.eql(u8, glob[glob_index.*..][0..4], "/**/")) {
        glob_index.* += 3;
    }

    if (glob_index.* + 3 == glob.len and std.mem.eql(u8, glob[glob_index.*..][0..3], "/**")) {
        glob_index.* += 3;
    }

    glob_index.* -= 2;
}

test "basic glob matching" {
    const testing = std.testing;

    try testing.expect(isMatch("*.txt", "file.txt"));
    try testing.expect(!isMatch("*.txt", "file.md"));
    try testing.expect(isMatch("**/*.txt", "dir/file.txt"));
    try testing.expect(isMatch("src/**/*.zig", "src/foo/bar.zig"));
    try testing.expect(isMatch("{a,b}.txt", "a.txt"));
    try testing.expect(isMatch("{a,b}.txt", "b.txt"));
    try testing.expect(!isMatch("{a,b}.txt", "c.txt"));
}
