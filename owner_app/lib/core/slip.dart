import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'format.dart';

/// Payment slips are generated as PDF on the server (generate_slip) and
/// downloaded here to share as PDF or as an image.
class Slips {
  static final _cache = <String, Uint8List>{};

  static Future<Uint8List> pdf(String month, {bool fresh = false}) async {
    if (!fresh && _cache.containsKey(month)) return _cache[month]!;
    final r = await Api.call('generate_slip', {'month': month});
    final res = await http.get(Uri.parse('${r['url']}'));
    if (res.statusCode != 200) throw ApiError('SLIP', 'Could not download the slip');
    return _cache[month] = res.bodyBytes;
  }

  static Future<Uint8List> png(String month) async {
    final bytes = await pdf(month);
    await for (final page in Printing.raster(bytes, pages: [0], dpi: 150)) {
      return await page.toPng();
    }
    throw ApiError('SLIP', 'Could not create the image');
  }

  static String _name(String month) => 'payslip-$month';

  /// Opens the share sheet (WhatsApp is listed there).
  static Future<void> sharePdf(String month) async {
    final bytes = await pdf(month, fresh: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${_name(month)}.pdf')],
      text: 'Payment slip – ${monthLabel(month)}',
    ));
  }

  static Future<void> shareImage(String month) async {
    await pdf(month, fresh: true);
    final bytes = await png(month);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: '${_name(month)}.png')],
      text: 'Payment slip – ${monthLabel(month)}',
    ));
  }

  /// System print dialog – also offers "Save as PDF".
  static Future<void> printOrSave(String month) async {
    final bytes = await pdf(month, fresh: true);
    await Printing.layoutPdf(name: '${_name(month)}.pdf', onLayout: (_) async => bytes);
  }
}
