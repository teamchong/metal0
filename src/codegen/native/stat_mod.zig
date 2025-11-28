/// Python stat module - Interpret stat() results
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Re-export constants from _stat
pub const genS_IFMT = @import("_stat_mod.zig").genS_IFMT;
pub const genS_IFDIR = @import("_stat_mod.zig").genS_IFDIR;
pub const genS_IFCHR = @import("_stat_mod.zig").genS_IFCHR;
pub const genS_IFBLK = @import("_stat_mod.zig").genS_IFBLK;
pub const genS_IFREG = @import("_stat_mod.zig").genS_IFREG;
pub const genS_IFIFO = @import("_stat_mod.zig").genS_IFIFO;
pub const genS_IFLNK = @import("_stat_mod.zig").genS_IFLNK;
pub const genS_IFSOCK = @import("_stat_mod.zig").genS_IFSOCK;

pub const genS_ISUID = @import("_stat_mod.zig").genS_ISUID;
pub const genS_ISGID = @import("_stat_mod.zig").genS_ISGID;
pub const genS_ISVTX = @import("_stat_mod.zig").genS_ISVTX;

pub const genS_IRWXU = @import("_stat_mod.zig").genS_IRWXU;
pub const genS_IRUSR = @import("_stat_mod.zig").genS_IRUSR;
pub const genS_IWUSR = @import("_stat_mod.zig").genS_IWUSR;
pub const genS_IXUSR = @import("_stat_mod.zig").genS_IXUSR;

pub const genS_IRWXG = @import("_stat_mod.zig").genS_IRWXG;
pub const genS_IRGRP = @import("_stat_mod.zig").genS_IRGRP;
pub const genS_IWGRP = @import("_stat_mod.zig").genS_IWGRP;
pub const genS_IXGRP = @import("_stat_mod.zig").genS_IXGRP;

pub const genS_IRWXO = @import("_stat_mod.zig").genS_IRWXO;
pub const genS_IROTH = @import("_stat_mod.zig").genS_IROTH;
pub const genS_IWOTH = @import("_stat_mod.zig").genS_IWOTH;
pub const genS_IXOTH = @import("_stat_mod.zig").genS_IXOTH;

pub const genS_ISDIR = @import("_stat_mod.zig").genS_ISDIR;
pub const genS_ISCHR = @import("_stat_mod.zig").genS_ISCHR;
pub const genS_ISBLK = @import("_stat_mod.zig").genS_ISBLK;
pub const genS_ISREG = @import("_stat_mod.zig").genS_ISREG;
pub const genS_ISFIFO = @import("_stat_mod.zig").genS_ISFIFO;
pub const genS_ISLNK = @import("_stat_mod.zig").genS_ISLNK;
pub const genS_ISSOCK = @import("_stat_mod.zig").genS_ISSOCK;

pub const genS_IMODE = @import("_stat_mod.zig").genS_IMODE;
pub const genFilemode = @import("_stat_mod.zig").genFilemode;

pub const genST_MODE = @import("_stat_mod.zig").genST_MODE;
pub const genST_INO = @import("_stat_mod.zig").genST_INO;
pub const genST_DEV = @import("_stat_mod.zig").genST_DEV;
pub const genST_NLINK = @import("_stat_mod.zig").genST_NLINK;
pub const genST_UID = @import("_stat_mod.zig").genST_UID;
pub const genST_GID = @import("_stat_mod.zig").genST_GID;
pub const genST_SIZE = @import("_stat_mod.zig").genST_SIZE;
pub const genST_ATIME = @import("_stat_mod.zig").genST_ATIME;
pub const genST_MTIME = @import("_stat_mod.zig").genST_MTIME;
pub const genST_CTIME = @import("_stat_mod.zig").genST_CTIME;

pub const genFILE_ATTRIBUTE_ARCHIVE = @import("_stat_mod.zig").genFILE_ATTRIBUTE_ARCHIVE;
pub const genFILE_ATTRIBUTE_COMPRESSED = @import("_stat_mod.zig").genFILE_ATTRIBUTE_COMPRESSED;
pub const genFILE_ATTRIBUTE_DEVICE = @import("_stat_mod.zig").genFILE_ATTRIBUTE_DEVICE;
pub const genFILE_ATTRIBUTE_DIRECTORY = @import("_stat_mod.zig").genFILE_ATTRIBUTE_DIRECTORY;
pub const genFILE_ATTRIBUTE_ENCRYPTED = @import("_stat_mod.zig").genFILE_ATTRIBUTE_ENCRYPTED;
pub const genFILE_ATTRIBUTE_HIDDEN = @import("_stat_mod.zig").genFILE_ATTRIBUTE_HIDDEN;
pub const genFILE_ATTRIBUTE_NORMAL = @import("_stat_mod.zig").genFILE_ATTRIBUTE_NORMAL;
pub const genFILE_ATTRIBUTE_NOT_CONTENT_INDEXED = @import("_stat_mod.zig").genFILE_ATTRIBUTE_NOT_CONTENT_INDEXED;
pub const genFILE_ATTRIBUTE_OFFLINE = @import("_stat_mod.zig").genFILE_ATTRIBUTE_OFFLINE;
pub const genFILE_ATTRIBUTE_READONLY = @import("_stat_mod.zig").genFILE_ATTRIBUTE_READONLY;
pub const genFILE_ATTRIBUTE_REPARSE_POINT = @import("_stat_mod.zig").genFILE_ATTRIBUTE_REPARSE_POINT;
pub const genFILE_ATTRIBUTE_SPARSE_FILE = @import("_stat_mod.zig").genFILE_ATTRIBUTE_SPARSE_FILE;
pub const genFILE_ATTRIBUTE_SYSTEM = @import("_stat_mod.zig").genFILE_ATTRIBUTE_SYSTEM;
pub const genFILE_ATTRIBUTE_TEMPORARY = @import("_stat_mod.zig").genFILE_ATTRIBUTE_TEMPORARY;
pub const genFILE_ATTRIBUTE_VIRTUAL = @import("_stat_mod.zig").genFILE_ATTRIBUTE_VIRTUAL;
