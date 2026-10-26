import 'dart:convert';
import 'dart:io';

// Test-only AST guard uses the pinned transitive analyzer; the migration freezes dependencies.
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/analysis/utilities.dart';
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/ast/ast.dart';
// ignore: depend_on_referenced_packages
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseline = '0830294eff5b8cd86324545ed00689648c70bd23';
const _connectionButtonPath = 'lib/features/home/widget/connection_button.dart';
const _settingsPagePath = 'lib/features/settings/overview/settings_page.dart';
const _homePagePath = 'lib/features/home/widget/home_page.dart';
const _activeProxyCardPath = 'lib/features/proxy/active/active_proxy_card.dart';
const _profilesModalPath = 'lib/features/profile/overview/profiles_modal.dart';
const _warpLicenseDialogPath = 'lib/core/router/dialog/widgets/warp_license_dialog.dart';
const _qrScannerPath = 'lib/features/common/qr_code_scanner_screen.dart';
const _introPagePath = 'lib/features/intro/widget/intro_page.dart';
// Existing presentation surfaces explicitly enumerated in the migration plan.
const _files = <String>[
  'lib/core/theme/app_theme.dart',
  'lib/core/theme/theme_extensions.dart',
  'lib/core/router/adaptive_layout/my_adaptive_layout.dart',
  'lib/features/home/widget/home_page.dart',
  'lib/features/home/widget/connection_button.dart',
  'lib/features/profile/widget/profile_tile.dart',
  'lib/features/proxy/widget/proxy_tile.dart',
  'lib/features/proxy/active/active_proxy_card.dart',
  'lib/features/proxy/active/active_proxy_delay_indicator.dart',
  'lib/features/proxy/overview/proxies_overview_page.dart',
  'lib/features/common/qr_code_scanner_screen.dart',
  'lib/features/common/qr_code_dialog.dart',
  'lib/features/settings/widget/preference_tile.dart',
  'lib/features/common/general_pref_tiles.dart',
  'lib/features/profile/add/add_profile_modal.dart',
  'lib/features/profile/add/widgets/fix_btn.dart',
  'lib/features/profile/add/widgets/fix_btns.dart',
  'lib/features/profile/add/widgets/nav_bar.dart',
  'lib/features/profile/overview/profiles_modal.dart',
  'lib/core/router/bottom_sheets/widgets/quick_settings_modal.dart',
  'lib/features/profile/details/profile_details_page.dart',
  'lib/features/profile/details/json_editor.dart',
  'lib/features/log/overview/logs_page.dart',
  'lib/features/about/widget/about_page.dart',
  'lib/features/intro/widget/intro_page.dart',
];
const _directories = <String>['lib/core/router/dialog/widgets/', 'lib/features/settings/overview/'];
const _callbacks = <String>{
  'onTap',
  'onPressed',
  'onLongPress',
  'onChanged',
  'onSelected',
  'onSelectionChanged',
  'onReset',
  'validator',
  'validateInput',
  'inputToValue',
  'initialOnSuccess',
  'initialOnFailure',
};

String _tokens(AstNode node) {
  final result = <String>[];
  var token = node.beginToken;
  while (true) {
    result.add(token.lexeme);
    if (identical(token, node.endToken)) break;
    token = token.next!;
  }
  return jsonEncode(result);
}

String _providerBindingKey(String accessor, String provider) =>
    'state:${jsonEncode(['ref', '.', accessor, '(', provider, ')'])}';

String _warpFocusPredicate(String key) =>
    'conditional:${jsonEncode(['focusStates', '[', 'WarpConst', '.', key, ']', '!', '.', 'value'])}';

String _warpLinkStyleCall(String key) =>
    jsonEncode(['linkStyle', '(', 'focusStates', '[', 'WarpConst', '.', key, ']', '!', '.', 'value', ')']);

const _warpFocusKeys = <String>['warpTermsOfServiceKey', 'warpPrivacyPolicyKey'];

String _introFocusPredicate(String key) =>
    'conditional:${jsonEncode(['focusStates', '[', 'IntroConst', '.', key, ']', '!', '.', 'value'])}';

String _introLinkStyleCall(String key) =>
    jsonEncode(['linkStyle', '(', 'focusStates', '[', 'IntroConst', '.', key, ']', '!', '.', 'value', ')']);

const _introFocusCallCounts = <String, int>{'termsAndConditionsKey': 1, 'githubKey': 2};

class _ApprovedStateAddition {
  const _ApprovedStateAddition({
    required this.path,
    required this.className,
    required this.methodName,
    required this.provider,
  });

  final String path;
  final String className;
  final String methodName;
  final String provider;

  String get expression => 'ref.watch($provider)';
  String get bindingKey => _providerBindingKey('watch', provider);
  String get siteKey => '$className::$methodName::$bindingKey';
}

const _approvedStateAdditions = <_ApprovedStateAddition>[
  _ApprovedStateAddition(
    path: 'lib/features/proxy/overview/proxies_overview_page.dart',
    className: 'ProxiesOverviewPage',
    methodName: 'build',
    provider: 'activeProfileProvider',
  ),
  _ApprovedStateAddition(
    path: 'lib/features/proxy/active/active_proxy_delay_indicator.dart',
    className: 'ActiveProxyDelayIndicator',
    methodName: 'build',
    provider: 'iosActiveProxyMeasurementEnabledProvider',
  ),
  _ApprovedStateAddition(
    path: 'lib/features/proxy/active/active_proxy_card.dart',
    className: 'ActiveProxyFooter',
    methodName: 'build',
    provider: 'iosActiveProxyMeasurementEnabledProvider',
  ),
  _ApprovedStateAddition(
    path: 'lib/features/proxy/active/active_proxy_card.dart',
    className: 'ActiveProxyFooter',
    methodName: 'build',
    provider: 'iosActiveProxyMeasurementStateProvider',
  ),
];

class _Bindings extends GeneralizingAstVisitor<void> {
  _Bindings(this.path);

  final String path;
  final classes = <ClassDeclaration>[];
  final creations = <InstanceCreationExpression>[];
  final invocations = <MethodInvocation>[];
  final namedExpressions = <NamedExpression>[];
  final variables = <VariableDeclaration>[];
  final exact = <String, int>{};
  final stateSites = <String, int>{};
  final predicates = <String, int>{};
  final ifStatements = <IfStatement>[];
  final switchExpressions = <SwitchExpression>[];
  final directStatements = <String, List<String>>{};
  final localInitializers = <String, List<String>>{};
  void add(Map<String, int> into, String kind, AstNode node) {
    final key = '$kind:${_tokens(node)}';
    into.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  void addStateSite(AstNode node) {
    String? className;
    String? methodName;
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is FunctionExpression || current is FunctionDeclaration) return;
      if (methodName == null && current is MethodDeclaration) methodName = current.name.lexeme;
      if (current is ClassDeclaration) {
        className = current.name.lexeme;
        break;
      }
    }
    if (className == null || methodName == null) return;
    final key = '$className::$methodName::state:${_tokens(node)}';
    stateSites.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  String? directMethodSite(AstNode node) {
    final parent = node.parent;
    if (node is! Statement || parent is! Block || parent.parent is! BlockFunctionBody) return null;
    final method = parent.parent!.parent;
    if (method is! MethodDeclaration || method.parent is! ClassDeclaration) return null;
    return '${(method.parent! as ClassDeclaration).name.lexeme}::${method.name.lexeme}';
  }

  String? localVariableSite(VariableDeclaration node) {
    String? methodName;
    String? className;
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is FunctionExpression || current is FunctionDeclaration) return null;
      if (methodName == null && current is MethodDeclaration) methodName = current.name.lexeme;
      if (current is ClassDeclaration) {
        className = current.name.lexeme;
        break;
      }
    }
    if (className == null || methodName == null) return null;
    return '$className::$methodName::${node.name.lexeme}';
  }

  @override
  void visitNode(AstNode node) {
    if (node is ClassDeclaration) classes.add(node);
    if (node is InstanceCreationExpression) creations.add(node);
    if (node is MethodInvocation) invocations.add(node);
    if (node is NamedExpression) namedExpressions.add(node);
    if (node is VariableDeclaration) variables.add(node);
    final directSite = directMethodSite(node);
    if (directSite != null) {
      directStatements.putIfAbsent(directSite, () => <String>[]).add(_tokens(node));
    }
    if (node is VariableDeclaration && node.initializer != null) {
      final variableSite = localVariableSite(node);
      if (variableSite != null) {
        localInitializers.putIfAbsent(variableSite, () => <String>[]).add(_tokens(node.initializer!));
      }
    }
    if (node is NamedExpression && _callbacks.contains(node.name.label.name)) {
      add(exact, node.name.label.name, node.expression);
    }
    if (node is MethodDeclaration && node.name.lexeme == '_onTap') {
      add(exact, '_onTap', node);
    }
    if (node is MethodInvocation) {
      final name = node.methodName.name;
      if (RegExp('^use[A-Z]').hasMatch(name) ||
          (const {'watch', 'read', 'listen', 'listenManual'}.contains(name) &&
              RegExp(r'\bref\b').hasMatch(node.target?.toSource() ?? ''))) {
        add(exact, 'state', node);
        addStateSite(node);
      }
    }
    if (node is FunctionExpressionInvocation && RegExp('^use[A-Z]').hasMatch(node.function.toSource())) {
      add(exact, 'state', node);
    }
    if (node is GuardedPattern) add(exact, 'switch-pattern', node);
    if (node is SwitchCase) add(exact, 'switch-case', node.expression);
    if (node is SwitchExpression) {
      add(exact, 'switch-value', node.expression);
      switchExpressions.add(node);
    }
    if (node is SwitchStatement) add(exact, 'switch-value', node.expression);
    if (node is IfStatement) {
      add(predicates, 'if', node.expression);
      ifStatements.add(node);
    }
    if (node is IfElement) add(predicates, 'if', node.expression);
    if (node is ConditionalExpression) add(predicates, 'conditional', node.condition);
    super.visitNode(node);
  }
}

_Bindings _inventory(String source, String path) {
  final parsed = parseString(content: source, path: path, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) {
    throw StateError('AST parse diagnostics in $path: ${parsed.errors}');
  }
  final inventory = _Bindings(path);
  parsed.unit.accept(inventory);
  return inventory;
}

String _secureLabelPredicate(String accessor) =>
    'if:${jsonEncode(['delay', '<=', '0', '||', 'delay', '>', '65000', '||', 'connectionStatus', '.', accessor, '!=', 'const', 'Connected', '(', ')'])}';

String _recoveryContext(IfStatement node) {
  final parts = [
    _tokens(node.thenStatement),
    if (node.elseStatement == null) 'no-else' else _tokens(node.elseStatement!),
  ];
  AstNode current = node;
  while (current.parent != null) {
    final parent = current.parent!;
    if (parent is ClassDeclaration) {
      parts.add('class:${parent.name.lexeme}');
      break;
    }
    if (parent is MethodDeclaration) parts.add('method:${parent.name.lexeme}');
    parts.add('${parent.runtimeType}:${parent.childEntities.toList().indexOf(current)}');
    current = parent;
  }
  return jsonEncode(parts);
}

bool _sameRecoverySite(_Bindings baseline, _Bindings live) {
  final before = baseline.ifStatements
      .where((node) => 'if:${_tokens(node.expression)}' == _secureLabelPredicate('value'))
      .toList();
  final after = live.ifStatements
      .where((node) => 'if:${_tokens(node.expression)}' == _secureLabelPredicate('valueOrNull'))
      .toList();
  return before.length == 1 && after.length == 1 && _recoveryContext(before.single) == _recoveryContext(after.single);
}

bool _isApprovedStateAddition(_Bindings baseline, _Bindings live, String key) {
  final additions = _approvedStateAdditions.where(
    (addition) => addition.path == live.path && addition.bindingKey == key,
  );
  if (additions.length != 1) return false;
  final addition = additions.single;
  return (baseline.exact[key] ?? 0) == 0 && live.exact[key] == 1 && live.stateSites[addition.siteKey] == 1;
}

String _statementTokens(String source) {
  final parsed = parseString(content: 'class Fixture { void build() { $source } }');
  final inventory = _Bindings('fixture');
  parsed.unit.accept(inventory);
  return inventory.directStatements['Fixture::build']!.single;
}

String _initializerTokens(String source) {
  final parsed = parseString(content: 'class Fixture { void build() { final value = $source; } }');
  final inventory = _Bindings('fixture');
  parsed.unit.accept(inventory);
  return inventory.localInitializers['Fixture::build::value']!.single;
}

String? _singleInitializer(_Bindings bindings, String key) {
  final values = bindings.localInitializers[key];
  return values?.length == 1 ? values!.single : null;
}

const _actionLabelInitializerSource = '''
switch (connectionStatus) {
  AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
  AsyncData(value: Connected()) => t.connection.disconnect,
  AsyncData(value: Disconnected()) || AsyncError() => t.connection.connect,
  AsyncData(value: final status) => status.present(t),
  _ => '',
}
''';

String _actionLabelFixture(String initializer, {bool duplicate = false}) =>
    '''
class ConnectionButton {
  void build() {
    final actionLabel = $initializer;
    ${duplicate ? 'final duplicateActionLabel = $initializer;' : ''}
  }
}
''';

Map<String, int> get _approvedActionLabelBindings =>
    _inventory(_actionLabelFixture(_actionLabelInitializerSource), 'approved-action-label').exact;

bool _isApprovedActionLabelAddition(_Bindings baseline, _Bindings live, String key) {
  if (baseline.path != 'baseline/$_connectionButtonPath' || live.path != _connectionButtonPath) return false;
  if (_singleInitializer(baseline, 'ConnectionButton::build::actionLabel') != null ||
      _singleInitializer(live, 'ConnectionButton::build::actionLabel') !=
          _initializerTokens(_actionLabelInitializerSource)) {
    return false;
  }
  final approvedCount = _approvedActionLabelBindings[key];
  return approvedCount != null && live.exact[key] == (baseline.exact[key] ?? 0) + approvedCount;
}

const _homeProfileSwitchSource = '''
switch (activeProfile) {
  AsyncData(value: final profile?) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 76),
    child: ProfileTile(
      profile: profile,
      isMain: true,
      color: Theme.of(context).colorScheme.surfaceContainer,
    ),
  ),
  _ => const SizedBox.shrink(),
}
''';

String _homeProfileSwitchFixture(String? expression, {bool duplicate = false}) =>
    '''
class HomePage {
  void build() {
    Widget(slivers: blizzard ? [${expression ?? ''}${duplicate ? ', $expression' : ''}] : const []);
  }
}
''';

Map<String, int> get _approvedHomeProfileBindings =>
    _inventory(_homeProfileSwitchFixture(_homeProfileSwitchSource), 'approved-home-profile').exact;

bool _isInBlizzardSliversBranch(SwitchExpression node) {
  String? className;
  String? methodName;
  var inApprovedBranch = false;
  for (AstNode? current = node.parent; current != null; current = current.parent) {
    if (current is ConditionalExpression &&
        _tokens(current.condition) == jsonEncode(['blizzard']) &&
        current.parent is NamedExpression &&
        (current.parent! as NamedExpression).name.label.name == 'slivers' &&
        node.offset >= current.thenExpression.offset &&
        node.end <= current.thenExpression.end) {
      inApprovedBranch = true;
    }
    if (methodName == null && current is MethodDeclaration) methodName = current.name.lexeme;
    if (current is ClassDeclaration) {
      className = current.name.lexeme;
      break;
    }
  }
  return className == 'HomePage' && methodName == 'build' && inApprovedBranch;
}

bool _isApprovedHomeProfileAddition(_Bindings baseline, _Bindings live, String key) {
  if (baseline.path != 'baseline/$_homePagePath' || live.path != _homePagePath) return false;
  final expectedTokens = _initializerTokens(_homeProfileSwitchSource);
  final baselineMatches = baseline.switchExpressions.where((node) => _tokens(node) == expectedTokens).length;
  final liveMatches = live.switchExpressions
      .where((node) => _tokens(node) == expectedTokens && _isInBlizzardSliversBranch(node))
      .length;
  if (baselineMatches != 0 || liveMatches != 1) return false;
  final approvedCount = _approvedHomeProfileBindings[key];
  return approvedCount != null && live.exact[key] == (baseline.exact[key] ?? 0) + approvedCount;
}

const _settingsResetSource = "() async { await ref.read(resetTunnelNotifierProvider.notifier).run(); }";

String _settingsMenuFixture() =>
    '''
class BlizzardSettingsMenu {
  Widget build() {
    final t = ref.watch(translationsProvider).requireValue;
    return ListView(children: [ListTile(onTap: $_settingsResetSource)]);
  }
}
''';

bool _isApprovedSettingsAddition(_Bindings baseline, _Bindings live, String key) {
  if (baseline.path != 'baseline/$_settingsPagePath' || live.path != _settingsPagePath) return false;
  if (baseline.classes.any((node) => node.name.lexeme == 'BlizzardSettingsMenu')) return false;
  final menus = live.classes.where((node) => node.name.lexeme == 'BlizzardSettingsMenu').toList();
  if (menus.length != 1) return false;
  final builds = menus.single.members
      .whereType<MethodDeclaration>()
      .where((node) => node.name.lexeme == 'build')
      .toList();
  if (builds.length != 1 || builds.single.body is! BlockFunctionBody) return false;
  final statements = (builds.single.body as BlockFunctionBody).block.statements;
  if (statements.length != 2 ||
      _tokens(statements.first) != _statementTokens('final t = ref.watch(translationsProvider).requireValue;') ||
      statements.last is! ReturnStatement)
    return false;
  final expected = _inventory(_settingsMenuFixture(), 'expected-settings').exact;
  final actual = _inventory('class Check { ${builds.single.toSource()} }', 'actual-settings').exact;
  if (actual.length != expected.length || expected.keys.any((binding) => actual[binding] != expected[binding]))
    return false;

  // The reset must remain a ListTile callback in the returned widget tree.
  final tiles = live.invocations
      .where(
        (node) =>
            node.methodName.name == 'ListTile' &&
            node.offset >= statements.last.offset &&
            node.end <= statements.last.end,
      )
      .toList();
  final resets = tiles
      .expand((tile) => tile.argumentList.arguments.whereType<NamedExpression>())
      .where(
        (argument) =>
            argument.name.label.name == 'onTap' &&
            _tokens(argument.expression) == _initializerTokens(_settingsResetSource),
      )
      .toList();
  if (resets.length != 1) return false;
  for (AstNode? node = resets.single.parent; node != statements.last; node = node.parent) {
    if (node == null ||
        node is FunctionExpression ||
        node is FunctionDeclaration ||
        node is ConditionalExpression ||
        node is IfElement)
      return false;
  }

  // Exactly one construction, directly selected by the presentation gate in SettingsPage.build.
  final uses = live.creations.where((node) => node.constructorName.type.toSource() == 'BlizzardSettingsMenu').toList();
  if (uses.length != 1 || _tokens(uses.single) != _initializerTokens('const BlizzardSettingsMenu()')) return false;
  final gate = uses.single.parent;
  if (gate is! ConditionalExpression ||
      gate.thenExpression != uses.single ||
      _tokens(gate.condition) != _initializerTokens('BlizzardPresentation.isActive(context)') ||
      gate.elseExpression is! MethodInvocation ||
      (gate.elseExpression as MethodInvocation).methodName.name != 'ListView')
    return false;
  final argument = gate.parent;
  if (argument is! NamedExpression || argument.parent?.parent is! MethodInvocation) return false;
  final owner = argument.parent!.parent! as MethodInvocation;
  final originalBackdrop = argument.name.label.name == 'child' && owner.methodName.name == 'BlizzardBackdrop';
  final scaffoldArgument = owner.parent;
  final fullPageBackdrop = argument.name.label.name == 'body' &&
      owner.methodName.name == 'Scaffold' &&
      scaffoldArgument is NamedExpression &&
      scaffoldArgument.name.label.name == 'child' &&
      scaffoldArgument.parent?.parent is MethodInvocation &&
      (scaffoldArgument.parent!.parent! as MethodInvocation).methodName.name == 'BlizzardBackdrop';
  if (!originalBackdrop && !fullPageBackdrop) return false;
  AstNode? ancestor = argument;
  while (ancestor != null && ancestor is! MethodDeclaration) {
    if (ancestor is FunctionExpression || ancestor is FunctionDeclaration) return false;
    ancestor = ancestor.parent;
  }
  if (ancestor is! MethodDeclaration ||
      ancestor.name.lexeme != 'build' ||
      ancestor.parent is! ClassDeclaration ||
      (ancestor.parent! as ClassDeclaration).name.lexeme != 'SettingsPage')
    return false;
  final count = expected[key];
  return count != null && live.exact[key] == (baseline.exact[key] ?? 0) + count;
}

String get _serverChoiceCallbackKey =>
    'onPressed:${jsonEncode(['(', ')', '=>', 'context', '.', 'goNamed', '(', "'proxies'", ')'])}';

String get _combinedActiveProxyGuard =>
    'if:${jsonEncode(['connectionState', '!=', 'const', 'Connected', '(', ')', '||', 'activeProxy', '==', 'null'])}';

bool _isApprovedServerChoiceFallback(_Bindings baseline, _Bindings live) {
  if (baseline.path != 'baseline/$_activeProxyCardPath' || live.path != _activeProxyCardPath) return false;
  if (baseline.predicates[_combinedActiveProxyGuard] != 1 || (live.predicates[_combinedActiveProxyGuard] ?? 0) != 0) {
    return false;
  }
  if ((baseline.exact[_serverChoiceCallbackKey] ?? 0) != 0 || live.exact[_serverChoiceCallbackKey] != 1) return false;

  final statements = live.directStatements['ActiveProxyFooter::build'];
  if (statements == null) return false;
  final connectedGuard = _statementTokens('''
if (connectionState != const Connected()) {
  return const SizedBox.shrink();
}
''');
  final fallback = _statementTokens('''
if (activeProxy == null) {
  if (!ios) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.all(16),
    child: OutlinedButton.icon(
      onPressed: () => context.goNamed('proxies'),
      icon: const BlizzardSystemSymbol(icon: Icons.public),
      label: Text(t.pages.proxies.title),
    ),
  );
}
''');
  final connectedIndex = statements.indexOf(connectedGuard);
  if (connectedIndex < 0 || statements.where((statement) => statement == connectedGuard).length != 1) return false;
  if (connectedIndex + 1 >= statements.length || statements[connectedIndex + 1] != fallback) return false;
  if (statements.where((statement) => statement == fallback).length != 1) return false;

  return _singleInitializer(live, 'ActiveProxyFooter::build::legacyProxy') ==
          _initializerTokens('ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull))') &&
      _singleInitializer(live, 'ActiveProxyFooter::build::ios') ==
          _initializerTokens(
            'Theme.of(context).platform == TargetPlatform.iOS && ref.watch(iosActiveProxyMeasurementEnabledProvider)',
          ) &&
      _singleInitializer(live, 'ActiveProxyFooter::build::activeProxy') ==
          _initializerTokens(
            'ios ? ref.watch(iosActiveProxyMeasurementStateProvider).asData?.value.proxy : legacyProxy',
          );
}

const _nativeConnectionStateSource = '''
switch (connectionStatus) {
  AsyncData(value: Connected()) => 'connected',
  AsyncData(value: Disconnected()) => 'disconnected',
  AsyncData(value: Connecting()) => 'connecting',
  AsyncData(value: Disconnecting()) => 'disconnecting',
  AsyncError() => 'error',
  _ => 'pending',
}
''';

Map<String, int> get _nativeConnectionControlAddedBindings => _inventory('''
class ConnectionButton {
  void build() {
    Widget(onTap: onTap);
    Widget(onPressed: onTap, connectionState: $_nativeConnectionStateSource);
  }
}
''', 'approved-native-connection-control').exact;

String _callbackKey(String expression) => 'onPressed:${_initializerTokens(expression)}';

bool _isInClassMethod(
  AstNode node, {
  required String className,
  required String methodName,
  bool allowFunctionExpression = false,
}) {
  for (AstNode? current = node.parent; current != null; current = current.parent) {
    if (!allowFunctionExpression && (current is FunctionExpression || current is FunctionDeclaration)) return false;
    if (current is MethodDeclaration) {
      return current.name.lexeme == methodName &&
          current.parent is ClassDeclaration &&
          (current.parent! as ClassDeclaration).name.lexeme == className;
    }
  }
  return false;
}

bool _isDirectFinalLocal(
  _Bindings bindings, {
  required String variableName,
  required String className,
  required String methodName,
  required String? typeName,
}) {
  final matches = bindings.variables
      .where(
        (node) =>
            node.name.lexeme == variableName && _isInClassMethod(node, className: className, methodName: methodName),
      )
      .toList();
  if (matches.length != 1) return false;
  final declaration = matches.single;
  final declarationList = declaration.parent;
  if (declarationList is! VariableDeclarationList ||
      declarationList.variables.length != 1 ||
      declarationList.keyword?.lexeme != 'final' ||
      declarationList.type?.toSource() != typeName) {
    return false;
  }
  final statement = declarationList.parent;
  return statement is VariableDeclarationStatement &&
      statement.parent is Block &&
      statement.parent!.parent is BlockFunctionBody;
}

Expression? _singleConstructorArgument(
  _Bindings bindings, {
  required String constructorName,
  required String argumentName,
  required String className,
  required String methodName,
}) {
  final matches = bindings.namedExpressions.where((node) {
    final invocation = node.parent?.parent;
    return node.name.label.name == argumentName &&
        _callName(invocation) == constructorName &&
        _isInClassMethod(node, className: className, methodName: methodName);
  }).toList();
  return matches.length == 1 ? matches.single.expression : null;
}

String? _callName(AstNode? node) => switch (node) {
  InstanceCreationExpression() => node.constructorName.type.toSource(),
  MethodInvocation() => node.methodName.name,
  _ => null,
};

List<AstNode> _callsNamed(_Bindings bindings, String name) => <AstNode>[
  ...bindings.creations.where((node) => _callName(node) == name),
  ...bindings.invocations.where((node) => _callName(node) == name),
];

int _constructorArgumentSiteCount(
  _Bindings bindings, {
  required String constructorName,
  required String argumentName,
  required String expression,
  required String className,
  required String methodName,
}) => bindings.namedExpressions.where((node) {
  final invocation = node.parent?.parent;
  return node.name.label.name == argumentName &&
      _tokens(node.expression) == _initializerTokens(expression) &&
      _callName(invocation) == constructorName &&
      _isInClassMethod(node, className: className, methodName: methodName);
}).length;

bool _nativeControlUsesApprovedGate(_Bindings live) {
  final controls = _callsNamed(
    live,
    'BlizzardNativeConnectionControl',
  ).where((node) => _isInClassMethod(node, className: 'ConnectionButton', methodName: 'build')).toList();
  if (controls.length != 1) return false;

  final gates = <ConditionalExpression>[];
  AstNode? current = controls.single;
  while (current != null && current is! MethodDeclaration) {
    if (current is FunctionExpression || current is FunctionDeclaration || current is IfElement) return false;
    if (current is ConditionalExpression) gates.add(current);
    current = current.parent;
  }
  if (gates.length != 1) return false;
  final gate = gates.single;
  if (_tokens(gate.condition) != _initializerTokens('nativeConnectionControl') ||
      controls.single.offset < gate.thenExpression.offset ||
      controls.single.end > gate.thenExpression.end ||
      _tokens(gate.elseExpression) != _initializerTokens('button')) {
    return false;
  }
  final declaration = gate.parent;
  if (declaration is! VariableDeclaration || declaration.name.lexeme != 'control') return false;
  return _singleInitializer(live, 'ConnectionButton::build::control') == _tokens(gate) &&
      _isDirectFinalLocal(
        live,
        variableName: 'control',
        className: 'ConnectionButton',
        methodName: 'build',
        typeName: null,
      );
}

bool _hasApprovedNativeConnectionControlTransformation(_Bindings baseline, _Bindings live) {
  if (baseline.path != 'baseline/$_connectionButtonPath' || live.path != _connectionButtonPath) return false;
  if (_singleInitializer(baseline, 'ConnectionButton::build::actionLabel') != null ||
      _singleInitializer(live, 'ConnectionButton::build::actionLabel') !=
          _initializerTokens(_actionLabelInitializerSource)) {
    return false;
  }

  final baselineOnTap = _singleConstructorArgument(
    baseline,
    constructorName: '_ConnectionButton',
    argumentName: 'onTap',
    className: 'ConnectionButton',
    methodName: 'build',
  );
  final baselineEnabled = _singleConstructorArgument(
    baseline,
    constructorName: '_ConnectionButton',
    argumentName: 'enabled',
    className: 'ConnectionButton',
    methodName: 'build',
  );
  if (baselineOnTap == null || baselineEnabled == null) return false;

  if (_singleInitializer(live, 'ConnectionButton::build::onTap') != _tokens(baselineOnTap) ||
      !_isDirectFinalLocal(
        live,
        variableName: 'onTap',
        className: 'ConnectionButton',
        methodName: 'build',
        typeName: 'VoidCallback',
      ) ||
      _singleInitializer(live, 'ConnectionButton::build::enabled') != _tokens(baselineEnabled) ||
      !_isDirectFinalLocal(
        live,
        variableName: 'enabled',
        className: 'ConnectionButton',
        methodName: 'build',
        typeName: null,
      ) ||
      _singleInitializer(live, 'ConnectionButton::build::nativeConnectionControl') !=
          _initializerTokens('blizzard && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS') ||
      !_isDirectFinalLocal(
        live,
        variableName: 'nativeConnectionControl',
        className: 'ConnectionButton',
        methodName: 'build',
        typeName: null,
      )) {
    return false;
  }

  if (_callsNamed(baseline, '_ConnectionButton').length != 1 ||
      _callsNamed(live, '_ConnectionButton').length != 1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: '_ConnectionButton',
            argumentName: 'onTap',
            expression: 'onTap',
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: '_ConnectionButton',
            argumentName: 'enabled',
            expression: 'enabled',
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: 'BlizzardNativeConnectionControl',
            argumentName: 'onPressed',
            expression: 'onTap',
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: 'BlizzardNativeConnectionControl',
            argumentName: 'enabled',
            expression: 'enabled',
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: 'BlizzardNativeConnectionControl',
            argumentName: 'label',
            expression: 'actionLabel',
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      _constructorArgumentSiteCount(
            live,
            constructorName: 'BlizzardNativeConnectionControl',
            argumentName: 'connectionState',
            expression: _nativeConnectionStateSource,
            className: 'ConnectionButton',
            methodName: 'build',
          ) !=
          1 ||
      !_nativeControlUsesApprovedGate(live)) {
    return false;
  }

  final originalCallbackKey = 'onTap:${_tokens(baselineOnTap)}';
  if (baseline.exact[originalCallbackKey] != 1 || (live.exact[originalCallbackKey] ?? 0) != 0) return false;
  for (final entry in _nativeConnectionControlAddedBindings.entries) {
    final actionLabelCount = _approvedActionLabelBindings[entry.key] ?? 0;
    if (live.exact[entry.key] != (baseline.exact[entry.key] ?? 0) + actionLabelCount + entry.value) return false;
  }
  return true;
}

bool _isApprovedNativeConnectionControlTransformation(_Bindings baseline, _Bindings live, String key) {
  if (!_hasApprovedNativeConnectionControlTransformation(baseline, live)) return false;
  final baselineOnTap = _singleConstructorArgument(
    baseline,
    constructorName: '_ConnectionButton',
    argumentName: 'onTap',
    className: 'ConnectionButton',
    methodName: 'build',
  )!;
  final originalCallbackKey = 'onTap:${_tokens(baselineOnTap)}';
  if (key == originalCallbackKey) return true;
  return _nativeConnectionControlAddedBindings.containsKey(key);
}

int _callbackSiteCount(
  _Bindings bindings,
  String expression, {
  required String className,
  required String methodName,
  bool allowFunctionExpression = false,
}) => bindings.namedExpressions
    .where(
      (node) =>
          node.name.label.name == 'onPressed' &&
          _tokens(node.expression) == _initializerTokens(expression) &&
          _isInClassMethod(
            node,
            className: className,
            methodName: methodName,
            allowFunctionExpression: allowFunctionExpression,
          ),
    )
    .length;

bool _isInReturnedToolbarBranch(NamedExpression node, String expectedCondition) {
  String? actualCondition;
  var insideReturnedTree = false;
  for (AstNode? current = node.parent; current != null; current = current.parent) {
    if (current is FunctionExpression || current is FunctionDeclaration) return false;
    if (current is IfElement) {
      final condition = _tokens(current.expression);
      if (condition != _initializerTokens('blizzard') && condition != _initializerTokens('!blizzard')) return false;
      if (node.offset < current.thenElement.offset || node.end > current.thenElement.end) return false;
      if (actualCondition != null) return false;
      actualCondition = condition;
    }
    if (current is ReturnStatement) insideReturnedTree = true;
    if (current is MethodDeclaration) {
      return insideReturnedTree &&
          actualCondition == _initializerTokens(expectedCondition) &&
          current.name.lexeme == 'build' &&
          current.parent is ClassDeclaration &&
          (current.parent! as ClassDeclaration).name.lexeme == '_ProfilesSheetContent';
    }
  }
  return false;
}

int _returnedToolbarCallbackCount(_Bindings bindings, String expression, String condition) => bindings.namedExpressions
    .where(
      (node) =>
          node.name.label.name == 'onPressed' &&
          _tokens(node.expression) == _initializerTokens(expression) &&
          _isInReturnedToolbarBranch(node, condition),
    )
    .length;

bool _isApprovedProfilesToolbarTransformation(_Bindings baseline, _Bindings live, String key) {
  if (baseline.path != 'baseline/$_profilesModalPath' || live.path != _profilesModalPath) return false;

  const sortLambda = '() => ref.read(dialogNotifierProvider.notifier).showSortProfiles()';
  const updateLambda = '() => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger()';
  const sortCallback = 'showSortProfiles';
  const updateCallback = 'updateSubscriptions';
  final changedKeys = {
    _callbackKey(sortLambda),
    _callbackKey(updateLambda),
    _callbackKey(sortCallback),
    _callbackKey(updateCallback),
  };
  if (!changedKeys.contains(key)) return false;

  if (_callbackSiteCount(
            baseline,
            sortLambda,
            className: 'ProfilesModal',
            methodName: 'build',
            allowFunctionExpression: true,
          ) !=
          1 ||
      _callbackSiteCount(
            baseline,
            updateLambda,
            className: 'ProfilesModal',
            methodName: 'build',
            allowFunctionExpression: true,
          ) !=
          1 ||
      _returnedToolbarCallbackCount(live, sortCallback, 'blizzard') != 1 ||
      _returnedToolbarCallbackCount(live, sortCallback, '!blizzard') != 1 ||
      _returnedToolbarCallbackCount(live, updateCallback, 'blizzard') != 1 ||
      _returnedToolbarCallbackCount(live, updateCallback, '!blizzard') != 1) {
    return false;
  }

  final statements = live.directStatements['_ProfilesSheetContent::build'];
  if (statements == null) return false;
  final sortDeclaration = _statementTokens(
    'void showSortProfiles() => ref.read(dialogNotifierProvider.notifier).showSortProfiles();',
  );
  final updateDeclaration = _statementTokens(
    'void updateSubscriptions() => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();',
  );
  if (statements.where((statement) => statement == sortDeclaration).length != 1 ||
      statements.where((statement) => statement == updateDeclaration).length != 1) {
    return false;
  }

  return baseline.exact[_callbackKey(sortLambda)] == 1 &&
      baseline.exact[_callbackKey(updateLambda)] == 1 &&
      (baseline.exact[_callbackKey(sortCallback)] ?? 0) == 0 &&
      (baseline.exact[_callbackKey(updateCallback)] ?? 0) == 0 &&
      (live.exact[_callbackKey(sortLambda)] ?? 0) == 0 &&
      (live.exact[_callbackKey(updateLambda)] ?? 0) == 0 &&
      live.exact[_callbackKey(sortCallback)] == 2 &&
      live.exact[_callbackKey(updateCallback)] == 2;
}

bool _isInQrScannerBranch(NamedExpression node, {required bool thenBranch}) {
  var matchedBranch = false;
  for (AstNode? current = node.parent; current != null; current = current.parent) {
    if (current is ConditionalExpression && _tokens(current.condition) == _initializerTokens('blizzard')) {
      final branch = thenBranch ? current.thenExpression : current.elseExpression;
      if (node.offset < branch.offset || node.end > branch.end || matchedBranch) return false;
      matchedBranch = true;
    }
    if (current is MethodDeclaration) {
      return matchedBranch &&
          current.name.lexeme == 'build' &&
          current.parent is ClassDeclaration &&
          (current.parent! as ClassDeclaration).name.lexeme == 'QrCodeScannerDialog';
    }
  }
  return false;
}

bool _isApprovedQrScannerCloseTransformation(_Bindings baseline, _Bindings live, String key) {
  const callback = '() => context.pop()';
  final callbackKey = _callbackKey(callback);
  if (key != callbackKey ||
      baseline.path != 'baseline/$_qrScannerPath' ||
      live.path != _qrScannerPath ||
      baseline.exact[callbackKey] != 1 ||
      live.exact[callbackKey] != 2 ||
      _callbackSiteCount(
            baseline,
            callback,
            className: 'QrCodeScannerDialog',
            methodName: 'build',
            allowFunctionExpression: true,
          ) !=
          1) {
    return false;
  }
  final callbacks = live.namedExpressions.where(
    (node) => node.name.label.name == 'onPressed' && _tokens(node.expression) == _initializerTokens(callback),
  );
  return callbacks.where((node) => _isInQrScannerBranch(node, thenBranch: true)).length == 1 &&
      callbacks.where((node) => _isInQrScannerBranch(node, thenBranch: false)).length == 1;
}

List<String> _differences(_Bindings baseline, _Bindings live) {
  final issues = <String>[];
  final approvedServerChoiceFallback = _isApprovedServerChoiceFallback(baseline, live);
  final approvedWarpFocusStyling = _isApprovedWarpFocusStyling(baseline, live);
  final approvedIntroFocusStyling = _isApprovedIntroFocusStyling(baseline, live);
  for (final key in {...baseline.exact.keys, ...live.exact.keys}) {
    if (baseline.exact[key] != live.exact[key] &&
        !_isApprovedStateAddition(baseline, live, key) &&
        !_isApprovedActionLabelAddition(baseline, live, key) &&
        !_isApprovedHomeProfileAddition(baseline, live, key) &&
        !_isApprovedSettingsAddition(baseline, live, key) &&
        !_isApprovedProfilesToolbarTransformation(baseline, live, key) &&
        !_isApprovedQrScannerCloseTransformation(baseline, live, key) &&
        !_isApprovedNativeConnectionControlTransformation(baseline, live, key) &&
        !(approvedServerChoiceFallback && key == _serverChoiceCallbackKey)) {
      issues.add('binding multiplicity changed: $key');
    }
  }
  // Added appearance predicates are allowed; only the approved recovery getter may replace an existing condition.
  for (final key in baseline.predicates.keys) {
    if (approvedServerChoiceFallback && key == _combinedActiveProxyGuard) continue;
    if (approvedWarpFocusStyling && _warpFocusKeys.any((focusKey) => key == _warpFocusPredicate(focusKey))) {
      continue;
    }
    if (approvedIntroFocusStyling &&
        _introFocusCallCounts.keys.any((focusKey) => key == _introFocusPredicate(focusKey))) {
      continue;
    }
    if (baseline.path == 'baseline/$_connectionButtonPath' &&
        live.path == _connectionButtonPath &&
        key == _secureLabelPredicate('value')) {
      if (baseline.predicates[key] != 1 ||
          (live.predicates[key] ?? 0) != 0 ||
          live.predicates[_secureLabelPredicate('valueOrNull')] != 1 ||
          !_sameRecoverySite(baseline, live)) {
        issues.add('approved connection-button recovery predicate changed: $key');
      }
      continue;
    }
    if ((live.predicates[key] ?? 0) < baseline.predicates[key]!) {
      issues.add('existing predicate removed or changed: $key');
    }
  }
  return issues;
}

bool _isApprovedWarpFocusStyling(_Bindings baseline, _Bindings live) {
  if (baseline.path != 'baseline/$_warpLicenseDialogPath' || live.path != _warpLicenseDialogPath) return false;
  if (live.predicates['conditional:${jsonEncode(['focused'])}'] != 1) return false;
  for (final key in _warpFocusKeys) {
    final predicate = _warpFocusPredicate(key);
    if (baseline.predicates[predicate] != 1 || (live.predicates[predicate] ?? 0) != 0) return false;
    if (live.invocations.where((invocation) => _tokens(invocation) == _warpLinkStyleCall(key)).length != 1) {
      return false;
    }
  }
  return true;
}

bool _isApprovedIntroFocusStyling(_Bindings baseline, _Bindings live) {
  if (baseline.path != 'baseline/$_introPagePath' || live.path != _introPagePath) return false;
  if (live.predicates['conditional:${jsonEncode(['focused'])}'] != 1) return false;
  for (final entry in _introFocusCallCounts.entries) {
    final predicate = _introFocusPredicate(entry.key);
    if (baseline.predicates[predicate] != entry.value || (live.predicates[predicate] ?? 0) != 0) return false;
    if (live.invocations.where((invocation) => _tokens(invocation) == _introLinkStyleCall(entry.key)).length !=
        entry.value) {
      return false;
    }
  }
  return true;
}

void main() {
  group('approved Intro focus styling extraction', () {
    final baseline = Process.runSync('git', ['show', '$_baseline:$_introPagePath']).stdout as String;
    final live = File(_introPagePath).readAsStringSync();

    test('accepts the exact shared helper with every original focus value', () {
      expect(_differences(_inventory(baseline, 'baseline/$_introPagePath'), _inventory(live, _introPagePath)), isEmpty);
    });

    for (final mutation in <String, String Function(String)>{
      'wrong focus value': (source) =>
          source.replaceFirst('linkStyle(focusStates[IntroConst.termsAndConditionsKey]!.value)', 'linkStyle(false)'),
      'changed helper predicate': (source) =>
          source.replaceFirst('focused ? Colors.green : Colors.blue', 'false ? Colors.green : Colors.blue'),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(
            _inventory(baseline, 'baseline/$_introPagePath'),
            _inventory(mutation.value(live), _introPagePath),
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('approved QR scanner close-control branches', () {
    final baseline = Process.runSync('git', ['show', '$_baseline:$_qrScannerPath']).stdout as String;
    final live = File(_qrScannerPath).readAsStringSync();

    test('accepts the same close callback once in each exclusive visual branch', () {
      expect(_differences(_inventory(baseline, 'baseline/$_qrScannerPath'), _inventory(live, _qrScannerPath)), isEmpty);
    });

    for (final mutation in <String, String Function(String)>{
      'changed callback': (source) =>
          source.replaceFirst('onPressed: () => context.pop()', 'onPressed: () => context.pop(false)'),
      'ungated branches': (source) => source.replaceFirst('child: blizzard\n', 'child: true\n'),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(
            _inventory(baseline, 'baseline/$_qrScannerPath'),
            _inventory(mutation.value(live), _qrScannerPath),
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('approved WARP focus styling extraction', () {
    final baseline = Process.runSync('git', ['show', '$_baseline:$_warpLicenseDialogPath']).stdout as String;
    final live = File(_warpLicenseDialogPath).readAsStringSync();

    test('accepts the exact shared helper with both original focus values', () {
      expect(
        _differences(
          _inventory(baseline, 'baseline/$_warpLicenseDialogPath'),
          _inventory(live, _warpLicenseDialogPath),
        ),
        isEmpty,
      );
    });

    for (final mutation in <String, String Function(String)>{
      'wrong focus value': (source) =>
          source.replaceFirst('linkStyle(focusStates[WarpConst.warpTermsOfServiceKey]!.value)', 'linkStyle(false)'),
      'changed helper predicate': (source) =>
          source.replaceFirst('focused ? Colors.green : Colors.blue', 'false ? Colors.green : Colors.blue'),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(
            _inventory(baseline, 'baseline/$_warpLicenseDialogPath'),
            _inventory(mutation.value(live), _warpLicenseDialogPath),
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('approved server-header profile name read', () {
    const path = 'lib/features/proxy/overview/proxies_overview_page.dart';
    const baseline = 'class ProxiesOverviewPage { void build() {} }';
    const live = '''
class ProxiesOverviewPage {
  void build() {
    final profileName = ref.watch(activeProfileProvider).valueOrNull?.name;
    Text(profileName);
  }
}
''';
    test('accepts one exact additive watch at the server header build site', () {
      expect(_differences(_inventory(baseline, 'baseline/$path'), _inventory(live, path)), isEmpty);
    });
    for (final mutation in <String, String Function(String)>{
      'wrong provider': (source) => source.replaceFirst('activeProfileProvider', 'otherProvider'),
      'wrong method': (source) => source.replaceFirst('void build()', 'void other()'),
      'wrong class': (source) => source.replaceFirst('class ProxiesOverviewPage', 'class OtherPage'),
      'duplicate read': (source) =>
          source.replaceFirst('Text(profileName);', 'ref.watch(activeProfileProvider); Text(profileName);'),
      'moved into closure': (source) => source.replaceFirst(
        'final profileName = ref.watch(activeProfileProvider).valueOrNull?.name;',
        'final profileName = () => ref.watch(activeProfileProvider).valueOrNull?.name;',
      ),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(_inventory(baseline, 'baseline/$path'), _inventory(mutation.value(live), path)),
          isNotEmpty,
        );
      });
    }
  });
  group('Home header actions retain shipped callback bindings', () {
    const source = '''
class HomePage {
  Widget build() => AppBar(actions: [
    IconButton(onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings()),
    IconButton(onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile()),
  ]);
}
''';
    test('accepts the unchanged Flutter action callbacks', () {
      expect(_differences(_inventory(source, 'baseline/$_homePagePath'), _inventory(source, _homePagePath)), isEmpty);
    });
    for (final mutation in <String, String Function(String)>{
      'wrong action': (s) => s.replaceFirst('showQuickSettings()', 'showAddProfile()'),
      'wrong provider': (s) => s.replaceFirst('bottomSheetsNotifierProvider', 'otherProvider'),
      'missing callback': (s) =>
          s.replaceFirst('() => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings()', 'null'),
      'tearoff substitution': (s) => s.replaceFirst(
        '() => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings()',
        'showQuickSettings',
      ),
    }.entries) {
      test('rejects ${mutation.key}', () {
        final changed = mutation.value(source);
        expect(changed, isNot(source));
        expect(
          _differences(_inventory(source, 'baseline/$_homePagePath'), _inventory(changed, _homePagePath)),
          isNotEmpty,
        );
      });
    }
  });

  group('approved Profiles toolbar callback forwarding', () {
    const baseline = '''
class ProfilesModal {
  void build() {
    Widget(onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles());
    Widget(onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger());
  }
}
''';
    const live = '''
class _ProfilesSheetContent {
  void build() {
    void showSortProfiles() => ref.read(dialogNotifierProvider.notifier).showSortProfiles();
    void updateSubscriptions() => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
    return Widget(children: [
      if (blizzard) Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),
      if (!blizzard) Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),
    ]);
  }
}
''';

    test('accepts one provider call and two forwarding sites per action', () {
      expect(
        _differences(_inventory(baseline, 'baseline/$_profilesModalPath'), _inventory(live, _profilesModalPath)),
        isEmpty,
      );
    });

    for (final mutation in <String, String Function(String)>{
      'dropped forwarding site': (source) => source.replaceFirst('Widget(onPressed: showSortProfiles),', ''),
      'duplicated forwarding site': (source) => source.replaceFirst(
        'Widget(onPressed: showSortProfiles),',
        'Widget(onPressed: showSortProfiles), Widget(onPressed: showSortProfiles),',
      ),
      'renamed callback': (source) => source.replaceFirst('void showSortProfiles()', 'void renamedSortProfiles()'),
      'unused callback': (source) => source.replaceAll('onPressed: updateSubscriptions', 'onPressed: null'),
      'both actions on the Blizzard branch': (source) => source.replaceFirst('if (!blizzard)', 'if (blizzard)'),
      'both branches unconditional': (source) => source.replaceAll(RegExp(r'if \(!?blizzard\) '), ''),
      'legacy actions unreachable': (source) => source.replaceFirst('if (!blizzard)', 'if (false)'),
      'legacy actions nested under false': (source) => source.replaceFirst(
        '''if (!blizzard) Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),''',
        '''if (!blizzard) Widget(children: [
        if (false) Widget(children: [
          Widget(onPressed: showSortProfiles),
          Widget(onPressed: updateSubscriptions),
        ]),
      ]),''',
      ),
      'legacy actions in the opposite else branch': (source) => source.replaceFirst(
        '''if (!blizzard) Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),''',
        '''if (!blizzard) Widget() else Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),''',
      ),
      'unattached widget expressions': (source) => source
          .replaceFirst('return Widget(children: [', '''Widget(onPressed: showSortProfiles);
    Widget(onPressed: updateSubscriptions);
    return Widget(children: [''')
          .replaceFirst('''if (!blizzard) Widget(children: [
        Widget(onPressed: showSortProfiles),
        Widget(onPressed: updateSubscriptions),
      ]),''', ''),
      'duplicated provider call': (source) => source.replaceFirst(
        'void showSortProfiles() => ref.read(dialogNotifierProvider.notifier).showSortProfiles();',
        '''
        void showSortProfiles() {
          ref.read(dialogNotifierProvider.notifier).showSortProfiles();
          ref.read(dialogNotifierProvider.notifier).showSortProfiles();
        }''',
      ),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(
            _inventory(baseline, 'baseline/$_profilesModalPath'),
            _inventory(mutation.value(live), _profilesModalPath),
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('approved Blizzard settings presentation', () {
    const baseline = 'class SettingsPage { Widget build() { return ListView(); } }';
    final live =
        '''
class SettingsPage {
 Widget build() { return BlizzardBackdrop(child: BlizzardPresentation.isActive(context) ? const BlizzardSettingsMenu() : ListView()); }
}
${_settingsMenuFixture()}
''';
    test('accepts exact reset and translation bindings only in the gated menu', () {
      expect(
        _differences(_inventory(baseline, 'baseline/$_settingsPagePath'), _inventory(live, _settingsPagePath)),
        isEmpty,
      );
    });
    test('accepts the same gated menu under a full-page backdrop without changing bindings', () {
      final fullPage = live.replaceFirst(
        'BlizzardBackdrop(child: BlizzardPresentation.isActive(context) ? const BlizzardSettingsMenu() : ListView())',
        'BlizzardBackdrop(child: Scaffold(body: BlizzardPresentation.isActive(context) ? const BlizzardSettingsMenu() : ListView()))',
      );
      expect(_differences(_inventory(baseline, 'baseline/$_settingsPagePath'), _inventory(fullPage, _settingsPagePath)), isEmpty);
      final wrongOwner = fullPage.replaceFirst('BlizzardBackdrop(child: Scaffold', 'OtherBackdrop(child: Scaffold');
      expect(_differences(_inventory(baseline, 'baseline/$_settingsPagePath'), _inventory(wrongOwner, _settingsPagePath)), isNotEmpty);
    });
    for (final mutation in <String, String Function(String)>{
      'wrong provider': (s) => s.replaceFirst('resetTunnelNotifierProvider', 'otherProvider'),
      'wrong action': (s) => s.replaceFirst('.run()', '.reset()'),
      'duplicate callback': (s) =>
          s.replaceFirst('ListTile(onTap:', 'ListTile(onLongPress: $_settingsResetSource, onTap:'),
      'duplicate watch': (s) =>
          s.replaceFirst('return ListView(children:', 'ref.watch(translationsProvider); return ListView(children:'),
      'moved method': (s) => s.replaceFirst('Widget build() {\n    final t', 'Widget other() {\n    final t'),
      'ungated branch': (s) => s.replaceFirst('BlizzardPresentation.isActive(context)', 'true'),
      'reversed gate': (s) =>
          s.replaceFirst('BlizzardPresentation.isActive(context)', '!BlizzardPresentation.isActive(context)'),
      'wrong page': (s) => s.replaceFirst('class SettingsPage', 'class OtherPage'),
      'duplicate menu use': (s) => s.replaceFirst(': ListView()', ': const BlizzardSettingsMenu()'),
      'reset moved into closure': (s) => s.replaceFirst(
        'ListView(children: [ListTile(onTap: $_settingsResetSource)])',
        'Builder(builder: () => ListTile(onTap: $_settingsResetSource))',
      ),
    }.entries) {
      test('rejects ${mutation.key}', () {
        expect(
          _differences(
            _inventory(baseline, 'baseline/$_settingsPagePath'),
            _inventory(mutation.value(live), _settingsPagePath),
          ),
          isNotEmpty,
        );
      });
    }
  });

  test('all allowed presentation files preserve shipped state/action bindings', () {
    final listed = Process.runSync('git', ['ls-tree', '-r', '--name-only', _baseline, 'lib']);
    expect(listed.exitCode, 0, reason: '${listed.stderr}');
    final paths =
        (listed.stdout as String)
            .split('\n')
            .where((path) => path.endsWith('.dart') && (_files.contains(path) || _directories.any(path.startsWith)))
            .toList()
          ..sort();
    expect(
      paths.toSet().containsAll(_files),
      isTrue,
      reason: 'Every explicitly listed file must exist in shipped source.',
    );
    var count = 0;
    final receipts = <String>[];
    for (final path in paths) {
      final original = Process.runSync('git', ['show', '$_baseline:$path']);
      expect(original.exitCode, 0, reason: path);
      expect(File(path).existsSync(), isTrue, reason: 'Missing presentation file $path');
      final baseline = _inventory(original.stdout as String, 'baseline/$path');
      final live = _inventory(File(path).readAsStringSync(), path);
      expect(_differences(baseline, live), isEmpty, reason: path);
      final bindings = baseline.exact.values.fold<int>(0, (a, b) => a + b);
      count += bindings;
      receipts.add('$path: $bindings bindings, ${baseline.predicates.values.fold<int>(0, (a, b) => a + b)} predicates');
    }
    // Future pure presentation files must not introduce provider state or hooks.
    for (final path in ['lib/core/theme/blizzard_tokens.dart', 'lib/core/theme/blizzard_theme.dart']) {
      if (!File(path).existsSync()) continue;
      final inventory = _inventory(File(path).readAsStringSync(), path);
      expect(inventory.exact.keys.where((key) => key.startsWith('state:')), isEmpty, reason: path);
    }
    for (final directory in ['lib/core/widget/blizzard']) {
      if (!Directory(directory).existsSync()) continue;
      for (final file in Directory(
        directory,
      ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final inventory = _inventory(file.readAsStringSync(), file.path);
        expect(inventory.exact.keys.where((key) => key.startsWith('state:')), isEmpty, reason: file.path);
      }
    }
    stdout.writeln(
      'SHIPPED BINDING RECEIPT $_baseline: ${paths.length} files, $count exact bindings\n${receipts.join('\n')}',
    );
  });

  test('guard rejects a callback mutation in an actual shipped profile tile copy', () {
    const path = 'lib/features/profile/widget/profile_tile.dart';
    final original = Process.runSync('git', ['show', '$_baseline:$path']);
    expect(original.exitCode, 0);
    final source = original.stdout as String;
    final finder = _CallbackFinder();
    parseString(content: source).unit.accept(finder);
    expect(finder.expression, isNotNull);
    final callback = finder.expression!;
    final mutated = source.replaceRange(callback.offset, callback.end, 'null');
    expect(_differences(_inventory(source, path), _inventory(mutated, 'disposable/$path')), isNotEmpty);
  });

  group('approved connection-button error recovery', () {
    const path = 'lib/features/home/widget/connection_button.dart';
    const predicate = 'delay <= 0 || delay > 65000 || connectionStatus.value != const Connected()';
    late String source;

    setUp(() {
      final original = Process.runSync('git', ['show', '$_baseline:$path']);
      expect(original.exitCode, 0);
      source = original.stdout as String;
      expect(predicate.allMatches(source).length, 1);
    });

    test('guard accepts only the approved null-safe predicate', () {
      final corrected = source.replaceFirst(predicate, predicate.replaceFirst('.value ', '.valueOrNull '));
      expect(_differences(_inventory(source, 'baseline/$path'), _inventory(corrected, path)), isEmpty);
    });

    for (final mutation in <String, String>{
      'unsafe error getter': predicate,
      'changed latency boundary': predicate.replaceFirst('.value ', '.valueOrNull ').replaceFirst('65000', '64999'),
    }.entries) {
      test('guard rejects ${mutation.key} after approving recovery', () {
        final mutated = source.replaceFirst(predicate, mutation.value);
        expect(_differences(_inventory(source, 'baseline/$path'), _inventory(mutated, path)), isNotEmpty);
      });
    }

    test('guard does not allow the recovery substitution in another file', () {
      const otherPath = 'lib/features/proxy/widget/proxy_tile.dart';
      final corrected = source.replaceFirst(predicate, predicate.replaceFirst('.value ', '.valueOrNull '));
      expect(_differences(_inventory(source, 'baseline/$otherPath'), _inventory(corrected, otherPath)), isNotEmpty);
    });

    test('guard rejects a duplicated approved predicate', () {
      final correctedPredicate = predicate.replaceFirst('.value ', '.valueOrNull ');
      final duplicated = source.replaceFirst(
        predicate,
        '$correctedPredicate) { secureLabel = ""; } if ($correctedPredicate',
      );
      expect(_differences(_inventory(source, 'baseline/$path'), _inventory(duplicated, path)), isNotEmpty);
    });

    test('guard rejects relocating the approved predicate within the same file', () {
      final correctedPredicate = predicate.replaceFirst('.value ', '.valueOrNull ');
      final relocated = source
          .replaceFirst(predicate, 'true')
          .replaceFirst(
            'return _ConnectionButton(',
            'if ($correctedPredicate) { secureLabel = ""; } return _ConnectionButton(',
          );
      expect(_differences(_inventory(source, 'baseline/$path'), _inventory(relocated, path)), isNotEmpty);
    });

    test('guard rejects changing the approved recovery body', () {
      final changedBody = source
          .replaceFirst(predicate, predicate.replaceFirst('.value ', '.valueOrNull '))
          .replaceFirst('secureLabel = "";', 'secureLabel = "unexpected";');
      expect(_differences(_inventory(source, 'baseline/$path'), _inventory(changedBody, path)), isNotEmpty);
    });
  });

  group('approved connection-button action label', () {
    const baseline = 'class ConnectionButton { void build() {} }';

    test('guard accepts only the exact presentation mapping at the approved site', () {
      final live = _actionLabelFixture(_actionLabelInitializerSource);
      expect(
        _differences(_inventory(baseline, 'baseline/$_connectionButtonPath'), _inventory(live, _connectionButtonPath)),
        isEmpty,
      );
    });

    test('guard rejects changing the connected action mapping', () {
      final changed = _actionLabelInitializerSource.replaceFirst('t.connection.disconnect', 't.connection.connect');
      expect(
        _differences(
          _inventory(baseline, 'baseline/$_connectionButtonPath'),
          _inventory(_actionLabelFixture(changed), _connectionButtonPath),
        ),
        isNotEmpty,
      );
    });

    test('guard rejects duplicating the approved switch', () {
      expect(
        _differences(
          _inventory(baseline, 'baseline/$_connectionButtonPath'),
          _inventory(_actionLabelFixture(_actionLabelInitializerSource, duplicate: true), _connectionButtonPath),
        ),
        isNotEmpty,
      );
    });

    test('guard rejects the exact mapping in another file', () {
      const otherPath = 'lib/features/proxy/widget/proxy_tile.dart';
      expect(
        _differences(
          _inventory(baseline, 'baseline/$otherPath'),
          _inventory(_actionLabelFixture(_actionLabelInitializerSource), otherPath),
        ),
        isNotEmpty,
      );
    });
  });

  group('approved Blizzard home profile presentation', () {
    final baseline = _homeProfileSwitchFixture(null);

    test('guard accepts only the exact profile switch in the Blizzard slivers branch', () {
      final live = _homeProfileSwitchFixture(_homeProfileSwitchSource);
      expect(_differences(_inventory(baseline, 'baseline/$_homePagePath'), _inventory(live, _homePagePath)), isEmpty);
    });

    test('guard rejects changing the empty-profile presentation', () {
      final changed = _homeProfileSwitchSource.replaceFirst('const SizedBox.shrink()', "const Text('')");
      expect(
        _differences(
          _inventory(baseline, 'baseline/$_homePagePath'),
          _inventory(_homeProfileSwitchFixture(changed), _homePagePath),
        ),
        isNotEmpty,
      );
    });

    test('guard rejects duplicating the approved profile switch', () {
      expect(
        _differences(
          _inventory(baseline, 'baseline/$_homePagePath'),
          _inventory(_homeProfileSwitchFixture(_homeProfileSwitchSource, duplicate: true), _homePagePath),
        ),
        isNotEmpty,
      );
    });

    test('guard rejects the exact profile switch in another file', () {
      const otherPath = 'lib/features/profile/widget/profile_tile.dart';
      expect(
        _differences(
          _inventory(baseline, 'baseline/$otherPath'),
          _inventory(_homeProfileSwitchFixture(_homeProfileSwitchSource), otherPath),
        ),
        isNotEmpty,
      );
    });
  });

  group('approved iOS active-proxy provider watches', () {
    String fixture(
      _ApprovedStateAddition addition,
      List<String> expressions, {
      String? className,
      String? methodName,
    }) =>
        '''
class ${className ?? addition.className} {
  void ${methodName ?? addition.methodName}(dynamic ref) {
    ${expressions.map((expression) => '$expression;').join('\n    ')}
  }
}
''';

    test('guard accepts each exact additive watch once at its approved site', () {
      for (final addition in _approvedStateAdditions) {
        final baseline = fixture(addition, const []);
        final live = fixture(addition, [addition.expression]);
        expect(
          _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
          isEmpty,
          reason: addition.expression,
        );
      }
    });

    test('guard rejects a duplicate approved watch', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, [addition.expression, addition.expression]);
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the wrong provider', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, const ['ref.watch(unapprovedProvider)']);
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects read instead of watch', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, ['ref.read(${addition.provider})']);
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the approved watch in the wrong class', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, [addition.expression], className: 'OtherPresentation');
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the approved watch in the wrong method', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, [addition.expression], methodName: 'other');
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the approved watch inside an unused closure', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, ['final unused = () { ${addition.expression}; }']);
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the approved watch inside an unused local function', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, ['void unused() { ${addition.expression}; }']);
      expect(
        _differences(_inventory(baseline, 'baseline/${addition.path}'), _inventory(live, addition.path)),
        isNotEmpty,
      );
    });

    test('guard rejects the approved watch in the wrong file', () {
      final addition = _approvedStateAdditions.first;
      final baseline = fixture(addition, const []);
      final live = fixture(addition, [addition.expression]);
      const wrongPath = 'lib/features/proxy/widget/proxy_tile.dart';
      expect(_differences(_inventory(baseline, 'baseline/$wrongPath'), _inventory(live, wrongPath)), isNotEmpty);
    });
  });

  group('approved native connection-control delegation', () {
    const path = 'lib/features/home/widget/connection_button.dart';
    late String baseline;
    late String live;

    setUp(() {
      final original = Process.runSync('git', ['show', '$_baseline:$path']);
      expect(original.exitCode, 0);
      baseline = original.stdout as String;
      live = File(path).readAsStringSync();
    });

    test('guard accepts only the exact iOS Blizzard native delegation', () {
      expect(_differences(_inventory(baseline, 'baseline/$path'), _inventory(live, path)), isEmpty);
    });

    for (final mutation in <String, String Function(String)>{
      'changed local callback': (source) => source.replaceFirst(
        '\n          return await ref.read(connectionNotifierProvider.notifier).toggleConnection();',
        '\n          return await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);',
      ),
      'wrong fallback callback': (source) => source.replaceFirst('onTap: onTap,', 'onTap: () {},'),
      'wrong native callback': (source) => source.replaceFirst('onPressed: onTap,', 'onPressed: () {},'),
      'duplicated native callback': (source) =>
          source.replaceFirst('onPressed: onTap,', 'onPressed: onTap, onPressed: onTap,'),
      'non-Blizzard native leakage': (source) => source.replaceFirst(
        'blizzard && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS',
        '!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS',
      ),
      'reversed native gate': (source) =>
          source.replaceFirst('final control = nativeConnectionControl', 'final control = !nativeConnectionControl'),
      'moved callback into closure': (source) => source
          .replaceFirst(
            'final VoidCallback onTap = switch (connectionStatus)',
            'final VoidCallback onTap = () { final callback = switch (connectionStatus)',
          )
          .replaceFirst(
            '    final enabled = switch (connectionStatus)',
            '      ; callback(); };\n    final enabled = switch (connectionStatus)',
          ),
      'changed enabled mapping': (source) => source.replaceFirst(
        '\n      AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,',
        '\n      AsyncData(value: Connected()) || AsyncData(value: Disconnected()) => true,',
      ),
      'changed native state mapping': (source) => source.replaceFirst(
        "AsyncData(value: Connected()) => 'connected',",
        "AsyncData(value: Connected()) => 'disconnected',",
      ),
    }.entries) {
      test('guard rejects ${mutation.key}', () {
        final mutated = mutation.value(live);
        expect(mutated, isNot(live), reason: 'Mutation fixture must alter the production source.');
        expect(_differences(_inventory(baseline, 'baseline/$path'), _inventory(mutated, path)), isNotEmpty);
      });
    }
  });

  group('approved iOS server-choice fallback', () {
    const path = 'lib/features/proxy/active/active_proxy_card.dart';
    late String baseline;
    late String live;

    setUp(() {
      final original = Process.runSync('git', ['show', '$_baseline:$path']);
      expect(original.exitCode, 0);
      baseline = original.stdout as String;
      live = File(path).readAsStringSync();
    });

    test('guard accepts only the exact connected iOS null-proxy fallback', () {
      expect(_differences(_inventory(baseline, 'baseline/$path'), _inventory(live, path)), isEmpty);
    });

    for (final mutation in <String, String Function(String)>{
      'wrong destination': (source) => source.replaceFirst("goNamed('proxies')", "goNamed('profiles')"),
      'missing iOS gate leaks to non-iOS': (source) => source.replaceFirst(
        'if (!ios) return const SizedBox.shrink();',
        'if (false) return const SizedBox.shrink();',
      ),
      'disconnected exposure': (source) =>
          source.replaceFirst('if (connectionState != const Connected())', 'if (false)'),
      'legacy proxy substitution': (source) => source.replaceFirst(
        'ios ? ref.watch(iosActiveProxyMeasurementStateProvider).asData?.value.proxy : legacyProxy',
        'legacyProxy',
      ),
      'real metadata route bypass': (source) =>
          source.replaceFirst('if (activeProxy == null)', 'if (activeProxy != null)'),
      'non-Blizzard icon leakage': (source) =>
          source.replaceFirst('const BlizzardSystemSymbol(icon: Icons.public)', 'const Icon(Icons.public)'),
      'wrong system symbol': (source) => source.replaceFirst('Icons.public', 'Icons.public_off'),
    }.entries) {
      test('guard rejects ${mutation.key}', () {
        final mutated = mutation.value(live);
        expect(mutated, isNot(live), reason: 'Mutation fixture must alter the production source.');
        expect(_differences(_inventory(baseline, 'baseline/$path'), _inventory(mutated, path)), isNotEmpty);
      });
    }
  });

  const sample = '''
void build(dynamic ref) {
  final controller = useTextEditingController(text: 'draft');
  ref.watch(profileProvider);
  Tile(onTap: () => ref.read(actionsProvider).select('profile-1'));
  if (mounted) save(controller.text);
}
''';
  test('guard accepts whitespace and additional visual wrappers', () {
    final decorated = sample
        .replaceFirst('Tile(onTap:', 'Padding(child: Tile(onTap:')
        .replaceFirst("select('profile-1'));", "select('profile-1')));");
    expect(
      _differences(_inventory(sample, 'sample'), _inventory(decorated.replaceAll('  ', '    '), 'decorated')),
      isEmpty,
    );
  });
  for (final mutation in <String, String>{
    'changed profile ID': sample.replaceAll('profile-1', 'profile-2'),
    'removed callback': sample.replaceAll("onTap: () => ref.read(actionsProvider).select('profile-1')", ''),
    'duplicated callback': sample.replaceFirst(
      '  if (mounted)',
      "  Tile(onTap: () => ref.read(actionsProvider).select('profile-1'));\n  if (mounted)",
    ),
    'extra provider read': sample.replaceFirst('  if (mounted)', '  ref.read(extraProvider);\n  if (mounted)'),
    'changed controller initialization': sample.replaceAll("'draft'", "'reset'"),
    'removed lifetime condition': sample.replaceAll('if (mounted)', 'if (true)'),
  }.entries) {
    test('guard rejects ${mutation.key} in disposable source', () {
      expect(_differences(_inventory(sample, 'sample'), _inventory(mutation.value, 'mutated')), isNotEmpty);
    });
  }
  test('invalid Dart is a guard failure rather than partial inventory', () {
    expect(() => _inventory('void broken( {', 'invalid'), throwsStateError);
  });
}

class _CallbackFinder extends RecursiveAstVisitor<void> {
  Expression? expression;
  @override
  void visitNamedExpression(NamedExpression node) {
    if (_callbacks.contains(node.name.label.name)) expression ??= node.expression;
    super.visitNamedExpression(node);
  }
}
