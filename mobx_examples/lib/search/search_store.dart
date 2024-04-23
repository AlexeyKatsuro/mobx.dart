import 'dart:developer';
import 'dart:math' as math;

import 'package:mobx/mobx.dart';

class Item {
  final String label;

  Item({required this.label});
}

Future<List<Item>> fetchItems({
  required String query,
  bool willFail = false,
}) async {
  log('fetch Items: $query');
  await Future.delayed(const Duration(seconds: 1));
  if(willFail) {
    log('fetch failed');
    throw Exception('Test Error');
  }
  final result = List.generate(math.max(100 - 10 * query.length, 0),
      (index) => Item(label: 'Item $index $query'));
  log('fetched Items: $query');
  return result;
}

class SearchStore with Store {
  final Observable<String> _query = Observable('');
  final Observable<bool> _onlyEven = Observable(false);
  final Observable<bool> _simulateError = Observable(false);

  late final _itemList = AsyncComputed(
    () async {
      final queryText = _query.value;
      await Future.delayed(const Duration(milliseconds: 400)); // Debounce
      return fetchItems(
        query: queryText,
        willFail: untracked(() => _simulateError.value),
      );
    },
    context: context,
  );

  late final _filteredItems = AsyncComputed(() async {
    final items = await _itemList.future;
    if (_onlyEven.value == true) {
      return [
        for (int i = 0; i < items.length; i++)
          if (i % 2 == 0) items[i],
      ];
    }
    return items;
  });

  AsyncValue<List<Item>> get itemList => _filteredItems.value;

  bool get filtered => _onlyEven.value;

  bool get failRequest => _simulateError.value;

  Future<void> onRefresh() {
    _itemList.recompute();
    return untracked(() => _itemList.future);
  }

  void onChanged(String query) => runInAction(() {
        _query.value = query;
      });

  void toggleFilter() => runInAction(() {
        _onlyEven.value = !_onlyEven.value;
      });

  void toggleError() => runInAction(() {
        _simulateError.value = !_simulateError.value;
      });
}
