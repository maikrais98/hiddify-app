import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/nova_tokens.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/platform_utils.dart';

typedef ProxyPickerItemBuilder =
    Widget Function(BuildContext context, OutboundInfo proxy, bool selected, VoidCallback onSelect);

List<OutboundInfo> filterProxies(Iterable<OutboundInfo> proxies, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return List<OutboundInfo>.of(proxies);

  return proxies
      .where((proxy) {
        final fields = <String>[
          proxy.tag,
          proxy.tagDisplay,
          proxy.type,
          proxy.host,
          proxy.groupSelectedTag,
          proxy.groupSelectedTagDisplay,
          proxy.ipinfo.countryCode,
          proxy.ipinfo.region,
          proxy.ipinfo.city,
          proxy.ipinfo.org,
        ];
        return fields.any((field) => field.toLowerCase().contains(normalizedQuery));
      })
      .toList(growable: false);
}

String _proxyLabel(OutboundInfo proxy) {
  final display = proxy.tagDisplay.trim();
  return display.isEmpty ? proxy.tag : display;
}

class ProxyPickerContent extends StatefulWidget {
  const ProxyPickerContent({
    super.key,
    required this.group,
    required this.recentTags,
    required this.searchHint,
    required this.clearLabel,
    required this.selectedLabel,
    required this.recentLabel,
    required this.noResultsTitle,
    required this.noResultsBody,
    required this.onSelect,
    this.isActive = true,
    this.itemBuilder,
  });

  final OutboundGroup group;
  final List<String> recentTags;
  final String searchHint;
  final String clearLabel;
  final String selectedLabel;
  final String recentLabel;
  final String noResultsTitle;
  final String noResultsBody;
  final ValueChanged<OutboundInfo> onSelect;
  final bool isActive;
  final ProxyPickerItemBuilder? itemBuilder;

  @override
  State<ProxyPickerContent> createState() => _ProxyPickerContentState();
}

class _ProxyPickerContentState extends State<ProxyPickerContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProxyPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _searchController.clear();
      _query = '';
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final nova = NovaThemeData.of(context);
    final filtered = filterProxies(widget.group.items, _query);
    final proxiesByTag = {for (final proxy in widget.group.items) proxy.tag: proxy};
    final selectedProxy = proxiesByTag[widget.group.selected];
    final recent = widget.recentTags
        .where((tag) => tag != widget.group.selected)
        .map((tag) => proxiesByTag[tag])
        .whereType<OutboundInfo>()
        .take(3)
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(NovaSpacing.lg, NovaSpacing.md, NovaSpacing.lg, NovaSpacing.sm),
          child: TextField(
            key: const ValueKey('proxy_picker_search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('proxy_picker_search_clear_icon'),
                      tooltip: widget.clearLabel,
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        if (widget.group.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NovaSpacing.lg),
            child: Material(
              key: const ValueKey('proxy_picker_selected'),
              color: nova.accentFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NovaRadii.medium),
                side: BorderSide(color: nova.accent.withValues(alpha: 0.45)),
              ),
              child: Semantics(
                selected: true,
                container: true,
                label:
                    '${widget.selectedLabel}: ${selectedProxy == null ? widget.group.selected : _proxyLabel(selectedProxy)}',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.check_circle_rounded, color: nova.accent),
                  title: Text(widget.selectedLabel, style: TextStyle(color: nova.secondaryText)),
                  subtitle: Text(
                    selectedProxy == null ? widget.group.selected : _proxyLabel(selectedProxy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nova.primaryText, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(NovaSpacing.lg, NovaSpacing.sm, NovaSpacing.lg, 0),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: nova.secondaryText),
                const SizedBox(width: NovaSpacing.sm),
                Text(widget.recentLabel, style: TextStyle(color: nova.secondaryText)),
                const SizedBox(width: NovaSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final proxy in recent) ...[
                          ActionChip(
                            key: ValueKey('proxy_picker_recent_${proxy.tag}'),
                            avatar: const Icon(Icons.replay_rounded, size: 18),
                            label: Text(_proxyLabel(proxy)),
                            onPressed: () => widget.onSelect(proxy),
                          ),
                          const SizedBox(width: NovaSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NovaSpacing.sm),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(NovaSpacing.xl),
                    child: Semantics(
                      liveRegion: true,
                      container: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 40, color: nova.tertiaryText),
                          const SizedBox(height: NovaSpacing.md),
                          Text(
                            widget.noResultsTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: nova.primaryText, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: NovaSpacing.xs),
                          Text(
                            widget.noResultsBody,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: nova.tertiaryText),
                          ),
                          const SizedBox(height: NovaSpacing.md),
                          TextButton.icon(
                            key: const ValueKey('proxy_picker_clear'),
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                            label: Text(widget.clearLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 268).floor());
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 86),
                      itemCount: filtered.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisExtent: 72,
                      ),
                      itemBuilder: (context, index) {
                        final proxy = filtered[index];
                        final selected = widget.group.selected == proxy.tag;
                        return widget.itemBuilder?.call(context, proxy, selected, () => widget.onSelect(proxy)) ??
                            ListTile(
                              title: Text(_proxyLabel(proxy)),
                              selected: selected,
                              onTap: () => widget.onSelect(proxy),
                            );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
