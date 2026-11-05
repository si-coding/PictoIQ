import 'package:pictoiq_mobile/core/ml/model_registry.dart';

/// Loads and unloads models so only the ones in use take memory.
abstract interface class ModelManager {
  ModelRegistry get registry;
  Future<void> load(String name);
  Future<void> unload(String name);
}
