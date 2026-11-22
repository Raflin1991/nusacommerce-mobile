import 'report_file_saver_stub.dart'
    if (dart.library.io) 'report_file_saver_io.dart' as saver;

/// Persists exported CSV or PDF bytes to local device storage when supported
/// (Android/iOS/Desktop) and returns the saved absolute file path, or `null` on Web.
Future<String?> saveReportExportBytes({
  required String filename,
  required List<int> bytes,
}) {
  return saver.saveReportExportBytesImpl(filename: filename, bytes: bytes);
}
