# FACEIT Enhanced Parser – Copilot Guide

## Architecture & Data Flow
- CLI entrypoint `bin/faceit_enchanced_parser.dart` loads `.env.faceit`, builds `AppDatabase`, `HttpClientWrapper`, `FaceitApi`, then runs `Pipeline`.
- `Pipeline.run` (lib/orchestration/pipeline.dart) iterates a rank-ordered slice of top players, orchestrating ingestion, processing, teammate enrichment, and JSON export.
- Ingestion modules (lib/features/ingestion/*.dart) cover top players, match history, lifetime stats, and recent detailed stats; processing modules add activity histograms and teammate analytics.
- Export logic lives in `lib/features/export/export_complete_data.dart`, emitting chunked JSON files named `faceit_complete_data_<timestamp>_part_*`. Pipeline relies on this after each batch.
- Caching sets (`_statsFetched`, `_recentFetched`, `_activityComputed`) avoid repeat API calls when a player reappears as a teammate later in the run.

## Persistence & Schema
- Database layer uses `sqflite_common_ffi`; `AppDatabase.open` (lib/db/database.dart) memoizes file-backed handles and always runs `createOrMigrate` on open.
- Schema definitions and idempotent migrations live in `lib/db/schema.dart`; when adding columns prefer the `ensureColumn` helper so reruns stay safe.
- Repositories encapsulate SQL per entity (lib/repositories/*); follow existing patterns of using transactions + batches and `ConflictAlgorithm.ignore`/`replace` for upserts.
- Players marked `processed=1` after full enrichment; pipeline reselects unprocessed rows, so new logic must preserve that contract.

## External Services
- `FaceitApi` (lib/services/faceit_api.dart) wraps all REST calls; add new endpoints here so logging and headers stay consistent.
- `HttpClientWrapper` centralizes timeout and default headers (auth bearer token, JSON accept). Reuse it instead of raw `http` client.
- Only strict 5v5 matchmaking is ingested (`competition_type == matchmaking`, `game_mode == 5v5`). Preserve these guards in new ingestion code.

## CLI & Workflows
- Run pipeline: `dart run bin/faceit_enchanced_parser.dart --start 0 --end 20 --db faceit_stats.db` (defaults start=0, end=20, db name optional).
- Ensure `.env.faceit` contains `FACEIT_API_KEY=<token>`; the CLI exits early if the key is missing.
- Export files land in the repo root by default; adjust paths in `CompleteDataExporter` if needed.
- README still references `--continue`; that flag no longer exists—stick to `--start/--end/--db/--help` when updating docs or UX.

## Conventions & Gotchas
- Package name is `faceit_ecnhanced_parser` (typo is intentional); imports must match this string.
- `AppConfig` (lib/core/config.dart) holds tuning knobs such as `matchesPerPlayer`, `activityMatchWindow`, `minTeammateMatches`; prefer modifying these or wiring new flags instead of hardcoding literals.
- Teammate enrichment expects stats/profile backfill; use `PlayerRepository.upsertDiscovered` and `TeammateRepository.upsertTeammate` rather than manual SQL.
- When touching export logic, ensure teammate payload stays aligned with primary player schema (activity, recent averages, insights).

## Testing
- Execute tests with `dart test`; `test/faceit_enchanced_parser_test.dart` runs the pipeline against an in-memory DB using `_MockHttpClient` to stub all endpoints.
- For new HTTP behavior, add cases to the mock client so smoke tests continue to cover the pipeline path without real network calls.
- Use `AppDatabase.open(inMemory: true)` and repository helpers for unit tests instead of spinning up real SQLite files.
