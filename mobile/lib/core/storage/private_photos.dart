import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The photos the person marked as private. PictoIQ never shares them or
/// puts them in a reel. The list is a small file inside the app's own
/// storage and never leaves the phone.
class PrivatePhotoStore {
  PrivatePhotoStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final Set<String> _uris = {};

  Future<File> _file() async =>
      File('${(await _directory()).path}/private_photos.json');

  /// Reads the saved list. Safe to call again; a missing or damaged file just
  /// means nothing is marked yet.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        _uris
          ..clear()
          ..addAll(decoded.whereType<String>());
      }
    } catch (error) {
      debugPrint('Private photo list unavailable: $error');
    }
  }

  bool contains(String uri) => _uris.contains(uri);

  Set<String> get all => Set.unmodifiable(_uris);

  Future<void> setPrivate(String uri, bool value) async {
    final changed = value ? _uris.add(uri) : _uris.remove(uri);
    if (!changed) return;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_uris.toList()), flush: true);
    } catch (error) {
      debugPrint('Private photo list not saved: $error');
    }
  }
}
