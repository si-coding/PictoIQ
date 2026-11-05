import 'package:pictoiq_mobile/core/media/media_asset.dart';

/// Whether PictoIQ may read photos or videos. PictoIQ only asks for what the
/// tool in use needs, and never uploads anything.
abstract interface class MediaPermissionsService {
  Future<bool> hasAccess(MediaKind kind);
  Future<bool> request(MediaKind kind);
}
