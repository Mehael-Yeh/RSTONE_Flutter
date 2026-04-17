import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product_item.dart';

class TdsPdfService {
  static final RegExp _headingReg = RegExp(r'^(#{1,3})\s*(.+)$');

  static const List<String> _defaultDisclaimer = [
    '锐石为客户提供物料安全资料表，提供有关本产品的潜在健康影响、安全处理、贮存、使用和弃置的信息。锐石鼓励客户在使用锐石产品和其它原料之前先查阅物料安全资料表，以确保人身和环境安全。为了确保锐石的产品不被滥用于非指定用途或未经测试的用途，锐石的员工可帮助客户处理生态及产品安全方面的问题。您的锐石销售代表可安排适当联络。',
    '但是关于产品特性、应用、质量、安全性、产品规格、适销性，以及针对特定用途的适用性，本技术数据表中所涉及的内容仅供参考，无论是明示或隐含的信息，我们不提供任何保证。在此提供的任何信息不应被视作实施专利技术的许可，也不应被视作未经专利所有人许可的前提下实施专利技术的诱导。',
  ];

  static Future<File> generateAndShareTds(
    ProductItem product, {
    required String tdsMarkdown,
  }) async {
    final bytes = await _buildPdf(product, tdsMarkdown: tdsMarkdown);
    final dir = await getTemporaryDirectory();
    final safeName = product.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    final fileName = '${safeName.isEmpty ? '产品' : safeName} TDS(CN).pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${product.fileName} TDS(CN).pdf',
    );

    return file;
  }

  static Future<Uint8List> _buildPdf(
    ProductItem product, {
    required String tdsMarkdown,
  }) async {
    final body = _extractMarkdownBody(tdsMarkdown);
    final parsed = _parseTdsSections(body);
    final subtitle = _normalizeTextForPdf(parsed.subtitle);
    final shouldShowSubtitle = subtitle != null && !_isDuplicateSubtitle(subtitle, product.fileName);

    final pdfFonts = _PdfFonts(
      songtiRegular: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/SimSun.ttf', 'assets/fonts/simsun.ttf', 'assets/fonts/STSong.ttf'],
        fallback: PdfGoogleFonts.notoSerifSCRegular,
      ),
      songtiBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/SimSun-Bold.ttf', 'assets/fonts/simsunb.ttf'],
        fallback: PdfGoogleFonts.notoSerifSCBold,
      ),
      arialRegular: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/Arial.ttf', 'assets/fonts/arial.ttf'],
        fallback: PdfGoogleFonts.robotoRegular,
      ),
      yaheiBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/msyh.ttf', 'assets/fonts/MicrosoftYaHei.ttf', 'assets/fonts/微软雅黑.ttf'],
        fallback: PdfGoogleFonts.notoSansSCBold,
      ),
      impactLikeBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/Impact.ttf', 'assets/fonts/impact.ttf'],
        fallback: PdfGoogleFonts.oswaldBold,
      ),
    );

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 18, 24, 22),
        theme: pw.ThemeData.withFont(base: pdfFonts.songtiRegular, bold: pdfFonts.songtiBold),
        header: (context) => _buildHeader(pdfFonts),
        footer: (context) => _buildFooter(pdfFonts),
        build: (context) => [
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              '产品技术数据表（TDS）',
              style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            product.fileName,
            style: pw.TextStyle(font: pdfFonts.yaheiBold, fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (shouldShowSubtitle) ...[
            pw.Text(subtitle!, style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 10.5)),
            pw.SizedBox(height: 10),
          ],
          ...parsed.sections.map((section) => _buildSection(section, pdfFonts)),
          _buildDisclaimerSection(pdfFonts),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader(_PdfFonts pdfFonts) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'R',
                    style: pw.TextStyle(
                      font: pdfFonts.impactLikeBold,
                      fontSize: 48,
                      color: PdfColors.red,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: 'STONE',
                    style: pw.TextStyle(
                      font: pdfFonts.impactLikeBold,
                      fontSize: 28,
                      color: PdfColors.red,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  '嘉兴锐石化工有限公司',
                  style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'RSTONE (Jia Xing) Resins Company',
                  style: pw.TextStyle(font: pdfFonts.arialRegular, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 4, color: PdfColors.grey600),
      ],
    );
  }

  static pw.Widget _buildSection(_TdsSection section, _PdfFonts pdfFonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            pw.Text(section.title, style: pw.TextStyle(font: pdfFonts.songtiBold, fontSize: 14)),
            pw.SizedBox(height: 5),
          ],
          ...section.blocks.map((block) => _buildBlock(block, section, pdfFonts)),
        ],
      ),
    );
  }

  static pw.Widget _buildBlock(_TdsBlock block, _TdsSection section, _PdfFonts pdfFonts) {
    if (block.type == _TdsBlockType.table && block.tableRows != null && block.tableRows!.isNotEmpty) {
      final isPhysicalTable = section.title.contains('物理性能') && block.tableRows!.first.length >= 3;
      final table = pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(font: pdfFonts.songtiBold, fontSize: 10.5),
        cellStyle: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 10.5),
        cellAlignment: pw.Alignment.center,
        border: pw.TableBorder.all(width: 0.8),
        columnWidths: isPhysicalTable
            ? <int, pw.TableColumnWidth>{
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(1.2),
              }
            : null,
        headers: block.tableRows!.first,
        data: block.tableRows!.length > 1 ? block.tableRows!.sublist(1) : const <List<String>>[],
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: isPhysicalTable
            ? pw.Center(child: pw.SizedBox(width: 410, child: table))
            : table,
      );
    }

    if (block.type == _TdsBlockType.note && block.text != null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(_normalizeTextForPdf(block.text!)!, style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        _normalizeTextForPdf(block.text) ?? '',
        style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 10.5, lineSpacing: 2),
      ),
    );
  }

  static pw.Widget _buildDisclaimerSection(_PdfFonts pdfFonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('免责声明', style: pw.TextStyle(font: pdfFonts.songtiBold, fontSize: 14)),
          pw.SizedBox(height: 8),
          ..._defaultDisclaimer.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                line,
                style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 8, lineSpacing: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(_PdfFonts pdfFonts) {
    return pw.Column(
      children: [
        pw.Container(height: 4, color: PdfColors.grey600),
        pw.SizedBox(height: 7),
        pw.Text(
          '锐石主要从事紫外光固化（UV）树脂及水性乳液的研发、制造和销售，\n旨在创造世界级的中国化工品牌',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: pdfFonts.songtiBold, fontSize: 11),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '地址 ', style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
                  pw.TextSpan(text: 'ADD: ', style: pw.TextStyle(font: pdfFonts.arialRegular, fontSize: 9)),
                  pw.TextSpan(text: '嘉兴市秀洲区油车港镇永越大厦 11 楼 1102', style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
                ],
              ),
            ),
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '电话/传真 ', style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
                  pw.TextSpan(text: 'TEL/FAX: 15067388778 0573-82203606', style: pw.TextStyle(font: pdfFonts.arialRegular, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '网址 ', style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
                  pw.TextSpan(text: 'WEBSITE: http://www.rstone-resin.com/', style: pw.TextStyle(font: pdfFonts.arialRegular, fontSize: 9)),
                ],
              ),
            ),
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '邮箱 ', style: pw.TextStyle(font: pdfFonts.songtiRegular, fontSize: 9)),
                  pw.TextSpan(text: 'EMAIL: zhoulei22kb@rstone-resin.com', style: pw.TextStyle(font: pdfFonts.arialRegular, fontSize: 9)),
                ],
              ),
            ),
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

    _TdsSection? current;
    List<List<String>>? collectingTableRows;
    bool skippingMarkdownDisclaimer = false;

    void flushTableIfNeeded() {
      if (collectingTableRows != null && collectingTableRows!.isNotEmpty) {
        current ??= _TdsSection(title: '');
        current!.blocks.add(_TdsBlock.table(List<List<String>>.from(collectingTableRows!)));
      }
      collectingTableRows = null;
    }

    for (final line in lines) {
      if (line.isEmpty) {
        flushTableIfNeeded();
        continue;
      }
      if (line.startsWith('>')) {
        flushTableIfNeeded();
        current ??= _TdsSection(title: '');
        current!.blocks.add(_TdsBlock.note(line.replaceFirst(RegExp(r'^>\s*'), '').trim()));
        continue;
      }

      final headingMatch = _headingReg.firstMatch(line);
      if (headingMatch != null) {
        flushTableIfNeeded();
        final heading = headingMatch.group(2)!.trim();
        if (heading.contains('免责声明')) {
          if (current != null) sections.add(current!);
          current = null;
          skippingMarkdownDisclaimer = true;
          continue;
        }
        if (skippingMarkdownDisclaimer) {
          skippingMarkdownDisclaimer = false;
        }

        if (subtitle == null && heading.startsWith('RD')) {
          subtitle = heading;
          continue;
        }

        if (current != null) sections.add(current!);
        current = _TdsSection(title: heading);
        continue;
      }

      if (line.startsWith('|')) {
        if (skippingMarkdownDisclaimer) continue;
        current ??= _TdsSection(title: '');
        collectingTableRows ??= [];
        if (!RegExp(r'^\|?\s*[-:| ]+\|?$').hasMatch(line)) {
          collectingTableRows!.add(
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
        flushTableIfNeeded();
        subtitle = line;
        continue;
      }
      if (skippingMarkdownDisclaimer) continue;

      flushTableIfNeeded();
      current ??= _TdsSection(title: '');
      current!.blocks.add(_TdsBlock.paragraph(line));
    }

    flushTableIfNeeded();
    if (current != null) sections.add(current!);

    return _ParsedTds(subtitle: subtitle, sections: sections);
  }

  static String? _normalizeTextForPdf(String? text) {
    if (text == null || text.isEmpty) return text;
    return text.replaceAllMapped(RegExp(r'([A-Za-z]+)(\d{2,})'), (m) => '${m.group(1)}\u2060${m.group(2)}');
  }

  static bool _isDuplicateSubtitle(String subtitle, String productName) {
    final normalizedSubtitle = subtitle.trim().toUpperCase();
    final normalizedProduct = productName.trim().toUpperCase();
    return normalizedSubtitle == normalizedProduct || normalizedSubtitle.startsWith('$normalizedProduct ');
  }

  static Future<pw.Font> _loadFirstAvailableFont({
    required List<String> candidates,
    required Future<pw.Font> Function() fallback,
  }) async {
    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        return pw.Font.ttf(data);
      } catch (_) {
        // continue try next candidate
      }
    }
    return fallback();
  }
}

class _PdfFonts {
  const _PdfFonts({
    required this.songtiRegular,
    required this.songtiBold,
    required this.arialRegular,
    required this.yaheiBold,
    required this.impactLikeBold,
  });

  final pw.Font songtiRegular;
  final pw.Font songtiBold;
  final pw.Font arialRegular;
  final pw.Font yaheiBold;
  final pw.Font impactLikeBold;
}

class _ParsedTds {
  const _ParsedTds({
    required this.subtitle,
    required this.sections,
  });

  final String? subtitle;
  final List<_TdsSection> sections;
}

class _TdsSection {
  _TdsSection({
    required this.title,
  });

  final String title;
  final List<_TdsBlock> blocks = <_TdsBlock>[];
}

enum _TdsBlockType { paragraph, table, note }

class _TdsBlock {
  const _TdsBlock._({
    required this.type,
    this.text,
    this.tableRows,
  });

  factory _TdsBlock.paragraph(String text) => _TdsBlock._(type: _TdsBlockType.paragraph, text: text);
  factory _TdsBlock.note(String text) => _TdsBlock._(type: _TdsBlockType.note, text: text);
  factory _TdsBlock.table(List<List<String>> rows) => _TdsBlock._(type: _TdsBlockType.table, tableRows: rows);

  final _TdsBlockType type;
  final String? text;
  final List<List<String>>? tableRows;
}
