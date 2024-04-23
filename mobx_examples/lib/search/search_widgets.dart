import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:provider/provider.dart';

import 'search_store.dart';

class SearchPageWidget extends StatelessWidget {
  const SearchPageWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (context) => SearchStore(),
      child: Builder(builder: (context) {
        final searchStore = Provider.of<SearchStore>(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text("Search Page"),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.search),
                  ),
                  onChanged: searchStore.onChanged,
                ),
              ),
              Observer(builder: (context) {
                return CheckboxListTile(
                  value: searchStore.filtered,
                  title: const Text('Filter odd'),
                  onChanged: (_) => searchStore.toggleFilter(),
                );
              }),
              Observer(builder: (context) {
                return CheckboxListTile(
                  value: searchStore.failRequest,
                  title: const Text('Simulate Fetch error'),
                  onChanged: (_) => searchStore.toggleError(),
                );
              }),
              Observer(builder: (context) {
                return Expanded(
                  child: searchStore.itemList.when(
                    data: (itemList) => RefreshIndicator(
                      onRefresh: searchStore.onRefresh,
                      child: ListView.builder(
                        itemCount: itemList.length,
                        itemBuilder: (context, index) {
                          final item = itemList[index];
                          return ListTile(
                            title: Text(item.label),
                          );
                        },
                      ),
                    ),
                    error: (error, stackTrace) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Error: $error"),
                          FilledButton.icon(
                            onPressed: searchStore.onRefresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          )
                        ],
                      ),
                    ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }),
    );
  }
}
