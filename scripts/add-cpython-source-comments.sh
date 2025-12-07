#!/bin/bash
# add-cpython-source-comments.sh
# Adds CPython source path comments to mirrored Zig files
# ONLY replaces lines that already start with "//!" (doc comments)

METAL0="/Users/steven_chong/Downloads/repos/metal0"
CPYTHON="/Users/steven_chong/Downloads/repos/cpython"

add_comment() {
    local zig_dir="$1"
    local cpython_dirs="$2"  # space-separated list
    local ext="$3"

    for zig_file in "$zig_dir"/*.zig; do
        [[ -f "$zig_file" ]] || continue

        # Check if first line starts with "//!" - only update those files
        first_line=$(head -1 "$zig_file")
        if [[ ! "$first_line" =~ ^//! ]]; then
            echo "SKIP: $(basename "$zig_file") (first line is not //! comment)"
            continue
        fi

        basename=$(basename "$zig_file" .zig)
        source=""

        # Try each CPython directory
        for cpython_dir in $cpython_dirs; do
            # Try exact match
            if [[ -f "$CPYTHON/$cpython_dir/${basename}${ext}" ]]; then
                source="$cpython_dir/${basename}${ext}"
                break
            fi
            # Try with 'module' suffix (e.g., _abc -> _abcmodule.c)
            if [[ -f "$CPYTHON/$cpython_dir/${basename}module${ext}" ]]; then
                source="$cpython_dir/${basename}module${ext}"
                break
            fi
            # Try with 'object' suffix (e.g., bool -> boolobject.c)
            if [[ -f "$CPYTHON/$cpython_dir/${basename}object${ext}" ]]; then
                source="$cpython_dir/${basename}object${ext}"
                break
            fi
        done

        if [[ -n "$source" ]]; then
            echo "Updating: $(basename "$zig_file") -> $source"
            # Replace first line with CPython source comment
            sed -i '' "1s|.*|//! CPython source: $source|" "$zig_file"
        else
            echo "NO MATCH: $(basename "$zig_file") (no CPython file found)"
        fi
    done
}

echo "=== Lib/ ==="
add_comment "$METAL0/packages/runtime/src/Lib" "Lib" ".py"

echo ""
echo "=== Lib/encodings/ ==="
add_comment "$METAL0/packages/runtime/src/Lib/encodings" "Lib/encodings" ".py"

echo ""
echo "=== Objects/ (runtime) ==="
add_comment "$METAL0/packages/runtime/src/Objects" "Objects" ".c"

echo ""
echo "=== Modules/ (runtime) ==="
add_comment "$METAL0/packages/runtime/src/Modules" "Modules" ".c"

echo ""
echo "=== Python/ ==="
add_comment "$METAL0/packages/runtime/src/Python" "Python" ".c"

echo ""
echo "=== c_interop/objects/ ==="
add_comment "$METAL0/packages/c_interop/src/objects" "Objects" ".c"

echo ""
echo "=== c_interop/modules/ ==="
add_comment "$METAL0/packages/c_interop/src/modules" "Modules PC" ".c"

echo ""
echo "Done!"
