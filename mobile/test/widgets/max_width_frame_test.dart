import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/max_width_frame.dart';

void main() {
  Future<Size> contentSize(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size reported;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MaxWidthFrame(child: child!),
      home: Builder(builder: (context) {
        reported = MediaQuery.sizeOf(context);
        return const Scaffold(body: SizedBox.expand(key: Key('body')));
      }),
    ));
    expect(tester.getSize(find.byKey(const Key('body'))).width, reported.width);
    return reported;
  }

  testWidgets('phones are untouched', (tester) async {
    expect((await contentSize(tester, const Size(390, 844))).width, 390);
  });

  testWidgets('tablets get a centred 600 px column (MediaQuery agrees)', (tester) async {
    expect((await contentSize(tester, const Size(1024, 1366))).width, 600);
    expect(tester.getCenter(find.byKey(const Key('body'))).dx, 512);
  });
}
