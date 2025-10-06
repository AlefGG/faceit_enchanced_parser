# Architecture Overview

This document summarizes the modular architecture for the FACEIT CS2 statistics collector and exporter.

## Goals
- Strict 5v5 matchmaking only (exclude hubs/pugs/other modes)
- Minimal duplicate HTTP/API calls (caching inside one pipeline run)
- Teammate enrichment parity (lifetime + per-map stats, recent 20 averages, activity distributions, insights, profile info)
- Deterministic, resumable pipeline: players processed in rank order; each marked processed after full enrichment
- Single JSON export containing players and embedded teammates with aggregated metrics

## Layered Structure
```
lib/
  core/            -> Global config constants
  db/              -> Schema + database open helpers
  models/          -> Data models & (de)serialization maps
  repositories/    -> Encapsulated SQL per entity
  services/        -> External API wrappers (FaceitApi + HttpClientWrapper)
  features/
    ingestion/     -> Top players, matches, stats, recent detailed stats
    processing/    -> Activity calculator, teammates processor
    export/        -> Complete JSON exporter
  orchestration/   -> Pipeline coordination + logging + caching
  utils/           -> Generic helpers (HTTP)
```

## Data Flow (Per Player)
1. Ensure top player list (rank ordered) up to desired end index.
2. Select unprocessed players in the requested index range.
3. For each player:
   - Fetch lifetime + per-map stats (cached set `_statsFetched`).
   - Ingest match history (up to `matchesPerPlayer`).
   - Fetch recent detailed match stats for last 20 matches (`_recentFetched`).
   - Recompute activity distributions + insights for 20-match window (`_activityComputed`).
   - Discover & aggregate teammates with >= `minTeammateMatches` shared matches.
   - For each teammate: fetch recent detailed stats + activity (cached) and lifetime stats if missing (performed in teammates processor).
   - Mark player processed.
4. After batch: export single JSON snapshot.

## Caching (In-Memory, Per Run)
- `_statsFetched`: Players whose lifetime/per-map stats already stored.
- `_recentFetched`: Players whose recent per-match detailed stats pulled for the 20-match window.
- `_activityComputed`: Players whose activity (weekday/hour histogram + insights) computed.

This reduces redundant API calls when a player appears first as a teammate then later as a top-ranked primary (or vice versa).

## Activity & Insights
- Activity window: last 20 matches (config `activityMatchWindow`).
- Histograms: weekday (0-6) and hour (0-23).
- Insights: top active weekday, hour, and combined weekday-hour density.

## Teammates
- Aggregated from ingested matches after a player's match history is processed.
- Filter: `minTeammateMatches` shared matches (default 5).
- Each teammate enriched with:
  - Profile (nickname, country, skill level, elo)
  - Lifetime stats + per-map stats (lazy only if absent)
  - Recent 20-match average stats via detailed stats table
  - Activity + insights (same 20-match window logic)

## Export Schema (High-Level)
```
[
  {
    player_id, nickname, country, skill_level, faceit_elo,
    stats: { lifetime fields ... },
    map_stats: [ { map, matches, wins, kills, deaths, headshots_percent, ... } ],
    recent_20_avg_stats: { kills, deaths, assists, kd, hs_percent, ... },
    activity: { weekday: {...}, hour: {...} },
    activity_insights: { top_weekday, top_hour, top_weekday_hour },
    teammates: [ same structure (subset) for each teammate ]
  }
]
```

## Error Handling & Retries
- Single attempt per HTTP call (no retry) per requirements.
- Failures logged; missing data simply omitted (graceful degradation).

## Logging
- `[PLAYER_PROGRESS] start/done` lines with index, percent, performance metrics.
- `[PIPELINE_SUMMARY]` final aggregate timing.

## Future Enhancements (Suggested)
- Persistent caching layer for profiles & match detailed stats (avoid re-fetch across runs)
- Command-line configurable windows & thresholds
- Additional metrics (clutch stats, weapon stats) if endpoints allow
- Parallelization with controlled concurrency (rate limiting) for larger ranges

## Testing Strategy
- In-memory DB smoke test (basic pipeline run with mocked HTTP)
- Unit tests for repositories (CRUD invariants)
- Integration tests for pipeline with recorded fixtures (TODO)

## Configuration Constants (`core/config.dart`)
- `matchesPerPlayer = 300`
- `activityMatchWindow = 20`
- `minTeammateMatches = 5`

All tunable; consider environment variable override in future.

---
This document reflects codebase state as of 2025-10-06.
