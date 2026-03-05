import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../models/game_info.dart';

/// Manages persisted game list using SharedPreferences.
class GameManager {
  static const String _storageKey = 'krkr2_game_list';
  static const int _maxSessionSeconds = 86400; // 24h cap per session

  List<GameInfo> _games = [];

  List<GameInfo> get games => List.unmodifiable(_games);

  /// Load the game list from persistent storage.
  /// Call [applyPendingPlaySession] after this to credit play time if the app was last closed while in a game.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      _games = GameInfo.listFromJsonString(raw);
    }
  }

  /// If a pending play session exists (app was closed/killed while in game), add that duration and clear the pending session.
  Future<void> applyPendingPlaySession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(PrefsKeys.pendingPlaySession);
    if (jsonStr == null || jsonStr.isEmpty) return;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>?;
    } catch (_) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }
    final path = data!['path'] as String?;
    final startStr = data['startTime'] as String?;
    if (path == null || startStr == null) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    final start = DateTime.tryParse(startStr);
    if (start == null) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds <= 0 || seconds > _maxSessionSeconds) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    if (!_games.any((g) => g.path == path)) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }
    await addPlayDuration(path, seconds);
    await prefs.remove(PrefsKeys.pendingPlaySession);
  }

  /// Save the current game list to persistent storage.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, GameInfo.listToJsonString(_games));
  }

  /// Add a game. Returns true if added (not a duplicate).
  Future<bool> addGame(GameInfo game) async {
    // Deduplicate by path
    if (_games.any((g) => g.path == game.path)) {
      return false;
    }
    _games.add(game);
    await _save();
    return true;
  }

  /// Remove a game by path.
  Future<void> removeGame(String path) async {
    _games.removeWhere((g) => g.path == path);
    await _save();
  }

  /// Update the lastPlayed timestamp for a game.
  Future<void> markPlayed(String path) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].lastPlayed = DateTime.now();
      await _save();
    }
  }

  /// Add play duration (in seconds) for a game. Called when leaving the game page.
  Future<void> addPlayDuration(String path, int seconds) async {
    if (seconds <= 0) return;
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      final current = _games[index].playDurationSeconds ?? 0;
      _games[index].playDurationSeconds = current + seconds;
      await _save();
    }
  }

  /// Rename a game's title.
  Future<void> renameGame(String path, String newTitle) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].title = newTitle;
      await _save();
    }
  }

  /// Update a game's path (e.g. when iOS sandbox container UUID changes).
  Future<void> updateGamePath(String oldPath, String newPath) async {
    final index = _games.indexWhere((g) => g.path == oldPath);
    if (index >= 0) {
      _games[index].path = newPath;
      await _save();
    }
  }

  /// Set a custom cover image path for a game.
  Future<void> setCoverImage(String path, String? coverPath) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].coverPath = coverPath;
      await _save();
    }
  }
}
