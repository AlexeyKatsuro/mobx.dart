import 'dart:async';

import 'package:mobx/mobx.dart' hide when;
import 'package:test/test.dart';

import 'util.dart';

void main() {
  testSetup();
  test('sh', () async {
    final profilesDataProvider = AsyncComputed(() {
      print('#1 start - profilesData');
      return getProfilesData()
          .whenComplete(() => print('#1 end - profilesData'));
    });
    final customerProfileProvider = AsyncComputed(() async {
      print('#2 start - customerProfile');
      final profilesData = await profilesDataProvider.future;
      return getCustomerProfile(profilesData.customerId)
          .whenComplete(() => print('#2 end - customerProfile'));
    });

    final serviceProfileProvider = AsyncComputed(
      () async {
        print('#3 start - serviceProfile');
        final profilesData = await profilesDataProvider.future;
        return getServiceProfile(profilesData.serviceId)
            .whenComplete(() => print('#3 end - serviceProfile'));
      },
    );

    final stateProvider = AsyncComputed(() async {
      print('#4 start - stateProvider');
      final state = ProfilesState(
        customerProfile: await customerProfileProvider.future,
        serviceProfile: await serviceProfileProvider.future,
      );
      print('#4 start - stateProvider');
      return state;
    });

    final dispose = autorun((_) {
      print('autorun');
      print('${customerProfileProvider.value}');
    });

    await Future.delayed(Duration(seconds: 4));
    print('done');
    customerProfileProvider.updateData(
      (data) {
        return CustomerProfile(data.customerId, 'newName');
      },
    );
    await Future.delayed(Duration(seconds: 10));
    dispose();
  }, timeout: Timeout(Duration(minutes: 10)));
}

Future<ProfilesData> getProfilesData() async {
  print('1. start - getProfilesData');
  await Future.delayed(Duration(seconds: 1));
  print('1. end - getProfilesData');
  return const ProfilesData();
}

Future<CustomerProfile> getCustomerProfile(String id) async {
  print('2. start - getCustomerProfile');
  await Future.delayed(Duration(seconds: 1));
  print('2. end - getCustomerProfile');
  return CustomerProfile(id);
}

Future<ServiceProfile> getServiceProfile(String id) async {
  print('3. start - getServiceProfile');
  await Future.delayed(Duration(seconds: 1));
  print('3. end - getServiceProfile');
  return ServiceProfile(id);
}

class ProfilesData {
  const ProfilesData();

  final customerId = 'customerId';
  final serviceId = 'serviceId';
}

class CustomerProfile {
  final String customerId;
  final String name;

  @override
  String toString() {
    return 'CustomerProfile{customerId: $customerId, name: $name}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerProfile &&
          runtimeType == other.runtimeType &&
          customerId == other.customerId;

  @override
  int get hashCode => customerId.hashCode;

  CustomerProfile(this.customerId, [this.name = 'defaultName']);
}

class ServiceProfile {
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  ServiceProfile(this.id);
}

class ProfilesState {
  final CustomerProfile customerProfile;

  @override
  String toString() {
    return 'ProfilesState{customerProfile: $customerProfile}';
  }

  final ServiceProfile serviceProfile;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfilesState &&
          runtimeType == other.runtimeType &&
          customerProfile == other.customerProfile &&
          serviceProfile == other.serviceProfile;

  @override
  int get hashCode => customerProfile.hashCode ^ serviceProfile.hashCode;

  ProfilesState({required this.customerProfile, required this.serviceProfile});
}

extension MutableComputedExt<T> on MutableComputed<AsyncValue<T>> {
  void updateData(T Function(T data) update) {
    if (isComputed) {
      if (value case AsyncData(:final value)) {
        this.value = AsyncData(update(value));
      }
    }
  }
}
