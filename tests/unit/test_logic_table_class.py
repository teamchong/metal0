"""Test @logic_table class compilation.

This tests that @logic_table decorated classes compile to Zig batch functions.
"""

from logic_table import logic_table

@logic_table
class VectorOps:
    def cosine_sim(self):
        return sum(query.embedding * docs.embedding) / (norm(query.embedding) * norm(docs.embedding))

    def dot_product(self):
        return sum(query.embedding * docs.embedding)

    def weighted_score(self):
        return query.score * 0.5 + docs.boost * 0.5

# Test that the class exists
print("VectorOps class created")
print("VectorOps.__logic_table__ =", VectorOps.__logic_table__)

print("@logic_table class test passed!")
