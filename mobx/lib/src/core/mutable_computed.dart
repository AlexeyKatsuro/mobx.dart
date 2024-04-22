part of '../core.dart';

class MutableComputed<T> extends Computed<T> {
  factory MutableComputed(T Function() fn,
          {String? name,
          ReactiveContext? context,
          EqualityComparer<T>? equals,
          bool? keepAlive}) =>
      MutableComputed._(context ?? mainContext, fn,
          name: name, equals: equals, keepAlive: keepAlive);

  MutableComputed._(super.context, super._fn,
      {String? name, super.equals, super.keepAlive})
      : super._(name: name ?? context.nameFor('MutableComputed'));

  set value(T newValue) {
    if (_isComputing) {
      throw MobXCyclicReactionException(
          'Value mutation during computation not allowed. $name: $_fn');
    }
    if (!_isEqual(_value, newValue)) {
      _value = _updateValue(_value, newValue);
      _context
        ..startBatch()
        ..propagateChanged(this)
        ..endBatch();
    }
  }

  T _updateValue(T? previous, T next) {
    return next;
  }

  void recompute({RecomputePolicy? policy}) {
    if (_isComputing) {
      throw MobXCyclicReactionException(
          'recompute during computation not allowed. $name: $_fn');
    }

    _context
      ..startBatch()
      .._requestRecompute(this, policy: policy)
      ..endBatch();
  }

  @override
  String toString() =>
      'MutableComputed<$T>(name: $name, identity: ${identityHashCode(this)})';
}
