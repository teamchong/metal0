/// Python msilib module - Windows MSI file creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "init_database", genInitDatabase },
    .{ "add_data", genAddData },
    .{ "add_tables", genAddTables },
    .{ "add_stream", genAddStream },
    .{ "gen_uuid", genGenUuid },
    .{ "open_database", genOpenDatabase },
    .{ "create_record", genCreateRecord },
    .{ "c_a_b", genCAB },
    .{ "directory", genDirectory },
    .{ "feature", genFeature },
    .{ "dialog", genDialog },
    .{ "control", genControl },
    .{ "radio_button_group", genRadioButtonGroup },
    .{ "a_m_d64", genAMD64 },
    .{ "win64", genWin64 },
    .{ "itanium", genItanium },
    .{ "schema", genSchema },
    .{ "sequence", genSequence },
    .{ "text", genText },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genMSIDBOPEN_CREATEDIRECT },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genMSIDBOPEN_CREATE },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genMSIDBOPEN_DIRECT },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genMSIDBOPEN_READONLY },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genMSIDBOPEN_TRANSACT },
});

/// Generate msilib.init_database(name, schema, ProductName, ProductCode, ProductVersion, Manufacturer) - Initialize MSI database
pub fn genInitDatabase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.add_data(database, table, records) - Add data to table
pub fn genAddData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msilib.add_tables(database, module) - Add predefined tables
pub fn genAddTables(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msilib.add_stream(database, name, path) - Add binary stream
pub fn genAddStream(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate msilib.gen_uuid() - Generate UUID
pub fn genGenUuid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"{00000000-0000-0000-0000-000000000000}\"");
}

/// Generate msilib.OpenDatabase(path, persist) - Open MSI database
pub fn genOpenDatabase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.CreateRecord(count) - Create MSI record
pub fn genCreateRecord(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.CAB class - Cabinet file support
pub fn genCAB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.Directory class - Directory table entry
pub fn genDirectory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.Feature class - Feature table entry
pub fn genFeature(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.Dialog class - Dialog support
pub fn genDialog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.Control class - Control support
pub fn genControl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.RadioButtonGroup class - Radio button group
pub fn genRadioButtonGroup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.AMD64 constant
pub fn genAMD64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate msilib.Win64 constant
pub fn genWin64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate msilib.Itanium constant
pub fn genItanium(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate msilib.schema constant
pub fn genSchema(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.sequence constant
pub fn genSequence(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.text constant
pub fn genText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate msilib.MSIDBOPEN_CREATEDIRECT constant
pub fn genMSIDBOPEN_CREATEDIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate msilib.MSIDBOPEN_CREATE constant
pub fn genMSIDBOPEN_CREATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate msilib.MSIDBOPEN_DIRECT constant
pub fn genMSIDBOPEN_DIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate msilib.MSIDBOPEN_READONLY constant
pub fn genMSIDBOPEN_READONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate msilib.MSIDBOPEN_TRANSACT constant
pub fn genMSIDBOPEN_TRANSACT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}
