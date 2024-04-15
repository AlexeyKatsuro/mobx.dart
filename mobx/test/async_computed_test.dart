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

    test('should return loading and data if no error', () async {
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

    /* test('can return value synchronously', () async {
      final x = Observable(20);
      final y = Observable(10);
      final z = Observable(0);
      final c = AsyncComputed(() => x.value + y.value);

      final values = [];
      final dispose = c.observe((change) {
        values.add(change.newValue);
      });

      expect(c.value, equals(AsyncLoading<int>()));
      await Future(() {
        print(z.value);
      },);
      await pumpEventQueue();
      expect(values, equals([AsyncLoading<int>(), AsyncData<int>(30)]));
      dispose();
    });*/

    test('async tracking ', () async {
      final x = Observable(20);
      final y = Observable(10);
      final c = AsyncComputed(() async {
        final xValue = x.value;
        await sleep(300);
        return xValue + y.value;
      });

      fakeAsync((async) {
        final values = [];
        final dispose = c.observe((change) {
          values.add(change.newValue);
        });

        expect(c.value, equals(AsyncLoading<int>()));

        async.elapse(Duration(milliseconds: 400));
        expect(values, equals([AsyncLoading<int>(), AsyncData<int>(30)]));
        expect(x.isBeingObserved, isTrue);
        expect(y.isBeingObserved, isTrue);
        dispose();
      });
    });
  }, timeout: Timeout(Duration(minutes: 30)));
}
