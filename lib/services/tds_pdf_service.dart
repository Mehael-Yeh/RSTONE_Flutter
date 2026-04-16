import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product_item.dart';

class TdsPdfService {
  static final RegExp _headingReg = RegExp(r'^(#{1,3})\s*(.+)$');

  static Future<File> generateAndShareTds(ProductItem product) async {
    final bytes = await _buildPdf(product);
    final dir = await getTemporaryDirectory();
    final safeName = product.fileName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final file = File('${dir.path}/${safeName}_TDS.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${product.fileName}_TDS.pdf',
    );

    return file;
  }

  static Future<Uint8List> _buildPdf(ProductItem product) async {
    final body = _extractMarkdownBody(product.rawContent);
    final parsed = _parseTdsSections(body);

    final doc = pw.Document();
    final baseFont = await PdfGoogleFonts.notoSansSCRegular();
    final boldFont = await PdfGoogleFonts.notoSansSCBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (context) => [
          _buildHeader(product),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              '产品技术数据表（TDS）',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(product.fileName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (parsed.subtitle != null) ...[
            pw.Text(parsed.subtitle!, style: const pw.TextStyle(fontSize: 13)),
            pw.SizedBox(height: 12),
          ],
          ...parsed.sections.map(_buildSection),
          pw.SizedBox(height: 14),
          _buildDisclaimer(parsed.disclaimer),
          pw.Spacer(),
          _buildFooter(),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader(ProductItem product) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'RSTONE',
              style: pw.TextStyle(
                fontSize: 48,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('嘉兴锐石化工有限公司', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('RSTONE (Jia Xing) Resins Company', style: const pw.TextStyle(fontSize: 14)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildSection(_TdsSection section) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            pw.Text(section.title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
          ],
          if (section.paragraphs.isNotEmpty)
            ...section.paragraphs.map(
              (line) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 12, lineSpacing: 2)),
              ),
            ),
          if (section.tableRows != null && section.tableRows!.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              cellStyle: const pw.TextStyle(fontSize: 12),
              cellAlignment: pw.Alignment.center,
              border: pw.TableBorder(
                top: const pw.BorderSide(width: 1),
                bottom: const pw.BorderSide(width: 1),
                horizontalInside: pw.BorderSide(width: 0.6, color: PdfColors.grey500),
              ),
              headers: section.tableRows!.first,
              data: section.tableRows!.length > 1 ? section.tableRows!.sublist(1) : const <List<String>>[],
            ),
          if (section.note != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(section.note!, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildDisclaimer(List<String> disclaimer) {
    final lines = disclaimer.isEmpty
        ? const [
            '锐石为客户提供材料参考信息。请在使用前进行充分评估，确保产品适用于具体用途。',
            '本技术数据仅作参考，不应视作任何担保或法律承诺。',
          ]
        : disclaimer;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('免责声明', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        ...lines.map((line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
            )),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 6),
        pw.Text('锐石主要从事紫外光固化（UV）树脂及水性乳液的研发、制造和销售，旨在创造世界级的中国化工品牌',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('地址 ADD: 浙江省嘉兴市秀洲区油车港镇永越大厦11楼1102', style: pw.TextStyle(fontSize: 11)),
            pw.Text('电话/传真 TEL/FAX: 15067388778 0573-82203606', style: pw.TextStyle(fontSize: 11)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('网址 WEBSITE: http://www.rstone-resin.com/', style: pw.TextStyle(fontSize: 11)),
            pw.Text('邮箱 EMAIL: zhoulei22kb@rstone-resin.com', style: pw.TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  static String _extractMarkdownBody(String rawContent) {
    final normalized = rawContent.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return normalized.trim();
    }

    final endIndex = normalized.indexOf('\n---\n', 4);
    if (endIndex == -1) {
      return normalized.trim();
    }
    return normalized.substring(endIndex + 5).trim();
  }

  static _ParsedTds _parseTdsSections(String markdown) {
    final lines = markdown.split('\n').map((line) => line.trim()).toList();
    String? subtitle;
    final sections = <_TdsSection>[];
    final disclaimer = <String>[];

    _TdsSection? current;
    bool inDisclaimer = false;

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('>')) {
        current ??= _TdsSection(title: '', paragraphs: []);
        current.note = line.replaceFirst(RegExp(r'^>\s*'), '').trim();
        continue;
      }

      final headingMatch = _headingReg.firstMatch(line);
      if (headingMatch != null) {
        final heading = headingMatch.group(2)!.trim();

        if (subtitle == null && heading.startsWith('RD')) {
          subtitle = heading;
          continue;
        }

        if (current != null) sections.add(current);
        current = _TdsSection(title: heading, paragraphs: []);
        inDisclaimer = heading.contains('免责声明');
        continue;
      }

      if (line.startsWith('|')) {
        current ??= _TdsSection(title: '', paragraphs: []);
        current.tableRows ??= [];
        if (!RegExp(r'^\|?\s*[-:| ]+\|?$').hasMatch(line)) {
          current.tableRows!.add(
            line
                .split('|')
                .map((cell) => cell.trim())
                .where((cell) => cell.isNotEmpty)
                .toList(),
          );
        }
        continue;
      }

      if (subtitle == null) {
        subtitle = line;
        continue;
      }

      if (inDisclaimer) {
        disclaimer.add(line.replaceFirst(RegExp(r'^\d+[.、]\s*'), ''));
      } else {
        current ??= _TdsSection(title: '', paragraphs: []);
        current.paragraphs.add(line.replaceFirst(RegExp(r'^\d+[.、]\s*'), ''));
      }
    }

    if (current != null) sections.add(current);

    return _ParsedTds(subtitle: subtitle, sections: sections, disclaimer: disclaimer);
  }
}

class _ParsedTds {
  const _ParsedTds({
    required this.subtitle,
    required this.sections,
    required this.disclaimer,
  });

  final String? subtitle;
  final List<_TdsSection> sections;
  final List<String> disclaimer;
}

class _TdsSection {
  _TdsSection({
    required this.title,
    required this.paragraphs,
    this.tableRows,
    this.note,
  });

  final String title;
  final List<String> paragraphs;
  List<List<String>>? tableRows;
  String? note;
}
