import 'package:flutter/material.dart';

import 'presentation/design_system/app_theme.dart';
import 'presentation/design_system/component_gallery.dart';

/// Design review entry point — does not start Firebase.
///
///     flutter run -t lib/design_system_gallery.dart
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Safety Helmet — components',
      theme: buildAppTheme(),
      home: const ComponentGalleryPage(),
    ),
  );
}
