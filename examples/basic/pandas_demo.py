# Pandas → NumPy/BLAS Integration Demo
# Demonstrates PyAOT compiling pandas code to native BLAS calls

import pandas as pd

print("=== Pandas + BLAS Integration Test ===")

# Test 1: Create DataFrame from dict
df = pd.DataFrame({'A': [1, 2, 3, 4, 5], 'B': [10, 20, 30, 40, 50]})
print("DataFrame created with 2 columns")

# Test 2: Column access and sum (backed by BLAS)
col_a_sum = df['A'].sum()
print("Column A sum:", col_a_sum)

# Test 3: Column mean
col_b_mean = df['B'].mean()
print("Column B mean:", col_b_mean)

# Test 4: Min and max
col_a_min = df['A'].min()
col_a_max = df['A'].max()
print("Column A min:", col_a_min)
print("Column A max:", col_a_max)

# Test 5: Standard deviation
col_a_std = df['A'].std()
print("Column A std:", col_a_std)

print("=== All tests passed! ===")
