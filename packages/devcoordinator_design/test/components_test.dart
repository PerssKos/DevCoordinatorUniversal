import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = <AppNavigationDestination>[
  AppNavigationDestination(icon: Icons.home_outlined, label: 'Home'),
  AppNavigationDestination(icon: Icons.settings_outlined, label: 'Settings'),
];

void main() {
  testWidgets('AppScaffold adapts bottom navigation to a rail', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    Widget app() => MaterialApp(
      theme: AppThemes.light(VisualStyle.material),
      home: AppScaffold(
        title: 'Coordinator',
        destinations: _destinations,
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        body: const Text('Content'),
      ),
    );

    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets(
    'material pages without bars protect content from system insets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.light(VisualStyle.oneUiInspired),
          home: AppScaffold(body: const Text('First-run content')),
        ),
      );

      final safeArea = tester.widget<SafeArea>(
        find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(SafeArea),
        ),
      );
      expect(safeArea.top, isTrue);
      expect(safeArea.bottom, isTrue);
    },
  );

  testWidgets('Cupertino style uses Cupertino bottom navigation', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 800);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.light(VisualStyle.cupertino),
        home: AppScaffold(
          destinations: _destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          body: const Text('Content'),
        ),
      ),
    );

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('AppButton blocks repeat actions while loading', (tester) async {
    var taps = 0;

    Future<void> pump({required bool loading}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.light(VisualStyle.oneUiInspired),
          home: Center(
            child: AppButton(
              label: 'Deploy',
              loading: loading,
              onPressed: () => taps += 1,
            ),
          ),
        ),
      );
    }

    await pump(loading: false);
    await tester.tap(find.text('Deploy'));
    expect(taps, 1);

    await pump(loading: true);
    await tester.tap(find.text('Deploy'));
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AppStatus renders text and a non-color state cue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.dark(VisualStyle.material),
        home: const Center(
          child: AppStatus(label: 'Connected', tone: AppStatusTone.success),
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('AppStatus wraps a long message at a narrow width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.light(VisualStyle.oneUiInspired),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AppStatus(
              label:
                  'This deliberately long connection status must remain fully '
                  'visible on a narrow Android screen.',
              tone: AppStatusTone.info,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(AppStatus)).width,
      lessThanOrEqualTo(358),
    );
  });

  testWidgets('core components render in every style and brightness', (
    tester,
  ) async {
    for (final style in VisualStyle.values) {
      for (final brightness in Brightness.values) {
        var cardTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppThemes.resolve(style, brightness),
            home: Center(
              child: AppCard(
                onTap: () => cardTaps += 1,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppStatus(label: 'Ready', tone: AppStatusTone.info),
                    AppButton(label: 'Open', onPressed: null),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(AppCard));
        expect(cardTaps, 1, reason: '${style.name}/${brightness.name}');
        expect(tester.takeException(), isNull);
      }
    }
  });
}
