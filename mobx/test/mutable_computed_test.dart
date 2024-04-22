import 'package:collection/collection.dart';
import 'package:mobx/mobx.dart' hide when;
import 'package:mobx/src/utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'shared_mocks.dart';
import 'util.dart';

void main() {
  testSetup();

  group('Computed', () {
    test('toString', () {
      final object = MutableComputed(() {}, name: 'MyName');
      expect(object.toString(), contains('MyName'));
    });

    test('debugCreationStack', () {
      DebugCreationStack.enable = true;
      addTearDown(() => DebugCreationStack.enable = false);
      final object = MutableComputed(() {});
      expect(object.debugCreationStack, isNotNull);
    });

    test('basics work', () {
      final x = Observable(20);
      final y = Observable(10);
      final c = MutableComputed(() => x.value + y.value);

      x.value = 30;
      y.value = 20;
      expect(c.value, equals(50));

      expect(mainContext.isComputingDerivation(), isFalse);
    });
    test('basics work', () {
      final x = Observable(20);
      final y = Observable(10);
      final c = MutableComputed(() => x.value + y.value);

      x.value = 30;
      y.value = 20;
      expect(c.value, equals(50));
      expect(c.value, equals(50));

      expect(mainContext.isComputingDerivation(), isFalse);
    });

    test('value hierarchy', () {
      final x = Observable(10, name: 'x');
      final y = Observable(20, name: 'y');
      final z = Observable(30, name: 'z');

      var c1ComputationCount = 0;
      var c3ComputationCount = 0;

      final c1 = MutableComputed(() {
        c1ComputationCount++;
        return x.value + y.value;
      }, name: 'c1');

      final c2 = MutableComputed(() => z.value, name: 'c2');

      final c3 = MutableComputed(() {
        c3ComputationCount++;
        return c1.value + c2.value;
      }, name: 'c3');

      final d = autorun((_) {
        c3.value;
      });

      expect(c3.value, equals(60));
      expect(c1ComputationCount, equals(1));
      expect(c3ComputationCount, equals(1));

      Action(() {
        // Setting values such that c3 need not be computed again
        x.value = 20;
        y.value = 10;
      })();

      // Should not change as value is same as before
      expect(c3ComputationCount, equals(1));

      // should be recomputed as both x and y have changed
      expect(c1ComputationCount, equals(2));

      Action(() {
        x.value = 30;
      })();

      expect(c1ComputationCount, equals(3));
      expect(c3ComputationCount, equals(2));

      expect(mainContext.isComputingDerivation(), isFalse);

      d();
    });

    test('can be observed', () {
      final x = Observable(10);
      final y = Observable(20);

      var executionCount = 0;

      final total = MutableComputed(() {
        executionCount++;
        return x.value + y.value;
      });

      final dispose1 = total.observe((change) {
        expect(change.newValue, equals(30));
        expect(executionCount, equals(1));
      });

      dispose1(); // no more observations

      x.value = 100; // should not invoke observe

      expect(executionCount, equals(1));
    });

    test('only notifies observers when computed value changed', () {
      final x = Observable(10);
      final y = Observable(20);

      var observationCount = 0;

      final total = MutableComputed(() => x.value + y.value);

      final dispose = total.observe((change) {
        observationCount++;
      });

      expect(observationCount, equals(1));

      // shouldn't notify because the total is the same
      Action(() {
        x.value = x.value + 10;
        y.value = y.value - 10;
      })();

      expect(observationCount, equals(1));

      dispose();
    });

    test('can use a custom equality', () {
      final list = ObservableList<int>.of([1, 2, 4]);

      var observationCount = 0;

      final evens = MutableComputed(
          () => list.where((element) => element.isEven).toList(),
          equals: const ListEquality().equals);

      final dispose = evens.observe((change) {
        observationCount++;
      });

      expect(observationCount, equals(1));

      // evens didn't change, so should not invoke observe
      list.add(5);
      expect(observationCount, equals(1));

      // evens changed, so should invoke observe
      list.add(6);
      expect(observationCount, equals(2));

      dispose();
    });

    test('uses provided context', () {
      final context = MockContext();
      when(() => context.nameFor(any())).thenReturn('Test-Computed');

      int fn() => 1;

      final c = MutableComputed(fn, context: context)
        ..computeValue(track: true);

      verify(() => context.nameFor('MutableComputed'));
      verify(() => context.trackDerivation(c, fn));
    });

    test('catches exception in evaluation', () {
      var shouldThrow = true;

      final x = MutableComputed(() {
        if (shouldThrow) {
          shouldThrow = false;
          throw Exception('FAIL');
        }
      });

      expect(() {
        x.value;
      }, throwsException);
      expect(x.errorValue, isException);

      x.value;
      expect(x.errorValue, isNull);
    });

    test('throws on finding a cycle', () {
      late Computed<int> c1;
      c1 = MutableComputed(() => c1.value);

      expect(() {
        c1.value;
      }, throwsException);

      // ignore: avoid_as
      expect((c1.errorValue?.exception as MobXException).message.toLowerCase(),
          contains('cycle'));
    });

    test('with disableErrorBoundaries = true, exception is thrown', () {
      final c = MutableComputed(() => throw Exception('FAIL'),
          context: createContext(
              config: ReactiveConfig(disableErrorBoundaries: true)));

      expect(() => c.value, throwsException);
    });

    test('with nullable values will propagate changes after errors', () {
      final shouldThrow = Observable(true);

      final c1 = Computed<int?>(() {
        if (shouldThrow.value) {
          throw Exception('FAIL');
        }
        return null;
      });

      final c2 = Computed<String>(() {
        c1.value;
        return 'SUCCESS';
      });

      String? value;
      MobXCaughtException? error;
      autorun((_) {
        try {
          value = c2.value;
        } finally {
          error = c2.errorValue;
        }
      });

      expect(value, isNull);
      expect(error, isNotNull);

      shouldThrow.value = false;

      expect(value, equals('SUCCESS'));
      expect(error, isNull);
    });

    test("keeping computed properties alive does not run before access", () {
      var calcs = 0;
      final x = Observable(1);
      // ignore: unused_local_variable
      final y = MutableComputed(() {
        calcs++;
        return x.value * 2;
      }, keepAlive: true);

      expect(calcs, 0); // initially there is no calculation done
    });

    test("keeping computed properties alive runs on first access", () {
      var calcs = 0;
      final x = Observable(1);
      final y = MutableComputed(() {
        calcs++;
        return x.value * 2;
      }, keepAlive: true);

      expect(calcs, 0);
      expect(y.value, 2); // perform calculation on access
      expect(calcs, 1);
    });

    test(
        "keeping computed properties alive caches values on subsequent accesses",
        () {
      var calcs = 0;
      final x = Observable(1);
      final y = MutableComputed(() {
        calcs++;
        return x.value * 2;
      }, keepAlive: true);

      expect(y.value, 2); // first access: do calculation
      expect(y.value, 2); // second access: use cached value, no calculation
      expect(calcs, 1); // only one calculation: cached!
    });

    test("keeping computed properties alive does not recalculate when dirty",
        () {
      var calcs = 0;
      final x = Observable(1);
      final y = MutableComputed(() {
        calcs++;
        return x.value * 2;
      }, keepAlive: true);

      expect(y.value, 2); // first access: do calculation
      expect(calcs, 1);
      x.value = 3; // mark as dirty: no calculation
      expect(calcs, 1);
      expect(y.value, 6);
    });

    test(
        "keeping computed properties alive recalculates when accessing it dirty",
        () {
      var calcs = 0;
      final x = Observable(1);
      final y = MutableComputed(() {
        calcs++;
        return x.value * 2;
      }, keepAlive: true);

      expect(y.value, 2); // first access: do calculation
      expect(calcs, 1);
      x.value = 3; // mark as dirty: no calculation
      expect(calcs, 1);
      expect(y.value, 6);
      expect(calcs, 2);
    });

    test("value set should triggers observers only", () {
      final x = Observable(10);
      final y = Observable(20);

      var executionCount = 0;
      var observationCount = 0;

      final total = MutableComputed(() {
        executionCount++;
        return x.value + y.value;
      });

      final dispose1 = total.observe((change) {
        observationCount++;
      });

      expect(total.value, equals(30));
      expect(observationCount, equals(1));

      total.value = 50; // triggers observers only, not execution
      expect(observationCount, equals(2));
      expect(total.value, equals(50));
      expect(executionCount, equals(1));

      dispose1(); // no more observations
    });

    test("recompute should triggers observers only", () {
      final x = Observable(10);
      final y = Observable(20);

      var executionCount = 0;
      var observationCount = 0;

      final total = MutableComputed(() {
        if (executionCount++ == 0) {
          return x.value;
        }

        return y.value;
      });

      final dispose1 = total.observe((change) {
        observationCount++;
      });

      expect(total.value, equals(10));
      expect(observationCount, equals(1));
      expect(executionCount, equals(1));
      total.recompute();

      expect(total.value, equals(20));
      expect(observationCount, equals(2));
      expect(executionCount, equals(2));

      dispose1(); // no more observations
    });

    test("set value should triggers observers only", () {
      var executionCount = 0;
      var observationCount = 0;

      final x = MutableComputed(() {
        executionCount++;
        return 5;
      }, name: 'x');

      final total = MutableComputed(() {
        return x.value * 2;
      }, name: 'total');

      final dispose1 = total.observe((change) {
        observationCount++;
      });

      expect(total.value, equals(10));
      expect(observationCount, equals(1));
      expect(executionCount, equals(1));
      x.value = 20;

      expect(total.value, equals(40));
      expect(observationCount, equals(2));
      expect(executionCount, equals(1));

      dispose1(); // no more observations
    });

    test('recompute should override exception', () {
      var shouldThrow = true;
      final x = MutableComputed(() {
        if (shouldThrow) {
          shouldThrow = false;
          throw Exception('FAIL');
        }
      });

      expect(() {
        x.value;
      }, throwsException);
      expect(x.errorValue, isException);
      x.recompute();
      expect(x.value, equals(null));
      expect(x.errorValue, isNull);
    });
    group('recompute', () {
      group('single policy', () {
        test('should propagate changes to observers', () {
          final policy = RecomputePolicy.single;
          var untrackedValue = 5;
          var xExecutionCount = 0;
          final x = MutableComputed(() {
            xExecutionCount++;
            return untrackedValue;
          }, name: 'x');

          final values = [];
          final dispose1 = x.observe((change) {
            values.add(change.newValue);
          });

          expect(values, equals([5]));
          expect(xExecutionCount, equals(1));

          x.recompute(policy: policy);
          expect(values, equals([5])); // no changes
          expect(xExecutionCount, equals(2));

          untrackedValue = 10;
          x.recompute(policy: policy);
          expect(values, equals([5, 10]));
          expect(xExecutionCount, equals(3));

          dispose1(); // no more observations
        });

        test('should propagate error to observers', () {
          final policy = RecomputePolicy.single;
          var xExecutionCount = 0;
          var yExecutionCount = 0;
          final exception = Exception('FAIL');

          final x = MutableComputed(() {
            xExecutionCount++;
            if (xExecutionCount == 2) {
              throw exception;
            }
            return 5;
          }, name: 'x');

          final y = MutableComputed(() {
            yExecutionCount++;
            return x.value * 2;
          }, name: 'y');

          final values = [];
          final dispose1 = y.observe((change) {
            values.add(change.newValue);
          });

          expect(values, equals([10]));
          expect(xExecutionCount, equals(1));
          expect(yExecutionCount, equals(1));

          x.recompute(policy: policy);
          expect(() => y.value, throwsException);
          expect(x.errorValue, isException);
          expect(y.errorValue, isException);
          expect(xExecutionCount, equals(2));
          expect(yExecutionCount, equals(2));
          expect(values, equals([10]));
          dispose1(); // no more observations
        });

        test('should rerun only target Computed', () {
          final policy = RecomputePolicy.single;
          var xExecutionCount = 0;
          var yExecutionCount = 0;

          final x = MutableComputed(() {
            xExecutionCount++;
            return 5;
          }, name: 'x');

          final y = MutableComputed(() {
            yExecutionCount++;
            return x.value * 2;
          }, name: 'y');

          final dispose1 = y.observe((change) {});

          expect(xExecutionCount, equals(1));
          expect(yExecutionCount, equals(1));
          y.recompute(policy: policy);
          expect(xExecutionCount, equals(1));
          expect(yExecutionCount, equals(2));
          dispose1(); // no more observations
        });
      });
      group('cascadeError policy', () {
        test('should rerun only observables with error state', () {
          final policy = RecomputePolicy.cascadeForError;
          var observationCount = 0;
          var xExecutionCount = 0;
          var yExecutionCount = 0;
          var zExecutionCount = 0;

          final exception = Exception('FAIL');
          var shouldThrow = true;
          final x = MutableComputed<int>(() {
            xExecutionCount++;
            if (shouldThrow) {
              shouldThrow = false;
              throw exception;
            }
            return 5;
          }, name: 'x');

          final y = MutableComputed(() {
            yExecutionCount++;
            return 10;
          }, name: 'y');

          final z = MutableComputed(() {
            zExecutionCount++;
            return y.value + x.value;
          }, name: 'z');

          final dispose1 = z.observe((change) {
            observationCount++;
          });

          expect(() => z.value, throwsA(isA<MobXCaughtException>()));
          expect(xExecutionCount, equals(1));
          expect(yExecutionCount, equals(1));
          expect(zExecutionCount, equals(1));
          expect(observationCount, equals(0)); // because error;

          z.recompute(policy: policy);
          expect(xExecutionCount, equals(2)); // error be recomputed
          expect(yExecutionCount, equals(1)); // shouldn't be recomputed
          expect(zExecutionCount, equals(2));
          expect(observationCount, equals(1));

          z.recompute(policy: policy);
          expect(xExecutionCount, equals(2)); // shouldn't be recomputed again
          expect(yExecutionCount, equals(1)); // shouldn't be recomputed
          expect(zExecutionCount, equals(3));
          expect(observationCount, equals(1)); // final results the same
          dispose1(); // no more observations
        });
      });
      group('cascade policy', () {
        test('should rerun all observables', () {
          final policy = RecomputePolicy.cascade;
          var observationCount = 0;
          var xExecutionCount = 0;
          var yExecutionCount = 0;
          var zExecutionCount = 0;

          final exception = Exception('FAIL');
          var shouldThrow = true;
          final x = MutableComputed<int>(() {
            xExecutionCount++;
            if (shouldThrow) {
              shouldThrow = false;
              throw exception;
            }
            return 5;
          }, name: 'x');

          final y = MutableComputed(() {
            yExecutionCount++;
            return 10;
          }, name: 'y');

          final z = MutableComputed(() {
            zExecutionCount++;
            return y.value + x.value;
          }, name: 'z');

          final dispose1 = z.observe((change) {
            observationCount++;
          });

          expect(() => z.value, throwsA(isA<MobXCaughtException>()));
          expect(xExecutionCount, equals(1));
          expect(yExecutionCount, equals(1));
          expect(zExecutionCount, equals(1));
          expect(observationCount, equals(0)); // because error;

          z.recompute(policy: policy);
          expect(z.value, equals(15));
          expect(xExecutionCount, equals(2));
          expect(yExecutionCount, equals(2));
          expect(zExecutionCount, equals(2));
          expect(observationCount, equals(1));

          z.recompute(policy: policy);
          expect(xExecutionCount, equals(3));
          expect(yExecutionCount, equals(3));
          expect(zExecutionCount, equals(3));
          expect(observationCount, equals(1));
          dispose1(); // no more observations
        });
      });
    });
  });
}
