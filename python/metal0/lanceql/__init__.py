"""LanceQL - PyArrow-compatible driver for Lance columnar files."""

__version__ = "0.1.0"

from . import parquet
from .cache import HotTierCache, hot_tier_cache
from .vector import VectorAccelerator, vector_accelerator
from .remote import RemoteLanceDataset, IVFIndex

# polars is optional - import lazily to avoid ImportError if not installed
def __getattr__(name):
    if name == "polars":
        from . import polars
        return polars
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")

__all__ = [
    "parquet",
    "polars",
    "HotTierCache",
    "hot_tier_cache",
    "VectorAccelerator",
    "vector_accelerator",
    "RemoteLanceDataset",
    "IVFIndex",
    "__version__",
]
