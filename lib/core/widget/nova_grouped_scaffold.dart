import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';

class NovaGroupedScaffold extends StatelessWidget {
  const NovaGroupedScaffold({super.key, this.appBar, this.body, this.floatingActionButton, this.bottomNavigationBar});

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: nova.groupedBackground,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar ?? (bottomInset == 0 ? null : SizedBox(height: bottomInset)),
    );
  }
}
