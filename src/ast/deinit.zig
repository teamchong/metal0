const std = @import("std");
const Node = @import("core.zig").Node;

/// Recursively free all allocations in the AST
pub fn deinit(node: *const Node, allocator: std.mem.Allocator) void {
    switch (node.*) {
        .module => |m| {
            for (m.body) |*n| deinit(n, allocator);
            allocator.free(m.body);
        },
        .assign => |a| {
            for (a.targets) |*t| deinit(t, allocator);
            allocator.free(a.targets);
            deinit(a.value, allocator);
            allocator.destroy(a.value);
        },
        .ann_assign => |a| {
            deinit(a.target, allocator);
            allocator.destroy(a.target);
            deinit(a.annotation, allocator);
            allocator.destroy(a.annotation);
            if (a.value) |v| {
                deinit(v, allocator);
                allocator.destroy(v);
            }
        },
        .aug_assign => |a| {
            deinit(a.target, allocator);
            allocator.destroy(a.target);
            deinit(a.value, allocator);
            allocator.destroy(a.value);
        },
        .binop => |b| {
            deinit(b.left, allocator);
            allocator.destroy(b.left);
            deinit(b.right, allocator);
            allocator.destroy(b.right);
        },
        .unaryop => |u| {
            deinit(u.operand, allocator);
            allocator.destroy(u.operand);
        },
        .compare => |c| {
            deinit(c.left, allocator);
            allocator.destroy(c.left);
            allocator.free(c.ops);
            for (c.comparators) |*comp| deinit(comp, allocator);
            allocator.free(c.comparators);
        },
        .boolop => |b| {
            for (b.values) |*v| deinit(v, allocator);
            allocator.free(b.values);
        },
        .call => |c| {
            deinit(c.func, allocator);
            allocator.destroy(c.func);
            for (c.args) |*a| deinit(a, allocator);
            allocator.free(c.args);
            for (c.keyword_args) |*kw| deinit(&kw.value, allocator);
            allocator.free(c.keyword_args);
        },
        .if_stmt => |i| {
            deinit(i.condition, allocator);
            allocator.destroy(i.condition);
            for (i.body) |*n| deinit(n, allocator);
            allocator.free(i.body);
            for (i.else_body) |*n| deinit(n, allocator);
            allocator.free(i.else_body);
        },
        .for_stmt => |f| {
            deinit(f.target, allocator);
            allocator.destroy(f.target);
            deinit(f.iter, allocator);
            allocator.destroy(f.iter);
            for (f.body) |*n| deinit(n, allocator);
            allocator.free(f.body);
        },
        .while_stmt => |w| {
            deinit(w.condition, allocator);
            allocator.destroy(w.condition);
            for (w.body) |*n| deinit(n, allocator);
            allocator.free(w.body);
        },
        .function_def => |f| {
            for (f.args) |arg| {
                if (arg.default) |def| {
                    deinit(def, allocator);
                    allocator.destroy(def);
                }
            }
            allocator.free(f.args);
            for (f.body) |*n| deinit(n, allocator);
            allocator.free(f.body);
            for (f.decorators) |*d| deinit(d, allocator);
            allocator.free(f.decorators);
        },
        .lambda => |l| {
            for (l.args) |arg| {
                if (arg.default) |def| {
                    deinit(def, allocator);
                    allocator.destroy(def);
                }
            }
            allocator.free(l.args);
            deinit(l.body, allocator);
            allocator.destroy(l.body);
        },
        .class_def => |c| {
            for (c.body) |*n| deinit(n, allocator);
            allocator.free(c.body);
            allocator.free(c.bases);
        },
        .return_stmt => |r| {
            if (r.value) |v| {
                deinit(v, allocator);
                allocator.destroy(v);
            }
        },
        .list => |l| {
            for (l.elts) |*e| deinit(e, allocator);
            allocator.free(l.elts);
        },
        .listcomp => |lc| {
            deinit(lc.elt, allocator);
            allocator.destroy(lc.elt);
            for (lc.generators) |*gen| {
                deinit(gen.target, allocator);
                allocator.destroy(gen.target);
                deinit(gen.iter, allocator);
                allocator.destroy(gen.iter);
                for (gen.ifs) |*f| deinit(f, allocator);
                allocator.free(gen.ifs);
            }
            allocator.free(lc.generators);
        },
        .dict => |d| {
            for (d.keys) |*k| deinit(k, allocator);
            allocator.free(d.keys);
            for (d.values) |*v| deinit(v, allocator);
            allocator.free(d.values);
        },
        .dictcomp => |dc| {
            deinit(dc.key, allocator);
            allocator.destroy(dc.key);
            deinit(dc.value, allocator);
            allocator.destroy(dc.value);
            for (dc.generators) |*gen| {
                deinit(gen.target, allocator);
                allocator.destroy(gen.target);
                deinit(gen.iter, allocator);
                allocator.destroy(gen.iter);
                for (gen.ifs) |*f| deinit(f, allocator);
                allocator.free(gen.ifs);
            }
            allocator.free(dc.generators);
        },
        .set => |s| {
            for (s.elts) |*e| deinit(e, allocator);
            allocator.free(s.elts);
        },
        .tuple => |t| {
            for (t.elts) |*e| deinit(e, allocator);
            allocator.free(t.elts);
        },
        .subscript => |s| {
            deinit(s.value, allocator);
            allocator.destroy(s.value);
            switch (s.slice) {
                .index => |idx| {
                    deinit(idx, allocator);
                    allocator.destroy(idx);
                },
                .slice => |sl| {
                    if (sl.lower) |l| {
                        deinit(l, allocator);
                        allocator.destroy(l);
                    }
                    if (sl.upper) |u| {
                        deinit(u, allocator);
                        allocator.destroy(u);
                    }
                    if (sl.step) |st| {
                        deinit(st, allocator);
                        allocator.destroy(st);
                    }
                },
            }
        },
        .attribute => |a| {
            deinit(a.value, allocator);
            allocator.destroy(a.value);
        },
        .expr_stmt => |e| {
            deinit(e.value, allocator);
            allocator.destroy(e.value);
        },
        .await_expr => |a| {
            deinit(a.value, allocator);
            allocator.destroy(a.value);
        },
        .import_stmt => |i| {
            // Strings are owned by parser arena, no need to free
            _ = i;
        },
        .import_from => |i| {
            allocator.free(i.names);
            allocator.free(i.asnames);
        },
        .assert_stmt => |a| {
            deinit(a.condition, allocator);
            allocator.destroy(a.condition);
            if (a.msg) |msg| {
                deinit(msg, allocator);
                allocator.destroy(msg);
            }
        },
        .try_stmt => |t| {
            for (t.body) |*n| deinit(n, allocator);
            allocator.free(t.body);
            for (t.handlers) |handler| {
                for (handler.body) |*n| deinit(n, allocator);
                allocator.free(handler.body);
            }
            allocator.free(t.handlers);
            for (t.else_body) |*n| deinit(n, allocator);
            allocator.free(t.else_body);
            for (t.finalbody) |*n| deinit(n, allocator);
            allocator.free(t.finalbody);
        },
        .raise_stmt => |r| {
            if (r.exc) |exc| {
                deinit(exc, allocator);
                allocator.destroy(exc);
            }
        },
        .fstring => |f| {
            for (f.parts) |*part| {
                switch (part.*) {
                    .expr => |expr| {
                        deinit(expr, allocator);
                        allocator.destroy(expr);
                    },
                    .format_expr => |fe| {
                        deinit(fe.expr, allocator);
                        allocator.destroy(fe.expr);
                    },
                    .literal => {},
                }
            }
            allocator.free(f.parts);
        },
        .global_stmt => |g| {
            allocator.free(g.names);
        },
        .with_stmt => |w| {
            deinit(w.context_expr, allocator);
            allocator.destroy(w.context_expr);
            for (w.body) |*n| deinit(n, allocator);
            allocator.free(w.body);
        },
        .starred => |s| {
            deinit(s.value, allocator);
            allocator.destroy(s.value);
        },
        .del_stmt => |d| {
            for (d.targets) |*t| deinit(t, allocator);
            allocator.free(d.targets);
        },
        // Leaf nodes need no cleanup
        .name, .constant, .pass, .break_stmt, .continue_stmt, .ellipsis_literal => {},
    }
}
