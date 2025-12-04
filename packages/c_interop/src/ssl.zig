const std = @import("std");

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

pub fn init() void {
    _ = c.SSL_library_init();
    c.SSL_load_error_strings();
    _ = c.OpenSSL_add_all_algorithms();
}

pub const Context = struct {
    ctx: ?*c.SSL_CTX,

    pub fn init() !Context {
        const method = c.TLS_client_method();
        const ctx = c.SSL_CTX_new(method);
        if (ctx == null) {
            return error.ContextFailed;
        }
        return Context{ .ctx = ctx };
    }

    pub fn free(self: *Context) void {
        c.SSL_CTX_free(self.ctx);
    }
};

/// Python-compatible API: SSLContext() returns a Context
pub fn SSLContext() !Context {
    return Context.init();
}
