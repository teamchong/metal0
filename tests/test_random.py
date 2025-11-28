# Test random module
import random

# Test random.seed (for reproducibility)
random.seed(42)

# Test random.random()
r = random.random()
print("random:", r)

# Test random.randint(a, b)
n = random.randint(1, 100)
print("randint(1,100):", n)

# Test random.uniform
u = random.uniform(0.0, 1.0)
print("uniform:", u)

# Test random.gauss
g = random.gauss(0.0, 1.0)
print("gauss:", g)
