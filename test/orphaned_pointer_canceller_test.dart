import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupertino_native_better/utils/orphaned_pointer_canceller.dart';

void main() {
  group('OrphanedPointerCanceller', () {
    final barKey = GlobalKey();
    final navKey = GlobalKey<NavigatorState>();
    late List<int> cancelled;
    late OrphanedPointerCanceller canceller;

    void recordCancel(PointerEvent event) {
      if (event is PointerCancelEvent) cancelled.add(event.pointer);
    }

    Rect barRect() {
      final box = barKey.currentContext!.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    // Host route with a 50pt "bar" at the bottom; the canceller is bound to
    // the host route's secondaryAnimation, as CNTabBar does.
    Future<void> pumpHost(
      WidgetTester tester, {
      bool autoDispose = true,
    }) async {
      cancelled = <int>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(recordCancel);
      addTearDown(
        () => GestureBinding.instance.pointerRouter.removeGlobalRoute(
          recordCancel,
        ),
      );
      canceller = OrphanedPointerCanceller(
        globalRect: () => barKey.currentContext == null ? null : barRect(),
      );
      if (autoDispose) addTearDown(canceller.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          navigatorKey: navKey,
          home: Builder(
            builder: (context) {
              canceller.coveringAnimation = ModalRoute.of(
                context,
              )?.secondaryAnimation;
              return Column(
                children: [
                  const Spacer(),
                  SizedBox(key: barKey, height: 50, width: double.infinity),
                ],
              );
            },
          ),
        ),
      );
    }

    // Starts a push, lets it run for a few frames (so the down lands
    // mid-transition, after Navigator's own push-time cancel), runs [during],
    // then completes the transition.
    Future<void> pushOver(
      WidgetTester tester,
      Future<void> Function() during,
    ) async {
      navKey.currentState!.push(
        CupertinoPageRoute<void>(builder: (_) => const SizedBox.expand()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await during();
      await tester.pumpAndSettle();
    }

    testWidgets('cancels a pointer that went down inside the bar', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await tester.createGesture(pointer: 11);
      await pushOver(tester, () => gesture.down(barRect().center));
      expect(cancelled, [11]);
      expect(canceller.trackedPointerCount, 0);
    });

    testWidgets('uses the bar rect at down time, not after the parallax', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await tester.createGesture(pointer: 15);
      await pushOver(
        tester,
        () => gesture.down(barRect().centerRight - const Offset(10, 0)),
      );
      expect(cancelled, [15]);
    });

    testWidgets('leaves a pointer outside the bar untouched', (tester) async {
      await pumpHost(tester);
      final gesture = await tester.createGesture(pointer: 12);
      await pushOver(tester, () => gesture.down(const Offset(100, 100)));
      expect(cancelled, isEmpty);
      expect(canceller.trackedPointerCount, 0);
      await gesture.up();
    });

    testWidgets('ignores a pointer that went up before the push completed', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await tester.createGesture(pointer: 13);
      await pushOver(tester, () async {
        await gesture.down(barRect().center);
        await gesture.up();
      });
      expect(cancelled, isEmpty);
      expect(canceller.trackedPointerCount, 0);
    });

    testWidgets('dispose stops tracking and cancelling', (tester) async {
      await pumpHost(tester, autoDispose: false);
      canceller.dispose();
      final gesture = await tester.createGesture(pointer: 14);
      await pushOver(tester, () => gesture.down(barRect().center));
      expect(cancelled, isEmpty);
      expect(canceller.trackedPointerCount, 0);
      await gesture.up();
    });
  });
}
