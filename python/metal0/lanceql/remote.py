"""Remote Lance Dataset with IVF vector search.

Provides HTTP Range-based access to remote Lance datasets
with GPU-accelerated IVF vector search.
"""

import struct
import urllib.request
from typing import List, Optional, Tuple, Callable, Dict, Any
import numpy as np

from .vector import vector_accelerator


def fetch_range(url: str, start: int, end: int) -> bytes:
    """Fetch a byte range from a URL."""
    req = urllib.request.Request(url)
    req.add_header('Range', f'bytes={start}-{end}')
    with urllib.request.urlopen(req) as response:
        return response.read()


class IVFIndex:
    """IVF Index for approximate nearest neighbor search.

    Loads centroids and partition data from remote Lance dataset.
    Uses in-memory caching for partition data to speed up subsequent searches.
    """

    def __init__(self, base_url: str):
        self.base_url = base_url
        self.centroids: Optional[np.ndarray] = None
        self.dimension: int = 0
        self.num_partitions: int = 0
        self.partition_offsets: Optional[np.ndarray] = None
        self.partition_vectors_url: Optional[str] = None
        self.has_partition_index: bool = False
        self._partition_cache: Dict[int, Dict[str, Any]] = {}

    def load(self) -> bool:
        """Load IVF index from remote dataset."""
        # Try to load centroids
        centroids_url = f"{self.base_url}/_indices/vector_idx/centroids.npy"
        try:
            data = fetch_range(centroids_url, 0, 1024 * 1024)  # First 1MB
            # Parse numpy header (simplified: assume 128-byte header)
            header_size = 128
            if len(data) > header_size:
                arr = np.frombuffer(data[header_size:], dtype=np.float32)
                self.num_partitions = 256
                self.dimension = len(arr) // self.num_partitions
                self.centroids = arr.reshape(self.num_partitions, self.dimension)
                print(f"[IVFIndex] Loaded {self.num_partitions} centroids, dim={self.dimension}")
        except Exception as e:
            print(f"[IVFIndex] No centroids found: {e}")
            return False

        # Try to load partition offsets
        offsets_url = f"{self.base_url}/_indices/vector_idx/ivf_partitions.bin"
        try:
            data = fetch_range(offsets_url, 0, (self.num_partitions + 1) * 8)
            self.partition_offsets = np.frombuffer(data, dtype=np.uint64)
            self.partition_vectors_url = f"{self.base_url}/_indices/vector_idx/ivf_vectors.bin"
            self.has_partition_index = True
            print("[IVFIndex] Loaded partition offsets")
        except Exception as e:
            print(f"[IVFIndex] No partition offsets found: {e}")

        return self.centroids is not None

    def find_nearest_partitions(self, query_vec: np.ndarray, nprobe: int = 10) -> List[int]:
        """Find nearest partition centroids."""
        if self.centroids is None:
            return []

        # Compute dot products (cosine similarity for normalized vectors)
        scores = self.centroids @ query_vec

        # Get top nprobe partitions
        top_indices = np.argsort(-scores)[:nprobe]
        return top_indices.tolist()

    def fetch_partition_data(
        self,
        partition_indices: List[int],
        dim: int,
        on_progress: Optional[Callable[[int, int], None]] = None
    ) -> Optional[Dict[str, Any]]:
        """Fetch partition data (row IDs + vectors)."""
        if not self.has_partition_index:
            return None

        all_row_ids = []
        all_vectors = []
        total_bytes = 0
        loaded_bytes = 0

        # Check cache and calculate bytes to fetch
        uncached = []
        for p in partition_indices:
            if p in self._partition_cache:
                cached = self._partition_cache[p]
                all_row_ids.extend(cached['row_ids'])
                all_vectors.extend(cached['vectors'])
            else:
                uncached.append(p)
                start = int(self.partition_offsets[p])
                end = int(self.partition_offsets[p + 1])
                total_bytes += end - start

        if not uncached:
            if on_progress:
                on_progress(100, 100)
            return {'row_ids': all_row_ids, 'vectors': all_vectors}

        print(f"[IVFIndex] Fetching {len(uncached)} partitions, {total_bytes / 1024 / 1024:.1f} MB")

        # Fetch partitions
        for p in uncached:
            start = int(self.partition_offsets[p])
            end = int(self.partition_offsets[p + 1]) - 1

            data = fetch_range(self.partition_vectors_url, start, end)

            # Parse: [row_count: uint32][row_ids: uint32 × n][vectors: float32 × n × dim]
            row_count = struct.unpack('<I', data[:4])[0]
            row_ids = np.frombuffer(data[4:4 + row_count * 4], dtype=np.uint32).tolist()
            vectors_flat = np.frombuffer(data[4 + row_count * 4:], dtype=np.float32)
            vectors = [vectors_flat[j * dim:(j + 1) * dim] for j in range(row_count)]

            # Cache
            self._partition_cache[p] = {'row_ids': row_ids, 'vectors': vectors}
            all_row_ids.extend(row_ids)
            all_vectors.extend(vectors)

            loaded_bytes += len(data)
            if on_progress:
                on_progress(loaded_bytes, total_bytes)

        return {'row_ids': all_row_ids, 'vectors': all_vectors}


class RemoteLanceDataset:
    """Remote Lance Dataset with IVF vector search.

    Example:
        dataset = RemoteLanceDataset.open("https://data.metal0.dev/laion-1m/images.lance")

        # Search
        query = np.random.randn(384).astype(np.float32)
        results = dataset.vector_search(query, top_k=10)
        print(results['indices'], results['scores'])
    """

    def __init__(self, base_url: str):
        self.base_url = base_url
        self._ivf_index: Optional[IVFIndex] = None

    @classmethod
    def open(cls, base_url: str) -> "RemoteLanceDataset":
        """Open a remote dataset."""
        dataset = cls(base_url)

        # Try to load IVF index
        dataset._ivf_index = IVFIndex(base_url)
        dataset._ivf_index.load()

        return dataset

    def has_index(self) -> bool:
        """Check if dataset has IVF index."""
        return self._ivf_index is not None and self._ivf_index.centroids is not None

    def vector_search(
        self,
        query_vec: np.ndarray,
        top_k: int = 10,
        nprobe: int = 10,
        on_progress: Optional[Callable[[int, int], None]] = None
    ) -> Dict[str, Any]:
        """Vector search using IVF index.

        Args:
            query_vec: Query vector (dim,)
            top_k: Number of results
            nprobe: Number of partitions to search
            on_progress: Progress callback (current, total)

        Returns:
            Dict with 'indices' and 'scores'
        """
        if not self.has_index():
            raise RuntimeError("No IVF index available")

        # Find nearest partitions
        partitions = self._ivf_index.find_nearest_partitions(query_vec, nprobe)

        # Fetch partition data
        data = self._ivf_index.fetch_partition_data(
            partitions,
            self._ivf_index.dimension,
            lambda loaded, total: on_progress(int(loaded / total * 80), 100) if on_progress else None
        )

        if not data or not data['row_ids']:
            raise RuntimeError("No vectors found in partitions")

        # Compute similarities using VectorAccelerator (GPU if available)
        print(f"[VectorSearch] Computing similarity for {len(data['row_ids'])} vectors via {vector_accelerator.backend}")
        scores = vector_accelerator.batch_cosine_similarity(
            query_vec.astype(np.float32),
            np.array(data['vectors'], dtype=np.float32),
            normalized=True
        )

        if on_progress:
            on_progress(90, 100)

        # Find top-k
        top_indices = np.argsort(-scores)[:top_k]

        if on_progress:
            on_progress(100, 100)

        return {
            'indices': [data['row_ids'][i] for i in top_indices],
            'scores': scores[top_indices]
        }
