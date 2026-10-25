import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/categories/presentation/providers/categories_providers.dart';
import 'package:golden_gift/features/home/presentation/providers/home_providers.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';

void main() {
  test('greeting by local time (SRS §5.4 item 1)', () {
    expect(greetingFor(DateTime(2026, 1, 1, 5)), Greeting.morning);
    expect(greetingFor(DateTime(2026, 1, 1, 11, 59)), Greeting.morning);
    expect(greetingFor(DateTime(2026, 1, 1, 12)), Greeting.afternoon);
    expect(greetingFor(DateTime(2026, 1, 1, 16, 59)), Greeting.afternoon);
    expect(greetingFor(DateTime(2026, 1, 1, 17)), Greeting.evening);
    expect(greetingFor(DateTime(2026, 1, 1, 2)), Greeting.evening);
  });

  group('category search is local and multilingual (SRS §5.7)', () {
    final categories = [
      const CategoryModel(id: 'mugs', title: LocalizedText('Mugs', ar: 'أكواب', ku: 'کوپ')),
      const CategoryModel(id: 'mothers-day', title: LocalizedText("Mother's Day", ar: 'عيد الأم', ku: 'ڕۆژی دایک')),
      const CategoryModel(id: 'jewelry', title: LocalizedText('Jewelry and Watches', ar: 'مجوهرات وساعات', ku: 'زێڕ و کاتژمێر')),
    ];

    test('empty query keeps everything in order', () {
      expect(filterCategories(categories, '  ').map((c) => c.id), ['mugs', 'mothers-day', 'jewelry']);
    });

    test('matches English case-insensitively, Arabic and Kurdish', () {
      expect(filterCategories(categories, 'watch').map((c) => c.id), ['jewelry']);
      expect(filterCategories(categories, 'الأم').map((c) => c.id), ['mothers-day']);
      expect(filterCategories(categories, 'دایک').map((c) => c.id), ['mothers-day']);
    });

    test('Arabic-keyboard letters find Kurdish spellings (ك → ک)', () {
      expect(filterCategories(categories, 'كوپ').map((c) => c.id), ['mugs']);
    });
  });
}
