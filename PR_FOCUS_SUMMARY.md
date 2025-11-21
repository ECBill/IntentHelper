# PR Summary: Focus State Machine Implementation

## Problem Solved

Replaced naive periodic LLM topic extraction with intelligent Focus State Machine addressing:
- ❌ Redundant topic judgments ("判定人生的价值", "人生价值的判定"...)
- ❌ Too-fast weight decay losing multi-topic context
- ❌ Fragmented intent/topic/causal analysis
- ❌ Full refresh every 5 seconds causing instability

## Solution Overview

Unified focus tracking system with:
- ✅ Multi-dimensional scoring (recency, repetition, emotion, causal, drift)
- ✅ Intelligent deduplication and merging
- ✅ Slow-tail decay preserving relevant older topics
- ✅ 6-12 active + 8 latent focuses (adaptive)
- ✅ Drift trajectory prediction
- ✅ Incremental delta updates (no full refreshes)

## Changes

**Added (1,729 lines)**:
- `lib/models/focus_models.dart` - FocusPoint, transitions, deltas
- `lib/services/focus_drift_model.dart` - Trajectory tracking
- `lib/services/focus_state_machine.dart` - Main orchestrator
- `test/focus_state_machine_test.dart` - 20 unit tests
- `FOCUS_STATE_MACHINE.md` - Documentation

**Modified (+367 lines)**:
- `lib/services/human_understanding_system.dart` - Integration
- `lib/views/human_understanding_dashboard.dart` - New "关注点" tab

## Key Algorithms

**Salience Score**:
```
S = 0.25*recency + 0.20*repetition + 0.15*emotion + 0.20*causal + 0.20*drift
```

**Recency Decay** (slow-tail):
```
f(Δt) = 1 / (1 + (Δt / 300)^0.7)
```

**Repetition** (log-scaled):
```
f(n) = log(1 + n) / log(21)
```

## Integration

```
Utterance → FocusStateMachine → Top 12 Focuses → KnowledgeGraphManager
```

- Replaces old topic tracker as primary source
- Feeds knowledge graph retrieval
- Links focuses via causal relations
- Provides drift predictions

## Testing

- ✅ 20 unit tests (initialization, ingestion, merging, scoring, limiting, stats)
- 📋 Manual validation: Dashboard → "关注点" tab

## Thesis Contribution

Solves "开放式长对话实时语音流下用户关注点漂移导致后续做事件图谱匹配困难" by maintaining persistent, multi-dimensional attention model feeding high-quality constraints to knowledge graph retrieval.
