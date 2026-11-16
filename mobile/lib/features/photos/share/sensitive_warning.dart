import 'package:flutter/material.dart';

/// What the person chose in the warning about photos that cannot be shared.
enum SensitiveChoice { review, continueWithout }

/// Tells the person that [blocked] photos will not be shared or put in a reel,
/// and lets them look at those photos or carry on without them. Returns null
/// when the dialog is dismissed or they cancel.
Future<SensitiveChoice?> showSensitiveWarning(
  BuildContext context, {
  required int blocked,
  required int remaining,
  required String action,
}) {
  final photos = blocked == 1 ? '1 photo' : '$blocked photos';
  return showDialog<SensitiveChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: Text('$photos will not be shared'),
      content: Text(
        '${blocked == 1 ? 'It is' : 'They are'} marked private or look '
        'sensitive, so PictoIQ will not $action ${blocked == 1 ? 'it' : 'them'}.\n\n'
        'Review ${blocked == 1 ? 'it' : 'them'} to decide what to do: keep '
        '${blocked == 1 ? 'it' : 'them'} private, or delete '
        '${blocked == 1 ? 'it' : 'them'} from your gallery. If you come '
        'across illegal images, do not pass them on; report them to the '
        'police or your national reporting hotline.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, SensitiveChoice.review),
          child: const Text('Review'),
        ),
        if (remaining > 0)
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, SensitiveChoice.continueWithout),
            child: Text('Continue with $remaining'),
          ),
      ],
    ),
  );
}
