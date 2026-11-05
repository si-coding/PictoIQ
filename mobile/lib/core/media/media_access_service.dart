import 'package:pictoiq_mobile/core/media/media_asset.dart';

/// Lists the albums and items on the device for one kind of media. Photos are
/// served today by the album pages and the folder scanner; videos will plug
/// in here without changing the photo tools.
abstract interface class MediaAccessService {
  Future<List<String>> albumNames(MediaKind kind);
}
