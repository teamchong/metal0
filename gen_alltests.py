
binary_ops = [
    "add", "radd", "sub", "rsub", "mul", "rmul", "matmul", "rmatmul",
    "truediv", "rtruediv", "floordiv", "rfloordiv", "mod", "rmod",
    "divmod", "rdivmod", "pow", "rpow", "rshift", "rrshift", "lshift", "rlshift",
    "and", "rand", "or", "ror", "xor", "rxor", "contains", "getitem",
]

unary_ops = ["neg", "pos", "abs"]

# (name, args_count_excluding_self)
others = [
    ("hash", 0), ("str", 0), ("repr", 0), ("int", 0), ("index", 0), ("float", 0),
    ("eq", 1), ("ne", 1), ("lt", 1), ("le", 1), ("gt", 1), ("ge", 1),
    ("setitem", 2), ("delitem", 1), ("init", 0)
]

print("class AllTests:")
for name, args in others:
    arg_names = ["arg" + str(i) for i in range(args)]
    arg_str_def = ", ".join(arg_names)
    if arg_str_def: arg_str_def = ", " + arg_str_def
    
    arg_str_call = ", ".join(["self"] + arg_names)
    
    label = "__" + name + "__"
    print(f"    def {label}(self{arg_str_def}):")
    print(f"        callLst.append(('{label}', ({arg_str_call},)))")
    
    if name == "hash":
        print("        return hash(id(self))")
    elif name == "str":
        print("        return 'AllTests'")
    elif name == "repr":
        print("        return 'AllTests'")
    elif name == "int":
        print("        return 1")
    elif name == "index":
        print("        return 1")
    elif name == "float":
        print("        return 1.0")
    elif name == "eq":
        print("        return True")
    elif name == "ne":
        print("        return False")
    elif name == "lt":
        print("        return False")
    elif name == "le":
        print("        return True")
    elif name == "gt":
        print("        return False")
    elif name == "ge":
        print("        return True")
    else:
        print("        pass")

for m in binary_ops:
    label = "__" + m + "__"
    print(f"    def {label}(self, other):")
    print(f"        callLst.append(('{label}', (self, other)))")
    print("        pass")

for m in unary_ops:
    label = "__" + m + "__"
    print(f"    def {label}(self):")
    print(f"        callLst.append(('{label}', (self,)))")
    print("        pass")
