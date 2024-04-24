part of '../core.dart';

typedef _ResultOrCancel = Object?;

class AsyncComputed<T> extends MutableComputed<AsyncValue<T>>
    with AsyncDerivation {
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
          () => throw StateError(
              'Initial computation function must not be invoked directly.'),
          name: name ?? context.nameFor('AsyncComputed'),
        ) {
    _fn = () {
      AsyncValue<T>? syncValue;
      final FutureOr<_ResultOrCancel> futureOr;
      final disposer = _Disposer();
      if (_state == AsyncDerivationState.computing) {
        _state = AsyncDerivationState.wasRerun;
      }
      try {
        futureOr = _runInZone(_asyncFn, disposer: disposer);
      } catch (error, stackTrace) {
        endAsyncComputation();
        return AsyncValue.error(error, stackTrace);
      }
      if (futureOr is! Future) {
        endAsyncComputation();
        return AsyncData(futureOr as T);
      }
      bool sync = true;
      futureOr.then(
        (data) {
          if (data is! T || disposer.isDisposed) return;
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
        endAsyncComputation();
      });

      sync = false;

      return syncValue ??
          AsyncLoading<T>().copyWithPrevious(_value, isRefresh: false);
    };
  }

  @override
  AsyncValue<T> _updateValue(AsyncValue<T>? previous, AsyncValue<T> next) {
    return next.copyWithPrevious(previous, isRefresh: false);
  }

  late final _computedFuture =
      AsyncComputedFuture(() => value, name: 'AsyncComputedFuture.$name');

  Future<T> get future => _computedFuture.value;

  void endAsyncComputation() {
    _prevZone?.disposer.close();
    _prevZone = null;
    _state = AsyncDerivationState.upToDate;
    _removeDetachedObservables();
  }

  @override
  AsyncValue<T>? computeValue({required bool track}) {
    // Tracking invocations inside the zone
    return super.computeValue(track: false);
  }

  @override
  void _bindDependencies() {
    final derivation = this;
    final newObservables =
        derivation._newObservables!.difference(derivation._observables);

    final justDetached =
        derivation._observables.difference(derivation._newObservables!);
    final previouslyDetached = derivation._detachedObservables;

    final detachedObservables =
        justDetached.union(previouslyDetached.difference(newObservables));

    var lowestNewDerivationState = DerivationState.upToDate;

    // Add newly found observables
    for (final observable in newObservables) {
      observable._addObserver(derivation);

      // Computed = Observable + Derivation
      if (observable is Computed) {
        if (observable._dependenciesState.index >
            lowestNewDerivationState.index) {
          lowestNewDerivationState = observable._dependenciesState;
        }
      }
    }

    // Remove previous observables
    for (final ob in justDetached) {
      ob._detachObserver(derivation);
    }

    if (lowestNewDerivationState != DerivationState.upToDate) {
      derivation
        .._dependenciesState = lowestNewDerivationState
        .._onBecomeStale();
    }

    derivation
      .._observables = derivation._newObservables!
      .._detachedObservables = detachedObservables
      .._newObservables = {}; // No need for newObservables beyond this point
  }

  void _removeDetachedObservables() {
    for (final ob in _detachedObservables) {
      ob._removeObserver(this);
    }
  }

  final FutureOr<T> Function() _asyncFn;
  Zone? _prevZone;

  Zone _createZone(_Disposer disposer) {
    final spec = ZoneSpecification(run: _run, runUnary: _runUnary);
    final depth = Zone.current.depth + 1;
    return Zone.current.fork(specification: spec, zoneValues: {
      #disposer: disposer,
      #depth: depth,
    });
  }

  FutureOr<_ResultOrCancel>? _runInZone(FutureOr<T> Function() body,
      {required _Disposer disposer}) {
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
      return #cancel as R;
    }
    if (self.disposer.isClose) {
      return parent.run(zone, f);
    }

    return _tack(() => parent.run(zone, f), self.depth - 1);
  }

  // Will be invoked for a catch clause that has a single argument: exception or
  // when a result is produced
  R _runUnary<R, A>(
      Zone self, ZoneDelegate parent, Zone zone, R Function(A a) f, A a) {
    if (self.disposer.isDisposed) {
      return #cancel as R;
    }
    if (self.disposer.isClose) {
      return parent.runUnary(zone, f, a);
    }

    return _tack(() => parent.runUnary(zone, f, a), self.depth - 1);
  }

  R _tack<R>(R Function() fn, int depth) {
    if (context._state.asyncComputationDepth != depth) {
      return fn();
    }
    if (context._state.trackingDerivation == this) {
      return fn();
    }
    _context.startAsyncBatch();
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
      _context.endAsyncBatch();
    }
  }

  @override
  String toString() =>
      'AsyncComputed<$T>(name: $name, identity: ${identityHashCode(this)})';
}

mixin AsyncDerivation {
  AsyncDerivationState _state = AsyncDerivationState.notTracked;
  Set<Atom> _detachedObservables = {};
}

enum AsyncDerivationState {
  notTracked,
  computing,
  wasRerun,
  upToDate;
}

extension on Zone {
  _Disposer get disposer {
    return this[#disposer] as _Disposer;
  }

  int get depth {
    return this[#depth] as int? ?? 0;
  }
}

class _Disposer {
  void dispose() => isDisposed = true;

  void close() => isClose = true;
  bool isDisposed = false;
  bool isClose = false;
}
