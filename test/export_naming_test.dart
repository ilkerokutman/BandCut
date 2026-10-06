import 'package:bandcut/services/export_service.dart';
import 'package:bandcut/services/project_name_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('project name extraction', () {
    test('uses the complete stem when it starts with a valid date', () {
      expect(
        ProjectNameService.fromWavPath('/recordings/20261005.wav'),
        '20261005',
      );
      expect(
        ProjectNameService.fromWavPath('/recordings/2026100501.wav'),
        '2026100501',
      );
    });

    test('rejects missing and invalid date prefixes', () {
      expect(
        ProjectNameService.fromWavPath('/recordings/rehearsal.wav'),
        isNull,
      );
      expect(
        ProjectNameService.fromWavPath('/recordings/20261340.wav'),
        isNull,
      );
    });
  });

  group('export filename', () {
    test('slugifies project and track around an underscore', () {
      expect(
        ExportService.outputFileName('20261005', 'Smoke on the water'),
        '20261005_smoke-on-the-water.mp3',
      );
      expect(
        ExportService.outputFileName('My Rehearsal', 'Track 01!'),
        'my-rehearsal_track-01.mp3',
      );
    });
  });
}
