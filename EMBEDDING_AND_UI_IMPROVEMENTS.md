# Event Embedding and UI Improvements

## Overview
This document describes the improvements made to the event node embedding generation and the vector query UI to enhance search accuracy and user experience.

## Problem Statement

### Issue 1: Limited Event Embedding Coverage
The original `EventNode.getEmbeddingText()` method only used 4 fields:
- `name` - Event name
- `description` - Event description  
- `purpose` - Event purpose
- `result` - Event result

However, EventNode contains many more semantically rich fields that were not being utilized:
- `type` - Event type/category
- `location` - Event location
- `startTime` / `endTime` - Temporal information
- Relationships to entities (participants, tools, locations, concepts)

**Impact**: Vector queries were less accurate because embeddings didn't capture the full semantic context of events.

### Issue 2: Similarity Scores Showing "N/A"
The vector search UI was displaying "N/A" for all similarity scores instead of the actual values.

**Root Cause**: The `rankEventsByPriority` method returns results with a `cosine_similarity` key, but the UI was looking for a `similarity` key.

**Impact**: Users couldn't see how well events matched their queries, reducing trust and usability.

## Solutions Implemented

### 1. Enhanced Event Embedding Strategy

#### Changes to `graph_models.dart`
Modified `EventNode.getEmbeddingText()` to include all available semantic fields with implicit weighting:

```dart
String getEmbeddingText() {
  final buffer = StringBuffer();

  // 1. Event name (highest weight - appears twice)
  buffer.write(name);
  
  // 2. Event type (high weight - provides categorization)
  if (type.isNotEmpty) {
    buffer.write(' ');
    buffer.write(type);
    buffer.write('类事件');  // Natural language: "{type}类事件"
  }

  // 3. Event description (high weight - main semantic content)
  if (description != null && description!.isNotEmpty) {
    buffer.write(' ');
    buffer.write(description!);
  }

  // 4. Repeat event name (further boost name weight)
  buffer.write(' ');
  buffer.write(name);

  // 5. Location (medium weight - spatial semantics)
  if (location != null && location!.isNotEmpty) {
    buffer.write(' 地点：');
    buffer.write(location!);
  }

  // 6. Time (medium weight - temporal context)
  if (startTime != null) {
    buffer.write(' 时间：');
    // Format: "YYYY年MM月DD日 HH时MM分 {period}"
    // Period: 凌晨/上午/下午/晚上
    // ... (time formatting logic)
  }

  // 7. Purpose (medium weight)
  if (purpose != null && purpose!.isNotEmpty) {
    buffer.write(' 目的：');
    buffer.write(purpose!);
  }

  // 8. Result (medium weight)
  if (result != null && result!.isNotEmpty) {
    buffer.write(' 结果：');
    buffer.write(result!);
  }

  return buffer.toString().trim();
}
```

#### Field Weighting Strategy

**High Weight Fields** (appear early and/or multiple times):
- **Name**: Appears at the beginning and again after description (2x occurrence)
- **Type**: Formatted as natural language "{type}类事件" for better semantic integration
- **Description**: Full text included once

**Medium Weight Fields** (appear once with labels):
- **Location**: Prefixed with "地点：" 
- **Time**: Formatted as natural language with period labels (凌晨/上午/下午/晚上)
- **Purpose**: Prefixed with "目的："
- **Result**: Prefixed with "结果："

**Rationale**:
1. **Repetition = Higher Weight**: The embedding service uses feature hashing that naturally gives more weight to frequently occurring tokens
2. **Natural Language Labels**: Prefixes like "地点：" and "时间：" help the model understand field semantics
3. **Temporal Context**: Converting times to natural language (e.g., "2024年11月17日 14时30分 下午") provides richer semantic context than raw timestamps
4. **Order Matters**: More important fields appear earlier in the text

### 2. Fixed Similarity Display Bug

#### Changes to `knowledge_graph_service.dart`

Added result mapping at the end of `searchEventsByTextWithPriority()`:

```dart
// 8. 🔥 修复：确保结果包含 'similarity' 键，UI需要这个字段
// 将 'cosine_similarity' 映射为 'similarity' 以保持向后兼容
final mappedResults = results.map((r) {
  return {
    'event': r['event'],
    'similarity': r['cosine_similarity'], // UI expects 'similarity'
    'cosine_similarity': r['cosine_similarity'],
    'priority_score': r['priority_score'],
    'final_score': r['final_score'],
    'components': r['components'],
  };
}).toList();

return mappedResults;
```

**Why This Works**:
- Maintains backward compatibility by including both `similarity` and `cosine_similarity` keys
- UI can access the score via either key name
- Preserves all other metadata from the priority scoring system

### 3. Improved Vector Query UI

#### Changes to `kg_test_page.dart`

**New Similarity Badge Component**:
```dart
Widget _buildSimilarityBadge(double similarity) {
  final percentage = (similarity * 100).toStringAsFixed(0);
  final color = _getSimilarityColor(similarity);
  String label;
  if (similarity >= 0.7) {
    label = '高';  // High
  } else if (similarity >= 0.4) {
    label = '中';  // Medium
  } else {
    label = '低';  // Low
  }

  return Container(
    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(color: color, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.stars, size: 14, color: color),
        SizedBox(width: 4.w),
        Text(
          '$percentage%',
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(width: 2.w),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    ),
  );
}
```

**Color Coding**:
- **Green** (>=70%): High relevance - Strong semantic match
- **Orange** (40-70%): Medium relevance - Moderate semantic match
- **Red** (<40%): Low relevance - Weak semantic match

**Enhanced Card Layout**:
1. **Header Row**: Event name + similarity badge
2. **Metadata Row**: Type label + timestamp
3. **Description**: 2-line preview of event description
4. **Location**: Icon + location text (if available)

**Improved States**:
- **Loading**: Spinner with text "正在搜索相似事件..."
- **Empty**: Icon + helpful messages
- **Results**: Shows count "找到 X 个相关事件"

## Benefits

### 1. Better Search Accuracy
- **More semantic information**: Embeddings now capture type, location, and temporal context
- **Weighted by importance**: Name appears twice, descriptions are prominent
- **Natural language formatting**: Temporal information converted to human-readable format with period labels

### 2. Improved User Experience
- **Visual feedback**: Color-coded similarity badges make it easy to assess relevance at a glance
- **Transparency**: Users can see exactly how well each result matches their query
- **Better information hierarchy**: Event cards show the most important information first
- **Professional appearance**: Enhanced visual design with proper spacing and shadows

### 3. Maintainability
- **Well-documented**: Comments explain the weighting strategy and rationale
- **Backward compatible**: Both `similarity` and `cosine_similarity` keys available
- **Extensible**: Easy to add new fields to embeddings in the future

## Migration Notes

### For Existing Embeddings
When you regenerate embeddings for existing events using the "为所有事件生成向量" button:
1. The new `getEmbeddingText()` will be used automatically
2. Existing embeddings will be replaced with enhanced versions
3. Search results should become more accurate immediately

### Recommended Actions
1. Navigate to "图谱维护" tab
2. Click "为所有事件生成向量" to regenerate all embeddings
3. Test vector search with various queries to verify improvements

## Technical Details

### Embedding Dimensions
- Vector dimensions: 384 (unchanged)
- Algorithm: Feature hashing with stable MD5-based tokenization
- Normalization: L2 normalization applied to all vectors

### Performance Considerations
- Text length increase: ~2-3x longer embedding text
- Embedding generation time: Minimal impact (text processing is fast)
- Storage: No change (same 384-dimension vectors)
- Query time: No change (cosine similarity computation unchanged)

## Future Enhancements

Potential improvements to consider:

1. **Per-field Embeddings**: Generate separate embeddings for each field and combine with learned weights
2. **Entity Embeddings**: Include semantic information from related entities (participants, tools, concepts)
3. **Hierarchical Encoding**: Use a two-level embedding (event-level + field-level)
4. **Temporal Decay**: Weight recent events higher in similarity calculations
5. **User Preferences**: Learn per-user field importance weights

## References

- Issue: "请你帮我检查一下我的向量相关的逻辑"
- Files modified:
  - `lib/models/graph_models.dart` - Enhanced getEmbeddingText()
  - `lib/services/knowledge_graph_service.dart` - Fixed similarity mapping
  - `lib/views/kg_test_page.dart` - Improved UI with color-coded badges

---

**Last Updated**: 2025-11-17
**Author**: GitHub Copilot (with assistance from code analysis)
