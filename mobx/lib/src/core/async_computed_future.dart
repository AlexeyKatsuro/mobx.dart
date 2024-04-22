part of '../core.dart';

class AsyncComputedFuture<T> extends Computed<Future<T>> {
  factory AsyncComputedFuture(AsyncValue<T> Function() fn,
          {String? name,
          ReactiveContext? context,
          EqualityComparer<Future<T>>? equals,
          bool? keepAlive}) =>
      AsyncComputedFuture._(
        context ?? mainContext,
        fn,
        name: name,
        equals: equals,
        keepAlive: keepAlive,
      );

  AsyncComputedFuture._(ReactiveContext context, AsyncValue<T> Function() fn,
      {String? name, super.equals, super.keepAlive})
      : super._(
          context,
          () => throw StateError(
              'Initial computation function must not be invoked directly.'),
          name: name ?? context.nameFor('AsyncComputedFuture'),
        ) {
    _fn = () {
      final newValue = fn();
      final prevValue = _prevValue;
      final Future<T> future;
      late final completer = _completer ??= Completer();
      switch (newValue) {
        case AsyncData():
          {
            switch (prevValue) {
              case AsyncData():
                {
                  if (newValue.value != prevValue.value) {
                    _completer = null;
                    future = Future.value(newValue.value);
                  } else {
                    future = _value!;
                  }
                }
              case AsyncError():
                {
                  _completer = null;
                  future = Future.value(newValue.value);
                }
              case AsyncLoading():
                {
                  completer.complete(newValue.value);
                  future = _value!;
                }
              case null:
                {
                  _completer = null;
                  future = Future.value(newValue.value);
                }
            }
          }
        case AsyncError():
          {
            switch (prevValue) {
              case AsyncData():
                {
                  _completer = null;
                  future = Future.error(newValue.error, newValue.stackTrace);
                }
              case AsyncError():
                {
                  if (prevValue.error != newValue.error ||
                      prevValue.stackTrace != newValue.stackTrace) {
                    _completer = null;
                    future = Future.error(newValue.error, newValue.stackTrace);
                  } else {
                    future = _value!;
                  }
                }
              case AsyncLoading():
                {
                  completer.completeError(newValue.error, newValue.stackTrace);
                  future = completer.future;
                }
              case null:
                {
                  _completer = null;
                  future = Future.error(newValue.error, newValue.stackTrace);
                }
            }
          }
        case AsyncLoading():
          {
            switch (prevValue) {
              case AsyncData() || AsyncError():
                {
                  _completer = Completer();
                  future = completer.future;
                }
              case AsyncLoading():
                {
                  future = _value!;
                }
              case null:
                {
                  future = completer.future;
                }
            }
          }
      }
      _prevValue = newValue;
      return future;
    };
  }

  @override
  void _suspend() {
    super._suspend();
    if (!_keepAlive) {
      _prevValue = null;
      _completer = null;
    }
  }

  AsyncValue<T>? _prevValue;
  Completer<T>? _completer;

  @override
  String toString() =>
      'AsyncComputedFuture<$T>(name: $name, identity: ${identityHashCode(this)})';
}
