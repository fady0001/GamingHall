import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/game_resource.dart';
import '../../domain/entities/resource_kind.dart';
import '../../domain/entities/resource_type.dart';
import '../../domain/repositories/resource_repository.dart';

class ResourcesState {
  final List<GameResource> resources;
  final List<ResourceType> types;
  final bool isLoading;
  const ResourcesState({
    this.resources = const [],
    this.types = const [],
    this.isLoading = true,
  });

  GameResource? byId(int id) {
    for (final r in resources) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// أنواع الطاولات (التي يختار منها المدير عند إضافة طاولة).
  List<ResourceType> get tableTypes =>
      types.where((t) => t.kind == ResourceKind.table).toList();

  ResourcesState copyWith({
    List<GameResource>? resources,
    List<ResourceType>? types,
    bool? isLoading,
  }) =>
      ResourcesState(
        resources: resources ?? this.resources,
        types: types ?? this.types,
        isLoading: isLoading ?? this.isLoading,
      );
}

class ResourcesCubit extends Cubit<ResourcesState> {
  final ResourceRepository _repository;
  StreamSubscription<List<GameResource>>? _subscription;
  StreamSubscription<List<ResourceType>>? _typesSubscription;

  ResourcesCubit(this._repository) : super(const ResourcesState()) {
    _subscription = _repository.watchAll().listen(
          (list) => emit(state.copyWith(resources: list, isLoading: false)),
        );
    _typesSubscription = _repository.watchTypes().listen(
          (list) => emit(state.copyWith(types: list)),
        );
  }

  Future<GameResource> add(GameResource r) => _repository.add(r);
  Future<GameResource> update(GameResource r) => _repository.update(r);
  Future<void> setOutOfService(int id, bool value) =>
      _repository.setOutOfService(id, value);
  Future<void> remove(int id) => _repository.remove(id);
  Future<String?> blockReason(int id, {required bool forDelete}) =>
      _repository.blockReason(id, forDelete: forDelete);

  Future<ResourceType> addType(String name) => _repository.addType(name);
  Future<void> renameType(int id, String name) => _repository.renameType(id, name);
  Future<void> removeType(int id) => _repository.removeType(id);

  @override
  Future<void> close() {
    _subscription?.cancel();
    _typesSubscription?.cancel();
    return super.close();
  }
}
