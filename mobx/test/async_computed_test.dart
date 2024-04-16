import 'package:fake_async/fake_async.dart';
import 'package:mobx/mobx.dart' hide when;
import 'package:mobx/src/api/async.dart';
import 'package:mobx/src/utils.dart';
import 'package:test/test.dart';

import 'async_action_test.dart';
import 'util.dart';

void main() {
  testSetup();

  group('AsyncComputed', () {
    test('toString', () {
      final object = AsyncComputed(() async {}, name: 'MyName');
      expect(object.toString(), contains('MyName'));
    });

    test('debugCreationStack', () {
      DebugCreationStack.enable = true;
      addTearDown(() => DebugCreationStack.enable = false);
      final object = AsyncComputed(() async {});
      expect(object.debugCreationStack, isNotNull);
    });

    test('can return value synchronously', () async {
      final computed = AsyncComputed(() => 0);
      expect(computed.value, equals(AsyncData<int>(0)));
    });

    test('can set and get value synchronously', () async {
      int computationCount = 0;
      final computed = AsyncComputed(() {
        computationCount++;
        return 0;
      });

      var values = [];
      computed.observe((change) {
        values.add(change.newValue);
      });

      computed.value = AsyncData(1);
      computed.value = AsyncData(2);

      expect(values, equals([AsyncData<int>(0), AsyncData<int>(1), AsyncData<int>(2)]));
      expect(computationCount, equals(1));
    });

    test('should catch synchronous errors', () async {
      final exception = Exception('FAIL');
      final x = AsyncComputed<void>(() {
        throw exception;
      });

      expect(
        x.value,
        isA<AsyncError<void>>().having((error) => error.error, 'error', equals(exception)),
      );
      expect(x.errorValue, isNull);
    });
    test('should catch asynchronous errors', () async {
      int observationCount = 0;
      final exception = Exception('FAIL');
      final computed = AsyncComputed<void>(() async {
        throw exception;
      });

      computed.observe((change) {
        observationCount++;
      });

      expect(
        computed.value,
        equals(AsyncLoading<void>()),
      );
      await pumpEventQueue();
      expect(
        computed.value,
        isA<AsyncError<void>>().having((error) => error.error, 'error', equals(exception)),
      );
      expect(computed.errorValue, isNull);
      expect(observationCount, equals(2));
    });

    test('should return loading and data for asynchronous value', () async {
      int computationCount = 0;
      final computed = AsyncComputed(() async {
        computationCount++;
        await sleep(50);
        return 0;
      });

      fakeAsync((async) {
        expect(computationCount, equals(0)); // computation should be cold

        var values = [];
        computed.observe((change) {
          values.add(change.newValue);
        });

        async.elapse(Duration(milliseconds: 50));
        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(0)]));
        expect(computationCount, equals(1));
      });
    });

    test('should work with sync Computed', () async {
      int computationCount = 0;
      final asyncValue = AsyncComputed(() async {
        await sleep(50);
        return 0;
      });
      final computed = Computed(() {
        computationCount++;
        return asyncValue.value;
      });

      fakeAsync((async) {
        expect(computationCount, equals(0)); // computation should be cold

        var values = [];
        computed.observe((change) {
          values.add(change.newValue);
        });

        async.elapse(Duration(milliseconds: 50));
        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(0)]));
        expect(computationCount, equals(2));
      });
    });

    test('recompute should emit loading with previous data', () async {
      int computationCount = 0;
      final computed = AsyncComputed(() async {
        computationCount++;
        await sleep(50);
        return 0;
      });

      fakeAsync((async) {
        var values = [];
        computed.observe((change) {
          values.add(change.newValue);
        });

        async.elapse(Duration(milliseconds: 60));
        values = []; // skip first loading, data
        computed.recompute();
        async.elapse(Duration(milliseconds: 60));
        expect(values, [
          isA<AsyncLoading<int>>()
              // having value form previous computation
              .having((loading) => loading.hasValue, 'hasValue', equals(true))
              .having((loading) => loading.value, 'value', equals(0)),
          equals(AsyncData<int>(0)),
        ]);
        expect(computationCount, equals(2));
      });
    });

    test('recompute should emit loading with previous error', () async {
      int computationCount = 0;
      final exception = Exception('FAIL');
      final computed = AsyncComputed(() async {
        await sleep(50);
        if (computationCount++ == 0) {
          throw exception;
        }
        return 0;
      });

      fakeAsync((async) {
        var values = [];
        computed.observe((change) {
          values.add(change.newValue);
        });

        async.elapse(Duration(milliseconds: 60));
        values = []; // skip first loading, error
        computed.recompute();
        async.elapse(Duration(milliseconds: 60));
        expect(values, [
          isA<AsyncLoading<int>>()
              // having value form previous computation
              .having((loading) => loading.hasError, 'hasError', equals(true))
              .having((loading) => loading.error, 'error', equals(exception)),
          equals(AsyncData<int>(0)),
        ]);
        expect(computationCount, equals(2));
      });
    });
  });

  group('AsyncComputed tacking', () {
    test('can track observable asynchronous', () async {
      final x = Observable(0);
      final y = AsyncComputed(() async {
        await sleep(300);
        return x.value;
      });

      fakeAsync((async) {
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);

        final values = [];
        final dispose = y.observe((change) {
          values.add(change.newValue);
        });
        expect(x.isBeingObserved, isFalse); // should be tracked after async gap
        expect(y.isBeingObserved, isTrue);

        expect(y.value, equals(AsyncLoading<int>()));
        async.elapse(Duration(milliseconds: 300));

        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(0)]));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        dispose();
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);
      });
    });
    test('can track observable synchronously', () async {
      final x = Observable(0);
      final y = AsyncComputed(() async {
        return x.value; // No async gap
      });

      fakeAsync((async) {
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);

        final values = [];
        final dispose = y.observe((change) {
          values.add(change.newValue);
        });
        expect(x.isBeingObserved, isTrue); // should be tracked immediately
        expect(y.isBeingObserved, isTrue);

        expect(y.value, equals(AsyncLoading<int>()));
        async.elapse(Duration(milliseconds: 300));

        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(0)]));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        dispose();
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);
      });
    });

    test('can track observables before and after async gap', () async {
      final x = Observable(1);
      final y = Observable(2);
      final z = Observable(3);
      final computed = AsyncComputed(() async {
        final xValue = x.value;
        await sleep(100);
        final yValue = y.value;
        await sleep(100);
        final zValue = z.value;
        return xValue + yValue + zValue;
      });

      fakeAsync((async) {
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);
        expect(z.isBeingObserved, isFalse);
        expect(computed.isBeingObserved, isFalse);

        final values = [];
        final dispose = computed.observe((change) {
          values.add(change.newValue);
        });
        expect(computed.isBeingObserved, isTrue);
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isFalse);
        expect(z.isBeingObserved, isFalse);

        async.elapse(Duration(milliseconds: 110));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        expect(z.isBeingObserved, isFalse);
        async.elapse(Duration(milliseconds: 110));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        expect(z.isBeingObserved, isTrue);
        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(6)]));

        dispose();
        expect(x.isBeingObserved, isFalse);
        expect(y.isBeingObserved, isFalse);
        expect(z.isBeingObserved, isFalse);
        expect(computed.isBeingObserved, isFalse);
      });
    });
    test('should recompute values after observable changes', () async {
      int observationCount = 0;
      int computationCount = 0;
      final x = Observable(1);
      final y = Observable(2);
      final z = Observable(3);
      final computed = AsyncComputed(() async {
        computationCount++;
        final xValue = x.value;
        await sleep(100);
        final yValue = y.value;
        await sleep(100);
        final zValue = z.value;
        return xValue + yValue + zValue;
      });

      fakeAsync((async) {
        final dispose = computed.observe((change) {
          observationCount++;
        });

        async.elapse(Duration(milliseconds: 200));

        expect(computationCount, equals(1));
        x.value = x.value + 1;
        expect(computationCount, equals(2));
        expect(
          computed.value,
          isA<AsyncLoading<int>>().having((loading) => loading.value, 'value', equals(6)),
        );
        async.elapse(Duration(milliseconds: 200));
        expect(computed.value, equals(AsyncData<int>(7)));
        expect(observationCount, equals(4));
        expect(computationCount, equals(2));

        dispose();
      });
    });

    test('should recompute once if several dependencies have changed in action', () async {
      int observationCount = 0;
      int computationCount = 0;
      final x = Observable(1);
      final y = Observable(2);
      final z = Observable(3);
      final computed = AsyncComputed(() async {
        computationCount++;
        final xValue = x.value;
        await sleep(100);
        final yValue = y.value;
        await sleep(100);
        final zValue = z.value;
        return xValue + yValue + zValue;
      });

      fakeAsync((async) {
        final dispose = computed.observe((change) {
          observationCount++;
        });

        async.elapse(Duration(milliseconds: 200));
        expect(observationCount, equals(2)); // loading + data
        expect(computationCount, equals(1));
        runInAction(() {
          y.value = y.value + 2;
          z.value = z.value + 1;
        });
        async.elapse(Duration(milliseconds: 200));
        expect(computationCount, equals(2));
        expect(observationCount, equals(4)); // 1. loading + data 2. loading + data

        dispose();
      });
    });

    test(
        'after recompute, should stop tracking dependencies that began to be observed after the async gap',
        () async {
      int observationCount = 0;
      int computationCount = 0;
      final x = Observable(1);
      final y = Observable(2);
      final z = Observable(3);
      final computed = AsyncComputed(() async {
        computationCount++;
        final xValue = x.value;
        await sleep(100);
        final yValue = y.value;
        await sleep(100);
        final zValue = z.value;
        return xValue + yValue + zValue;
      });

      fakeAsync((async) {
        final dispose = computed.observe((change) {
          observationCount++;
        });

        async.elapse(Duration(milliseconds: 200));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        expect(z.isBeingObserved, isTrue);
        expect(observationCount, equals(2)); // loading + data
        expect(computationCount, equals(1));

        // recompute
        x.value = x.value + 1;
        expect(computationCount, equals(2));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isFalse);
        expect(z.isBeingObserved, isFalse);
        async.elapse(Duration(milliseconds: 200));
        // Observe again
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        expect(z.isBeingObserved, isTrue);
        dispose();
      });
    });
  });
}
