// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_driver/src/common/diagnostics_tree.dart';
import 'package:flutter_driver/src/common/find.dart';
import 'package:flutter_driver/src/common/geometry.dart';
import 'package:flutter_driver/src/common/request_data.dart';
import 'package:flutter_driver/src/common/text.dart';
import 'package:flutter_driver/src/extension/extension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('waitUntilNoTransientCallbacks', () {
    FlutterDriverExtension extension;
    Map<String, dynamic> result;
    int messageId = 0;
    final List<String> log = <String>[];

    setUp(() {
      result = null;
      extension = FlutterDriverExtension((String message) async { log.add(message); return (messageId += 1).toString(); }, false);
    });

    testWidgets('returns immediately when transient callback queue is empty', (WidgetTester tester) async {
      extension.call(const WaitUntilNoTransientCallbacks().serialize())
        .then<void>(expectAsync1((Map<String, dynamic> r) {
          result = r;
        }));

      await tester.idle();
      expect(
          result,
          <String, dynamic>{
            'isError': false,
            'response': null,
          },
      );
    });

    testWidgets('waits until no transient callbacks', (WidgetTester tester) async {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        // Intentionally blank. We only care about existence of a callback.
      });

      extension.call(const WaitUntilNoTransientCallbacks().serialize())
        .then<void>(expectAsync1((Map<String, dynamic> r) {
          result = r;
        }));

      // Nothing should happen until the next frame.
      await tester.idle();
      expect(result, isNull);

      // NOW we should receive the result.
      await tester.pump();
      expect(
          result,
          <String, dynamic>{
            'isError': false,
            'response': null,
          },
      );
    });

    testWidgets('handler', (WidgetTester tester) async {
      expect(log, isEmpty);
      final dynamic result = RequestDataResult.fromJson((await extension.call(const RequestData('hello').serialize()))['response']);
      expect(log, <String>['hello']);
      expect(result.message, '1');
    });
  });

  group('getSemanticsId', () {
    FlutterDriverExtension extension;
    setUp(() {
      extension = FlutterDriverExtension((String arg) async => '', true);
    });

    testWidgets('works when semantics are enabled', (WidgetTester tester) async {
      final SemanticsHandle semantics = RendererBinding.instance.pipelineOwner.ensureSemantics();
      await tester.pumpWidget(
        const Text('hello', textDirection: TextDirection.ltr));

      final Map<String, Object> arguments = GetSemanticsId(const ByText('hello')).serialize();
      final GetSemanticsIdResult result = GetSemanticsIdResult.fromJson((await extension.call(arguments))['response']);

      expect(result.id, 1);
      semantics.dispose();
    });

    testWidgets('throws state error if no data is found', (WidgetTester tester) async {
      await tester.pumpWidget(
        const Text('hello', textDirection: TextDirection.ltr));

      final Map<String, Object> arguments = GetSemanticsId(const ByText('hello')).serialize();
      final Map<String, Object> response = await extension.call(arguments);

      expect(response['isError'], true);
      expect(response['response'], contains('Bad state: No semantics data found'));
    }, semanticsEnabled: false);

    testWidgets('throws state error multiple matches are found', (WidgetTester tester) async {
      final SemanticsHandle semantics = RendererBinding.instance.pipelineOwner.ensureSemantics();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(children: const <Widget>[
            SizedBox(width: 100.0, height: 100.0, child: Text('hello')),
            SizedBox(width: 100.0, height: 100.0, child: Text('hello')),
          ]),
        ),
      );

      final Map<String, Object> arguments = GetSemanticsId(const ByText('hello')).serialize();
      final Map<String, Object> response = await extension.call(arguments);

      expect(response['isError'], true);
      expect(response['response'], contains('Bad state: Too many elements'));
      semantics.dispose();
    });
  });

  testWidgets('getOffset', (WidgetTester tester) async {
    final FlutterDriverExtension extension = FlutterDriverExtension((String arg) async => '', true);

    Future<Offset> getOffset(OffsetType offset) async {
      final Map<String, Object> arguments = GetOffset(ByValueKey(1), offset).serialize();
      final GetOffsetResult result = GetOffsetResult.fromJson((await extension.call(arguments))['response']);
      return Offset(result.dx, result.dy);
    }

    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: Transform.translate(
          offset: const Offset(40, 30),
          child: Container(
            key: const ValueKey<int>(1),
            width: 100,
            height: 120,
          ),
        ),
      ),
    );

    expect(await getOffset(OffsetType.topLeft), const Offset(40, 30));
    expect(await getOffset(OffsetType.topRight), const Offset(40 + 100.0, 30));
    expect(await getOffset(OffsetType.bottomLeft), const Offset(40, 30 + 120.0));
    expect(await getOffset(OffsetType.bottomRight), const Offset(40 + 100.0, 30 + 120.0));
    expect(await getOffset(OffsetType.center), const Offset(40 + (100 / 2), 30 + (120 / 2)));
  });

  testWidgets('descendant finder', (WidgetTester tester) async {
    flutterDriverLog.listen((LogRecord _) {}); // Silence logging.
    final FlutterDriverExtension extension = FlutterDriverExtension((String arg) async => '', true);

    Future<String> getDescendantText({ String of, bool matchRoot = false}) async {
      final Map<String, Object> arguments = GetText(Descendant(
        of: ByValueKey(of),
        matching: ByValueKey('text2'),
        matchRoot: matchRoot,
      ), timeout: const Duration(seconds: 1)).serialize();
      final Map<String, dynamic> result = await extension.call(arguments);
      if (result['isError']) {
        return null;
      }
      return GetTextResult.fromJson(result['response']).text;
    }

    await tester.pumpWidget(
        MaterialApp(
            home: Column(
              key: const ValueKey<String>('column'),
              children: const <Widget>[
                Text('Hello1', key: ValueKey<String>('text1')),
                Text('Hello2', key: ValueKey<String>('text2')),
                Text('Hello3', key: ValueKey<String>('text3')),
              ],
            )
        )
    );

    expect(await getDescendantText(of: 'column'), 'Hello2');
    expect(await getDescendantText(of: 'column', matchRoot: true), 'Hello2');
    expect(await getDescendantText(of: 'text2', matchRoot: true), 'Hello2');

    // Find nothing
    Future<String> result = getDescendantText(of: 'text1', matchRoot: true);
    await tester.pump(const Duration(seconds: 2));
    expect(await result, null);

    result = getDescendantText(of: 'text2');
    await tester.pump(const Duration(seconds: 2));
    expect(await result, null);
  });

  testWidgets('ancestor finder', (WidgetTester tester) async {
    flutterDriverLog.listen((LogRecord _) {}); // Silence logging.
    final FlutterDriverExtension extension = FlutterDriverExtension((String arg) async => '', true);

    Future<Offset> getAncestorTopLeft({ String of, String matching, bool matchRoot = false}) async {
      final Map<String, Object> arguments = GetOffset(Ancestor(
        of: ByValueKey(of),
        matching: ByValueKey(matching),
        matchRoot: matchRoot,
      ), OffsetType.topLeft, timeout: const Duration(seconds: 1)).serialize();
      final Map<String, dynamic> response = await extension.call(arguments);
      if (response['isError']) {
        return null;
      }
      final GetOffsetResult result = GetOffsetResult.fromJson(response['response']);
      return Offset(result.dx, result.dy);
    }

    await tester.pumpWidget(
        MaterialApp(
          home: Center(
              child: Container(
                key: const ValueKey<String>('parent'),
                height: 100,
                width: 100,
                child: Center(
                  child: Row(
                    children: <Widget>[
                      Container(
                        key: const ValueKey<String>('leftchild'),
                        width: 25,
                        height: 25,
                      ),
                      Container(
                        key: const ValueKey<String>('righttchild'),
                        width: 25,
                        height: 25,
                      ),
                    ],
                  ),
                ),
              )
          ),
        )
    );

    expect(
      await getAncestorTopLeft(of: 'leftchild', matching: 'parent'),
      const Offset((800 - 100) / 2, (600 - 100) / 2),
    );
    expect(
      await getAncestorTopLeft(of: 'leftchild', matching: 'parent', matchRoot: true),
      const Offset((800 - 100) / 2, (600 - 100) / 2),
    );
    expect(
      await getAncestorTopLeft(of: 'parent', matching: 'parent', matchRoot: true),
      const Offset((800 - 100) / 2, (600 - 100) / 2),
    );

    // Find nothing
    Future<Offset> result = getAncestorTopLeft(of: 'leftchild', matching: 'leftchild');
    await tester.pump(const Duration(seconds: 2));
    expect(await result, null);

    result = getAncestorTopLeft(of: 'leftchild', matching: 'righttchild');
    await tester.pump(const Duration(seconds: 2));
    expect(await result, null);
  });

  testWidgets('GetDiagnosticsTree', (WidgetTester tester) async {
    final FlutterDriverExtension extension = FlutterDriverExtension((String arg) async => '', true);

    Future<Map<String, Object>> getDiagnosticsTree(DiagnosticsType type, SerializableFinder finder, { int depth = 0, bool properties = true }) async {
      final Map<String, Object> arguments = GetDiagnosticsTree(finder, type, subtreeDepth: depth, includeProperties: properties).serialize();
      final DiagnosticsTreeResult result = DiagnosticsTreeResult((await extension.call(arguments))['response']);
      return result.json;
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: const Text('Hello World', key: ValueKey<String>('Text'))
        ),
      ),
    );

    // Widget
    Map<String, Object> result = await getDiagnosticsTree(DiagnosticsType.widget, ByValueKey('Text'), depth: 0);
    expect(result['children'], isNull); // depth: 0
    expect(result['widgetRuntimeType'], 'Text');

    List<Map<String, Object>> properties = result['properties'];
    Map<String, Object> stringProperty = properties.singleWhere((Map<String, Object> property) => property['name'] == 'data');
    expect(stringProperty['description'], '"Hello World"');
    expect(stringProperty['propertyType'], 'String');

    result = await getDiagnosticsTree(DiagnosticsType.widget, ByValueKey('Text'), depth: 0, properties: false);
    expect(result['widgetRuntimeType'], 'Text');
    expect(result['properties'], isNull); // properties: false

    result = await getDiagnosticsTree(DiagnosticsType.widget, ByValueKey('Text'), depth: 1);
    List<Map<String, Object>> children = result['children'];
    expect(children.single['children'], isNull);

    result = await getDiagnosticsTree(DiagnosticsType.widget, ByValueKey('Text'), depth: 100);
    children = result['children'];
    expect(children.single['children'], isEmpty);

    // RenderObject
    result = await getDiagnosticsTree(DiagnosticsType.renderObject, ByValueKey('Text'), depth: 0);
    expect(result['children'], isNull); // depth: 0
    expect(result['properties'], isNotNull);
    expect(result['description'], startsWith('RenderParagraph'));

    result = await getDiagnosticsTree(DiagnosticsType.renderObject, ByValueKey('Text'), depth: 0, properties: false);
    expect(result['properties'], isNull); // properties: false
    expect(result['description'], startsWith('RenderParagraph'));

    result = await getDiagnosticsTree(DiagnosticsType.renderObject, ByValueKey('Text'), depth: 1);
    children = result['children'];
    final Map<String, Object> textSpan = children.single;
    expect(textSpan['description'], 'TextSpan');
    properties = textSpan['properties'];
    stringProperty = properties.singleWhere((Map<String, Object> property) => property['name'] == 'text');
    expect(stringProperty['description'], '"Hello World"');
    expect(stringProperty['propertyType'], 'String');
    expect(children.single['children'], isNull);

    result = await getDiagnosticsTree(DiagnosticsType.renderObject, ByValueKey('Text'), depth: 100);
    children = result['children'];
    expect(children.single['children'], isEmpty);
  });

  group('waitUntilFrameSync', () {
    FlutterDriverExtension extension;
    Map<String, dynamic> result;

    setUp(() {
      extension = FlutterDriverExtension((String arg) async => '', true);
      result = null;
    });

    testWidgets('returns immediately when frame is synced', (
        WidgetTester tester) async {
      extension.call(const WaitUntilFrameSync().serialize())
          .then<void>(expectAsync1((Map<String, dynamic> r) {
        result = r;
      }));

      await tester.idle();
      expect(
        result,
        <String, dynamic>{
          'isError': false,
          'response': null,
        },
      );
    });

    testWidgets(
        'waits until no transient callbacks', (WidgetTester tester) async {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        // Intentionally blank. We only care about existence of a callback.
      });

      extension.call(const WaitUntilFrameSync().serialize())
          .then<void>(expectAsync1((Map<String, dynamic> r) {
        result = r;
      }));

      // Nothing should happen until the next frame.
      await tester.idle();
      expect(result, isNull);

      // NOW we should receive the result.
      await tester.pump();
      expect(
        result,
        <String, dynamic>{
          'isError': false,
          'response': null,
        },
      );
    });

    testWidgets(
        'waits until no pending scheduled frame', (WidgetTester tester) async {
      SchedulerBinding.instance.scheduleFrame();

      extension.call(const WaitUntilFrameSync().serialize())
          .then<void>(expectAsync1((Map<String, dynamic> r) {
        result = r;
      }));

      // Nothing should happen until the next frame.
      await tester.idle();
      expect(result, isNull);

      // NOW we should receive the result.
      await tester.pump();
      expect(
        result,
        <String, dynamic>{
          'isError': false,
          'response': null,
        },
      );
    });
  });
}
