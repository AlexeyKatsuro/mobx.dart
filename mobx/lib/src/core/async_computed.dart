part of '../core.dart';

class AsyncComputed<T> extends MutableComputed<AsyncValue<T>> {
  factory AsyncComputed(
    FutureOr<T> Function() fn, {
    String? name,
    ReactiveContext? context,
    EqualityComparer<AsyncValue<T>>? equals,
    bool? keepAlive,
  }) {
    return AsyncComputed._(
      context ?? mainContext,
      fn,
      name: name,
      equals: equals,
      keepAlive: keepAlive,
    );
  }

  AsyncComputed._(ReactiveContext context, this._asyncFn,
      {String? name, super.equals, super.keepAlive})
      : super._(
          context,
          () => throw StateError('Initial computation function must not be invoked directly.'),
          name: name ?? context.nameFor('AsyncComputed'),
        ) {
    _fn = () {
      AsyncValue<T>? syncValue;
      final FutureOr<T> futureOr;
      try {
        futureOr = run(_asyncFn);
      } catch (error, stackTrace) {
        return AsyncValue.error(error, stackTrace);
      }
      if (futureOr is! Future<T>) {
        return AsyncData(futureOr);
      }
      bool sync = true;
      futureOr.then(
        (data) {
          if (sync) {
            syncValue = AsyncData(data);
          } else {
            value = AsyncData(data);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (sync) {
            syncValue = AsyncError<T>(error, stackTrace);
          } else {
            value = AsyncError<T>(error, stackTrace);
          }
        },
      );

      sync = false;

      return syncValue ?? AsyncLoading<T>().copyWithPrevious(_value, isRefresh: false);
    };
  }

  @override
  set value(AsyncValue<T> newValue) {
    if (_isComputing) {
      throw MobXCyclicReactionException(
          'Value mutation during computation not allowed. $name: $_fn');
    }
    final previous = _value;
    if (!_isEqual(_value, newValue)) {
      _value = newValue.copyWithPrevious(previous, isRefresh: false);
      _context
        ..startBatch()
        ..propagateChanged(this)
        ..endBatch();
    }
  }

  @override
  AsyncValue<T>? computeValue({required bool track}) {
    // Tracking invocations inside the zone
    return super.computeValue(track: false);
  }

  final FutureOr<T> Function() _asyncFn;
  Zone? _zoneField;

  bool _asyncComputing = false;

  Zone get _zone {
    if (_zoneField == null) {
      final spec = ZoneSpecification(run: _run, runUnary: _runUnary);
      _zoneField = Zone.current.fork(specification: spec);
    }
    return _zoneField!;
  }

  FutureOr<R> run<R>(FutureOr<R> Function() body) {
    final futureOr = _zone.run(body);
    if (futureOr is! Future<R>) {
      _asyncComputing = false;
      return futureOr;
    }
    return futureOr.whenComplete(() => _asyncComputing = false);
  }

  R _run<R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
    if (context._state.trackingDerivation == this) {
      return parent.run(zone, f);
    }
    _context.startBatch();
    final prevDerivation = context._startTracking(this);
    if (_asyncComputing) {
      _newObservables = {..._observables};
    } else {
      _asyncComputing = true;
    }
    try {
      final result = parent.run(zone, f);
      return result;
    } finally {
      context._endTracking(this, prevDerivation);
      _context.endBatch();
    }
  }

  // Will be invoked for a catch clause that has a single argument: exception or
  // when a result is produced
  R _runUnary<R, A>(Zone self, ZoneDelegate parent, Zone zone, R Function(A a) f, A a) {
    if (context._state.trackingDerivation == this) {
      return parent.runUnary(zone, f, a);
    }
    _context.startBatch();
    final prevDerivation = context._startTracking(this);
    if (_asyncComputing) {
      _newObservables = {..._observables};
    } else {
      _asyncComputing = true;
    }
    try {
      final result = parent.runUnary(zone, f, a);
      return result;
    } finally {
      context._endTracking(this, prevDerivation);
      _context.endBatch();
    }
  }

  @override
  String toString() => 'AsyncComputed<$T>(name: $name, identity: ${identityHashCode(this)})';
}
