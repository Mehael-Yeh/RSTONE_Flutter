import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/utils/grade_lookup.dart';

void main() {
  group('findExactTds', () {
    test('matches only the identical full grade', () {
      const tds = {'RS93001': '# base', 'RS93001-2': '# variant'};

      expect(findExactTds(tds, 'RS93001-2'), '# variant');
      expect(findExactTds(tds, 'RS93001'), '# base');
      expect(findExactTds(tds, 'RS9300'), isNull);
    });

    test('ignores surrounding whitespace and case only', () {
      const tds = {'RS93002-2': '# variant'};

      expect(findExactTds(tds, ' rs93002-2 '), '# variant');
      expect(findExactTds(tds, 'RS93002'), isNull);
    });

    test('root entry does not bypass duplicate-basename ambiguity', () {
      const tds = {'RS93004': '# root', 'archive/RS93004': '# archive'};
      expect(findExactTds(tds, 'RS93004'), isNull);
    });

    test('does not resolve a basename repeated in subfolders', () {
      const tds = {'甲/RS93003': '# A', '乙/RS93003': '# B'};

      expect(findExactTds(tds, 'RS93003'), isNull);
    });
  });
}
