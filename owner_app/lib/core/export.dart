import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'format.dart';

/// "Export all data": one Excel sheet per table, then the share sheet.
Future<void> exportAllData() async {
  final r = await Api.call('export_data');
  final data = Map<String, dynamic>.from(r['data']);
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  for (final entry in data.entries) {
    final rows = (entry.value as List).map((e) => Map<String, dynamic>.from(e)).toList();
    final sheet = excel[entry.key];
    final cols = <String>{};
    for (final row in rows) {
      cols.addAll(row.keys);
    }
    final header = cols.toList();
    sheet.appendRow(header.map((h) => TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(header.map<CellValue?>((h) {
        final v = row[h];
        if (v == null) return null;
        if (v is int) return IntCellValue(v);
        if (v is double) return DoubleCellValue(v);
        if (v is bool) return BoolCellValue(v);
        if (v is Map || v is List) return TextCellValue(jsonEncode(v));
        return TextCellValue('$v');
      }).toList());
    }
  }
  if (defaultSheet != null && !data.containsKey(defaultSheet)) excel.delete(defaultSheet);

  final bytes = excel.encode();
  if (bytes == null) throw ApiError('EXPORT', 'Could not create the Excel file');
  final name = 'cook-dashboard-export-${ymd(istToday())}.xlsx';
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: name,
      ),
    ],
    text: 'Cook Dashboard – all data',
  ));
}
