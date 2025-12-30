/**
 * IndexedDB cache for dataset metadata.
 * Caches schema, column types, and fragment info to speed up repeat visits.
 */
export class MetadataCache {
    constructor(dbName = 'lanceql-cache', version = 1) {
        this.dbName = dbName;
        this.version = version;
        this.db = null;
    }

    async open() {
        if (this.db) return this.db;

        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.dbName, this.version);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (!db.objectStoreNames.contains('datasets')) {
                    const store = db.createObjectStore('datasets', { keyPath: 'url' });
                    store.createIndex('timestamp', 'timestamp');
                }
            };
        });
    }

    /**
     * Get cached metadata for a dataset URL.
     * @param {string} url - Dataset URL
     * @returns {Promise<Object|null>} Cached metadata or null
     */
    async get(url) {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readonly');
                const store = tx.objectStore('datasets');
                const request = store.get(url);
                request.onsuccess = () => resolve(request.result || null);
                request.onerror = () => resolve(null);
            });
        } catch (e) {
            console.warn('[MetadataCache] Get failed:', e);
            return null;
        }
    }

    /**
     * Cache metadata for a dataset URL.
     * @param {string} url - Dataset URL
     * @param {Object} metadata - Metadata to cache (schema, columnTypes, fragments, etc.)
     */
    async set(url, metadata) {
        try {
            const db = await this.open();
            return new Promise((resolve, reject) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                const data = {
                    url,
                    timestamp: Date.now(),
                    ...metadata
                };
                const request = store.put(data);
                request.onsuccess = () => resolve();
                request.onerror = () => reject(request.error);
            });
        } catch (e) {
            console.warn('[MetadataCache] Set failed:', e);
        }
    }

    /**
     * Delete cached metadata for a URL.
     * @param {string} url - Dataset URL
     */
    async delete(url) {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                store.delete(url);
                tx.oncomplete = () => resolve();
            });
        } catch (e) {
            console.warn('[MetadataCache] Delete failed:', e);
        }
    }

    /**
     * Clear all cached metadata.
     */
    async clear() {
        try {
            const db = await this.open();
            return new Promise((resolve) => {
                const tx = db.transaction('datasets', 'readwrite');
                const store = tx.objectStore('datasets');
                store.clear();
                tx.oncomplete = () => resolve();
            });
        } catch (e) {
            console.warn('[MetadataCache] Clear failed:', e);
        }
    }
}

// Global cache instance
export const metadataCache = new MetadataCache();
