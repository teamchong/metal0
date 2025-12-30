# LanceQL Browser: Unified Data Layer for Modern Apps

## The Problem

Every modern web app needs to manage data from multiple sources:

```
┌─────────────────────────────────────────────────────────────┐
│                      Your App                                │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  REST API   │  GraphQL    │  Local State │  IndexedDB      │
│  (users)    │  (products) │  (UI)        │  (offline)      │
└──────┬──────┴──────┬──────┴──────┬───────┴────────┬────────┘
       │             │             │                │
       ▼             ▼             ▼                ▼
   React Query    Apollo      Zustand         Dexie.js
       │             │             │                │
       └─────────────┴──────┬──────┴────────────────┘
                            │
                    🔥 GLUE CODE 🔥
                    - Manual joins
                    - Type mismatches
                    - Sync logic
                    - Cache invalidation
```

**Developers spend 40%+ of their time on data plumbing, not features.**

---

## Current Solutions Fall Short

| Solution | What It Does | What's Missing |
|----------|--------------|----------------|
| **Zustand/Jotai** | Local UI state | No persistence, no queries, no remote data |
| **React Query/SWR** | Remote data + caching | Per-endpoint caching, no joins, manual sync |
| **Apollo Client** | GraphQL + cache | Requires GraphQL server, complex normalization |
| **IndexedDB/Dexie** | Browser persistence | No query language, manual schema management |
| **Redux + RTK Query** | Everything | Massive boilerplate, steep learning curve |

### The Glue Code Tax

```javascript
// Typical app: 3 data sources, 3 libraries, manual integration
function Dashboard() {
  // Source 1: REST API
  const { data: users } = useQuery('users', fetchUsers);

  // Source 2: Another API
  const { data: orders } = useQuery('orders', fetchOrders);

  // Source 3: Local storage
  const preferences = useStore(state => state.preferences);

  // 😩 Manual join - YOUR responsibility
  const enrichedUsers = useMemo(() => {
    if (!users || !orders) return [];
    return users.map(user => ({
      ...user,
      orderCount: orders.filter(o => o.userId === user.id).length,
      totalSpent: orders
        .filter(o => o.userId === user.id)
        .reduce((sum, o) => sum + o.amount, 0),
      isVIP: preferences.vipThreshold <= /* ... */
    }));
  }, [users, orders, preferences]);

  // 😩 Offline? Good luck.
  // 😩 Type safety across joins? Manual.
  // 😩 Cache invalidation? Prayer.
}
```

---

## LanceQL Browser: One Query, All Sources

```javascript
import { db } from '@lanceql/browser';

function Dashboard() {
  const { data: users } = useQuery('dashboard', () => db.query(`
    SELECT
      u.*,
      COUNT(o.id) as order_count,
      SUM(o.amount) as total_spent,
      CASE WHEN SUM(o.amount) > p.vip_threshold THEN true ELSE false END as is_vip
    FROM local://users u
    LEFT JOIN remote://api.example.com/orders.lance o ON u.id = o.user_id
    CROSS JOIN local://preferences p
    GROUP BY u.id
  `));

  // ✅ Single query across all sources
  // ✅ SQL joins - no manual mapping
  // ✅ Works offline (local:// always available)
  // ✅ Type-safe results
}
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your React/Vue/Svelte App                │
│                                                             │
│   const data = useQuery(() => db.query("SELECT ..."))       │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   LanceQL Browser SDK                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    SQL Parser                          │ │
│  │         SELECT * FROM local://users WHERE ...          │ │
│  └────────────────────────┬───────────────────────────────┘ │
│                           │                                  │
│  ┌────────────────────────▼───────────────────────────────┐ │
│  │                 Query Planner                          │ │
│  │   - Source routing (local/remote/cached)               │ │
│  │   - Join optimization                                  │ │
│  │   - Predicate pushdown                                 │ │
│  └────────────────────────┬───────────────────────────────┘ │
│                           │                                  │
│  ┌────────────────────────▼───────────────────────────────┐ │
│  │              Unified Storage Layer                     │ │
│  │                                                        │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │ │
│  │  │  OPFS    │  │  HTTP    │  │  Hot Tier Cache      │ │ │
│  │  │ (local)  │  │ (remote) │  │  (auto-cached)       │ │ │
│  │  └──────────┘  └──────────┘  └──────────────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## URL Scheme: Universal Data Addressing

```sql
-- Local data (OPFS - always available, offline-first)
SELECT * FROM local://users
SELECT * FROM local://settings

-- Remote data (HTTP Range requests - on-demand)
SELECT * FROM remote://api.example.com/products.lance
SELECT * FROM remote://cdn.example.com/analytics.lance

-- Cached remote (auto-managed hot tier)
SELECT * FROM cached://api.example.com/products.lance

-- Cross-source joins just work
SELECT u.name, p.title, o.amount
FROM local://users u
JOIN remote://api.example.com/products.lance p ON u.favorite_product = p.id
JOIN cached://orders o ON u.id = o.user_id
```

---

## Core Features

### 1. Local-First by Default

```javascript
// Data lives in OPFS first
await db.exec(`
  CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT
  )
`);

// Insert works offline
await db.exec(`INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')`);

// Query works offline
const users = await db.query(`SELECT * FROM local://users`);
```

### 2. Remote Data with Smart Caching

```javascript
// First query: fetches from remote, caches to hot tier
const products = await db.query(`
  SELECT * FROM remote://api.example.com/products.lance
  WHERE category = 'electronics'
`);

// Subsequent queries: served from cache
// Predicate pushdown: only fetches needed columns/rows
```

### 3. Sync Strategies

```javascript
// Define sync rules
db.sync({
  'local://users': {
    remote: 'https://api.example.com/users.lance',
    strategy: 'pull-on-stale',  // or 'push-on-change', 'manual'
    staleTime: 5 * 60 * 1000,   // 5 minutes
  },
  'local://orders': {
    remote: 'https://api.example.com/orders.lance',
    strategy: 'realtime',
    conflict: 'server-wins',  // or 'client-wins', 'manual'
  }
});
```

### 4. Reactive Queries

```javascript
// React hook - auto-updates when data changes
function UserList() {
  const { data, isLoading, isOffline } = useLanceQuery(`
    SELECT * FROM local://users
    ORDER BY created_at DESC
  `);

  if (isOffline) {
    return <OfflineBanner />;
  }

  return <UserTable data={data} />;
}
```

### 5. Type Safety

```typescript
// Schema inference from Lance files
type User = InferSchema<'local://users'>;
// { id: number, name: string, email: string, created_at: Date }

// Type-safe queries
const users = await db.query<User[]>(`SELECT * FROM local://users`);
```

---

## Use Cases

### 1. Offline-First Apps

```javascript
// Works without network
const todos = await db.query(`SELECT * FROM local://todos`);
await db.exec(`INSERT INTO local://todos (title) VALUES ('Buy milk')`);

// Syncs when online
db.on('online', () => db.syncAll());
```

### 2. Data-Heavy Dashboards

```javascript
// Join across multiple data sources in one query
const dashboard = await db.query(`
  SELECT
    d.date,
    SUM(s.revenue) as revenue,
    COUNT(DISTINCT u.id) as active_users,
    AVG(p.response_time) as avg_latency
  FROM local://dates d
  LEFT JOIN remote://analytics/sales.lance s ON d.date = s.date
  LEFT JOIN remote://analytics/users.lance u ON d.date = u.active_date
  LEFT JOIN cached://metrics/performance.lance p ON d.date = p.date
  WHERE d.date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  GROUP BY d.date
`);
```

### 3. E-commerce

```javascript
// Product catalog from CDN, cart local, orders synced
const cart = await db.query(`
  SELECT p.*, c.quantity, p.price * c.quantity as subtotal
  FROM local://cart c
  JOIN remote://cdn.shop.com/products.lance p ON c.product_id = p.id
`);
```

### 4. Real-time Collaboration

```javascript
// Local changes with optimistic updates
await db.exec(`UPDATE local://documents SET content = ? WHERE id = ?`, [content, docId]);

// Background sync
db.sync('local://documents', {
  strategy: 'crdt',  // Conflict-free merge
  realtime: true
});
```

---

## Comparison

| Feature | LanceQL Browser | React Query + Zustand | Apollo Client |
|---------|-----------------|----------------------|---------------|
| Local state | SQL tables | Zustand stores | Reactive vars |
| Remote data | SQL queries | Custom fetchers | GraphQL |
| Offline | OPFS (persistent) | Memory only | Memory only |
| Cross-source joins | Native SQL | Manual JS | N/A |
| Type safety | Schema inference | Manual types | Codegen |
| Bundle size | ~50KB | ~30KB + ~20KB | ~120KB |
| Learning curve | SQL | Low | High |
| Backend requirement | Lance files | Any API | GraphQL server |

---

## Implementation Roadmap

### Phase 1: Foundation (Current)
- [x] OPFS storage with chunked reads
- [x] Lance file parsing in WASM
- [x] Basic SQL execution
- [x] Memory management
- [ ] URL scheme routing (`local://`, `remote://`, `cached://`)

### Phase 2: Query Layer
- [ ] Multi-source query planning
- [ ] Cross-source JOIN execution
- [ ] Predicate pushdown to remote
- [ ] Result caching

### Phase 3: React Integration
- [ ] `useLanceQuery` hook
- [ ] Suspense support
- [ ] Optimistic updates
- [ ] DevTools

### Phase 4: Sync Engine
- [ ] Pull/push strategies
- [ ] Conflict resolution
- [ ] Real-time subscriptions
- [ ] Background sync worker

### Phase 5: Developer Experience
- [ ] TypeScript schema inference
- [ ] Migration system
- [ ] CLI tools
- [ ] Documentation site

---

## API Preview

```typescript
import { createDatabase, useLanceQuery } from '@lanceql/browser';

// Initialize
const db = await createDatabase({
  name: 'myapp',
  sources: {
    'api': 'https://api.example.com',
    'cdn': 'https://cdn.example.com'
  }
});

// Define local tables
await db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE
  )
`);

// Query across sources
const data = await db.query(`
  SELECT u.name, COUNT(o.id) as orders
  FROM local://users u
  LEFT JOIN remote://api/orders.lance o ON u.id = o.user_id
  GROUP BY u.id
`);

// React hook
function App() {
  const { data, loading, error, refetch } = useLanceQuery(`
    SELECT * FROM local://users WHERE active = true
  `);

  return <UserList users={data} />;
}
```

---

## Why Lance Format?

1. **Columnar** - Only read columns you need
2. **HTTP Range** - No full download for remote files
3. **Versioned** - Time travel, rollback
4. **ML-ready** - Vector search built-in
5. **Compact** - Efficient encoding, small files

---

## Target Users

1. **Frontend developers** tired of data plumbing
2. **Startups** who can't afford complex backends
3. **Offline-first apps** (PWAs, mobile web)
4. **Data dashboards** with multiple sources
5. **AI/ML apps** needing vector search in browser

---

## Success Metrics

- **Adoption**: 1K GitHub stars in 6 months
- **Bundle size**: <50KB gzipped
- **Performance**: <100ms query on 100K rows
- **DX**: Zero-config for simple cases
- **Reliability**: Works offline, syncs seamlessly
