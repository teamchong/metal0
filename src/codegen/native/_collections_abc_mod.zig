/// Python _collections_abc module - Abstract Base Classes for containers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Abstract Base Classes for containers
// These are type markers used for isinstance checks
// ============================================================================

pub fn genAwaitable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genCoroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genAsyncIterable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genAsyncIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genAsyncGenerator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genHashable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genIterable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genGenerator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genReversible(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genContainer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genCollection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genMutableSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genMapping(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genMutableMapping(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genSequence(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genMutableSequence(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genByteString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genMappingView(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genKeysView(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genItemsView(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genValuesView(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genSized(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

pub fn genBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}
