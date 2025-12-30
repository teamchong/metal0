#!/usr/bin/env python3
"""
Generate test Lance files with known values for WASM parser validation.

Each test file has a specific purpose and known expected values that
can be verified by the test suite.
"""

import lance
import pyarrow as pa
import numpy as np
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

def generate_basic_types():
    """Test file with int64, string, float64 columns."""
    table = pa.table({
        'id': pa.array([0, 1, 2, 3, 4], type=pa.int64()),
        'name': pa.array(['alpha', 'beta', 'gamma', 'delta', 'epsilon'], type=pa.string()),
        'score': pa.array([1.5, 2.5, 3.5, 4.5, 5.5], type=pa.float64()),
    })
    
    path = os.path.join(OUTPUT_DIR, 'basic_types.lance')
    lance.write_dataset(table, path, mode='overwrite', data_storage_version='2.0')
    print(f'Created {path}')
    print(f'  Columns: id (int64), name (string), score (float64)')
    print(f'  Rows: 5')
    print(f'  Expected values:')
    print(f'    id: [0, 1, 2, 3, 4]')
    print(f'    name: ["alpha", "beta", "gamma", "delta", "epsilon"]')
    print(f'    score: [1.5, 2.5, 3.5, 4.5, 5.5]')
    return path

def generate_vectors():
    """Test file with vector embeddings (fixed size list)."""
    # 4-dimensional vectors for easy verification
    embeddings = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
        [0.5, 0.5, 0.5, 0.5],
    ]
    
    embedding_type = pa.list_(pa.float32(), 4)
    table = pa.table({
        'id': pa.array([0, 1, 2, 3, 4], type=pa.int64()),
        'embedding': pa.array(embeddings, type=embedding_type),
    })
    
    path = os.path.join(OUTPUT_DIR, 'vectors.lance')
    lance.write_dataset(table, path, mode='overwrite', data_storage_version='2.0')
    print(f'Created {path}')
    print(f'  Columns: id (int64), embedding (fixed_size_list<float32>[4])')
    print(f'  Rows: 5')
    print(f'  Expected values:')
    print(f'    id: [0, 1, 2, 3, 4]')
    print(f'    embedding[0]: [1.0, 0.0, 0.0, 0.0]')
    print(f'    embedding[4]: [0.5, 0.5, 0.5, 0.5]')
    return path

def generate_strings_various():
    """Test file with various string lengths including empty and unicode."""
    table = pa.table({
        'id': pa.array([0, 1, 2, 3, 4], type=pa.int64()),
        'text': pa.array([
            '',           # empty string
            'a',          # single char
            'hello',      # normal
            'hello world with spaces',  # spaces
            '你好世界',    # unicode
        ], type=pa.string()),
    })
    
    path = os.path.join(OUTPUT_DIR, 'strings_various.lance')
    lance.write_dataset(table, path, mode='overwrite', data_storage_version='2.0')
    print(f'Created {path}')
    print(f'  Columns: id (int64), text (string)')
    print(f'  Rows: 5')
    print(f'  Expected values:')
    print(f'    text[0]: "" (empty)')
    print(f'    text[1]: "a"')
    print(f'    text[2]: "hello"')
    print(f'    text[3]: "hello world with spaces"')
    print(f'    text[4]: "你好世界" (unicode)')
    return path

def generate_large_file():
    """Test file with many rows to verify pagination."""
    n_rows = 1000
    table = pa.table({
        'id': pa.array(list(range(n_rows)), type=pa.int64()),
        'value': pa.array([float(i * 0.1) for i in range(n_rows)], type=pa.float64()),
    })
    
    path = os.path.join(OUTPUT_DIR, 'large.lance')
    lance.write_dataset(table, path, mode='overwrite', data_storage_version='2.0')
    print(f'Created {path}')
    print(f'  Columns: id (int64), value (float64)')
    print(f'  Rows: {n_rows}')
    print(f'  Expected values:')
    print(f'    id[0]: 0, id[999]: 999')
    print(f'    value[0]: 0.0, value[999]: 99.9')
    return path

def verify_files():
    """Verify generated files can be read back correctly."""
    print('\n--- Verification ---')
    
    for name in ['basic_types', 'vectors', 'strings_various', 'large']:
        path = os.path.join(OUTPUT_DIR, f'{name}.lance')
        ds = lance.dataset(path)
        print(f'{name}.lance: {ds.count_rows()} rows, {len(ds.schema)} columns')
        
        # Print schema
        for field in ds.schema:
            print(f'  {field.name}: {field.type}')

if __name__ == '__main__':
    print('Generating Lance test files...\n')
    generate_basic_types()
    print()
    generate_vectors()
    print()
    generate_strings_various()
    print()
    generate_large_file()
    print()
    verify_files()
    print('\nDone!')
