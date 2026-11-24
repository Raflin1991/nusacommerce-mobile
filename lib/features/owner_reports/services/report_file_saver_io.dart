import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveReportExportBytesImpl({
  required String filename,
  required List<int> bytes,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'oxora_reports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(p.join(exportDir.path, safe));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
