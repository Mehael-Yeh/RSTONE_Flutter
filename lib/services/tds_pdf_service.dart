/// TDS PDF 生成服务，负责解析 Markdown 并输出可分享文档。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product_item.dart';

class TdsPdfService {
  static final RegExp _headingReg = RegExp(r'^(#{1,3})\s*(.+)$');
  static final RegExp _leadingPunctuationReg = RegExp(
    r'^[，。！？；：、）》】』’”,.!?;:\)\]}>]',
  );

  static const List<String> _defaultDisclaimer = [
    '锐石为客户提供物料安全资料表，提供有关本产品的潜在健康影响、安全处理、贮存、使用和弃置的信息。锐石鼓励客户在使用锐石产品和其它原料之前先查阅物料安全资料表，以确保人身和环境安全。为了确保锐石的产品不被滥用于非指定用途或未经测试的用途，锐石的员工可帮助客户处理生态及产品安全方面的问题。您的锐石销售代表可安排适当联络。',
    '但是关于产品特性、应用、质量、安全性、产品规格、适销性，以及针对特定用途的适用性，本技术数据表中所涉及的内容仅供参考，无论是明示或隐含的信息，我们不提供任何保证。在此提供的任何信息不应被视作实施专利技术的许可，也不应被视作未经专利所有人许可的前提下实施专利技术的诱导。',
  ];

  static Future<File> generateAndShareTds(
    ProductItem product, {
    required String tdsMarkdown,
  }) async {
    final bytes = await generatePdfBytes(
      product,
      tdsMarkdown: tdsMarkdown,
    );
    final dir = await getTemporaryDirectory();
    final safeName = product.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    final fileName = '${safeName.isEmpty ? '产品' : safeName} TDS(CN).pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      subject: '${product.fileName} TDS(CN).pdf',
      text: '产品 TDS PDF 文件',
    );

    return file;
  }

  static Future<Uint8List> generatePdfBytes(
    ProductItem product, {
    required String tdsMarkdown,
  }) async {
    final body = _extractMarkdownBody(tdsMarkdown);
    final parsed = _parseTdsSections(body);
    final productGrade = _normalizeTextForPdf(parsed.productCode) ??
        _normalizeTextForPdf(product.fileName) ??
        product.fileName;
    final productSubtitle = _normalizeTextForPdf(parsed.productSubtitle);

    final pdfFonts = _PdfFonts(
      bodyRegular: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/MicrosoftYaHei.ttf'],
        fallback: PdfGoogleFonts.notoSansSCRegular,
      ),
      bodyBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/MicrosoftYaHeiBold.ttf'],
        fallback: PdfGoogleFonts.notoSansSCBold,
      ),
      arialRegular: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/Arial.ttf'],
        fallback: PdfGoogleFonts.robotoRegular,
      ),
      tdsHeaderArialBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/ArialBold.ttf'],
        fallback: PdfGoogleFonts.robotoBold,
      ),
      simheiRegular: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/SimHei.ttf', 'assets/fonts/simhei.ttf'],
        fallback: PdfGoogleFonts.notoSansSCRegular,
      ),
      simheiBold: await _loadFirstAvailableFont(
        candidates: const ['assets/fonts/SimHei.ttf', 'assets/fonts/simhei.ttf'],
        fallback: PdfGoogleFonts.notoSansSCBold,
      ),
    );

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 18, 24, 22),
        theme: pw.ThemeData.withFont(
          base: pdfFonts.bodyRegular,
          bold: pdfFonts.bodyBold,
        ),
        header: (context) => _buildHeader(pdfFonts),
        footer: (context) => _buildFooter(pdfFonts),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              '产品技术数据表（TDS）',
              style: _bodyBoldTextStyle(pdfFonts, fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            productGrade,
            style: _bodyBoldTextStyle(pdfFonts, fontSize: 14),
          ),
          if (productSubtitle != null && productSubtitle.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              productSubtitle,
              style: _bodyBoldTextStyle(pdfFonts, fontSize: 10.5),
            ),
          ],
          pw.SizedBox(height: 10),
          for (var i = 0; i < parsed.sections.length; i++)
            _buildSection(parsed.sections[i], pdfFonts, sectionIndex: i),
          _buildDisclaimerSection(pdfFonts),
        ],
      ),
    );

    return doc.save();
  }

  static pw.TextStyle _bodyTextStyle(
    _PdfFonts fonts, {
    required double fontSize,
    pw.FontWeight? fontWeight,
    double lineSpacing = 0,
  }) {
    return pw.TextStyle(
      font: fonts.bodyRegular,
      fontNormal: fonts.bodyRegular,
      fontBold: fonts.bodyBold,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineSpacing: lineSpacing,
    );
  }

  static pw.TextStyle _bodyBoldTextStyle(
    _PdfFonts fonts, {
    required double fontSize,
    double lineSpacing = 0,
  }) {
    return _bodyTextStyle(
      fonts,
      fontSize: fontSize,
      fontWeight: pw.FontWeight.bold,
      lineSpacing: lineSpacing,
    );
  }

  static pw.Widget _buildHeader(_PdfFonts fonts) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'RSTONE',
              style: pw.TextStyle(
                font: fonts.tdsHeaderArialBold,
                fontSize: 44,
                color: const PdfColor.fromInt(0xFF9A3F10),
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  '嘉兴锐石化工有限公司',
                  style: pw.TextStyle(
                    font: fonts.simheiBold,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'RSTONE (Jia Xing) CHEMICAL CO., LTD.',
                  style: pw.TextStyle(font: fonts.arialRegular, fontSize: 15),
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

  static pw.Widget _buildSection(
    _TdsSection section,
    _PdfFonts fonts, {
    required int sectionIndex,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            pw.Text(
              section.title,
              style: _bodyBoldTextStyle(fonts, fontSize: 14),
            ),
            pw.SizedBox(height: 5),
          ],
          for (var i = 0; i < section.blocks.length; i++)
            _buildBlock(
              section.blocks[i],
              section,
              fonts,
              blockIndex: i,
              forceRegularParagraph: sectionIndex == 0,
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildBlock(
    _TdsBlock block,
    _TdsSection section,
    _PdfFonts fonts, {
    required int blockIndex,
    required bool forceRegularParagraph,
  }) {
    if (block.type == _TdsBlockType.table && block.tableRows != null && block.tableRows!.isNotEmpty) {
      final isPhysicalTable =
          section.title.contains('物理性能') && block.tableRows!.first.length >= 3;
      final table = pw.TableHelper.fromTextArray(
        headerStyle: _bodyBoldTextStyle(fonts, fontSize: 9.5),
        cellStyle: _bodyTextStyle(fonts, fontSize: 9.3),
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
        data: block.tableRows!.length > 1
            ? block.tableRows!.sublist(1)
            : const <List<String>>[],
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Center(
          child: pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxWidth: 460),
            child: table,
          ),
        ),
      );
    }

    if (block.type == _TdsBlockType.note && block.text != null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: _buildMarkdownStyledText(
          block.text!,
          fonts: fonts,
          fontSize: 9,
        ),
      );
    }

    final centerParagraph =
        _shouldCenterSingleLineParagraph(section.blocks, blockIndex);
    final paragraph = _buildMarkdownStyledText(
      _formatParagraphText(block),
      fonts: fonts,
      fontSize: 10.5,
      lineSpacing: 2,
      textAlign: centerParagraph ? pw.TextAlign.center : pw.TextAlign.left,
      enableMarkdownBold: !forceRegularParagraph,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: centerParagraph ? pw.Center(child: paragraph) : paragraph,
    );
  }

  static bool _shouldCenterSingleLineParagraph(List<_TdsBlock> blocks, int index) {
    if (index <= 0 || index >= blocks.length) return false;
    final block = blocks[index];
    if (block.type != _TdsBlockType.paragraph || block.sourceLineCount != 1) {
      return false;
    }

    final previousBlock = blocks[index - 1];
    if (previousBlock.type != _TdsBlockType.table) return false;

    final hasNextBlock = index + 1 < blocks.length;
    return !hasNextBlock || blocks[index + 1].type == _TdsBlockType.table;
  }

  static String _formatParagraphText(_TdsBlock block) {
    final source = block.text ?? '';
    if (source.isEmpty) return source;
    if (block.type != _TdsBlockType.paragraph) return source;
    return source;
  }

  static pw.Widget _buildMarkdownStyledText(
    String text, {
    required _PdfFonts fonts,
    required double fontSize,
    double lineSpacing = 0,
    pw.TextAlign textAlign = pw.TextAlign.left,
    bool enableMarkdownBold = true,
  }) {
    final spans = <pw.InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var start = 0;
    final source = _normalizeTextForPdf(
          enableMarkdownBold
              ? text
              : text.replaceAllMapped(
                  pattern,
                  (match) => match.group(1) ?? '',
                ),
        ) ??
        '';

    final boldMatches = enableMarkdownBold
        ? pattern.allMatches(source)
        : const <RegExpMatch>[];
    for (final match in boldMatches) {
      if (match.start > start) {
        spans.add(
          pw.TextSpan(
            text: source.substring(start, match.start),
            style: _bodyTextStyle(
              fonts,
              fontSize: fontSize,
              lineSpacing: lineSpacing,
            ),
          ),
        );
      }
      final boldText = match.group(1) ?? '';
      spans.add(
        pw.TextSpan(
          text: boldText,
          style: _bodyBoldTextStyle(
            fonts,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
          ),
        ),
      );
      start = match.end;
    }

    if (start < source.length) {
      spans.add(
        pw.TextSpan(
          text: source.substring(start),
          style: _bodyTextStyle(
            fonts,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
          ),
        ),
      );
    }

    if (spans.isEmpty) {
      return pw.Text(
        source,
        textAlign: textAlign,
        style: _bodyTextStyle(
          fonts,
          fontSize: fontSize,
          lineSpacing: lineSpacing,
        ),
      );
    }

    return pw.RichText(
      textAlign: textAlign,
      text: pw.TextSpan(children: spans),
    );
  }

  static pw.Widget _buildDisclaimerSection(_PdfFonts fonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '免责声明',
            style: _bodyBoldTextStyle(fonts, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          ..._defaultDisclaimer.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: _buildMarkdownStyledText(
                line,
                fonts: fonts,
                fontSize: 8,
                lineSpacing: 2,
                textAlign: pw.TextAlign.left,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(_PdfFonts fonts) {
    return pw.Column(
      children: [
        pw.Container(height: 4, color: PdfColors.grey600),
        pw.SizedBox(height: 7),
        pw.Text(
          '锐石主要从事紫外光固化（UV）树脂及水性乳液的研发、制造和销售，\n旨在创造世界级的中国化工品牌',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: fonts.simheiBold, fontSize: 11),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '地址', style: pw.TextStyle(font: fonts.simheiRegular, fontSize: 9)),
                  pw.TextSpan(text: ' ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                  pw.TextSpan(text: 'ADD: ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                  pw.TextSpan(text: '嘉兴市秀洲区油车港镇永越大厦11楼1102', style: pw.TextStyle(font: fonts.simheiRegular, fontSize: 9)),
                ],
              ),
            ),
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '电话/传真', style: pw.TextStyle(font: fonts.simheiRegular, fontSize: 9)),
                  pw.TextSpan(text: ' ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                  pw.TextSpan(text: 'TEL/FAX: 15067388778 0573-82203606', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(text: '网址', style: pw.TextStyle(font: fonts.simheiRegular, fontSize: 9)),
                      pw.TextSpan(text: ' ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                      pw.TextSpan(text: 'WEBSITE: ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                    ],
                  ),
                ),
                pw.UrlLink(
                  destination: 'http://www.rstone-resin.com/',
                  child: pw.Text(
                    'http://www.rstone-resin.com/',
                    style: pw.TextStyle(
                      font: fonts.arialRegular,
                      fontSize: 9,
                      color: PdfColors.blue700,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: '邮箱', style: pw.TextStyle(font: fonts.simheiRegular, fontSize: 9)),
                  pw.TextSpan(text: ' ', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
                  pw.TextSpan(text: 'EMAIL: zhoulei22kb@rstone-resin.com', style: pw.TextStyle(font: fonts.arialRegular, fontSize: 9)),
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
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    String? productCode;
    String? productSubtitle;
    final sections = <_TdsSection>[];

    _TdsSection? current;
    List<List<String>>? collectingTableRows;
    final paragraphBuffer = <String>[];
    bool skippingMarkdownDisclaimer = false;

    void flushTableIfNeeded() {
      if (collectingTableRows != null && collectingTableRows!.isNotEmpty) {
        current ??= _TdsSection(title: '');
        current!.blocks.add(_TdsBlock.table(List<List<String>>.from(collectingTableRows!)));
      }
      collectingTableRows = null;
    }

    void flushParagraphIfNeeded() {
      if (paragraphBuffer.isEmpty) return;
      current ??= _TdsSection(title: '');
      final paragraphText = _mergeWrappedParagraphLines(paragraphBuffer);
      current!.blocks.add(
        _TdsBlock.paragraph(
          paragraphText,
          sourceLineCount: paragraphBuffer.length,
        ),
      );
      paragraphBuffer.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flushTableIfNeeded();
        flushParagraphIfNeeded();
        continue;
      }
      if (line.startsWith('>')) {
        flushTableIfNeeded();
        flushParagraphIfNeeded();
        current ??= _TdsSection(title: '');
        current!.blocks.add(_TdsBlock.note(line.replaceFirst(RegExp(r'^>\s*'), '').trim()));
        continue;
      }

      final headingMatch = _headingReg.firstMatch(line);
      if (headingMatch != null) {
        flushTableIfNeeded();
        flushParagraphIfNeeded();
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

        final headingLevel = headingMatch.group(1) ?? '#';
        if (productCode == null && headingLevel == '#') {
          productCode = heading;
          continue;
        }

        if (current != null) sections.add(current!);
        current = _TdsSection(title: heading);
        continue;
      }

      if (line.startsWith('|')) {
        if (skippingMarkdownDisclaimer) continue;
        flushParagraphIfNeeded();
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

      if (productCode == null) {
        flushTableIfNeeded();
        productCode = line;
        continue;
      }

      if (current == null && productSubtitle == null) {
        flushTableIfNeeded();
        productSubtitle = line;
        continue;
      }
      if (skippingMarkdownDisclaimer) continue;

      flushTableIfNeeded();
      final isOrderedLine = RegExp(r'^((\d+[\.\)、])|([（(]\d+[）)]))\s+').hasMatch(line);
      if (isOrderedLine) {
        flushParagraphIfNeeded();
        current ??= _TdsSection(title: '');
        current!.blocks.add(
          _TdsBlock.paragraph(
            _normalizeParagraphSpacing(line),
            sourceLineCount: 1,
          ),
        );
        continue;
      }
      paragraphBuffer.add(line);
    }

    flushTableIfNeeded();
    flushParagraphIfNeeded();
    if (current != null) sections.add(current!);

    return _ParsedTds(
      productCode: productCode,
      productSubtitle: productSubtitle,
      sections: sections,
    );
  }

  static String _mergeWrappedParagraphLines(List<String> lines) {
    if (lines.isEmpty) return '';
    final cleanedLines = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (cleanedLines.isEmpty) return '';

    final buffer = StringBuffer(cleanedLines.first);
    for (var i = 1; i < cleanedLines.length; i++) {
      final currentLine = cleanedLines[i];
      if (_leadingPunctuationReg.hasMatch(currentLine)) {
        buffer.write(currentLine);
        continue;
      }
      final previousText = buffer.toString();
      if (_shouldInsertSpace(previousText, currentLine)) {
        buffer.write(' ');
      }
      buffer.write(currentLine);
    }
    return _normalizeParagraphSpacing(buffer.toString());
  }

  static bool _shouldInsertSpace(String leftText, String rightText) {
    if (leftText.isEmpty || rightText.isEmpty) return false;
    final leftChar = leftText.substring(leftText.length - 1);
    final rightChar = rightText.substring(0, 1);
    return RegExp(r'[A-Za-z0-9]').hasMatch(leftChar) &&
        RegExp(r'[A-Za-z0-9]').hasMatch(rightChar);
  }

  static String _normalizeParagraphSpacing(String text) {
    var normalized = text
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();

    normalized = normalized
        // 中文/全角字符之间不应出现额外空格
        .replaceAll(
          RegExp(
            r'([\u4E00-\u9FFF\u3000-\u303F\uFF00-\uFFEF])\s+([\u4E00-\u9FFF\u3000-\u303F\uFF00-\uFFEF])',
          ),
          r'$1$2',
        )
        // 中文后接标点前不应保留空格
        .replaceAll(
          RegExp(
            r'([\u4E00-\u9FFF\u3000-\u303F\uFF00-\uFFEF])\s+([，。！？；：、）》】』’”,.!?;:\)\]}>])',
          ),
          r'$1$2',
        )
        // 左侧括号后不应有空格
        .replaceAll(
          RegExp(r'([（《【『“‘(<\[])\s+'),
          r'$1',
        );

    return normalized;
  }

  static String? _normalizeTextForPdf(String? text) {
    if (text == null || text.isEmpty) return text;
    var normalized = text;
    normalized = normalized.replaceAllMapped(RegExp(r'([A-Za-z]+)[ \t\n]+(\d{2,}[A-Za-z0-9-]*)'), (m) => '${m.group(1)}${m.group(2)}');
    normalized = normalized.replaceAllMapped(RegExp(r'([A-Za-z]+)(\d{2,})'), (m) => '${m.group(1)}${m.group(2)}');
    return normalized;
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
    required this.bodyRegular,
    required this.bodyBold,
    required this.arialRegular,
    required this.tdsHeaderArialBold,
    required this.simheiRegular,
    required this.simheiBold,
  });

  final pw.Font bodyRegular;
  final pw.Font bodyBold;
  final pw.Font arialRegular;
  final pw.Font tdsHeaderArialBold;
  final pw.Font simheiRegular;
  final pw.Font simheiBold;
}

class _ParsedTds {
  const _ParsedTds({
    required this.productCode,
    required this.productSubtitle,
    required this.sections,
  });

  final String? productCode;
  final String? productSubtitle;
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
  _TdsBlock._({
    required this.type,
    this.text,
    this.tableRows,
    this.sourceLineCount = 0,
  });

  factory _TdsBlock.paragraph(
    String text, {
    required int sourceLineCount,
  }) =>
      _TdsBlock._(
        type: _TdsBlockType.paragraph,
        text: text,
        sourceLineCount: sourceLineCount,
      );

  factory _TdsBlock.note(String text) => _TdsBlock._(
        type: _TdsBlockType.note,
        text: text,
      );

  factory _TdsBlock.table(List<List<String>> rows) => _TdsBlock._(
        type: _TdsBlockType.table,
        tableRows: rows,
      );

  final _TdsBlockType type;
  final String? text;
  final List<List<String>>? tableRows;
  final int sourceLineCount;
}
