"""VectorAccelerator - GPU/CPU accelerated batch vector operations.

Acceleration hierarchy:
1. PyTorch with CUDA/MPS (if available)
2. CuPy with CUDA (if available)
3. NumPy with BLAS (fallback, still fast via vectorization)

For L2-normalized vectors, dot product = cosine similarity.
"""

import numpy as np
from typing import Optional, Tuple, List, Union


class VectorAccelerator:
    """GPU-accelerated batch cosine similarity.

    Example:
        accelerator = VectorAccelerator()
        print(f"Using backend: {accelerator.backend}")

        query = np.random.randn(384).astype(np.float32)
        vectors = [np.random.randn(384).astype(np.float32) for _ in range(1000)]

        # Batch similarity
        scores = accelerator.batch_cosine_similarity(query, vectors)

        # Top-k search
        indices, scores = accelerator.top_k_similarity(query, vectors, k=10)
    """

    def __init__(self, prefer_gpu: bool = True):
        """Initialize the accelerator.

        Args:
            prefer_gpu: Whether to prefer GPU backends when available
        """
        self._backend = "numpy"
        self._device = None
        self._torch = None
        self._cupy = None

        if prefer_gpu:
            self._init_gpu()

    def _init_gpu(self):
        """Try to initialize GPU backends."""
        # Try PyTorch first (supports both CUDA and MPS/Metal)
        try:
            import torch
            self._torch = torch

            if torch.cuda.is_available():
                self._backend = "torch-cuda"
                self._device = torch.device("cuda")
                print(f"[VectorAccelerator] Using PyTorch with CUDA")
            elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                self._backend = "torch-mps"
                self._device = torch.device("mps")
                print(f"[VectorAccelerator] Using PyTorch with Metal (MPS)")
            else:
                # PyTorch available but no GPU
                self._torch = None
        except ImportError:
            pass

        # Try CuPy if PyTorch not available with GPU
        if self._backend == "numpy":
            try:
                import cupy as cp
                self._cupy = cp
                self._backend = "cupy"
                print(f"[VectorAccelerator] Using CuPy with CUDA")
            except ImportError:
                pass

        if self._backend == "numpy":
            print(f"[VectorAccelerator] Using NumPy (CPU)")

    @property
    def backend(self) -> str:
        """Get current backend name."""
        return self._backend

    def is_gpu_available(self) -> bool:
        """Check if GPU acceleration is available."""
        return self._backend != "numpy"

    def batch_cosine_similarity(
        self,
        query: np.ndarray,
        vectors: Union[List[np.ndarray], np.ndarray],
        normalized: bool = True,
    ) -> np.ndarray:
        """Compute cosine similarity between query and all vectors.

        Args:
            query: Query vector (dim,)
            vectors: List of vectors or 2D array (num_vectors, dim)
            normalized: Whether vectors are L2-normalized

        Returns:
            Similarity scores (num_vectors,)
        """
        # Convert to 2D array if list
        if isinstance(vectors, list):
            if len(vectors) == 0:
                return np.array([], dtype=np.float32)
            vectors = np.stack(vectors)

        if vectors.ndim == 1:
            vectors = vectors.reshape(1, -1)

        # Ensure float32
        query = query.astype(np.float32)
        vectors = vectors.astype(np.float32)

        if self._backend.startswith("torch"):
            return self._torch_similarity(query, vectors, normalized)
        elif self._backend == "cupy":
            return self._cupy_similarity(query, vectors, normalized)
        else:
            return self._numpy_similarity(query, vectors, normalized)

    def _torch_similarity(
        self, query: np.ndarray, vectors: np.ndarray, normalized: bool
    ) -> np.ndarray:
        """Compute similarity using PyTorch."""
        import torch

        # Check if vectors are already cached on GPU
        vectors_id = id(vectors)
        if not hasattr(self, '_cached_vectors_id') or self._cached_vectors_id != vectors_id:
            # Cache vectors on GPU (expensive, but only done once per dataset)
            self._cached_vectors = torch.from_numpy(vectors).to(self._device)
            self._cached_vectors_id = vectors_id

        # Only transfer query (small, fast)
        q = torch.from_numpy(query).to(self._device)
        v = self._cached_vectors

        if normalized:
            # Dot product = cosine similarity for normalized vectors
            scores = torch.mv(v, q)
        else:
            # Full cosine similarity
            q_norm = q / torch.norm(q)
            v_norm = v / torch.norm(v, dim=1, keepdim=True)
            scores = torch.mv(v_norm, q_norm)

        return scores.cpu().numpy()

    def _cupy_similarity(
        self, query: np.ndarray, vectors: np.ndarray, normalized: bool
    ) -> np.ndarray:
        """Compute similarity using CuPy."""
        cp = self._cupy

        q = cp.asarray(query)
        v = cp.asarray(vectors)

        if normalized:
            scores = v @ q
        else:
            q_norm = q / cp.linalg.norm(q)
            v_norm = v / cp.linalg.norm(v, axis=1, keepdims=True)
            scores = v_norm @ q_norm

        return cp.asnumpy(scores)

    def _numpy_similarity(
        self, query: np.ndarray, vectors: np.ndarray, normalized: bool
    ) -> np.ndarray:
        """Compute similarity using NumPy (CPU BLAS)."""
        if normalized:
            # Simple matrix-vector multiply (uses BLAS)
            return vectors @ query
        else:
            q_norm = query / np.linalg.norm(query)
            v_norm = vectors / np.linalg.norm(vectors, axis=1, keepdims=True)
            return v_norm @ q_norm

    def top_k_similarity(
        self,
        query: np.ndarray,
        vectors: Union[List[np.ndarray], np.ndarray],
        k: int = 10,
        normalized: bool = True,
    ) -> Tuple[np.ndarray, np.ndarray]:
        """Find top-k most similar vectors.

        Args:
            query: Query vector (dim,)
            vectors: List of vectors or 2D array (num_vectors, dim)
            k: Number of results
            normalized: Whether vectors are L2-normalized

        Returns:
            Tuple of (indices, scores)
        """
        scores = self.batch_cosine_similarity(query, vectors, normalized)

        # Partial argsort for efficiency (numpy)
        if len(scores) <= k:
            indices = np.argsort(-scores)
        else:
            # argpartition is O(n) vs O(n log n) for full sort
            indices = np.argpartition(-scores, k)[:k]
            indices = indices[np.argsort(-scores[indices])]

        return indices[:k], scores[indices[:k]]


# Global accelerator instance
vector_accelerator = VectorAccelerator()
