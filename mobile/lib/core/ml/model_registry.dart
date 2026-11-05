/// The on-device models PictoIQ may use, by name. Photos use ML Kit face
/// detection today; scene and video models would be registered here.
class ModelInfo {
  const ModelInfo({required this.name, required this.version, this.sizeBytes});

  final String name;
  final String version;
  final int? sizeBytes;
}

class ModelRegistry {
  const ModelRegistry(this.models);

  final List<ModelInfo> models;

  ModelInfo? find(String name) {
    for (final model in models) {
      if (model.name == name) return model;
    }
    return null;
  }
}
