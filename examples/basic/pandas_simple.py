# Simplified Pandas Demo - Direct Column Operations
# Demonstrates DataFrame creation and operations without subscript syntax

import pandas as pd

print("=== Pandas + BLAS Integration Test (Simplified) ===")

# Test 1: Create DataFrame from dict
df = pd.DataFrame({'A': [1, 2, 3, 4, 5], 'B': [10, 20, 30, 40, 50]})

print("DataFrame created with 2 columns")
print("Total columns:", df.columnCount())
print("Total rows:", df.len())

print("=== Tests complete! ===")
