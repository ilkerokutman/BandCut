import 'package:path/path.dart' as path;

class ProjectNameService {
  static String? fromWavPath(String wavPath) {
    final stem = path.basenameWithoutExtension(wavPath);
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(stem);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );
    if (date == null ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      return null;
    }
    return stem;
  }
}
