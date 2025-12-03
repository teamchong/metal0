/// Module function dispatchers (json, http, asyncio, os, etc.)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// Import specialized handlers
const json = @import("../json.zig");
const http = @import("../http.zig");
const async_mod = @import("../async.zig");
const unittest_mod = @import("../unittest/mod.zig");
const re_mod = @import("../re.zig");
const os_mod = @import("../os.zig");
const pathlib_mod = @import("../pathlib.zig");
const datetime_mod = @import("../datetime.zig");
const io_mod = @import("../io.zig");
const collections_mod = @import("../collections_mod.zig");
const functools_mod = @import("../functools_mod.zig");
const itertools_mod = @import("../itertools_mod.zig");
const copy_mod = @import("../copy_mod.zig");
const typing_mod = @import("../typing_mod.zig");
const contextlib_mod = @import("../contextlib_mod.zig");
const hashlib_mod = @import("../hashlib_mod.zig");
const struct_mod = @import("../struct_mod.zig");
const base64_mod = @import("../base64_mod.zig");
const pickle_mod = @import("../pickle_mod.zig");
const hmac_mod = @import("../hmac_mod.zig");
const socket_mod = @import("../socket_mod.zig");
const random_mod = @import("../random_mod.zig");
const string_mod = @import("../string_mod.zig");
const time_mod = @import("../time_mod.zig");
const sys_mod = @import("../sys_mod.zig");
const uuid_mod = @import("../uuid_mod.zig");
const subprocess_mod = @import("../subprocess_mod.zig");
const tempfile_mod = @import("../tempfile_mod.zig");
const textwrap_mod = @import("../textwrap_mod.zig");
const shutil_mod = @import("../shutil_mod.zig");
const glob_mod = @import("../glob_mod.zig");
const fnmatch_mod = @import("../fnmatch_mod.zig");
const secrets_mod = @import("../secrets_mod.zig");
const csv_mod = @import("../csv_mod.zig");
const configparser_mod = @import("../configparser_mod.zig");
const argparse_mod = @import("../argparse_mod.zig");
const zipfile_mod = @import("../zipfile_mod.zig");
const gzip_mod = @import("../gzip_mod.zig");
const logging_mod = @import("../logging_mod.zig");
const threading_mod = @import("../threading_mod.zig");
const queue_mod = @import("../queue_mod.zig");
const html_mod = @import("../html_mod.zig");
const urllib_mod = @import("../urllib_mod.zig");
const xml_mod = @import("../xml_mod.zig");
const decimal_mod = @import("../decimal_mod.zig");
const fractions_mod = @import("../fractions_mod.zig");
const email_mod = @import("../email_mod.zig");
const sqlite3_mod = @import("../sqlite3_mod.zig");
const heapq_mod = @import("../heapq_mod.zig");
const weakref_mod = @import("../weakref_mod.zig");
const types_mod = @import("../types_mod.zig");
const bisect_mod = @import("../bisect_mod.zig");
const statistics_mod = @import("../statistics_mod.zig");
const abc_mod = @import("../abc_mod.zig");
const inspect_mod = @import("../inspect_mod.zig");
const dataclasses_mod = @import("../dataclasses_mod.zig");
const enum_mod = @import("../enum_mod.zig");
const operator_mod = @import("../operator_mod.zig");
const atexit_mod = @import("../atexit_mod.zig");
const warnings_mod = @import("../warnings_mod.zig");
const traceback_mod = @import("../traceback_mod.zig");
const linecache_mod = @import("../linecache_mod.zig");
const pprint_mod = @import("../pprint_mod.zig");
const getpass_mod = @import("../getpass_mod.zig");
const platform_mod = @import("../platform_mod.zig");
const locale_mod = @import("../locale_mod.zig");
const codecs_mod = @import("../codecs_mod.zig");
const shelve_mod = @import("../shelve_mod.zig");
const cmath_mod = @import("../cmath_mod.zig");
const array_mod = @import("../array_mod.zig");
const difflib_mod = @import("../difflib_mod.zig");
const filecmp_mod = @import("../filecmp_mod.zig");
const graphlib_mod = @import("../graphlib_mod.zig");
const numbers_mod = @import("../numbers_mod.zig");
const http_mod = @import("../http_mod.zig");
const multiprocessing_mod = @import("../multiprocessing_mod.zig");
const concurrent_futures_mod = @import("../concurrent_futures_mod.zig");
const ctypes_mod = @import("../ctypes_mod.zig");
const select_mod = @import("../select_mod.zig");
const signal_mod = @import("../signal_mod.zig");
const mmap_mod = @import("../mmap_mod.zig");
const fcntl_mod = @import("../fcntl_mod.zig");
const termios_mod = @import("../termios_mod.zig");
const pty_mod = @import("../pty_mod.zig");
const tty_mod = @import("../tty_mod.zig");
const errno_mod = @import("../errno_mod.zig");
const resource_mod = @import("../resource_mod.zig");
const grp_mod = @import("../grp_mod.zig");
const pwd_mod = @import("../pwd_mod.zig");
const syslog_mod = @import("../syslog_mod.zig");
const curses_mod = @import("../curses_mod.zig");
const bz2_mod = @import("../bz2_mod.zig");
const lzma_mod = @import("../lzma_mod.zig");
const tarfile_mod = @import("../tarfile_mod.zig");
const shlex_mod = @import("../shlex_mod.zig");
const gettext_mod = @import("../gettext_mod.zig");
const calendar_mod = @import("../calendar_mod.zig");
const cmd_mod = @import("../cmd_mod.zig");
const code_mod = @import("../code_mod.zig");
const codeop_mod = @import("../codeop_mod.zig");
const dis_mod = @import("../dis_mod.zig");
const gc_mod = @import("../gc_mod.zig");
const ast_module = @import("../ast_mod.zig");
const unittest_mock_mod = @import("../unittest_mock_mod.zig");
const doctest_mod = @import("../doctest_mod.zig");
const profile_mod = @import("../profile_mod.zig");
const pdb_mod = @import("../pdb_mod.zig");
const timeit_mod = @import("../timeit_mod.zig");
const trace_mod = @import("../trace_mod.zig");
const binascii_mod = @import("../binascii_mod.zig");
const smtplib_mod = @import("../smtplib_mod.zig");
const imaplib_mod = @import("../imaplib_mod.zig");
const ftplib_mod = @import("../ftplib_mod.zig");
const poplib_mod = @import("../poplib_mod.zig");
const nntplib_mod = @import("../nntplib_mod.zig");
const ssl_mod = @import("../ssl_mod.zig");
const selectors_mod = @import("../selectors_mod.zig");
const ipaddress_mod = @import("../ipaddress_mod.zig");
const telnetlib_mod = @import("../telnetlib_mod.zig");
const xmlrpc_mod = @import("../xmlrpc_mod.zig");
const http_cookiejar_mod = @import("../http_cookiejar_mod.zig");
const urllib_request_mod = @import("../urllib_request_mod.zig");
const urllib_error_mod = @import("../urllib_error_mod.zig");
const urllib_robotparser_mod = @import("../urllib_robotparser_mod.zig");
const cgi_mod = @import("../cgi_mod.zig");
const wsgiref_mod = @import("../wsgiref_mod.zig");
const audioop_mod = @import("../audioop_mod.zig");
const wave_mod = @import("../wave_mod.zig");
const aifc_mod = @import("../aifc_mod.zig");
const sunau_mod = @import("../sunau_mod.zig");
const sndhdr_mod = @import("../sndhdr_mod.zig");
const imghdr_mod = @import("../imghdr_mod.zig");
const colorsys_mod = @import("../colorsys_mod.zig");
const netrc_mod = @import("../netrc_mod.zig");
const xdrlib_mod = @import("../xdrlib_mod.zig");
const plistlib_mod = @import("../plistlib_mod.zig");
const rlcompleter_mod = @import("../rlcompleter_mod.zig");
const readline_mod = @import("../readline_mod.zig");
const sched_mod = @import("../sched_mod.zig");
const mailbox_mod = @import("../mailbox_mod.zig");
const mailcap_mod = @import("../mailcap_mod.zig");
const mimetypes_mod = @import("../mimetypes_mod.zig");
const quopri_mod = @import("../quopri_mod.zig");
const uu_mod = @import("../uu_mod.zig");
const html_parser_mod = @import("../html_parser_mod.zig");
const html_entities_mod = @import("../html_entities_mod.zig");
const xml_sax_mod = @import("../xml_sax_mod.zig");
const xml_dom_mod = @import("../xml_dom_mod.zig");
const builtins_mod = @import("../builtins_mod.zig");
const typing_extensions_mod = @import("../typing_extensions_mod.zig");
const importlib_mod = @import("../importlib_mod.zig");
const pkgutil_mod = @import("../pkgutil_mod.zig");
const runpy_mod = @import("../runpy_mod.zig");
const venv_mod = @import("../venv_mod.zig");
const zipimport_mod = @import("../zipimport_mod.zig");
const compileall_mod = @import("../compileall_mod.zig");
const py_compile_mod = @import("../py_compile_mod.zig");
const contextvars_mod = @import("../contextvars_mod.zig");
const site_mod = @import("../site_mod.zig");
const __future___mod = @import("../__future___mod.zig");
const copyreg_mod = @import("../copyreg_mod.zig");
const _thread_mod = @import("../_thread_mod.zig");
const posixpath_mod = @import("../posixpath_mod.zig");
const reprlib_mod = @import("../reprlib_mod.zig");
const _collections_abc_mod = @import("../_collections_abc_mod.zig");
const keyword_mod = @import("../keyword_mod.zig");
const token_mod = @import("../token_mod.zig");
const tokenize_mod = @import("../tokenize_mod.zig");
const dbm_mod = @import("../dbm_mod.zig");
const symtable_mod = @import("../symtable_mod.zig");
const crypt_mod = @import("../crypt_mod.zig");
const posix_mod = @import("../posix_mod.zig");
const _io_mod = @import("../_io_mod.zig");
const genericpath_mod = @import("../genericpath_mod.zig");
const ntpath_mod = @import("../ntpath_mod.zig");
const zlib_mod = @import("../zlib_mod.zig");
const zipapp_mod = @import("../zipapp_mod.zig");
const ensurepip_mod = @import("../ensurepip_mod.zig");
const _string_mod = @import("../_string_mod.zig");
const _weakref_mod = @import("../_weakref_mod.zig");
const _functools_mod = @import("../_functools_mod.zig");
const _operator_mod = @import("../_operator_mod.zig");
const _json_mod = @import("../_json_mod.zig");
const _codecs_mod = @import("../_codecs_mod.zig");
const _collections_mod = @import("../_collections_mod.zig");
const _stat_mod = @import("../_stat_mod.zig");
const stat_mod = @import("../stat_mod.zig");
const _heapq_mod = @import("../_heapq_mod.zig");
const _bisect_mod = @import("../_bisect_mod.zig");
const _random_mod = @import("../_random_mod.zig");
const _struct_mod = @import("../_struct_mod.zig");
const _pickle_mod = @import("../_pickle_mod.zig");
const _datetime_mod = @import("../_datetime_mod.zig");
const _csv_mod = @import("../_csv_mod.zig");
const _socket_mod = @import("../_socket_mod.zig");
const _hashlib_mod = @import("../_hashlib_mod.zig");
const _locale_mod = @import("../_locale_mod.zig");
const _signal_mod = @import("../_signal_mod.zig");
const math_mod = @import("../math_mod.zig");
const faulthandler_mod = @import("../faulthandler_mod.zig");
const tracemalloc_mod = @import("../tracemalloc_mod.zig");
const sysconfig_mod = @import("../sysconfig_mod.zig");
const fileinput_mod = @import("../fileinput_mod.zig");
const getopt_mod = @import("../getopt_mod.zig");
const chunk_mod = @import("../chunk_mod.zig");
const bdb_mod = @import("../bdb_mod.zig");
const pstats_mod = @import("../pstats_mod.zig");
const unicodedata_mod = @import("../unicodedata_mod.zig");
const zoneinfo_mod = @import("../zoneinfo_mod.zig");
const tomllib_mod = @import("../tomllib_mod.zig");
const webbrowser_mod = @import("../webbrowser_mod.zig");
const modulefinder_mod = @import("../modulefinder_mod.zig");
const pyclbr_mod = @import("../pyclbr_mod.zig");
const tabnanny_mod = @import("../tabnanny_mod.zig");
const stringprep_mod = @import("../stringprep_mod.zig");
const pickletools_mod = @import("../pickletools_mod.zig");
const pipes_mod = @import("../pipes_mod.zig");
const socketserver_mod = @import("../socketserver_mod.zig");
const cgitb_mod = @import("../cgitb_mod.zig");
const optparse_mod = @import("../optparse_mod.zig");
const sre_compile_mod = @import("../sre_compile_mod.zig");
const sre_constants_mod = @import("../sre_constants_mod.zig");
const sre_parse_mod = @import("../sre_parse_mod.zig");
const encodings_mod = @import("../encodings_mod.zig");
const marshal_mod = @import("../marshal_mod.zig");
const opcode_mod = @import("../opcode_mod.zig");
const _abc_mod = @import("../_abc_mod.zig");
const _asyncio_mod = @import("../_asyncio_mod.zig");
const _compression_mod = @import("../_compression_mod.zig");
const _blake2_mod = @import("../_blake2_mod.zig");
const _strptime_mod = @import("../_strptime_mod.zig");
const _threading_local_mod = @import("../_threading_local_mod.zig");
const _typing_mod = @import("../_typing_mod.zig");
const _warnings_mod = @import("../_warnings_mod.zig");
const _weakrefset_mod = @import("../_weakrefset_mod.zig");
const pyexpat_mod = @import("../pyexpat_mod.zig");
const _ctypes_mod = @import("../_ctypes_mod.zig");
const _curses_mod = @import("../_curses_mod.zig");
const _decimal_mod = @import("../_decimal_mod.zig");
const _testcapi_mod = @import("../_testcapi_mod.zig");
const _elementtree_mod = @import("../_elementtree_mod.zig");
const _md5_mod = @import("../_md5_mod.zig");
const _multiprocessing_mod = @import("../_multiprocessing_mod.zig");
const _sha1_mod = @import("../_sha1_mod.zig");
const _sha2_mod = @import("../_sha2_mod.zig");
const _sha3_mod = @import("../_sha3_mod.zig");
const _sre_mod = @import("../_sre_mod.zig");
const _ssl_mod = @import("../_ssl_mod.zig");
const _sqlite3_mod = @import("../_sqlite3_mod.zig");
const _tokenize_mod = @import("../_tokenize_mod.zig");
const _uuid_mod = @import("../_uuid_mod.zig");
const _posixsubprocess_mod = @import("../_posixsubprocess_mod.zig");
const _zoneinfo_mod = @import("../_zoneinfo_mod.zig");
const _tracemalloc_mod = @import("../_tracemalloc_mod.zig");
const _lzma_mod = @import("../_lzma_mod.zig");
const _bz2_mod = @import("../_bz2_mod.zig");
const _ast_mod = @import("../_ast_mod.zig");
const _contextvars_mod = @import("../_contextvars_mod.zig");
const _queue_mod = @import("../_queue_mod.zig");
const _imp_mod = @import("../_imp_mod.zig");
const _opcode_mod = @import("../_opcode_mod.zig");
const _lsprof_mod = @import("../_lsprof_mod.zig");
const _statistics_mod = @import("../_statistics_mod.zig");
const _symtable_mod = @import("../_symtable_mod.zig");
const _markupbase_mod = @import("../_markupbase_mod.zig");
const _sitebuiltins_mod = @import("../_sitebuiltins_mod.zig");
const _curses_panel_mod = @import("../_curses_panel_mod.zig");
const _dbm_mod = @import("../_dbm_mod.zig");
const pydoc_mod = @import("../pydoc_mod.zig");
const antigravity_mod = @import("../antigravity_mod.zig");
const this_mod = @import("../this_mod.zig");
const _py_abc_mod = @import("../_py_abc_mod.zig");
const _pydatetime_mod = @import("../_pydatetime_mod.zig");
const _pydecimal_mod = @import("../_pydecimal_mod.zig");
const _pyio_mod = @import("../_pyio_mod.zig");
const _pylong_mod = @import("../_pylong_mod.zig");
const _compat_pickle_mod = @import("../_compat_pickle_mod.zig");
const _multibytecodec_mod = @import("../_multibytecodec_mod.zig");
const _codecs_cn_mod = @import("../_codecs_cn_mod.zig");
const _codecs_hk_mod = @import("../_codecs_hk_mod.zig");
const _codecs_iso2022_mod = @import("../_codecs_iso2022_mod.zig");
const _codecs_jp_mod = @import("../_codecs_jp_mod.zig");
const _codecs_kr_mod = @import("../_codecs_kr_mod.zig");
const _codecs_tw_mod = @import("../_codecs_tw_mod.zig");
const _crypt_mod = @import("../_crypt_mod.zig");
const _gdbm_mod = @import("../_gdbm_mod.zig");
const _frozen_importlib_mod = @import("../_frozen_importlib_mod.zig");
const _frozen_importlib_external_mod = @import("../_frozen_importlib_external_mod.zig");
const _aix_support_mod = @import("../_aix_support_mod.zig");
const _osx_support_mod = @import("../_osx_support_mod.zig");
const _msi_mod = @import("../_msi_mod.zig");
const _overlapped_mod = @import("../_overlapped_mod.zig");
const _posixshmem_mod = @import("../_posixshmem_mod.zig");
const _scproxy_mod = @import("../_scproxy_mod.zig");
const _tkinter_mod = @import("../_tkinter_mod.zig");
const _winapi_mod = @import("../_winapi_mod.zig");
const _wmi_mod = @import("../_wmi_mod.zig");
const lib2to3_mod = @import("../lib2to3_mod.zig");
const msilib_mod = @import("../msilib_mod.zig");
const msvcrt_mod = @import("../msvcrt_mod.zig");
const nis_mod = @import("../nis_mod.zig");
const nt_mod = @import("../nt_mod.zig");
const nturl2path_mod = @import("../nturl2path_mod.zig");
const ossaudiodev_mod = @import("../ossaudiodev_mod.zig");
const pydoc_data_mod = @import("../pydoc_data_mod.zig");
const spwd_mod = @import("../spwd_mod.zig");
const tkinter_mod = @import("../tkinter_mod.zig");
const turtle_mod = @import("../turtle_mod.zig");
const turtledemo_mod = @import("../turtledemo_mod.zig");
const idlelib_mod = @import("../idlelib_mod.zig");
const winreg_mod = @import("../winreg_mod.zig");
const winsound_mod = @import("../winsound_mod.zig");

/// Handler function type for module dispatchers
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
const FuncMap = std.StaticStringMap(ModuleHandler);

const AstFuncs = ast_module.Funcs;

/// unittest.mock module functions
const UnittestMockFuncs = unittest_mock_mod.Funcs;

/// doctest module functions
const DoctestFuncs = doctest_mod.Funcs;

/// profile module functions
const ProfileFuncs = profile_mod.Funcs;

/// pdb module functions
const PdbFuncs = pdb_mod.Funcs;

/// timeit module functions
const TimeitFuncs = timeit_mod.Funcs;

/// trace module functions
const TraceFuncs = trace_mod.Funcs;

/// binascii module functions
const BinasciiFuncs = binascii_mod.Funcs;

/// smtplib module functions
const SmtplibFuncs = smtplib_mod.Funcs;

/// imaplib module functions
const ImaplibFuncs = imaplib_mod.Funcs;

/// ftplib module functions
const FtplibFuncs = ftplib_mod.Funcs;

/// poplib module functions
const PoplibFuncs = poplib_mod.Funcs;

/// nntplib module functions
const NntplibFuncs = nntplib_mod.Funcs;

/// ssl module functions
const SslFuncs = ssl_mod.Funcs;

/// selectors module functions
const SelectorsFuncs = selectors_mod.Funcs;

/// ipaddress module functions
const IpaddressFuncs = ipaddress_mod.Funcs;

/// telnetlib module functions
const TelnetlibFuncs = telnetlib_mod.Funcs;

/// xmlrpc.client module functions
const XmlrpcClientFuncs = xmlrpc_mod.ClientFuncs;

/// xmlrpc.server module functions
const XmlrpcServerFuncs = xmlrpc_mod.ServerFuncs;

/// stat module functions (same as _stat)
const StatFuncs = stat_mod.Funcs;

/// opcode module functions (moved to opcode_mod.zig)
const OpcodeFuncs = opcode_mod.Funcs;

/// _abc module functions (moved to _abc_mod.zig)
const AbcInternalFuncs = _abc_mod.Funcs;

/// _asyncio module functions (moved to _asyncio_mod.zig)
const AsyncioInternalFuncs = _asyncio_mod.Funcs;

/// _compression module functions (moved to _compression_mod.zig)
const CompressionInternalFuncs = _compression_mod.Funcs;

/// _blake2 module functions (moved to _blake2_mod.zig)
const Blake2InternalFuncs = _blake2_mod.Funcs;

/// _strptime module functions (moved to _strptime_mod.zig)
const StrptimeInternalFuncs = _strptime_mod.Funcs;

/// _threading_local module functions (moved to _threading_local_mod.zig)
const ThreadingLocalInternalFuncs = _threading_local_mod.Funcs;

/// _typing module functions (moved to _typing_mod.zig)
const TypingInternalFuncs = _typing_mod.Funcs;

/// _warnings module functions (moved to _warnings_mod.zig)
const WarningsInternalFuncs = _warnings_mod.Funcs;

/// _weakrefset module functions (moved to _weakrefset_mod.zig)
const WeakrefsetInternalFuncs = _weakrefset_mod.Funcs;

/// pyexpat module functions (moved to pyexpat_mod.zig)
const PyexpatFuncs = pyexpat_mod.Funcs;

/// Module to function map lookup
const ModuleMap = std.StaticStringMap(FuncMap).initComptime(.{
    .{ "json", json.Funcs },
    .{ "http", http.Funcs },
    .{ "asyncio", async_mod.Funcs },
    .{ "unittest", unittest_mod.Funcs },
    .{ "re", re_mod.Funcs },
    .{ "os", os_mod.Funcs },
    .{ "os.path", os_mod.PathFuncs },
    .{ "path", os_mod.PathFuncs }, // for "from os import path" then path.exists()
    .{ "pathlib", pathlib_mod.Funcs },
    .{ "datetime", datetime_mod.Funcs },
    .{ "datetime.datetime", datetime_mod.DatetimeFuncs },
    .{ "datetime.date", datetime_mod.DateFuncs },
    .{ "io", io_mod.Funcs },
    .{ "collections", collections_mod.Funcs },
    .{ "functools", functools_mod.Funcs },
    .{ "itertools", itertools_mod.Funcs },
    .{ "copy", copy_mod.Funcs },
    .{ "typing", typing_mod.Funcs },
    .{ "contextlib", contextlib_mod.Funcs },
    .{ "hashlib", hashlib_mod.Funcs },
    .{ "struct", struct_mod.Funcs },
    .{ "base64", base64_mod.Funcs },
    .{ "pickle", pickle_mod.Funcs },
    .{ "hmac", hmac_mod.Funcs },
    .{ "socket", socket_mod.Funcs },
    .{ "random", random_mod.Funcs },
    .{ "string", string_mod.Funcs },
    .{ "time", time_mod.Funcs },
    .{ "sys", sys_mod.Funcs },
    .{ "uuid", uuid_mod.Funcs },
    .{ "subprocess", subprocess_mod.Funcs },
    .{ "tempfile", tempfile_mod.Funcs },
    .{ "textwrap", textwrap_mod.Funcs },
    .{ "shutil", shutil_mod.Funcs },
    .{ "glob", glob_mod.Funcs },
    .{ "fnmatch", fnmatch_mod.Funcs },
    .{ "secrets", secrets_mod.Funcs },
    .{ "csv", csv_mod.Funcs },
    .{ "configparser", configparser_mod.Funcs },
    .{ "argparse", argparse_mod.Funcs },
    .{ "zipfile", zipfile_mod.Funcs },
    .{ "gzip", gzip_mod.Funcs },
    .{ "logging", logging_mod.Funcs },
    .{ "threading", threading_mod.Funcs },
    .{ "queue", queue_mod.Funcs },
    .{ "html", html_mod.Funcs },
    .{ "urllib.parse", urllib_mod.Funcs },
    .{ "xml.etree.ElementTree", xml_mod.Funcs },
    .{ "ET", xml_mod.Funcs },
    .{ "decimal", decimal_mod.Funcs },
    .{ "fractions", fractions_mod.Funcs },
    .{ "email.message", email_mod.EmailMessageFuncs },
    .{ "email.mime.text", email_mod.EmailMimeTextFuncs },
    .{ "email.mime.multipart", email_mod.EmailMimeMultipartFuncs },
    .{ "email.mime.base", email_mod.EmailMimeBaseFuncs },
    .{ "email.mime.application", email_mod.EmailMimeBaseFuncs },
    .{ "email.mime.image", email_mod.EmailMimeBaseFuncs },
    .{ "email.mime.audio", email_mod.EmailMimeBaseFuncs },
    .{ "email.utils", email_mod.EmailUtilsFuncs },
    .{ "sqlite3", sqlite3_mod.Funcs },
    .{ "heapq", heapq_mod.Funcs },
    .{ "weakref", weakref_mod.Funcs },
    .{ "types", types_mod.Funcs },
    .{ "bisect", bisect_mod.Funcs },
    .{ "statistics", statistics_mod.Funcs },
    .{ "abc", abc_mod.Funcs },
    .{ "inspect", inspect_mod.Funcs },
    .{ "dataclasses", dataclasses_mod.Funcs },
    .{ "enum", enum_mod.Funcs },
    .{ "operator", operator_mod.Funcs },
    .{ "atexit", atexit_mod.Funcs },
    .{ "warnings", warnings_mod.Funcs },
    .{ "traceback", traceback_mod.Funcs },
    .{ "linecache", linecache_mod.Funcs },
    .{ "pprint", pprint_mod.Funcs },
    .{ "getpass", getpass_mod.Funcs },
    .{ "platform", platform_mod.Funcs },
    .{ "locale", locale_mod.Funcs },
    .{ "codecs", codecs_mod.Funcs },
    .{ "shelve", shelve_mod.Funcs },
    .{ "cmath", cmath_mod.Funcs },
    .{ "array", array_mod.Funcs },
    .{ "difflib", difflib_mod.Funcs },
    .{ "filecmp", filecmp_mod.Funcs },
    .{ "graphlib", graphlib_mod.Funcs },
    .{ "numbers", numbers_mod.Funcs },
    .{ "http.client", http_mod.HttpClientFuncs },
    .{ "http.server", http_mod.HttpServerFuncs },
    .{ "http.cookies", http_mod.HttpCookiesFuncs },
    .{ "multiprocessing", multiprocessing_mod.Funcs },
    .{ "concurrent.futures", concurrent_futures_mod.Funcs },
    .{ "ctypes", ctypes_mod.Funcs },
    .{ "select", select_mod.Funcs },
    .{ "signal", signal_mod.Funcs },
    .{ "mmap", mmap_mod.Funcs },
    .{ "fcntl", fcntl_mod.Funcs },
    .{ "termios", termios_mod.Funcs },
    .{ "pty", pty_mod.Funcs },
    .{ "tty", tty_mod.Funcs },
    .{ "errno", errno_mod.Funcs },
    .{ "resource", resource_mod.Funcs },
    .{ "grp", grp_mod.Funcs },
    .{ "pwd", pwd_mod.Funcs },
    .{ "syslog", syslog_mod.Funcs },
    .{ "curses", curses_mod.Funcs },
    .{ "bz2", bz2_mod.Funcs },
    .{ "lzma", lzma_mod.Funcs },
    .{ "tarfile", tarfile_mod.Funcs },
    .{ "shlex", shlex_mod.Funcs },
    .{ "gettext", gettext_mod.Funcs },
    .{ "calendar", calendar_mod.Funcs },
    .{ "cmd", cmd_mod.Funcs },
    .{ "code", code_mod.Funcs },
    .{ "codeop", codeop_mod.Funcs },
    .{ "dis", dis_mod.Funcs },
    .{ "gc", gc_mod.Funcs },
    .{ "ast", AstFuncs },
    .{ "unittest.mock", UnittestMockFuncs },
    .{ "mock", UnittestMockFuncs }, // Also support direct "from mock import ..."
    .{ "doctest", DoctestFuncs },
    .{ "profile", ProfileFuncs },
    .{ "cProfile", profile_mod.Funcs },
    .{ "pdb", PdbFuncs },
    .{ "timeit", TimeitFuncs },
    .{ "trace", TraceFuncs },
    .{ "binascii", BinasciiFuncs },
    .{ "smtplib", SmtplibFuncs },
    .{ "imaplib", ImaplibFuncs },
    .{ "ftplib", FtplibFuncs },
    .{ "poplib", PoplibFuncs },
    .{ "nntplib", NntplibFuncs },
    .{ "ssl", SslFuncs },
    .{ "selectors", SelectorsFuncs },
    .{ "ipaddress", IpaddressFuncs },
    .{ "telnetlib", TelnetlibFuncs },
    .{ "xmlrpc.client", XmlrpcClientFuncs },
    .{ "xmlrpc.server", XmlrpcServerFuncs },
    .{ "http.cookiejar", http_cookiejar_mod.Funcs },
    .{ "urllib.request", urllib_request_mod.Funcs },
    .{ "urllib.error", urllib_error_mod.Funcs },
    .{ "urllib.robotparser", urllib_robotparser_mod.Funcs },
    .{ "cgi", cgi_mod.Funcs },
    .{ "wsgiref.simple_server", wsgiref_mod.Funcs },
    .{ "wsgiref.util", wsgiref_mod.Funcs },
    .{ "wsgiref.headers", wsgiref_mod.Funcs },
    .{ "wsgiref.handlers", wsgiref_mod.Funcs },
    .{ "wsgiref.validate", wsgiref_mod.Funcs },
    .{ "audioop", audioop_mod.Funcs },
    .{ "wave", wave_mod.Funcs },
    .{ "aifc", aifc_mod.Funcs },
    .{ "sunau", sunau_mod.Funcs },
    .{ "sndhdr", sndhdr_mod.Funcs },
    .{ "imghdr", imghdr_mod.Funcs },
    .{ "colorsys", colorsys_mod.Funcs },
    .{ "netrc", netrc_mod.Funcs },
    .{ "xdrlib", xdrlib_mod.Funcs },
    .{ "plistlib", plistlib_mod.Funcs },
    .{ "rlcompleter", rlcompleter_mod.Funcs },
    .{ "readline", readline_mod.Funcs },
    .{ "sched", sched_mod.Funcs },
    .{ "mailbox", mailbox_mod.Funcs },
    .{ "mailcap", mailcap_mod.Funcs },
    .{ "mimetypes", mimetypes_mod.Funcs },
    .{ "quopri", quopri_mod.Funcs },
    .{ "uu", uu_mod.Funcs },
    .{ "html.parser", html_parser_mod.Funcs },
    .{ "html.entities", html_entities_mod.Funcs },
    .{ "xml.sax", xml_sax_mod.Funcs },
    .{ "xml.sax.handler", xml_sax_mod.Funcs },
    .{ "xml.sax.xmlreader", xml_sax_mod.Funcs },
    .{ "xml.dom", xml_dom_mod.Funcs },
    .{ "builtins", builtins_mod.Funcs },
    .{ "typing_extensions", typing_extensions_mod.Funcs },
    .{ "importlib", importlib_mod.Funcs },
    .{ "importlib.abc", importlib_mod.Funcs },
    .{ "importlib.resources", importlib_mod.Funcs },
    .{ "importlib.metadata", importlib_mod.Funcs },
    .{ "importlib.util", importlib_mod.Funcs },
    .{ "importlib.machinery", importlib_mod.Funcs },
    .{ "pkgutil", pkgutil_mod.Funcs },
    .{ "runpy", runpy_mod.Funcs },
    .{ "venv", venv_mod.Funcs },
    .{ "zipimport", zipimport_mod.Funcs },
    .{ "compileall", compileall_mod.Funcs },
    .{ "py_compile", py_compile_mod.Funcs },
    .{ "contextvars", contextvars_mod.Funcs },
    .{ "site", site_mod.Funcs },
    .{ "__future__", __future___mod.Funcs },
    .{ "copyreg", copyreg_mod.Funcs },
    .{ "_thread", _thread_mod.Funcs },
    .{ "posixpath", posixpath_mod.Funcs },
    .{ "reprlib", reprlib_mod.Funcs },
    .{ "collections.abc", _collections_abc_mod.Funcs },
    .{ "_collections_abc", _collections_abc_mod.Funcs },
    .{ "keyword", keyword_mod.Funcs },
    .{ "token", token_mod.Funcs },
    .{ "tokenize", tokenize_mod.Funcs },
    .{ "dbm", dbm_mod.Funcs },
    .{ "dbm.dumb", dbm_mod.Funcs },
    .{ "dbm.gnu", dbm_mod.Funcs },
    .{ "dbm.ndbm", dbm_mod.Funcs },
    .{ "symtable", symtable_mod.Funcs },
    .{ "crypt", crypt_mod.Funcs },
    .{ "posix", posix_mod.Funcs },
    .{ "_io", _io_mod.Funcs },
    .{ "genericpath", genericpath_mod.Funcs },
    .{ "ntpath", ntpath_mod.Funcs },
    .{ "zlib", zlib_mod.Funcs },
    .{ "zipapp", zipapp_mod.Funcs },
    .{ "ensurepip", ensurepip_mod.Funcs },
    .{ "_string", _string_mod.Funcs },
    .{ "_weakref", _weakref_mod.Funcs },
    .{ "_functools", _functools_mod.Funcs },
    .{ "_operator", _operator_mod.Funcs },
    .{ "_json", _json_mod.Funcs },
    .{ "_codecs", _codecs_mod.Funcs },
    .{ "_collections", _collections_mod.Funcs },
    .{ "_stat", _stat_mod.Funcs },
    .{ "stat", StatFuncs },
    .{ "_heapq", _heapq_mod.Funcs },
    .{ "_bisect", _bisect_mod.Funcs },
    .{ "_random", _random_mod.Funcs },
    .{ "_struct", _struct_mod.Funcs },
    .{ "_pickle", _pickle_mod.Funcs },
    .{ "_datetime", _datetime_mod.Funcs },
    .{ "_csv", _csv_mod.Funcs },
    .{ "_socket", _socket_mod.Funcs },
    .{ "_hashlib", _hashlib_mod.Funcs },
    .{ "_locale", _locale_mod.Funcs },
    .{ "_signal", _signal_mod.Funcs },
    .{ "math", math_mod.Funcs },
    .{ "faulthandler", faulthandler_mod.Funcs },
    .{ "tracemalloc", tracemalloc_mod.Funcs },
    .{ "sysconfig", sysconfig_mod.Funcs },
    .{ "fileinput", fileinput_mod.Funcs },
    .{ "getopt", getopt_mod.Funcs },
    .{ "chunk", chunk_mod.Funcs },
    .{ "bdb", bdb_mod.Funcs },
    .{ "pstats", pstats_mod.Funcs },
    .{ "unicodedata", unicodedata_mod.Funcs },
    .{ "zoneinfo", zoneinfo_mod.Funcs },
    .{ "tomllib", tomllib_mod.Funcs },
    .{ "webbrowser", webbrowser_mod.Funcs },
    .{ "modulefinder", modulefinder_mod.Funcs },
    .{ "pyclbr", pyclbr_mod.Funcs },
    .{ "tabnanny", tabnanny_mod.Funcs },
    .{ "stringprep", stringprep_mod.Funcs },
    .{ "pickletools", pickletools_mod.Funcs },
    .{ "pipes", pipes_mod.Funcs },
    .{ "socketserver", socketserver_mod.Funcs },
    .{ "cgitb", cgitb_mod.Funcs },
    .{ "optparse", optparse_mod.Funcs },
    .{ "sre_compile", sre_compile_mod.Funcs },
    .{ "sre_constants", sre_constants_mod.Funcs },
    .{ "sre_parse", sre_parse_mod.Funcs },
    .{ "encodings", encodings_mod.Funcs },
    .{ "marshal", marshal_mod.Funcs },
    .{ "opcode", OpcodeFuncs },
    .{ "_abc", AbcInternalFuncs },
    .{ "_asyncio", AsyncioInternalFuncs },
    .{ "_compression", CompressionInternalFuncs },
    .{ "_blake2", Blake2InternalFuncs },
    .{ "_strptime", StrptimeInternalFuncs },
    .{ "_threading_local", ThreadingLocalInternalFuncs },
    .{ "_typing", TypingInternalFuncs },
    .{ "_warnings", WarningsInternalFuncs },
    .{ "_weakrefset", WeakrefsetInternalFuncs },
    .{ "pyexpat", PyexpatFuncs },
    .{ "xml.parsers.expat", PyexpatFuncs },
    .{ "_ctypes", _ctypes_mod.Funcs },
    .{ "_curses", _curses_mod.Funcs },
    .{ "_decimal", _decimal_mod.Funcs },
    .{ "_testcapi", _testcapi_mod.Funcs },
    .{ "_elementtree", _elementtree_mod.Funcs },
    .{ "_md5", _md5_mod.Funcs },
    .{ "_multiprocessing", _multiprocessing_mod.Funcs },
    .{ "_sha1", _sha1_mod.Funcs },
    .{ "_sha2", _sha2_mod.Funcs },
    .{ "_sha3", _sha3_mod.Funcs },
    .{ "_sre", _sre_mod.Funcs },
    .{ "_ssl", _ssl_mod.Funcs },
    .{ "_sqlite3", _sqlite3_mod.Funcs },
    .{ "_tokenize", _tokenize_mod.Funcs },
    .{ "_uuid", _uuid_mod.Funcs },
    .{ "_posixsubprocess", _posixsubprocess_mod.Funcs },
    .{ "_zoneinfo", _zoneinfo_mod.Funcs },
    .{ "_tracemalloc", _tracemalloc_mod.Funcs },
    .{ "_lzma", _lzma_mod.Funcs },
    .{ "_bz2", _bz2_mod.Funcs },
    .{ "_ast", _ast_mod.Funcs },
    .{ "_contextvars", _contextvars_mod.Funcs },
    .{ "_queue", _queue_mod.Funcs },
    .{ "_imp", _imp_mod.Funcs },
    .{ "_opcode", _opcode_mod.Funcs },
    .{ "_lsprof", _lsprof_mod.Funcs },
    .{ "_statistics", _statistics_mod.Funcs },
    .{ "_symtable", _symtable_mod.Funcs },
    .{ "_markupbase", _markupbase_mod.Funcs },
    .{ "_sitebuiltins", _sitebuiltins_mod.Funcs },
    .{ "_curses_panel", _curses_panel_mod.Funcs },
    .{ "_dbm", _dbm_mod.Funcs },
    .{ "pydoc", pydoc_mod.Funcs },
    .{ "antigravity", antigravity_mod.Funcs },
    .{ "this", this_mod.Funcs },
    .{ "_py_abc", _py_abc_mod.Funcs },
    .{ "_pydatetime", _pydatetime_mod.Funcs },
    .{ "_pydecimal", _pydecimal_mod.Funcs },
    .{ "_pyio", _pyio_mod.Funcs },
    .{ "_pylong", _pylong_mod.Funcs },
    .{ "_compat_pickle", _compat_pickle_mod.Funcs },
    .{ "_multibytecodec", _multibytecodec_mod.Funcs },
    .{ "_codecs_cn", _codecs_cn_mod.Funcs },
    .{ "_codecs_hk", _codecs_hk_mod.Funcs },
    .{ "_codecs_iso2022", _codecs_iso2022_mod.Funcs },
    .{ "_codecs_jp", _codecs_jp_mod.Funcs },
    .{ "_codecs_kr", _codecs_kr_mod.Funcs },
    .{ "_codecs_tw", _codecs_tw_mod.Funcs },
    .{ "_crypt", _crypt_mod.Funcs },
    .{ "_gdbm", _gdbm_mod.Funcs },
    .{ "_frozen_importlib", _frozen_importlib_mod.Funcs },
    .{ "_frozen_importlib_external", _frozen_importlib_external_mod.Funcs },
    .{ "_aix_support", _aix_support_mod.Funcs },
    .{ "_osx_support", _osx_support_mod.Funcs },
    .{ "_msi", _msi_mod.Funcs },
    .{ "_overlapped", _overlapped_mod.Funcs },
    .{ "_posixshmem", _posixshmem_mod.Funcs },
    .{ "_scproxy", _scproxy_mod.Funcs },
    .{ "_tkinter", _tkinter_mod.Funcs },
    .{ "_winapi", _winapi_mod.Funcs },
    .{ "_wmi", _wmi_mod.Funcs },
    .{ "lib2to3", lib2to3_mod.Funcs },
    .{ "msilib", msilib_mod.Funcs },
    .{ "msvcrt", msvcrt_mod.Funcs },
    .{ "nis", nis_mod.Funcs },
    .{ "nt", nt_mod.Funcs },
    .{ "nturl2path", nturl2path_mod.Funcs },
    .{ "ossaudiodev", ossaudiodev_mod.Funcs },
    .{ "pydoc_data", pydoc_data_mod.Funcs },
    .{ "spwd", spwd_mod.Funcs },
    .{ "tkinter", tkinter_mod.Funcs },
    .{ "turtle", turtle_mod.Funcs },
    .{ "turtledemo", turtledemo_mod.Funcs },
    .{ "idlelib", idlelib_mod.Funcs },
    .{ "winreg", winreg_mod.Funcs },
    .{ "winsound", winsound_mod.Funcs },
});

/// Try to dispatch module function call (e.g., json.loads, os.getcwd)
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, module_name: []const u8, func_name: []const u8, call: ast.Node.Call) CodegenError!bool {
    // Check for importlib.import_module() (defensive - import already blocked)
    if (std.mem.eql(u8, module_name, "importlib") and
        std.mem.eql(u8, func_name, "import_module"))
    {
        std.debug.print("\nError: importlib.import_module() not supported in AOT compilation\n", .{});
        std.debug.print("   |\n", .{});
        std.debug.print("   = metal0 resolves all imports at compile time\n", .{});
        std.debug.print("   = Dynamic runtime module loading not supported\n", .{});
        std.debug.print("   = Suggestion: Use static imports (import json) instead\n", .{});
        return error.OutOfMemory;
    }

    // Handle test.support module context managers
    // These are Zig structs that need .init() to be instantiated
    if (std.mem.eql(u8, module_name, "support")) {
        if (std.mem.eql(u8, func_name, "Stopwatch")) {
            // support.Stopwatch() -> support.Stopwatch.init()
            try self.emit("support.Stopwatch.init()");
            return true;
        }
        if (std.mem.eql(u8, func_name, "adjust_int_max_str_digits")) {
            // support.adjust_int_max_str_digits(n) -> support.adjust_int_max_str_digits(n)
            // This is a function, not a struct, so it works normally
            try self.emit("support.adjust_int_max_str_digits(");
            if (call.args.len > 0) {
                try self.genExpr(call.args[0]);
            }
            try self.emit(")");
            return true;
        }
    }

    // Handle _pylong.compute_powers with kwargs support
    if (std.mem.eql(u8, module_name, "_pylong") and std.mem.eql(u8, func_name, "compute_powers")) {
        if (call.args.len < 3) {
            try self.emit("(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))");
            return true;
        }
        try self.emit("(runtime.pylong.computePowers(__global_allocator, @intCast(");
        try self.genExpr(call.args[0]);
        try self.emit("), @intCast(");
        try self.genExpr(call.args[1]);
        try self.emit("), @intCast(");
        try self.genExpr(call.args[2]);
        try self.emit("), ");
        // Handle need_hi kwarg - convert to bool with != 0 in case it's i64
        var found_need_hi = false;
        for (call.keyword_args) |kw| {
            if (std.mem.eql(u8, kw.name, "need_hi")) {
                try self.emit("(");
                try self.genExpr(kw.value);
                try self.emit(" != 0)");
                found_need_hi = true;
                break;
            }
        }
        if (!found_need_hi) {
            if (call.args.len > 3) {
                try self.emit("(");
                try self.genExpr(call.args[3]);
                try self.emit(" != 0)");
            } else {
                try self.emit("false");
            }
        }
        try self.emit("))");
        return true;
    }

    // Handle pickle.dumps with protocol kwarg
    // pickle.dumps(obj, protocol=N) needs special handling for different protocols
    if (std.mem.eql(u8, module_name, "pickle") and std.mem.eql(u8, func_name, "dumps")) {
        if (call.args.len > 0) {
            // Check for protocol kwarg
            var protocol_value: ?i64 = null;

            // Check positional arg first (args[1])
            if (call.args.len > 1) {
                if (call.args[1] == .constant and call.args[1].constant.value == .int) {
                    protocol_value = call.args[1].constant.value.int;
                }
            }

            // Check kwargs for protocol=N
            for (call.keyword_args) |kw| {
                if (std.mem.eql(u8, kw.name, "protocol")) {
                    if (kw.value == .constant and kw.value.constant.value == .int) {
                        protocol_value = kw.value.constant.value.int;
                        break;
                    }
                }
            }

            // Infer type of first argument
            const arg_type = self.type_inferrer.inferExpr(call.args[0]) catch .unknown;

            if (arg_type == .bool) {
                if (protocol_value != null and protocol_value.? >= 2) {
                    // Protocol 2+: use binary format
                    try self.emit("if (");
                    try self.genExpr(call.args[0]);
                    try self.emit(") \"\\x80\\x02\\x88.\" else \"\\x80\\x02\\x89.\"");
                } else {
                    // Protocol 0/1: use text format
                    try self.emit("if (");
                    try self.genExpr(call.args[0]);
                    try self.emit(") \"I01\\n.\" else \"I00\\n.\"");
                }
                return true;
            }
        }
    }

    // O(1) module lookup, then O(1) function lookup
    if (ModuleMap.get(module_name)) |func_map| {
        if (func_map.get(func_name)) |handler| {
            try handler(self, call.args);
            return true;
        }
    }

    return false;
}
