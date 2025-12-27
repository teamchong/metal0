"""Test @logic_table class compilation.

This tests that @logic_table decorated classes compile to Zig batch functions.
Uses familiar Python ML syntax that metal0 compiles to native batch operations.
"""

import numpy as np
from logic_table import logic_table

@logic_table
class VectorOps:
    """Vector operations for similarity search and scoring."""

    def cosine_sim(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """Cosine similarity between query and document embeddings."""
        return np.sum(query.embedding * docs.embedding) / (
            np.linalg.norm(query.embedding) * np.linalg.norm(docs.embedding)
        )

    def dot_product(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """Dot product between query and document embeddings."""
        return np.dot(query.embedding, docs.embedding)

    def weighted_score(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """Weighted combination of query score and document boost."""
        return query.score * 0.5 + docs.boost * 0.5


@logic_table
class FeatureEngineering:
    """Feature engineering transformations."""

    def log_transform(self, data: np.ndarray) -> np.ndarray:
        """Log transform with offset for zero handling."""
        return np.log(data.value + 1.0)

    def normalize(self, data: np.ndarray) -> np.ndarray:
        """Min-max normalization."""
        return (data.value - data.min) / (data.max - data.min + 1e-8)

    def z_score(self, data: np.ndarray) -> np.ndarray:
        """Z-score standardization."""
        return (data.value - data.mean) / (data.std + 1e-8)


@logic_table
class RiskScoring:
    """Risk scoring for fraud detection."""

    def fraud_score(self, txn: np.ndarray) -> np.ndarray:
        """Multi-factor fraud risk score."""
        score = 0.0
        # High amount risk
        score = score + np.where(txn.amount > 10000, np.minimum(0.4, txn.amount / 125000), 0.0)
        # New customer risk
        score = score + np.where(txn.customer_age < 30, 0.3, 0.0)
        # High velocity risk
        score = score + np.where(txn.velocity > 5, np.minimum(0.2, txn.velocity / 100), 0.0)
        # Previous fraud history
        score = score + np.where(txn.previous_fraud, 0.5, 0.0)
        # Unverified account
        score = score + np.where(~txn.verified, 0.2, 0.0)
        return np.minimum(1.0, score)


# Test that classes exist and have the marker
print("VectorOps.__logic_table__ =", VectorOps.__logic_table__)
print("FeatureEngineering.__logic_table__ =", FeatureEngineering.__logic_table__)
print("RiskScoring.__logic_table__ =", RiskScoring.__logic_table__)
print("@logic_table class test passed!")
