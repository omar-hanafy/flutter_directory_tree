// example/lib/shared/icon_providers.dart
import 'package:flutter/material.dart' show Icon, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// Extends the stock [MaterialIconProvider] to show a trailing indicator for
/// virtual files/folders.
class FancyIconProvider extends MaterialIconProvider {
  const FancyIconProvider();

  @override
  Widget? trailingIcon(BuildContext context, VisibleNode node) {
    if (node.isVirtual) {
      return const Padding(
        padding: EdgeInsetsDirectional.only(start: 8),
        child: Icon(Icons.cloud_queue, size: 14),
      );
    }
    return null;
  }
}
