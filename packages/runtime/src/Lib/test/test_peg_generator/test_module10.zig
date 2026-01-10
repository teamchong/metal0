//! test.test_peg_generator.test_codegen - Code generation tests
//!
//! This module tests code generation from PEG grammars, including
//! parser code emission, optimization, and different target formats.

const std = @import("std");

/// Target language for code generation
pub const TargetLanguage = enum {
    zig,
    c,
    python,
    javascript,
    rust,

    pub fn extension(self: TargetLanguage) []const u8 {
        return switch (self) {
            .zig => ".zig",
            .c => ".c",
            .python => ".py",
            .javascript => ".js",
            .rust => ".rs",
        };
    }

    pub fn name(self: TargetLanguage) []const u8 {
        return switch (self) {
            .zig => "Zig",
            .c => "C",
            .python => "Python",
            .javascript => "JavaScript",
            .rust => "Rust",
        };
    }
};

/// Options for code generation
pub const CodeGenOptions = struct {
    target: TargetLanguage,
    optimize: bool,
    generate_comments: bool,
    inline_small_rules: bool,
    use_memoization: bool,
    generate_trace: bool,
    module_name: []const u8,
    include_source_locations: bool,

    pub fn default() CodeGenOptions {
        return .{
            .target = .zig,
            .optimize = true,
            .generate_comments = true,
            .inline_small_rules = true,
            .use_memoization = true,
            .generate_trace = false,
            .module_name = "parser",
            .include_source_locations = false,
        };
    }

    pub fn forDebug() CodeGenOptions {
        var opts = CodeGenOptions.default();
        opts.optimize = false;
        opts.generate_trace = true;
        opts.include_source_locations = true;
        return opts;
    }

    pub fn forProduction() CodeGenOptions {
        var opts = CodeGenOptions.default();
        opts.optimize = true;
        opts.generate_comments = false;
        opts.generate_trace = false;
        return opts;
    }
};

/// Code emitter for building generated code
pub const CodeEmitter = struct {
    buffer: std.ArrayList(u8),
    indent_level: usize,
    indent_string: []const u8,
    line_count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CodeEmitter {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
            .indent_string = "    ",
            .line_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CodeEmitter) void {
        self.buffer.deinit();
    }

    pub fn emit(self: *CodeEmitter, code: []const u8) !void {
        try self.buffer.appendSlice(code);
    }

    pub fn emitLine(self: *CodeEmitter, code: []const u8) !void {
        try self.emitIndent();
        try self.buffer.appendSlice(code);
        try self.buffer.append('\n');
        self.line_count += 1;
    }

    pub fn emitFmt(self: *CodeEmitter, comptime fmt: []const u8, args: anytype) !void {
        try self.emitIndent();
        try std.fmt.format(self.buffer.writer(), fmt, args);
    }

    pub fn emitIndent(self: *CodeEmitter) !void {
        for (0..self.indent_level) |_| {
            try self.buffer.appendSlice(self.indent_string);
        }
    }

    pub fn newline(self: *CodeEmitter) !void {
        try self.buffer.append('\n');
        self.line_count += 1;
    }

    pub fn indent(self: *CodeEmitter) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *CodeEmitter) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    pub fn startBlock(self: *CodeEmitter) !void {
        try self.emitLine("{");
        self.indent();
    }

    pub fn endBlock(self: *CodeEmitter) !void {
        self.dedent();
        try self.emitLine("}");
    }

    pub fn getOutput(self: CodeEmitter) []const u8 {
        return self.buffer.items;
    }

    pub fn getLineCount(self: CodeEmitter) usize {
        return self.line_count;
    }

    pub fn clear(self: *CodeEmitter) void {
        self.buffer.clearRetainingCapacity();
        self.indent_level = 0;
        self.line_count = 0;
    }
};

/// Code generator for PEG parsers
pub const CodeGenerator = struct {
    options: CodeGenOptions,
    emitter: CodeEmitter,
    rule_names: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: CodeGenOptions) CodeGenerator {
        return .{
            .options = options,
            .emitter = CodeEmitter.init(allocator),
            .rule_names = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        self.emitter.deinit();
        self.rule_names.deinit();
    }

    pub fn addRule(self: *CodeGenerator, name: []const u8) !void {
        try self.rule_names.append(name);
    }

    pub fn generateHeader(self: *CodeGenerator) !void {
        switch (self.options.target) {
            .zig => try self.generateZigHeader(),
            .c => try self.generateCHeader(),
            .python => try self.generatePythonHeader(),
            .javascript => try self.generateJsHeader(),
            .rust => try self.generateRustHeader(),
        }
    }

    fn generateZigHeader(self: *CodeGenerator) !void {
        try self.emitter.emitLine("//! Auto-generated parser");
        try self.emitter.emitFmt("//! Module: {s}\n", .{self.options.module_name});
        try self.emitter.newline();
        try self.emitter.emitLine("const std = @import(\"std\");");
        try self.emitter.newline();
    }

    fn generateCHeader(self: *CodeGenerator) !void {
        try self.emitter.emitLine("/* Auto-generated parser */");
        try self.emitter.newline();
        try self.emitter.emitLine("#include <stdio.h>");
        try self.emitter.emitLine("#include <stdlib.h>");
        try self.emitter.emitLine("#include <string.h>");
        try self.emitter.newline();
    }

    fn generatePythonHeader(self: *CodeGenerator) !void {
        try self.emitter.emitLine("# Auto-generated parser");
        try self.emitter.emitFmt("# Module: {s}\n", .{self.options.module_name});
        try self.emitter.newline();
        try self.emitter.emitLine("from typing import Optional, List, Any");
        try self.emitter.newline();
    }

    fn generateJsHeader(self: *CodeGenerator) !void {
        try self.emitter.emitLine("// Auto-generated parser");
        try self.emitter.emitLine("'use strict';");
        try self.emitter.newline();
    }

    fn generateRustHeader(self: *CodeGenerator) !void {
        try self.emitter.emitLine("//! Auto-generated parser");
        try self.emitter.newline();
        try self.emitter.emitLine("use std::collections::HashMap;");
        try self.emitter.newline();
    }

    pub fn generateRuleFunction(self: *CodeGenerator, name: []const u8) !void {
        switch (self.options.target) {
            .zig => try self.generateZigRule(name),
            .c => try self.generateCRule(name),
            .python => try self.generatePythonRule(name),
            .javascript => try self.generateJsRule(name),
            .rust => try self.generateRustRule(name),
        }
    }

    fn generateZigRule(self: *CodeGenerator, name: []const u8) !void {
        if (self.options.generate_comments) {
            try self.emitter.emitFmt("/// Parse rule: {s}\n", .{name});
        }
        try self.emitter.emitFmt("pub fn parse_{s}(self: *Parser) !?ParseResult {{\n", .{name});
        self.emitter.indent();
        try self.emitter.emitLine("const start = self.position;");
        try self.emitter.emitLine("// Rule implementation here");
        try self.emitter.emitLine("return null;");
        self.emitter.dedent();
        try self.emitter.emitLine("}");
        try self.emitter.newline();
    }

    fn generateCRule(self: *CodeGenerator, name: []const u8) !void {
        try self.emitter.emitFmt("ParseResult* parse_{s}(Parser* self) {{\n", .{name});
        self.emitter.indent();
        try self.emitter.emitLine("size_t start = self->position;");
        try self.emitter.emitLine("/* Rule implementation here */");
        try self.emitter.emitLine("return NULL;");
        self.emitter.dedent();
        try self.emitter.emitLine("}");
        try self.emitter.newline();
    }

    fn generatePythonRule(self: *CodeGenerator, name: []const u8) !void {
        try self.emitter.emitFmt("def parse_{s}(self) -> Optional[ParseResult]:\n", .{name});
        self.emitter.indent();
        try self.emitter.emitLine("start = self.position");
        try self.emitter.emitLine("# Rule implementation here");
        try self.emitter.emitLine("return None");
        self.emitter.dedent();
        try self.emitter.newline();
    }

    fn generateJsRule(self: *CodeGenerator, name: []const u8) !void {
        try self.emitter.emitFmt("parse_{s}() {{\n", .{name});
        self.emitter.indent();
        try self.emitter.emitLine("const start = this.position;");
        try self.emitter.emitLine("// Rule implementation here");
        try self.emitter.emitLine("return null;");
        self.emitter.dedent();
        try self.emitter.emitLine("}");
        try self.emitter.newline();
    }

    fn generateRustRule(self: *CodeGenerator, name: []const u8) !void {
        try self.emitter.emitFmt("fn parse_{s}(&mut self) -> Option<ParseResult> {{\n", .{name});
        self.emitter.indent();
        try self.emitter.emitLine("let start = self.position;");
        try self.emitter.emitLine("// Rule implementation here");
        try self.emitter.emitLine("None");
        self.emitter.dedent();
        try self.emitter.emitLine("}");
        try self.emitter.newline();
    }

    pub fn generate(self: *CodeGenerator) ![]const u8 {
        try self.generateHeader();

        for (self.rule_names.items) |name| {
            try self.generateRuleFunction(name);
        }

        return self.emitter.getOutput();
    }

    pub fn reset(self: *CodeGenerator) void {
        self.emitter.clear();
        self.rule_names.clearRetainingCapacity();
    }
};

/// Optimization pass for generated code
pub const CodeOptimizer = struct {
    passes: std.ArrayList(OptimizationPass),
    allocator: std.mem.Allocator,

    pub const OptimizationPass = enum {
        inline_small_rules,
        merge_character_classes,
        eliminate_dead_code,
        hoist_common_prefix,
        flatten_choices,

        pub fn name(self: OptimizationPass) []const u8 {
            return @tagName(self);
        }
    };

    pub fn init(allocator: std.mem.Allocator) CodeOptimizer {
        return .{
            .passes = std.ArrayList(OptimizationPass).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CodeOptimizer) void {
        self.passes.deinit();
    }

    pub fn addPass(self: *CodeOptimizer, pass: OptimizationPass) !void {
        try self.passes.append(pass);
    }

    pub fn addAllPasses(self: *CodeOptimizer) !void {
        try self.addPass(.inline_small_rules);
        try self.addPass(.merge_character_classes);
        try self.addPass(.eliminate_dead_code);
        try self.addPass(.hoist_common_prefix);
        try self.addPass(.flatten_choices);
    }

    pub fn optimize(self: CodeOptimizer, code: []const u8) []const u8 {
        // In real implementation, each pass would transform the code
        _ = self;
        return code;
    }

    pub fn passCount(self: CodeOptimizer) usize {
        return self.passes.items.len;
    }
};

// Tests
test "target_language_extension" {
    try std.testing.expectEqualStrings(".zig", TargetLanguage.zig.extension());
    try std.testing.expectEqualStrings(".py", TargetLanguage.python.extension());
    try std.testing.expectEqualStrings(".js", TargetLanguage.javascript.extension());
}

test "target_language_name" {
    try std.testing.expectEqualStrings("Zig", TargetLanguage.zig.name());
    try std.testing.expectEqualStrings("Python", TargetLanguage.python.name());
}

test "codegen_options_default" {
    const opts = CodeGenOptions.default();
    try std.testing.expect(opts.target == .zig);
    try std.testing.expect(opts.optimize);
    try std.testing.expect(opts.generate_comments);
    try std.testing.expect(!opts.generate_trace);
}

test "codegen_options_for_debug" {
    const opts = CodeGenOptions.forDebug();
    try std.testing.expect(!opts.optimize);
    try std.testing.expect(opts.generate_trace);
    try std.testing.expect(opts.include_source_locations);
}

test "codegen_options_for_production" {
    const opts = CodeGenOptions.forProduction();
    try std.testing.expect(opts.optimize);
    try std.testing.expect(!opts.generate_comments);
    try std.testing.expect(!opts.generate_trace);
}

test "code_emitter_emit" {
    var emitter = CodeEmitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emit("hello");
    try emitter.emit(" world");

    try std.testing.expectEqualStrings("hello world", emitter.getOutput());
}

test "code_emitter_emit_line" {
    var emitter = CodeEmitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emitLine("line 1");
    try emitter.emitLine("line 2");

    try std.testing.expectEqual(@as(usize, 2), emitter.getLineCount());
}

test "code_emitter_indent" {
    var emitter = CodeEmitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emitLine("level 0");
    emitter.indent();
    try emitter.emitLine("level 1");
    emitter.indent();
    try emitter.emitLine("level 2");
    emitter.dedent();
    try emitter.emitLine("level 1");

    const output = emitter.getOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "        level 2") != null);
}

test "code_emitter_block" {
    var emitter = CodeEmitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emitLine("function test()");
    try emitter.startBlock();
    try emitter.emitLine("return 42;");
    try emitter.endBlock();

    const output = emitter.getOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "{") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "}") != null);
}

test "code_emitter_clear" {
    var emitter = CodeEmitter.init(std.testing.allocator);
    defer emitter.deinit();

    try emitter.emitLine("some code");
    emitter.indent();
    try std.testing.expect(emitter.getOutput().len > 0);

    emitter.clear();
    try std.testing.expectEqual(@as(usize, 0), emitter.getOutput().len);
    try std.testing.expectEqual(@as(usize, 0), emitter.indent_level);
}

test "code_generator_init" {
    var gen = CodeGenerator.init(std.testing.allocator, CodeGenOptions.default());
    defer gen.deinit();

    try std.testing.expect(gen.options.target == .zig);
}

test "code_generator_add_rule" {
    var gen = CodeGenerator.init(std.testing.allocator, CodeGenOptions.default());
    defer gen.deinit();

    try gen.addRule("expr");
    try gen.addRule("term");
    try gen.addRule("factor");

    try std.testing.expectEqual(@as(usize, 3), gen.rule_names.items.len);
}

test "code_generator_generate_zig" {
    var gen = CodeGenerator.init(std.testing.allocator, CodeGenOptions.default());
    defer gen.deinit();

    try gen.addRule("expression");
    const output = try gen.generate();

    try std.testing.expect(std.mem.indexOf(u8, output, "parse_expression") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "const std") != null);
}

test "code_generator_generate_python" {
    var opts = CodeGenOptions.default();
    opts.target = .python;

    var gen = CodeGenerator.init(std.testing.allocator, opts);
    defer gen.deinit();

    try gen.addRule("statement");
    const output = try gen.generate();

    try std.testing.expect(std.mem.indexOf(u8, output, "def parse_statement") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "from typing") != null);
}

test "code_generator_reset" {
    var gen = CodeGenerator.init(std.testing.allocator, CodeGenOptions.default());
    defer gen.deinit();

    try gen.addRule("test");
    _ = try gen.generate();

    gen.reset();
    try std.testing.expectEqual(@as(usize, 0), gen.rule_names.items.len);
    try std.testing.expectEqual(@as(usize, 0), gen.emitter.getOutput().len);
}

test "optimizer_add_pass" {
    var opt = CodeOptimizer.init(std.testing.allocator);
    defer opt.deinit();

    try opt.addPass(.inline_small_rules);
    try opt.addPass(.eliminate_dead_code);

    try std.testing.expectEqual(@as(usize, 2), opt.passCount());
}

test "optimizer_add_all_passes" {
    var opt = CodeOptimizer.init(std.testing.allocator);
    defer opt.deinit();

    try opt.addAllPasses();

    try std.testing.expectEqual(@as(usize, 5), opt.passCount());
}

test "optimization_pass_name" {
    try std.testing.expectEqualStrings("inline_small_rules", CodeOptimizer.OptimizationPass.inline_small_rules.name());
    try std.testing.expectEqualStrings("eliminate_dead_code", CodeOptimizer.OptimizationPass.eliminate_dead_code.name());
}
