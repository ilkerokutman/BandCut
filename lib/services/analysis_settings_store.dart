import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/analysis_settings.dart';

class AnalysisSettingsStore {
  static const _fileName = 'analysis_settings.json';

  static Future<AnalysisSettings> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) return AnalysisSettings.defaults;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AnalysisSettings.fromJson(json);
  }

  static Future<void> save(AnalysisSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  static Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(path.join(directory.path, _fileName));
  }
}
