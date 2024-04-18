part of '../core.dart';

class AsyncComputed<T> extends MutableComputed<AsyncValue<T>> with AsyncDerivation {
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
      final disposer = _Disposer();
      try {
        futureOr = _runInZone(_asyncFn, disposer: disposer);
      } catch (error, stackTrace) {
        _state = AsyncDerivationState.upToDate;
        return AsyncValue.error(error, stackTrace);
      }
      if (futureOr is! Future<T>) {
        _state = AsyncDerivationState.upToDate;
        return AsyncData(futureOr);
      }
      bool sync = true;
      futureOr.then(
        (data) {
          if (disposer.isDisposed) return;

          if (sync) {
            syncValue = AsyncData(data);
          } else {
            value = AsyncData(data);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (disposer.isDisposed) return;

          if (sync) {
            syncValue = AsyncError<T>(error, stackTrace);
          } else {
            value = AsyncError<T>(error, stackTrace);
          }
        },
      ).whenComplete(() {
        if (disposer.isDisposed) return;
        _state = AsyncDerivationState.upToDate;
      });

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
  Zone? _prevZone;

  Zone _createZone(_Disposer disposer) {
    final spec = ZoneSpecification(run: _run, runUnary: _runUnary);
    return Zone.current.fork(specification: spec, zoneValues: {
      #disposer: disposer,
    });
  }

  FutureOr<R> _runInZone<R>(FutureOr<R> Function() body, {required _Disposer disposer}) {
    final prevZone = _prevZone;

    if (prevZone != null) {
      prevZone.disposer.dispose();
      _prevZone = null;
    }
    final zone = _createZone(disposer);
    _prevZone = zone;
    return zone.run(body);
  }

  R _run<R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
    if (self.disposer.isDisposed) {
      return parent.run(zone, f);
    }
    return _tack(() => parent.run(zone, f));
  }

  // Will be invoked for a catch clause that has a single argument: exception or
  // when a result is produced
  R _runUnary<R, A>(Zone self, ZoneDelegate parent, Zone zone, R Function(A a) f, A a) {
    if (self.disposer.isDisposed) {
      return parent.runUnary(zone, f, a);
    }
    return _tack(() => parent.runUnary(zone, f, a));
  }

  R _tack<R>(R Function() fn) {
    if (context._state.trackingDerivation == this) {
      return fn();
    }
    _context.startBatch();
    final prevDerivation = context._startTracking(this);
    if (_state == AsyncDerivationState.computing) {
      _newObservables = {..._observables};
    } else {
      _state = AsyncDerivationState.computing;
    }
    try {
      final result = fn();
      return result;
    } finally {
      context._endTracking(this, prevDerivation);
      _context.endBatch();
    }
  }

  @override
  String toString() => 'AsyncComputed<$T>(name: $name, identity: ${identityHashCode(this)})';
}

mixin AsyncDerivation {
  AsyncDerivationState _state = AsyncDerivationState.notTracked;
}

enum AsyncDerivationState {
  notTracked,
  computing,
  upToDate;
}

extension on Zone {
  _Disposer get disposer {
    return this[#disposer] as _Disposer;
  }
}

class _Disposer {
  void dispose() => isDisposed = true;
  bool isDisposed = false;
}
