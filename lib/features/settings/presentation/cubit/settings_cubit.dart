import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsState {
  final AppSettings settings;
  final bool isLoaded;
  const SettingsState({this.settings = const AppSettings(), this.isLoaded = false});
}

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository _repository;
  StreamSubscription<AppSettings>? _subscription;

  SettingsCubit(this._repository) : super(const SettingsState()) {
    _subscription = _repository.watch().listen(
          (s) => emit(SettingsState(settings: s, isLoaded: true)),
        );
  }

  Future<void> save(AppSettings settings) => _repository.save(settings);

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
