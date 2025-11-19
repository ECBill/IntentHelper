# OpenAI Embedding Integration

## Overview

The embedding service now uses OpenAI's `text-embedding-3-small` API as the primary embedding provider, with graceful fallback to the local `gte-small` model.

## Architecture

```
User Request
     ↓
generateTextEmbedding()
     ↓
Check Cache ──[HIT]──→ Return Cached Embedding
     ↓ [MISS]
Initialize OpenAI API Key (if not already)
     ↓
Try OpenAI API (text-embedding-3-small)
     ↓
  ┌──[SUCCESS]──→ Resize 1536d → 384d → Return
  │
  └──[FAILURE]──→ Try Local GTE Model
           ↓
        ┌──[SUCCESS]──→ Return 384d Embedding
        │
        └──[FAILURE]──→ Semantic Fallback → Return 384d Hash-based Embedding
```

## Configuration

### API Key Sources (Priority Order)
1. **ObjectBox Database** - `getConfigsByProvider("OpenAI")`
2. **FlutterForegroundTask** - `getData(key: 'llmToken')`
3. **Environment File** - `.env` file with `OPENAI_API_KEY`

### OpenAI Settings
- **Endpoint:** `https://api.openai.com/v1/embeddings`
- **Model:** `text-embedding-3-small`
- **Output Dimensions:** 1536 (resized to 384 for compatibility)
- **Timeout:** 30 seconds

### Local Model Fallback
- **Model:** gte-small (ONNX)
- **Output Dimensions:** 384
- **Used when:** OpenAI API fails or is unavailable

## Logging

All logs are prefixed with `[EmbeddingService]` for easy filtering and debugging.

### Example Log Flow

#### Successful OpenAI Request:
```
[EmbeddingService] 🔄 开始初始化 OpenAI embedding API...
[EmbeddingService] ✅ 从数据库获取到 OpenAI API Key
[EmbeddingService] ✅ OpenAI embedding API 初始化完成
[EmbeddingService] request.start provider=openai text_length=50 model=text-embedding-3-small
[EmbeddingService] request.success provider=openai latency=412ms original_dims=1536
[EmbeddingService] result.delivered source=openai dims=384 latency=412ms
```

#### OpenAI Failure with Fallback:
```
[EmbeddingService] request.start provider=openai text_length=50 model=text-embedding-3-small
[EmbeddingService] request.failure provider=openai status=502 error=Bad Gateway latency=523ms
[EmbeddingService] fallback.start provider=gte-small reason=openai_failed text_length=50
[EmbeddingService] fallback.success provider=gte-small latency=89ms dims=384
[EmbeddingService] result.delivered source=gte-small dims=384 latency=89ms
```

#### OpenAI Unavailable:
```
[EmbeddingService] ⚠️ 未找到 OpenAI API Key，将仅使用本地模型
[EmbeddingService] fallback.start provider=gte-small reason=openai_unavailable text_length=50
[EmbeddingService] fallback.success provider=gte-small latency=92ms dims=384
[EmbeddingService] result.delivered source=gte-small dims=384 latency=92ms
```

## Error Handling

### Error Types Handled:
1. **Timeout** - 30 second timeout on OpenAI API calls
2. **Network Errors** - `SocketException` for connectivity issues
3. **HTTP Errors** - Non-2xx status codes (401, 429, 500, etc.)
4. **Empty Response** - Malformed or empty data from API
5. **General Exceptions** - Catch-all for unexpected errors

### Fallback Strategy:
1. **Primary:** OpenAI API (`text-embedding-3-small`)
2. **Secondary:** Local ONNX model (`gte-small`)
3. **Tertiary:** Semantic hash-based fallback

All failures are logged with detailed error information for troubleshooting.

## Dimension Handling

### OpenAI to Local Compatibility:
- **OpenAI:** 1536 dimensions → resized to 384 dimensions
- **Local:** 384 dimensions (native)
- **Method:** Uses existing `_resizeEmbedding()` function
  - Truncates if source > target
  - Repeats pattern if source < target

This ensures all embeddings are 384 dimensions regardless of source, maintaining compatibility with:
- EventNode HNSW index (@HnswIndex(dimensions: 384))
- All existing similarity search functions
- Cached embeddings

## Performance Considerations

### Caching:
- All embeddings are cached by text hash
- Cache key includes fallback version number
- Reduces redundant API calls and local model inference

### Latency:
- **OpenAI API:** ~300-600ms (network dependent)
- **Local Model:** ~80-150ms (device dependent)
- **Semantic Fallback:** ~1-5ms (instant)

### Cost Optimization:
- Cache prevents duplicate OpenAI API calls
- Fallback to free local model on failure
- No retry logic to avoid runaway costs

## Testing

### Test Coverage:
1. OpenAI initialization without crashing when API key unavailable
2. Fallback to local model when OpenAI fails
3. Empty text handling (returns null)
4. Caching behavior (same text returns same embedding)
5. Dimension consistency (all embeddings are 384d)

### Manual Testing:
Run with various scenarios:
- With valid OpenAI API key
- Without OpenAI API key
- With network disconnected
- With invalid API key

Check logs to verify fallback behavior.

## Migration Notes

### Backward Compatibility:
✅ **No breaking changes** - all embeddings remain 384 dimensions
✅ **Existing consumers work unchanged** - API interface unchanged
✅ **Graceful degradation** - works without OpenAI API key

### What Changed:
- Embedding quality improved when OpenAI is available
- More detailed logging for troubleshooting
- Automatic fallback ensures service reliability

### What Stayed the Same:
- Vector dimensions (384)
- Method signatures
- Cache behavior
- Similarity search functions

## Troubleshooting

### Issue: "未找到 OpenAI API Key"
**Solution:** Add API key to one of:
1. ObjectBox database (provider: "OpenAI")
2. FlutterForegroundTask data (key: 'llmToken')
3. `.env` file (OPENAI_API_KEY=sk-...)

### Issue: OpenAI API always fails
**Check:**
- API key is valid
- Network connectivity
- OpenAI service status
- Logs show actual error (timeout, 401, 429, etc.)

### Issue: Poor embedding quality
**If using local fallback:**
- Verify OpenAI API key is configured
- Check logs to see which provider is being used
- OpenAI quality > local model quality

### Issue: High latency
**If using OpenAI:**
- Normal latency is 300-600ms
- Use cache to avoid repeated calls
- Consider batch processing for multiple texts

**If using local model:**
- First inference is slow (model loading)
- Subsequent calls are faster (~80-150ms)

## Future Enhancements

Potential improvements (not implemented):
- [ ] Batch embedding API calls for multiple texts
- [ ] Circuit breaker pattern for repeated OpenAI failures
- [ ] Configurable retry logic with exponential backoff
- [ ] Support for other OpenAI embedding models
- [ ] Dimension-matched local model (1536d) to avoid resizing
- [ ] Telemetry for provider usage statistics
- [ ] Rate limiting awareness (429 handling with backoff)
