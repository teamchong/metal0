/// Python winreg module - Windows registry access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate winreg.CloseKey(hkey) - Close registry key
pub fn genCloseKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.ConnectRegistry(computer_name, key) - Connect to remote registry
pub fn genConnectRegistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate winreg.CreateKey(key, sub_key) - Create registry key
pub fn genCreateKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate winreg.CreateKeyEx(key, sub_key, reserved, access) - Create registry key with options
pub fn genCreateKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate winreg.DeleteKey(key, sub_key) - Delete registry key
pub fn genDeleteKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.DeleteKeyEx(key, sub_key, access, reserved) - Delete registry key with options
pub fn genDeleteKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.DeleteValue(key, value) - Delete registry value
pub fn genDeleteValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.EnumKey(key, index) - Enumerate subkeys
pub fn genEnumKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate winreg.EnumValue(key, index) - Enumerate values
pub fn genEnumValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", null, 0 }");
}

/// Generate winreg.ExpandEnvironmentStrings(str) - Expand environment variables
pub fn genExpandEnvironmentStrings(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate winreg.FlushKey(key) - Flush registry key
pub fn genFlushKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.LoadKey(key, sub_key, file_name) - Load registry key from file
pub fn genLoadKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.OpenKey(key, sub_key, reserved, access) - Open registry key
pub fn genOpenKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate winreg.OpenKeyEx(key, sub_key, reserved, access) - Open registry key with options
pub fn genOpenKeyEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate winreg.QueryInfoKey(key) - Query registry key info
pub fn genQueryInfoKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ 0, 0, 0 }");
}

/// Generate winreg.QueryValue(key, sub_key) - Query registry value
pub fn genQueryValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate winreg.QueryValueEx(key, value_name) - Query registry value with type
pub fn genQueryValueEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ null, 0 }");
}

/// Generate winreg.SaveKey(key, file_name) - Save registry key to file
pub fn genSaveKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.SetValue(key, sub_key, type, value) - Set registry value
pub fn genSetValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.SetValueEx(key, value_name, reserved, type, value) - Set registry value with options
pub fn genSetValueEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.DisableReflectionKey(key) - Disable registry reflection
pub fn genDisableReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.EnableReflectionKey(key) - Enable registry reflection
pub fn genEnableReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate winreg.QueryReflectionKey(key) - Query registry reflection
pub fn genQueryReflectionKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

// Registry key constants

/// Generate winreg.HKEY_CLASSES_ROOT constant
pub fn genHKEY_CLASSES_ROOT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000000");
}

/// Generate winreg.HKEY_CURRENT_USER constant
pub fn genHKEY_CURRENT_USER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000001");
}

/// Generate winreg.HKEY_LOCAL_MACHINE constant
pub fn genHKEY_LOCAL_MACHINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000002");
}

/// Generate winreg.HKEY_USERS constant
pub fn genHKEY_USERS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000003");
}

/// Generate winreg.HKEY_PERFORMANCE_DATA constant
pub fn genHKEY_PERFORMANCE_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000004");
}

/// Generate winreg.HKEY_CURRENT_CONFIG constant
pub fn genHKEY_CURRENT_CONFIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000005");
}

/// Generate winreg.HKEY_DYN_DATA constant
pub fn genHKEY_DYN_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000006");
}

// Access rights constants

/// Generate winreg.KEY_ALL_ACCESS constant
pub fn genKEY_ALL_ACCESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xF003F");
}

/// Generate winreg.KEY_WRITE constant
pub fn genKEY_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20006");
}

/// Generate winreg.KEY_READ constant
pub fn genKEY_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20019");
}

/// Generate winreg.KEY_EXECUTE constant
pub fn genKEY_EXECUTE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x20019");
}

/// Generate winreg.KEY_QUERY_VALUE constant
pub fn genKEY_QUERY_VALUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0001");
}

/// Generate winreg.KEY_SET_VALUE constant
pub fn genKEY_SET_VALUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0002");
}

/// Generate winreg.KEY_CREATE_SUB_KEY constant
pub fn genKEY_CREATE_SUB_KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0004");
}

/// Generate winreg.KEY_ENUMERATE_SUB_KEYS constant
pub fn genKEY_ENUMERATE_SUB_KEYS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0008");
}

/// Generate winreg.KEY_NOTIFY constant
pub fn genKEY_NOTIFY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0010");
}

/// Generate winreg.KEY_CREATE_LINK constant
pub fn genKEY_CREATE_LINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0020");
}

/// Generate winreg.KEY_WOW64_64KEY constant
pub fn genKEY_WOW64_64KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0100");
}

/// Generate winreg.KEY_WOW64_32KEY constant
pub fn genKEY_WOW64_32KEY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x0200");
}

// Value type constants

/// Generate winreg.REG_NONE constant
pub fn genREG_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate winreg.REG_SZ constant
pub fn genREG_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate winreg.REG_EXPAND_SZ constant
pub fn genREG_EXPAND_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate winreg.REG_BINARY constant
pub fn genREG_BINARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate winreg.REG_DWORD constant
pub fn genREG_DWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate winreg.REG_DWORD_LITTLE_ENDIAN constant
pub fn genREG_DWORD_LITTLE_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate winreg.REG_DWORD_BIG_ENDIAN constant
pub fn genREG_DWORD_BIG_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("5");
}

/// Generate winreg.REG_LINK constant
pub fn genREG_LINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("6");
}

/// Generate winreg.REG_MULTI_SZ constant
pub fn genREG_MULTI_SZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("7");
}

/// Generate winreg.REG_RESOURCE_LIST constant
pub fn genREG_RESOURCE_LIST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate winreg.REG_FULL_RESOURCE_DESCRIPTOR constant
pub fn genREG_FULL_RESOURCE_DESCRIPTOR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("9");
}

/// Generate winreg.REG_RESOURCE_REQUIREMENTS_LIST constant
pub fn genREG_RESOURCE_REQUIREMENTS_LIST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("10");
}

/// Generate winreg.REG_QWORD constant
pub fn genREG_QWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("11");
}

/// Generate winreg.REG_QWORD_LITTLE_ENDIAN constant
pub fn genREG_QWORD_LITTLE_ENDIAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("11");
}
