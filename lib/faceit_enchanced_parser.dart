library faceit_ecnhanced_parser; // matches pubspec name (typo preserved in package name)

export 'core/config.dart';
export 'db/database.dart';
export 'services/faceit_api.dart';
export 'utils/http_client.dart';
export 'orchestration/pipeline.dart';

// Repositories (optional external usage)
export 'repositories/player_repository.dart';
export 'repositories/match_repository.dart';
export 'repositories/stats_repository.dart';
export 'repositories/activity_repository.dart';
export 'repositories/teammate_repository.dart';

// Features (in case of granular manual runs)
export 'features/ingestion/top_players_ingestor.dart';
export 'features/ingestion/player_matches_ingestor.dart';
export 'features/ingestion/player_stats_fetcher.dart';
export 'features/ingestion/recent_detailed_stats_fetcher.dart';
export 'features/processing/activity_calculator.dart';
export 'features/processing/teammates_processor.dart';
export 'features/export/export_complete_data.dart';

// Models
export 'models/player.dart';
export 'models/match.dart';
export 'models/player_stats.dart';
export 'models/player_map_stats.dart';
export 'models/activity.dart';
export 'models/recent_match_stat.dart';
