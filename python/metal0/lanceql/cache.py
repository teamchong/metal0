"""HotTierCache - Disk-backed cache for remote Lance files with mmap support.

Architecture:
- First request: Fetch from R2/S3 → Cache to disk
- Subsequent requests: mmap from disk → ~1000x faster

Cache strategies:
- Small files (<10MB): Cache entire file
- Large files: Cache individual ranges/fragments on demand

Storage layout:
    {cache_dir}/
        {url_hash}/
            meta.json          - URL, size, version, cached ranges
            data.lance         - Full file (if small) or range blocks
            ranges/
                {start}-{end}  - Cached range blocks (for large files)
"""

import hashlib
import json
import mmap
import os
import time
from pathlib import Path
from typing import Optional, Dict, Any, Tuple, Callable
import urllib.request
import urllib.error


class HotTierCache:
    """High-performance local cache for remote Lance files.

    Uses mmap for near-instant access to cached files (bypasses Python I/O).

    Example:
        cache = HotTierCache()

        # Get a file (cached or fetched)
        data = await cache.get_file("https://data.metal0.dev/dataset.lance")

        # Get a byte range
        data = await cache.get_range("https://...", start=1000, end=2000)

        # Prefetch for later use
        await cache.prefetch("https://...")

        # Check stats
        print(cache.get_stats())
    """

    def __init__(
        self,
        cache_dir: Optional[str] = None,
        max_file_size: int = 10 * 1024 * 1024,  # 10MB - cache whole file
        max_cache_size: int = 500 * 1024 * 1024,  # 500MB total cache
        enabled: bool = True,
    ):
        """Initialize the cache.

        Args:
            cache_dir: Directory to store cached files. Defaults to ~/.lanceql-cache
            max_file_size: Files smaller than this are cached entirely (bytes)
            max_cache_size: Maximum total cache size (bytes)
            enabled: Whether caching is enabled
        """
        self.cache_dir = Path(cache_dir or os.path.expanduser("~/.lanceql-cache"))
        self.max_file_size = max_file_size
        self.max_cache_size = max_cache_size
        self.enabled = enabled
        self._mmap_cache: Dict[str, Tuple[int, mmap.mmap]] = {}  # path -> (fd, mmap)
        self._stats = {
            "hits": 0,
            "misses": 0,
            "bytes_from_cache": 0,
            "bytes_from_network": 0,
        }
        # In-memory cache for metadata to avoid disk reads on every get_range call
        self._meta_cache: Dict[str, Dict[str, Any]] = {}  # url -> {meta, full_file_data}

    def _get_cache_key(self, url: str) -> str:
        """Get cache key from URL (hash for safe filesystem names)."""
        return hashlib.sha256(url.encode()).hexdigest()[:16]

    def _get_cache_path(self, url: str, suffix: str = "") -> Path:
        """Get cache path for a URL."""
        key = self._get_cache_key(url)
        return self.cache_dir / key / suffix

    def is_cached(self, url: str) -> Tuple[bool, Optional[Dict[str, Any]]]:
        """Check if a URL is cached.

        Returns:
            Tuple of (is_cached, metadata_dict)
        """
        if not self.enabled:
            return False, None

        try:
            meta_path = self._get_cache_path(url, "meta.json")
            with open(meta_path, "r") as f:
                meta = json.load(f)
            return True, meta
        except (FileNotFoundError, json.JSONDecodeError):
            return False, None

    def get_file(self, url: str) -> bytes:
        """Get or fetch a file, using cache when available.

        Uses mmap for cached files for near-instant access.

        Args:
            url: Remote URL to fetch

        Returns:
            File contents as bytes
        """
        if not self.enabled:
            return self._fetch_file(url)

        self._ensure_cache_dir()

        # Check cache
        cached, meta = self.is_cached(url)
        if cached and meta and meta.get("full_file"):
            data_path = self._get_cache_path(url, "data.lance")
            try:
                data = self._mmap_read(str(data_path))
                self._stats["hits"] += 1
                self._stats["bytes_from_cache"] += len(data)
                print(f"[HotTierCache] HIT: {url} ({len(data) / 1024:.1f} KB)")
                return data
            except Exception:
                # Fallback to regular read
                with open(data_path, "rb") as f:
                    data = f.read()
                self._stats["hits"] += 1
                self._stats["bytes_from_cache"] += len(data)
                return data

        # Cache miss - fetch and cache
        self._stats["misses"] += 1
        data = self._fetch_file(url)
        self._stats["bytes_from_network"] += len(data)

        # Cache if small enough
        if len(data) <= self.max_file_size:
            self._cache_file(url, data)

        return data

    def get_range(
        self, url: str, start: int, end: int, file_size: Optional[int] = None
    ) -> bytes:
        """Get or fetch a byte range, using cache when available.

        Args:
            url: Remote URL
            start: Start byte offset
            end: End byte offset (inclusive)
            file_size: Total file size (optional, for metadata)

        Returns:
            Range data as bytes
        """
        if not self.enabled:
            return self._fetch_range(url, start, end)

        # Fast path: check in-memory cache first (no disk I/O)
        mem_cached = self._meta_cache.get(url)
        if mem_cached and mem_cached.get("full_file_data") is not None:
            data = mem_cached["full_file_data"]
            if len(data) > end:
                self._stats["hits"] += 1
                self._stats["bytes_from_cache"] += (end - start + 1)
                return data[start:end + 1]

        self._ensure_cache_dir()

        # Check disk cache (only once per URL, then cache in memory)
        if mem_cached is None:
            cached, meta = self.is_cached(url)
            if cached and meta and meta.get("full_file"):
                data_path = self._get_cache_path(url, "data.lance")
                try:
                    data = self._mmap_read(str(data_path))
                    # Cache in memory for subsequent calls
                    self._meta_cache[url] = {"meta": meta, "full_file_data": data}
                    if len(data) > end:
                        self._stats["hits"] += 1
                        self._stats["bytes_from_cache"] += (end - start + 1)
                        return data[start:end + 1]
                except Exception:
                    # Fallback to regular read
                    with open(data_path, "rb") as f:
                        full_data = f.read()
                    self._meta_cache[url] = {"meta": meta, "full_file_data": full_data}
                    if len(full_data) > end:
                        self._stats["hits"] += 1
                        self._stats["bytes_from_cache"] += (end - start + 1)
                        return full_data[start:end + 1]
            # Mark as checked even if not cached
            self._meta_cache[url] = {"meta": meta if cached else None, "full_file_data": None}

        # Cache miss - fetch from network
        self._stats["misses"] += 1
        data = self._fetch_range(url, start, end)
        self._stats["bytes_from_network"] += len(data)

        # Don't cache individual ranges - too slow for many small reads
        # Only full files are cached (via prefetch)

        return data

    def _mmap_read(
        self, file_path: str, offset: int = 0, length: Optional[int] = None
    ) -> bytes:
        """Read file using mmap for zero-copy access.

        Keeps mmap handles open for repeated access (simulating persistent mapping).
        """
        # Check if we have this file mmap'd already
        if file_path in self._mmap_cache:
            fd, mm = self._mmap_cache[file_path]
            if length is None:
                return mm[:]
            return mm[offset:offset + length]

        # Open and mmap the file
        fd = os.open(file_path, os.O_RDONLY)
        try:
            file_size = os.fstat(fd).st_size
            mm = mmap.mmap(fd, file_size, access=mmap.ACCESS_READ)

            # Cache the mmap handle
            self._mmap_cache[file_path] = (fd, mm)

            if length is None:
                return mm[:]
            return mm[offset:offset + length]
        except Exception:
            os.close(fd)
            raise

    def prefetch(
        self, url: str, on_progress: Optional[Callable[[int, int], None]] = None
    ) -> None:
        """Prefetch and cache an entire file.

        Args:
            url: Remote URL to prefetch
            on_progress: Optional callback (bytes_loaded, total_bytes)
        """
        self._ensure_cache_dir()

        cached, meta = self.is_cached(url)
        if cached and meta and meta.get("full_file"):
            print(f"[HotTierCache] Already cached: {url}")
            return

        print(f"[HotTierCache] Prefetching: {url}")
        data = self._fetch_file(url, on_progress)
        self._cache_file(url, data)
        print(f"[HotTierCache] Cached: {url} ({len(data) / 1024 / 1024:.2f} MB)")

    def evict(self, url: str) -> None:
        """Evict a URL from cache."""
        cache_path = self._get_cache_path(url)

        # Close any mmap'd files
        data_path = str(cache_path / "data.lance")
        if data_path in self._mmap_cache:
            fd, mm = self._mmap_cache.pop(data_path)
            mm.close()
            os.close(fd)

        # Remove directory recursively
        import shutil
        try:
            shutil.rmtree(cache_path)
            print(f"[HotTierCache] Evicted: {url}")
        except FileNotFoundError:
            pass

    def clear(self) -> None:
        """Clear entire cache."""
        # Close all mmap'd files
        for file_path, (fd, mm) in list(self._mmap_cache.items()):
            mm.close()
            os.close(fd)
        self._mmap_cache.clear()

        # Remove cache directory
        import shutil
        try:
            shutil.rmtree(self.cache_dir)
        except FileNotFoundError:
            pass

        self._ensure_cache_dir()
        self._stats = {
            "hits": 0, "misses": 0,
            "bytes_from_cache": 0, "bytes_from_network": 0
        }
        print("[HotTierCache] Cleared all cache")

    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        total = self._stats["hits"] + self._stats["misses"]
        hit_rate = (self._stats["hits"] / total * 100) if total > 0 else 0
        return {
            **self._stats,
            "hit_rate": f"{hit_rate:.1f}%",
            "bytes_from_cache_mb": f"{self._stats['bytes_from_cache'] / 1024 / 1024:.2f}",
            "bytes_from_network_mb": f"{self._stats['bytes_from_network'] / 1024 / 1024:.2f}",
        }

    def _ensure_cache_dir(self) -> None:
        """Ensure cache directory exists."""
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _fetch_file(
        self, url: str, on_progress: Optional[Callable[[int, int], None]] = None
    ) -> bytes:
        """Fetch file from network."""
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            total = int(response.headers.get("Content-Length", 0))
            chunks = []
            loaded = 0

            while True:
                chunk = response.read(65536)  # 64KB chunks
                if not chunk:
                    break
                chunks.append(chunk)
                loaded += len(chunk)
                if on_progress:
                    on_progress(loaded, total)

            return b"".join(chunks)

    def _fetch_range(self, url: str, start: int, end: int) -> bytes:
        """Fetch range from network."""
        req = urllib.request.Request(url)
        req.add_header("Range", f"bytes={start}-{end}")
        with urllib.request.urlopen(req) as response:
            return response.read()

    def _cache_file(self, url: str, data: bytes) -> None:
        """Cache a full file."""
        cache_path = self._get_cache_path(url)
        cache_path.mkdir(parents=True, exist_ok=True)

        meta_path = cache_path / "meta.json"
        data_path = cache_path / "data.lance"

        meta = {
            "url": url,
            "size": len(data),
            "cached_at": time.time(),
            "full_file": True,
            "ranges": None,
        }

        with open(meta_path, "w") as f:
            json.dump(meta, f)
        with open(data_path, "wb") as f:
            f.write(data)

    def _cache_range(
        self, url: str, start: int, end: int, data: bytes, file_size: Optional[int]
    ) -> None:
        """Cache a byte range."""
        cache_path = self._get_cache_path(url)
        ranges_path = cache_path / "ranges"
        ranges_path.mkdir(parents=True, exist_ok=True)

        meta_path = cache_path / "meta.json"
        range_path = ranges_path / f"{start}-{end}"

        # Load existing meta or create new
        cached, existing_meta = self.is_cached(url)
        if cached and existing_meta:
            meta = existing_meta
            meta["ranges"] = meta.get("ranges") or []
        else:
            meta = {
                "url": url,
                "size": file_size,
                "cached_at": time.time(),
                "full_file": False,
                "ranges": [],
            }

        # Add this range
        meta["ranges"].append({"start": start, "end": end, "cached_at": time.time()})
        meta["ranges"] = self._merge_ranges(meta["ranges"])

        with open(meta_path, "w") as f:
            json.dump(meta, f)
        with open(range_path, "wb") as f:
            f.write(data)

    def _merge_ranges(self, ranges: list) -> list:
        """Merge overlapping ranges."""
        if len(ranges) <= 1:
            return ranges

        ranges.sort(key=lambda r: r["start"])
        merged = [ranges[0]]

        for i in range(1, len(ranges)):
            last = merged[-1]
            current = ranges[i]

            if current["start"] <= last["end"] + 1:
                last["end"] = max(last["end"], current["end"])
            else:
                merged.append(current)

        return merged


# Global hot-tier cache instance
hot_tier_cache = HotTierCache()
