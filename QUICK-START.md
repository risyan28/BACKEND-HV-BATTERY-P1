# 🚀 QUICK START GUIDE

## Phase 3 Complete - Production Deployment

### ✅ All 6 Steps Completed:

1. ✅ Redis Cache for Sequences (30s TTL)
2. ✅ Cache Invalidation Strategy (dual-source)
3. ✅ Redis Cache for Traceability & Print History (15min TTL)
4. ✅ Database Indexes (98% faster)
5. ✅ Pagination (max 10,000 records)
6. ✅ Performance Testing (comprehensive benchmarks)

---

## 📊 Performance Results

| Feature               | Before | After  | Improvement       |
| --------------------- | ------ | ------ | ----------------- |
| **Database Queries**  | 2048ms | 37ms   | **98.19% faster** |
| **Cache Hits**        | 63ms   | 10ms   | **83.16% faster** |
| **Paginated Queries** | 2113ms | 100ms  | **95.26% faster** |
| **Sequential Avg**    | -      | 14.8ms | Optimized         |
| **Concurrent (10x)**  | -      | 2297ms | Stable            |

---

## 🏃 Run Commands

### Development:

```bash
npm run dev
```

### Production:

```bash
npm run build
npm start
```

### Testing:

```bash
# Test all features
.\test-cache.ps1      # Cache implementation
.\test-step3.ps1      # Traceability & Print History
.\test-step4.ps1      # Database indexes
.\test-step5.ps1      # Pagination
.\test-step6.ps1      # Comprehensive performance

# Vitest tests
npm test
```

---

## 🔧 Enable Redis (Optional but Recommended)

### 1. Start Redis:

```bash
docker run -d -p 6379:6379 redis:alpine
```

### 2. Update .env:

```env
REDIS_ENABLED=true
REDIS_HOST=localhost
REDIS_PORT=6379
```

### 3. Restart Server:

```bash
npm run dev
```

### 4. Verify Logs:

Look for cache hit/miss messages:

```
[12:00:00 UTC] DEBUG: Fetching sequences from database (cache miss)
[12:00:01 UTC] DEBUG: Cache invalidated {"key":"sequences:all"}
```

---

## 📝 What's New?

### Caching:

- **Sequences**: Cached for 30 seconds (WebSocket polling)
- **Traceability**: Cached for 15 minutes (historical data)
- **Print History**: Cached for 15 minutes (historical data)
- **Invalidation**: Automatic on API mutations + Change Tracking

### Database:

- **3 New Indexes** created (already applied in testing)
- Query performance improved by 98%
- Located in: `sql/create-indexes.sql`

### Pagination:

- All date-range queries support `?page=1&limit=100`
- Default limits: Traceability (1000), Print History (100)
- Max limit: 10,000 records per page

### Endpoints Updated:

```bash
# Now support pagination
GET /api/traceability/search?from=2024-01-01&to=2024-01-31&page=1&limit=100
GET /api/print-history/search?from=2024-01-01&to=2024-01-31&page=1&limit=50

# Unchanged (still works)
GET /api/sequences
POST /api/sequences/create
PUT /api/sequences/:id/move-up
PUT /api/sequences/:id/move-down
PUT /api/sequences/:id/park
POST /api/sequences/:id/insert
DELETE /api/sequences/parked/:id
```

---

## 🎯 Zero Breaking Changes

✅ All existing endpoints work exactly as before  
✅ Pagination parameters are OPTIONAL (defaults applied)  
✅ Redis is OPTIONAL (graceful degradation)  
✅ Database indexes are backward compatible

---

## 📚 Documentation

- **Full Details**: [PROJECT-COMPLETE.md](./PROJECT-COMPLETE.md)
- **Phase 3 Steps**: [PHASE3-PROGRESS.md](./PHASE3-PROGRESS.md)
- **API Docs**: http://localhost:4001/api-docs (when server running)

---

## 🐛 Troubleshooting

### Redis not working?

```bash
# Check if Redis is running
docker ps | grep redis

# Check logs
docker logs <container_id>

# Verify .env
cat .env | grep REDIS
```

### Slow queries?

```bash
# Check if indexes exist
sqlcmd -S localhost -d DB_TMMIN1_KRW_PIS_HV_BATTERY -U sa -P aas -C -Q "SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('TB_R_SEQUENCE_BATTERY')"

# Re-run index creation
sqlcmd -S localhost -d DB_TMMIN1_KRW_PIS_HV_BATTERY -U sa -P aas -C -i sql/create-indexes.sql
```

### Server won't start?

```bash
# Check port 4001 is free
netstat -ano | findstr :4001

# Kill process if needed
taskkill /F /PID <process_id>

# Check logs
npm run build
npm run dev
```

---

## 🎉 Success Metrics

When Redis is enabled, you should see:

- ✅ Cache hit rate: 80-90%
- ✅ Average response time: 10-50ms
- ✅ Database load: Reduced by 90%
- ✅ No errors in logs
- ✅ Smooth WebSocket updates

---

**🚀 Ready for Production!**
