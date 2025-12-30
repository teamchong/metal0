"""
Real ML Workflow for @logic_table Benchmark

This file contains realistic ML/AI workloads that use numpy for:
- Feature engineering (normalization, log transforms, z-scores)
- Similarity search (cosine similarity, dot product, L2 distance)
- Fraud detection scoring
- Recommendation scoring

Compiled by metal0: metal0 build --emit-logic-table benchmarks/ml_workflow.py -o lib/logic_table.a
"""

import numpy as np
from logic_table import logic_table


@logic_table
class FeatureEngineering:
    """Feature engineering transformations for ML pipelines."""

    def normalize_minmax(self, data: np.ndarray) -> np.ndarray:
        """Min-max normalization to [0, 1] range."""
        min_val = np.min(data.values)
        max_val = np.max(data.values)
        return (data.values - min_val) / (max_val - min_val + 1e-8)

    def normalize_zscore(self, data: np.ndarray) -> np.ndarray:
        """Z-score standardization (mean=0, std=1)."""
        mean = np.mean(data.values)
        std = np.std(data.values)
        return (data.values - mean) / (std + 1e-8)

    def log_transform(self, data: np.ndarray) -> np.ndarray:
        """Log transform with offset for zero handling."""
        return np.log1p(data.values)

    def clip_outliers(self, data: np.ndarray) -> np.ndarray:
        """Clip values to 3 standard deviations."""
        mean = np.mean(data.values)
        std = np.std(data.values)
        lower = mean - 3 * std
        upper = mean + 3 * std
        return np.clip(data.values, lower, upper)

    def polynomial_features(self, data: np.ndarray) -> np.ndarray:
        """Generate polynomial features (x, x^2, x^3)."""
        x = data.values
        return np.stack([x, x ** 2, x ** 3], axis=-1)


@logic_table
class VectorSearch:
    """Vector similarity operations for semantic search."""

    def cosine_similarity(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """Cosine similarity between query and document embeddings.

        query: shape (embedding_dim,)
        docs: shape (num_docs, embedding_dim)
        returns: shape (num_docs,) similarity scores in [-1, 1]
        """
        # Normalize query
        query_norm = np.linalg.norm(query.embedding)
        query_normalized = query.embedding / (query_norm + 1e-8)

        # Normalize docs (row-wise)
        docs_norm = np.linalg.norm(docs.embedding, axis=1, keepdims=True)
        docs_normalized = docs.embedding / (docs_norm + 1e-8)

        # Dot product gives cosine similarity for normalized vectors
        return np.dot(docs_normalized, query_normalized)

    def euclidean_distance(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """L2 (Euclidean) distance between query and documents.

        Lower values = more similar.
        """
        diff = docs.embedding - query.embedding
        return np.sqrt(np.sum(diff ** 2, axis=1))

    def dot_product(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """Raw dot product (for pre-normalized embeddings)."""
        return np.dot(docs.embedding, query.embedding)

    def manhattan_distance(self, query: np.ndarray, docs: np.ndarray) -> np.ndarray:
        """L1 (Manhattan) distance between query and documents."""
        diff = np.abs(docs.embedding - query.embedding)
        return np.sum(diff, axis=1)


@logic_table
class FraudDetection:
    """Fraud risk scoring with multiple signals."""

    def transaction_risk_score(self, txn: np.ndarray) -> np.ndarray:
        """Multi-factor fraud risk score for transactions.

        Factors:
        - Amount: large transactions are riskier
        - Velocity: many transactions in short time
        - Location: unusual location patterns
        - Time: unusual time of day
        - History: past fraud incidents
        """
        score = np.zeros_like(txn.amount)

        # Amount risk (0-0.3): exponential decay for normal amounts
        amount_risk = 1.0 - np.exp(-txn.amount / 5000.0)
        score = score + np.minimum(0.3, amount_risk * 0.3)

        # Velocity risk (0-0.25): transactions per hour
        velocity_risk = np.minimum(1.0, txn.velocity / 10.0)
        score = score + velocity_risk * 0.25

        # Location risk (0-0.2): distance from usual location
        location_risk = np.minimum(1.0, txn.location_distance / 1000.0)
        score = score + location_risk * 0.2

        # Time risk (0-0.1): transactions at unusual hours (2am-5am)
        hour = txn.hour
        time_risk = np.where((hour >= 2) & (hour <= 5), 0.1, 0.0)
        score = score + time_risk

        # History risk (0-0.15): previous fraud incidents
        history_risk = np.minimum(1.0, txn.fraud_count / 3.0)
        score = score + history_risk * 0.15

        return np.clip(score, 0.0, 1.0)

    def anomaly_score(self, txn: np.ndarray) -> np.ndarray:
        """Z-score based anomaly detection."""
        # Compute z-scores for key features
        amount_z = np.abs(txn.amount - txn.amount_mean) / (txn.amount_std + 1e-8)
        velocity_z = np.abs(txn.velocity - txn.velocity_mean) / (txn.velocity_std + 1e-8)

        # Combined anomaly score
        return np.maximum(amount_z, velocity_z)


@logic_table
class Recommendations:
    """Recommendation scoring functions."""

    def collaborative_score(self, user: np.ndarray, items: np.ndarray) -> np.ndarray:
        """Score items based on user-item embedding similarity."""
        # Dot product of user embedding with item embeddings
        base_score = np.dot(items.embedding, user.embedding)

        # Apply popularity bias correction
        popularity_penalty = np.log1p(items.view_count) * 0.1

        # Apply recency boost
        recency_boost = np.exp(-items.age_days / 30.0) * 0.2

        return base_score - popularity_penalty + recency_boost

    def diversity_score(self, candidates: np.ndarray) -> np.ndarray:
        """Compute diversity penalty for result set.

        Penalizes items too similar to earlier items in the list.
        """
        n = len(candidates.embedding)
        diversity = np.ones(n)

        # Compare each item to all previous items
        for i in range(1, n):
            current = candidates.embedding[i]
            previous = candidates.embedding[:i]

            # Max similarity to any previous item
            similarities = np.dot(previous, current) / (
                np.linalg.norm(previous, axis=1) * np.linalg.norm(current) + 1e-8
            )
            max_sim = np.max(similarities)

            # Diversity = 1 - max_similarity
            diversity[i] = 1.0 - max_sim

        return diversity

    def hybrid_score(self, user: np.ndarray, items: np.ndarray) -> np.ndarray:
        """Hybrid scoring combining multiple signals."""
        # Embedding similarity (0.4 weight)
        embedding_score = np.dot(items.embedding, user.embedding)
        embedding_score = (embedding_score + 1.0) / 2.0  # Normalize to [0, 1]

        # Category match (0.2 weight)
        category_match = np.where(items.category == user.preferred_category, 1.0, 0.0)

        # Price match (0.2 weight) - closer to preferred price is better
        price_diff = np.abs(items.price - user.preferred_price)
        price_score = np.exp(-price_diff / user.price_tolerance)

        # Rating (0.2 weight)
        rating_score = items.avg_rating / 5.0

        return (
            0.4 * embedding_score +
            0.2 * category_match +
            0.2 * price_score +
            0.2 * rating_score
        )


# Verify classes are marked as logic_table
if __name__ == "__main__":
    print("Verifying @logic_table classes...")
    print(f"  FeatureEngineering.__logic_table__ = {FeatureEngineering.__logic_table__}")
    print(f"  VectorSearch.__logic_table__ = {VectorSearch.__logic_table__}")
    print(f"  FraudDetection.__logic_table__ = {FraudDetection.__logic_table__}")
    print(f"  Recommendations.__logic_table__ = {Recommendations.__logic_table__}")
    print("All @logic_table classes verified!")
