# Nested tuple access (using intermediate variables)
inner1 = (1, 2)
inner2 = (3, 4)
# Note: Direct nested literals like ((1,2),(3,4)) not yet supported
# Use intermediate variables instead
print(inner1[0])  # 1
print(inner1[1])  # 2
print(inner2[0])  # 3
print(inner2[1])  # 4
