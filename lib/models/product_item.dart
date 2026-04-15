/// 产品/应用数据模型
/// 
/// 用于表示产品列表和产品应用两大类数据。
/// 通过 [fromMdContent] 工厂构造函数从 Markdown 文件内容解析生成。
class ProductItem {
  static String _normalizeMdLinkValue(String value) {
    final trimmed = value.trim();
    final unquoted = (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'"))
        ? trimmed.substring(1, trimmed.length - 1).trim()
        : trimmed;

    final wikiMatch = RegExp(r'^\[\[(.+)\]\]$').firstMatch(unquoted);
    return wikiMatch?.group(1)?.trim() ?? unquoted;
  }

  final String fileName;       // 文件名（不含路径）
  final String filePath;       // 完整文件路径
  final String folder;         // 所属文件夹（产品列表/产品应用）
  final String rawContent;     // 原始MD内容
  final Map<String, dynamic> frontmatter;  // YAML前置数据
  final List<String> tags;     // 标签数组
  final String? engineer;      // 工程师
  final String? experimentalCode; // 实验牌号
  final String? solidContent;  // 固含
  final String? hydroxylValue;  // 羟值
  final String? waterContactAngle; // 水接触角
  final String? technologySource; // 技术源
  final String? benchmark;     // 对标
  final String? viscosity;     // 粘度
  
  // 产品应用相关字段
  final String? primer;        // 底漆
  final String? midCoat;      // 中漆
  final String? topCoat;      // 面漆
  final String? baseMaterial; // 基材

  ProductItem({
    required this.fileName,
    required this.filePath,
    required this.folder,
    required this.rawContent,
    required this.frontmatter,
    this.tags = const [],
    this.engineer,
    this.experimentalCode,
    this.solidContent,
    this.hydroxylValue,
    this.waterContactAngle,
    this.technologySource,
    this.benchmark,
    this.viscosity,
    this.primer,
    this.midCoat,
    this.topCoat,
    this.baseMaterial,
  });

  /// 从MD文件内容解析
  factory ProductItem.fromMdContent(String filePath, String content) {
    final fileName = filePath.split('/').last.replaceAll('.md', '');
    final folder = filePath.contains('产品列表')
        ? '产品列表'
        : filePath.contains('产品应用')
            ? '产品应用'
            : filePath.contains('产品配方')
                ? '产品配方'
                : '未知';
    
    Map<String, dynamic> frontmatter = {};
    List<String> tags = [];
    String? engineer;
    String? experimentalCode;
    String? solidContent;
    String? hydroxylValue;
    String? waterContactAngle;
    String? technologySource;
    String? benchmark;
    String? viscosity;
    String? primer;
    String? midCoat;
    String? topCoat;
    String? baseMaterial;

    // 解析前置数据
    final lines = content.split('\n');
    bool inFrontmatter = false;
    List<String> frontmatterLines = [];
    
    for (var line in lines) {
      if (line.trim() == '---') {
        if (!inFrontmatter) {
          inFrontmatter = true;
        } else {
          // 前置数据结束，跳过properties/views部分
          break;
        }
        continue;
      }
      if (inFrontmatter) {
        frontmatterLines.add(line);
      }
    }

    // 解析前置数据行
    for (int i = 0; i < frontmatterLines.length; i++) {
      final line = frontmatterLines[i];
      if (line.trim().startsWith('tags:')) {
        // 仅在 frontmatter 中解析 tags，避免把分隔符 "---" 误解析为 "--"
        final parsedTags = <String>[];
        for (int j = i + 1; j < frontmatterLines.length; j++) {
          final candidate = frontmatterLines[j].trim();
          if (candidate.startsWith('- ')) {
            final tag = candidate.substring(2).trim();
            if (tag.isNotEmpty) {
              parsedTags.add(tag);
            }
            continue;
          }

          // 读到下一个字段或空行则结束 tags 列表读取
          if (candidate.isEmpty || RegExp(r'^[^\s].*:\s*').hasMatch(candidate)) {
            break;
          }
        }
        if (parsedTags.isNotEmpty) {
          tags = parsedTags;
        }
      } else if (line.trim().startsWith('工程师:')) {
        engineer = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('实验牌号:')) {
        experimentalCode = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('固含:')) {
        solidContent = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('羟值:')) {
        hydroxylValue = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('水接触角:')) {
        waterContactAngle = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('技术源:')) {
        technologySource = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('对标:')) {
        benchmark = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('粘度:')) {
        viscosity = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('底漆:')) {
        primer = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('中漆:')) {
        midCoat = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('面漆:')) {
        topCoat = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      } else if (line.trim().startsWith('基材:')) {
        baseMaterial = _normalizeMdLinkValue(line.split(':').sublist(1).join(':'));
      }
    }

    // 解析tags的另一种格式
    if (tags.isEmpty) {
      final frontmatterContent = frontmatterLines.join('\n');
      final tagsLine = RegExp(r'tags:\s*\[(.*?)\]').firstMatch(frontmatterContent);
      if (tagsLine != null) {
        tags = tagsLine.group(1)?.split(',').map((t) => t.trim().replaceAll('"', '')).toList() ?? [];
      }
    }

    return ProductItem(
      fileName: fileName,
      filePath: filePath,
      folder: folder,
      rawContent: content,
      frontmatter: frontmatter,
      tags: tags,
      engineer: engineer,
      experimentalCode: experimentalCode,
      solidContent: solidContent,
      hydroxylValue: hydroxylValue,
      waterContactAngle: waterContactAngle,
      technologySource: technologySource,
      benchmark: benchmark,
      viscosity: viscosity,
      primer: primer,
      midCoat: midCoat,
      topCoat: topCoat,
      baseMaterial: baseMaterial,
    );
  }

  /// 获取显示名称
  String get displayName {
    if (folder == '产品列表') {
      return fileName;
    } else {
      return fileName;
    }
  }

  /// 用于搜索的所有文本
  String get searchText {
    final parts = <String>[
      fileName,
      ...tags,
      if (engineer != null) engineer!,
      if (experimentalCode != null) experimentalCode!,
      if (solidContent != null) solidContent!,
      if (baseMaterial != null) baseMaterial!,
      if (primer != null) primer!,
      if (midCoat != null) midCoat!,
      if (topCoat != null) topCoat!,
    ];
    return parts.join(' ').toLowerCase();
  }

  /// 获取表格显示的字段值
  Map<String, String> getTableFields() {
    if (folder == '产品列表') {
      return {
        '牌号': fileName,
        '标签': tags.join(', '),
        if (experimentalCode != null) '实验牌号': experimentalCode!,
        if (engineer != null) '工程师': engineer!,
        if (solidContent != null) '固含': solidContent!,
        if (hydroxylValue != null) '羟值': hydroxylValue!,
        if (waterContactAngle != null) '水接触角': waterContactAngle!,
        if (technologySource != null) '技术源': technologySource!,
        if (benchmark != null) '对标': benchmark!,
        if (viscosity != null) '粘度': viscosity!,
      };
    } else if (folder == '产品应用') {
      return {
        '名称': fileName,
        if (baseMaterial != null) '基材': baseMaterial!,
        if (primer != null) '底漆': primer!,
        if (midCoat != null) '中漆': midCoat!,
        if (topCoat != null) '面漆': topCoat!,
        '标签': tags.join(', '),
      };
    } else {
      return {
        '名称': fileName,
      };
    }
  }
}
