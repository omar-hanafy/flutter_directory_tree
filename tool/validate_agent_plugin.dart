/// Validates the AI coding-assistant plugin tree against this repository.
///
/// Deterministic checks (no network, no AI):
/// - the three manifests: the Agent Plugins 1.0 `plugin.json` at the plugin
///   root (read by Codex, Antigravity, and other Agent Plugins clients),
///   `.claude-plugin/plugin.json` (Claude Code), and the legacy
///   `.codex-plugin/plugin.json` (older Codex releases) agree on their shared
///   metadata, and their version is the `pubspec.yaml` version;
/// - the Codex interface is identical in both places Codex reads it, and the
///   icon is a complete, square PNG that the plugin directories accept;
/// - the plugin is instructions only, as both READMEs promise ("no hooks,
///   MCP servers, or network access"). The rule: the plugin folder holds
///   only the three manifests, `README.md`, `assets/icon.png`, Markdown
///   skills (`skills/<skill>/SKILL.md` and `skills/<skill>/references/*.md`),
///   and Markdown eval cases (`evals/<case>/prompt.md` and
///   `evals/<case>/graders/*.md`; `evals/results/`, which
///   `claude plugin eval` writes, is skipped); each manifest has only the
///   metadata fields listed below, so none declares hooks, MCP or LSP
///   servers, commands, agents, or any other component; and the root
///   manifest's `extensions` holds only `com.openai.interface`. No file in
///   the plugin can run code or open a connection; the skills only tell the
///   agent which ordinary tools to run, through its own approval prompts;
/// - both catalogs list this plugin under the manifests' `name`, from the
///   plugin folder itself, and agree with each other;
/// - kebab-case identifiers, skill frontmatter (Agent Skills fields, one
///   readable line per field, size limits), self-contained skill links
///   (inline, angle-bracket, and reference-style), and no machine-specific
///   or secret-looking content in any plugin file;
/// - every eval case has a prompt and graders, and its skill graders name
///   skills that exist;
/// - README.md and the plugin README show, as exact lines of a code block
///   outside HTML comments, the install commands that the catalogs and the
///   GitHub repository actually support, and the manifests' homepage is the
///   repository with an anchor that is a README heading;
/// - pub archive exclusions in `.pubignore`.
///
/// `tool/verify_agent_hosts.dart` complements this by installing the plugin
/// in the real host CLIs, and `test/agent_skill_claims_test.dart` checks
/// what the skills say against the package API.
///
/// Run from the repository root: `dart run tool/validate_agent_plugin.dart`
/// (or `dart tool/validate_agent_plugin.dart`, which needs no resolved
/// dependencies; the script imports only `dart:` libraries). Exits non-zero
/// when any check fails; prints every failure, not just the first.
library;

import 'dart:convert';
import 'dart:io';

const _pluginRoot = 'tooling/ai/flutter-directory-tree';
const _rootManifestPath = '$_pluginRoot/plugin.json';
const _claudeManifestPath = '$_pluginRoot/.claude-plugin/plugin.json';
const _codexManifestPath = '$_pluginRoot/.codex-plugin/plugin.json';
const _claudeCatalogPath = '.claude-plugin/marketplace.json';
const _codexCatalogPath = '.agents/plugins/marketplace.json';
const _skillsDir = '$_pluginRoot/skills';
const _evalsDir = '$_pluginRoot/evals';
const _pluginReadmePath = '$_pluginRoot/README.md';
const _agentPluginsSchema =
    'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json';

/// Metadata every manifest repeats; they must agree.
const _sharedFields = [
  'name',
  'version',
  'description',
  'author',
  'homepage',
  'repository',
  'license',
  'keywords',
];

/// The closed top-level field set of an Agent Plugins 1.0 manifest.
const _agentPluginsFields = {r'$schema', ..._sharedFields, 'extensions'};

/// The fields the Claude Code manifest may have: metadata only, so no
/// `hooks`, `mcpServers`, `commands`, `agents`, or other component paths.
const _claudeManifestFields = {..._sharedFields, 'displayName', 'icon'};

/// The fields the legacy Codex manifest may have: metadata, the skills
/// folder, and the interface.
const _codexManifestFields = {..._sharedFields, 'skills', 'interface'};

/// The fields of the Codex interface, in both places Codex reads it.
const _interfaceFields = {
  'displayName',
  'shortDescription',
  'longDescription',
  'developerName',
  'category',
  'websiteURL',
  'defaultPrompt',
  'brandColor',
  'composerIcon',
  'logo',
};

/// Agent Skills frontmatter fields (agentskills.io).
const _skillFields = {
  'name',
  'description',
  'license',
  'compatibility',
  'metadata',
  'allowed-tools',
};

/// The files an instructions-only plugin may contain, relative to its root.
final _allowedPluginFiles = [
  RegExp(r'^plugin\.json$'),
  RegExp(r'^\.claude-plugin/plugin\.json$'),
  RegExp(r'^\.codex-plugin/plugin\.json$'),
  RegExp(r'^README\.md$'),
  RegExp(r'^assets/icon\.png$'),
  RegExp(r'^skills/[a-z0-9-]+/SKILL\.md$'),
  RegExp(r'^skills/[a-z0-9-]+/references/[A-Za-z0-9._-]+\.md$'),
  RegExp(r'^evals/[a-z0-9-]+/prompt\.md$'),
  RegExp(r'^evals/[a-z0-9-]+/graders/[A-Za-z0-9._-]+\.md$'),
];

final _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _agentPluginsName = RegExp(
  r'^(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$',
);
final _githubRepository = RegExp(r'^https://github\.com/[\w.-]+/[\w-]+$');
final _errors = <String>[];

void _fail(String message) => _errors.add(message);

String? _readPubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _fail('pubspec.yaml not found (run from the repository root).');
    return null;
  }
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    _fail('pubspec.yaml has no version line.');
    return null;
  }
  return match.group(1);
}

Map<String, dynamic>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail('$path: missing file.');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      _fail('$path: top-level JSON value must be an object.');
      return null;
    }
    return decoded;
  } on FormatException catch (e) {
    _fail('$path: invalid JSON (${e.message}).');
    return null;
  }
}

/// Requires [path] to be `./` plus the plugin folder.
void _checkSourcePath(String path, String owner) {
  if (!path.startsWith('./')) {
    _fail('$owner: source path "$path" must start with "./".');
  }
  if (path.contains('..')) {
    _fail('$owner: source path "$path" must not contain "..".');
  }
  if (_folder(path) != _pluginRoot) {
    _fail(
      '$owner: source path "$path" must name the plugin folder '
      '"./$_pluginRoot".',
    );
  }
}

void _checkFields(Map<String, dynamic> map, Set<String> allowed, String owner) {
  for (final field in map.keys) {
    if (!allowed.contains(field)) {
      _fail(
        '$owner: "$field" is not an allowed field; the plugin is '
        'instructions only (see the rule in this tool\'s header).',
      );
    }
  }
}

/// Checks the three manifests and returns the root one for later checks.
Map<String, dynamic>? _checkManifests(String? pubspecVersion) {
  final manifests = <String, Map<String, dynamic>>{};
  for (final path in [
    _rootManifestPath,
    _claudeManifestPath,
    _codexManifestPath,
  ]) {
    final manifest = _readJson(path);
    if (manifest == null) continue;
    manifests[path] = manifest;
    final name = manifest['name'];
    if (name is! String || !_kebabCase.hasMatch(name)) {
      _fail('$path: "name" must be a kebab-case string, got "$name".');
    }
    final version = manifest['version'];
    if (pubspecVersion != null && version != pubspecVersion) {
      _fail(
        '$path: version "$version" does not match pubspec.yaml '
        'version "$pubspecVersion".',
      );
    }
    for (final field in ['description', 'license', 'repository', 'homepage']) {
      if (manifest[field] is! String || (manifest[field] as String).isEmpty) {
        _fail('$path: "$field" must be a non-empty string.');
      }
    }
  }

  final root = manifests[_rootManifestPath];
  if (root != null) _checkAgentPluginsManifest(root);

  // The shared metadata must not drift between hosts.
  if (root != null) {
    for (final MapEntry(key: path, value: manifest) in manifests.entries) {
      if (path == _rootManifestPath) continue;
      for (final field in _sharedFields) {
        if (jsonEncode(manifest[field]) != jsonEncode(root[field])) {
          _fail(
            '$path: "$field" differs from $_rootManifestPath; keep the '
            'shared metadata identical in every manifest.',
          );
        }
      }
    }
  }

  final claude = manifests[_claudeManifestPath];
  if (claude != null) {
    _checkFields(claude, _claudeManifestFields, _claudeManifestPath);
    final icon = claude['icon'];
    if (icon is String) {
      _checkIcon(icon, '$_claudeManifestPath "icon"');
    } else {
      _fail('$_claudeManifestPath: "icon" must name the plugin icon.');
    }
  }

  final codex = manifests[_codexManifestPath];
  if (codex != null) {
    _checkFields(codex, _codexManifestFields, _codexManifestPath);
    if (codex['skills'] != './skills/') {
      _fail('$_codexManifestPath: "skills" must be "./skills/".');
    }
    final legacy = codex['interface'];
    final openai = root?['extensions'] is Map
        ? (root!['extensions'] as Map)['com.openai']
        : null;
    final current = openai is Map ? openai['interface'] : null;
    if (legacy is! Map<String, dynamic>) {
      _fail('$_codexManifestPath: "interface" must be an object.');
    } else {
      _checkInterface(legacy, '$_codexManifestPath "interface"');
      // Codex uses the root extension when present and ignores this copy,
      // which only older releases read, so the two must stay identical.
      if (jsonEncode(legacy) != jsonEncode(current)) {
        _fail(
          '$_codexManifestPath: "interface" differs from '
          'extensions["com.openai"].interface in $_rootManifestPath.',
        );
      }
    }
  }
  return root;
}

void _checkAgentPluginsManifest(Map<String, dynamic> root) {
  const path = _rootManifestPath;
  if (root[r'$schema'] != _agentPluginsSchema) {
    _fail('$path: "\$schema" must be "$_agentPluginsSchema".');
  }
  for (final field in root.keys) {
    if (!_agentPluginsFields.contains(field)) {
      _fail(
        '$path: "$field" is not an Agent Plugins 1.0 field; put '
        'client-specific data under "extensions".',
      );
    }
  }
  final name = root['name'];
  if (name is! String ||
      name.length > 64 ||
      !_agentPluginsName.hasMatch(name)) {
    _fail('$path: "name" breaks the Agent Plugins naming rule.');
  }
  final author = root['author'];
  if (author is! Map ||
      author.keys.any((key) => !const {'name', 'email', 'url'}.contains(key))) {
    _fail('$path: "author" must be an object with name, email, or url only.');
  }
  final repository = root['repository'];
  if (repository is String && !_githubRepository.hasMatch(repository)) {
    _fail(
      '$path: "repository" must be https://github.com/<owner>/<repo>, '
      'which the install commands are built from.',
    );
  }
  final homepage = root['homepage'];
  if (homepage is String &&
      repository is String &&
      homepage != repository &&
      !homepage.startsWith('$repository#')) {
    _fail('$path: "homepage" must be the repository URL or an anchor in it.');
  }
  final extensions = root['extensions'];
  if (extensions is! Map || extensions.values.any((value) => value is! Map)) {
    _fail('$path: "extensions" must map namespaces to objects.');
    return;
  }
  final openai = extensions['com.openai'];
  if (openai is! Map || openai['interface'] is! Map) {
    _fail('$path: extensions["com.openai"].interface is required for Codex.');
  }
  // Only the Codex interface: an extension can declare components too.
  if (extensions.keys.any((key) => key != 'com.openai') ||
      (openai is Map && openai.keys.any((key) => key != 'interface'))) {
    _fail(
      '$path: "extensions" may hold only com.openai.interface; the plugin '
      'is instructions only.',
    );
  }
}

void _checkInterface(Map<String, dynamic> interface, String owner) {
  _checkFields(interface, _interfaceFields, owner);
  for (final field in [
    'displayName',
    'shortDescription',
    'longDescription',
    'developerName',
    'category',
  ]) {
    final value = interface[field];
    if (value is! String || value.trim().isEmpty) {
      _fail('$owner: "$field" must be a non-blank string.');
    }
  }
  final prompts = interface['defaultPrompt'];
  if (prompts is! List ||
      prompts.isEmpty ||
      prompts.length > 3 ||
      prompts.any((p) => p is! String || p.trim().isEmpty || p.length > 128)) {
    _fail(
      '$owner: "defaultPrompt" must list one to three non-blank prompts of '
      'at most 128 characters.',
    );
  }
  final website = interface['websiteURL'];
  if (website is! String || !website.startsWith('https://')) {
    _fail('$owner: "websiteURL" must be an https URL.');
  }
  final color = interface['brandColor'];
  if (color is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
    _fail('$owner: "brandColor" must be a #RRGGBB color.');
  }
  for (final field in ['composerIcon', 'logo']) {
    final value = interface[field];
    if (value is String) {
      _checkIcon(value, '$owner "$field"');
    } else {
      _fail('$owner: "$field" must name the plugin icon.');
    }
  }
}

/// Requires a complete square PNG inside the plugin, 512 to 2048 pixels on
/// a side and under 2 MB: the strictest of the hosts' icon rules.
void _checkIcon(String relativePath, String owner) {
  if (!relativePath.startsWith('./') || relativePath.contains('..')) {
    _fail('$owner: "$relativePath" must be a "./" path inside the plugin.');
    return;
  }
  final file = File('$_pluginRoot/${relativePath.substring(2)}');
  if (!file.existsSync()) {
    _fail('$owner: "$relativePath" does not exist.');
    return;
  }
  final bytes = file.readAsBytesSync();
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24 ||
      List.generate(8, (i) => bytes[i]).join(',') != signature.join(',')) {
    _fail('$owner: "$relativePath" is not a PNG file.');
    return;
  }
  // A complete PNG ends with the IEND chunk: its type, then its CRC.
  if (bytes.length < 45 ||
      ascii.decode(bytes.sublist(bytes.length - 8, bytes.length - 4)) !=
          'IEND') {
    _fail('$owner: "$relativePath" is truncated (no IEND chunk at the end).');
    return;
  }
  int readInt(int offset) =>
      bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
  final width = readInt(16);
  final height = readInt(20);
  if (width != height || width < 512 || width > 2048) {
    _fail(
      '$owner: "$relativePath" is ${width}x$height; it must be square and '
      '512 to 2048 pixels on a side.',
    );
  }
  if (bytes.length >= 2 * 1024 * 1024) {
    _fail('$owner: "$relativePath" must be under 2 MB.');
  }
}

/// Enforces the instructions-only file rule (see the library docs) and
/// scans every text file of the plugin for machine paths and secrets.
void _checkPluginFiles() {
  final root = Directory(_pluginRoot);
  if (!root.existsSync()) {
    _fail('$_pluginRoot: missing plugin folder.');
    return;
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(_pluginRoot.length + 1);
    if (relative.endsWith('.DS_Store') ||
        relative.startsWith('evals/results/')) {
      continue;
    }
    if (!_allowedPluginFiles.any((rule) => rule.hasMatch(relative))) {
      _fail(
        '${entity.path}: not allowed in an instructions-only plugin (only '
        'the manifests, README.md, assets/icon.png, and Markdown skills and '
        'eval cases).',
      );
      continue;
    }
    if (relative.endsWith('.md') || relative.endsWith('.json')) {
      _checkTextFile(entity);
    }
  }
}

/// Checks both catalogs and returns the marketplace name.
String? _checkCatalogs(String? pluginName) {
  final claude = _readJson(_claudeCatalogPath);
  final codex = _readJson(_codexCatalogPath);
  String? claudeName;
  String? codexName;
  final claudePlugins = <String>[];
  final codexPlugins = <String>[];
  // Plugin name to the folder each catalog installs it from.
  final claudeSources = <String, String>{};
  final codexSources = <String, String>{};

  if (claude != null) {
    claudeName = _stringOrNull(claude['name']);
    if (claudeName == null || !_kebabCase.hasMatch(claudeName)) {
      _fail('$_claudeCatalogPath: marketplace "name" must be kebab-case.');
    }
    if (claude['owner'] is! Map || (claude['owner'] as Map)['name'] == null) {
      _fail('$_claudeCatalogPath: "owner.name" is required.');
    }
    final plugins = claude['plugins'];
    if (plugins is! List || plugins.isEmpty) {
      _fail('$_claudeCatalogPath: "plugins" must be a non-empty array.');
    } else {
      for (final plugin in plugins) {
        if (plugin is! Map<String, dynamic>) {
          _fail('$_claudeCatalogPath: each "plugins" entry must be an object.');
          continue;
        }
        final name = _stringOrNull(plugin['name']);
        if (name == null || !_kebabCase.hasMatch(name)) {
          _fail('$_claudeCatalogPath: plugin "name" must be kebab-case.');
        } else if (claudePlugins.contains(name)) {
          _fail('$_claudeCatalogPath: duplicate plugin name "$name".');
        } else {
          claudePlugins.add(name);
        }
        final source = plugin['source'];
        if (source is String) {
          _checkSourcePath(source, '$_claudeCatalogPath ($name)');
          if (name != null) claudeSources[name] = source;
        } else {
          _fail(
            '$_claudeCatalogPath ($name): expected a relative-path string '
            'source for a repo-hosted plugin.',
          );
        }
        if (plugin.containsKey('version')) {
          _fail(
            '$_claudeCatalogPath ($name): do not set "version" in the '
            'catalog entry; plugin.json is the single version source.',
          );
        }
      }
    }
  }

  if (codex != null) {
    codexName = _stringOrNull(codex['name']);
    if (codexName == null || !_kebabCase.hasMatch(codexName)) {
      _fail('$_codexCatalogPath: marketplace "name" must be kebab-case.');
    }
    final plugins = codex['plugins'];
    if (plugins is! List || plugins.isEmpty) {
      _fail('$_codexCatalogPath: "plugins" must be a non-empty array.');
    } else {
      for (final plugin in plugins) {
        if (plugin is! Map<String, dynamic>) {
          _fail('$_codexCatalogPath: each "plugins" entry must be an object.');
          continue;
        }
        final name = _stringOrNull(plugin['name']);
        if (name == null || !_kebabCase.hasMatch(name)) {
          _fail('$_codexCatalogPath: plugin "name" must be kebab-case.');
        } else if (codexPlugins.contains(name)) {
          _fail('$_codexCatalogPath: duplicate plugin name "$name".');
        } else {
          codexPlugins.add(name);
        }
        final source = plugin['source'];
        if (source is Map<String, dynamic>) {
          if (source['source'] != 'local') {
            _fail(
              '$_codexCatalogPath ($name): expected {"source": "local"} for '
              'a repo-hosted plugin.',
            );
          }
          final path = source['path'];
          if (path is String) {
            _checkSourcePath(path, '$_codexCatalogPath ($name)');
            if (name != null) codexSources[name] = path;
          } else {
            _fail('$_codexCatalogPath ($name): "source.path" is required.');
          }
        } else {
          _fail('$_codexCatalogPath ($name): "source" must be an object.');
        }
        final policy = plugin['policy'];
        if (policy is! Map ||
            policy['installation'] is! String ||
            policy['authentication'] is! String ||
            plugin['category'] is! String) {
          _fail(
            '$_codexCatalogPath ($name): "policy.installation", '
            '"policy.authentication", and "category" are required.',
          );
        }
      }
    }
  }

  if (claudeName != null && codexName != null && claudeName != codexName) {
    _fail(
      'Marketplace names differ between catalogs: "$claudeName" (Claude) vs '
      '"$codexName" (Codex). Keep them identical so install docs stay true.',
    );
  }
  if (claude != null &&
      codex != null &&
      claudePlugins.join(',') != codexPlugins.join(',')) {
    _fail('The two catalogs must list the same plugins in the same order.');
  }
  // The install ids are `<manifest name>@<marketplace>`, so each catalog
  // must list the plugin under the name its manifests give it.
  if (pluginName != null) {
    for (final (path, names) in [
      (_claudeCatalogPath, claudePlugins),
      (_codexCatalogPath, codexPlugins),
    ]) {
      if (!names.contains(pluginName)) {
        _fail(
          '$path: lists ${names.map((n) => '"$n"').join(', ')}, not the '
          'manifests\' name "$pluginName"; the install commands would fail.',
        );
      }
    }
  }
  for (final MapEntry(key: name, value: path) in codexSources.entries) {
    final claudeSource = claudeSources[name];
    if (claudeSource != null && _folder(claudeSource) != _folder(path)) {
      _fail(
        'The catalogs install "$name" from different folders: '
        '"$claudeSource" (Claude) vs "$path" (Codex).',
      );
    }
  }
  return claudeName;
}

String? _stringOrNull(Object? value) => value is String ? value : null;

/// [path] without its leading `./` or trailing `/`.
String _folder(String path) =>
    path.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'/+$'), '');

/// Characters that cannot start a YAML plain scalar, or change its meaning.
const _yamlIndicators = r'>|[]{}&*!%@`#,';

/// Parses the frontmatter: one `key: value` line per field, values plain or
/// quoted. Rejects what this line reader cannot read the way a YAML parser
/// would (nested or multi-line values, block scalars, flow collections,
/// comments, `: ` in a plain value, duplicate keys). Returns the keys, the
/// unquoted `name` and `description`, and the index of the closing line.
({Set<String> keys, String? name, String? description, int end})
_parseFrontmatter(String path, String content) {
  const none = (keys: <String>{}, name: null, description: null, end: -1);
  final lines = const LineSplitter().convert(content);
  if (lines.isEmpty || lines.first.trim() != '---') {
    _fail('$path: missing YAML frontmatter opening "---".');
    return none;
  }
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end == -1) {
    _fail('$path: frontmatter never closes with "---".');
    return none;
  }
  final values = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    if (line.trim().isEmpty) continue;
    final match = RegExp(r'^([A-Za-z][\w-]*):(?: (.*))?$').firstMatch(line);
    if (match == null) {
      _fail(
        '$path: frontmatter line "$line" is not a one-line "key: value" '
        'field; nested and multi-line values are not supported.',
      );
      continue;
    }
    final key = match.group(1)!;
    final value = _yamlValue(path, key, (match.group(2) ?? '').trim());
    if (values.containsKey(key)) {
      _fail('$path: frontmatter repeats "$key".');
    } else if (value != null) {
      values[key] = value;
    }
  }
  return (
    keys: values.keys.toSet(),
    name: values['name'],
    description: values['description'],
    end: end,
  );
}

/// The value of a one-line frontmatter field, or `null` (after reporting)
/// when a YAML parser would read it differently from the text.
String? _yamlValue(String path, String key, String raw) {
  void reject(String why) =>
      _fail('$path: frontmatter "$key" $why; quote the value.');
  if (raw.isEmpty) {
    reject('has no value on its line (block values are not supported)');
    return null;
  }
  if (raw.startsWith('"')) {
    if (raw.length < 2 || !raw.endsWith('"')) {
      reject('opens a double quote that does not end the line');
      return null;
    }
    final inner = raw.substring(1, raw.length - 1);
    if (RegExp(r'(^|[^\\])"').hasMatch(inner)) {
      reject('has an unescaped double quote inside');
      return null;
    }
    return inner.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
  if (raw.startsWith("'")) {
    if (raw.length < 2 || !raw.endsWith("'")) {
      reject('opens a single quote that does not end the line');
      return null;
    }
    final inner = raw.substring(1, raw.length - 1);
    if (inner.replaceAll("''", '').contains("'")) {
      reject('has an unescaped single quote inside');
      return null;
    }
    return inner.replaceAll("''", "'");
  }
  if (_yamlIndicators.contains(raw[0]) ||
      (raw.length > 1 && '-?:'.contains(raw[0]) && raw[1] == ' ')) {
    reject('starts with the YAML indicator "${raw[0]}"');
    return null;
  }
  if (raw.contains(': ') || raw.endsWith(':')) {
    reject('contains ": ", which ends a plain YAML value');
    return null;
  }
  if (raw.contains(' #')) {
    reject('contains " #", which starts a YAML comment');
    return null;
  }
  return raw;
}

void _checkSkillLinks(String skillDir, String mdPath, String content) {
  final targets = [
    // Inline links, with or without angle brackets.
    for (final match in RegExp(
      r'\[[^\]]*\]\(\s*<?([^)>\s]+)>?[^)]*\)',
    ).allMatches(content))
      match.group(1)!,
    // Reference-style link definitions.
    for (final match in RegExp(
      r'^ {0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?',
      multiLine: true,
    ).allMatches(content))
      match.group(1)!,
  ];
  for (final raw in targets) {
    final target = raw.split('#').first.trim();
    if (target.isEmpty || target.contains('://')) continue;
    if (target.startsWith('/')) {
      _fail('$mdPath: absolute link target "$target" is not portable.');
      continue;
    }
    final normalized = Uri(path: '${File(mdPath).parent.path}/$target')
        .normalizePath()
        .path;
    if (!normalized.startsWith('$skillDir/')) {
      _fail(
        '$mdPath: link "$target" escapes the skill directory; skills must '
        'be self-contained.',
      );
      continue;
    }
    if (!File(normalized).existsSync()) {
      _fail('$mdPath: link target "$target" does not exist.');
    }
  }
}

void _checkTextFile(File file) {
  final text = file.readAsStringSync();
  for (final marker in ['/Users/', '/home/', r'C:\']) {
    if (text.contains(marker)) {
      _fail('${file.path}: contains machine-specific path marker "$marker".');
    }
  }
  for (final marker in ['-----BEGIN', 'ghp_', 'AKIA']) {
    if (text.contains(marker)) {
      _fail('${file.path}: contains secret-like marker "$marker".');
    }
  }
}

/// Checks every skill and returns their names.
Set<String> _checkSkills() {
  final skillsRoot = Directory(_skillsDir);
  if (!skillsRoot.existsSync()) {
    _fail('$_skillsDir: missing skills directory.');
    return const {};
  }
  final skillDirs = skillsRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (skillDirs.isEmpty) {
    _fail('$_skillsDir: no skills found.');
    return const {};
  }
  final seen = <String>{};
  for (final dir in skillDirs) {
    final dirName = dir.path.split(Platform.pathSeparator).last;
    final skillPath = '${dir.path}/SKILL.md';
    final skillFile = File(skillPath);
    if (!skillFile.existsSync()) {
      _fail('$skillPath: missing SKILL.md.');
      continue;
    }
    if (!_kebabCase.hasMatch(dirName) || dirName.length > 64) {
      _fail('${dir.path}: skill directory name must be kebab-case, max 64.');
    }
    if (!seen.add(dirName)) {
      _fail('${dir.path}: duplicate skill name.');
    }
    final content = skillFile.readAsStringSync();
    final frontmatter = _parseFrontmatter(skillPath, content);
    if (frontmatter.name != dirName) {
      _fail(
        '$skillPath: frontmatter name "${frontmatter.name}" must equal the '
        'directory name "$dirName" (agentskills.io requirement).',
      );
    }
    for (final key in frontmatter.keys.difference(_skillFields)) {
      _fail(
        '$skillPath: frontmatter "$key" is not an Agent Skills field; '
        'hosts other than the one it was written for ignore or reject it.',
      );
    }
    if (frontmatter.end >= 0) {
      final body = const LineSplitter()
          .convert(content)
          .skip(frontmatter.end + 1)
          .join('\n');
      if (body.trim().isEmpty) {
        _fail(
          '$skillPath: the skill has no instructions after its frontmatter.',
        );
      }
    }
    // Antigravity cuts SKILL.md at 24 KB, and the Agent Skills guidance
    // keeps the body under 500 lines with details in references/.
    if (skillFile.lengthSync() > 24 * 1024) {
      _fail('$skillPath: over 24 KB; move detail into references/.');
    }
    if (const LineSplitter().convert(content).length > 500) {
      _fail('$skillPath: over 500 lines; move detail into references/.');
    }
    final description = frontmatter.description;
    if (description == null || description.isEmpty) {
      _fail('$skillPath: frontmatter "description" is required.');
    } else if (description.length > 1024) {
      _fail(
        '$skillPath: description is ${description.length} chars; the '
        'portable limit is 1024.',
      );
    }
    for (final md
        in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))) {
      _checkSkillLinks(dir.path, md.path, md.readAsStringSync());
    }
  }
  return seen;
}

/// Checks the `claude plugin eval` suite's layout and skill references.
void _checkEvals(Set<String> skillNames) {
  final root = Directory(_evalsDir);
  if (!root.existsSync()) {
    _fail('$_evalsDir: missing; the plugin ships an eval suite.');
    return;
  }
  final cases = root
      .listSync()
      .whereType<Directory>()
      .where((d) => !d.path.endsWith('/results'))
      .toList();
  if (cases.isEmpty) _fail('$_evalsDir: no eval cases found.');
  for (final dir in cases) {
    if (!File('${dir.path}/prompt.md').existsSync()) {
      _fail('${dir.path}: an eval case needs a prompt.md.');
    }
    final graders = Directory('${dir.path}/graders');
    final graderFiles = graders.existsSync()
        ? graders.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.md'),
          )
        : const <File>[];
    if (graderFiles.isEmpty) {
      _fail('${dir.path}: an eval case needs at least one graders/*.md.');
    }
    // A renamed or misspelled skill would otherwise leave its graders
    // silently unmatched.
    for (final grader in graderFiles) {
      final text = grader.readAsStringSync();
      if (!text.contains('tool: Skill')) continue;
      final named =
          RegExp('[a-z0-9-]*flutter-directory-tree[a-z0-9-]*')
              .allMatches(text)
              .map((m) => m.group(0)!)
              .toSet()
            ..remove('flutter-directory-tree');
      // A grader for a loaded skill names it in the last group of its
      // `"skill"` pattern: `(?:skill-a|skill-b)`.
      for (final line in const LineSplitter().convert(text)) {
        if (!line.startsWith('input_match:') || !line.contains('"skill"')) {
          continue;
        }
        final groups = RegExp(r'\(\?:([^()]*)\)').allMatches(line).toList();
        if (groups.isEmpty) {
          _fail('${grader.path}: the "skill" pattern names no skill group.');
          continue;
        }
        named.addAll(groups.last.group(1)!.split('|'));
      }
      for (final name in named.difference(skillNames)) {
        _fail('${grader.path}: names skill "$name", which does not exist.');
      }
    }
  }
}

/// The trimmed lines inside fenced code blocks of [markdown], outside HTML
/// comments: where a reader can copy a command from.
Set<String> _codeLines(String markdown) {
  final visible = markdown.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final lines = <String>{};
  var fenced = false;
  for (final line in const LineSplitter().convert(visible)) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
    } else if (fenced) {
      lines.add(line.trim());
    }
  }
  return lines;
}

/// The anchors of the headings of [markdown] outside code blocks and HTML
/// comments, as GitHub builds them.
Set<String> _headingAnchors(String markdown) {
  final visible = markdown.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final anchors = <String>{};
  var fenced = false;
  for (final line in const LineSplitter().convert(visible)) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
      continue;
    }
    final match = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
    if (fenced || match == null) continue;
    anchors.add(
      match
          .group(1)!
          .trim()
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9 _-]'), '')
          .replaceAll(' ', '-'),
    );
  }
  return anchors;
}

/// Requires the documented install commands, as exact lines of a code
/// block, to match the catalogs, and the homepage anchor to be a heading of
/// README.md.
void _checkReadmes({
  required String? marketplace,
  required Map<String, dynamic>? rootManifest,
}) {
  final repository = rootManifest?['repository'];
  final homepage = rootManifest?['homepage'];
  final pluginName = rootManifest?['name'];
  if (marketplace == null || repository is! String || pluginName is! String) {
    return; // Already reported by the manifest and catalog checks.
  }
  final slug = repository.replaceFirst('https://github.com/', '');
  final id = '$pluginName@$marketplace';
  final commands = [
    '/plugin marketplace add $slug',
    '/plugin install $id',
    'codex plugin marketplace add $slug',
    'codex plugin add $id',
    'agy plugin install https://github.com/$slug/tree/main/$_pluginRoot',
  ];
  for (final path in ['README.md', _pluginReadmePath]) {
    final file = File(path);
    if (!file.existsSync()) {
      _fail('$path: missing.');
      continue;
    }
    final lines = _codeLines(file.readAsStringSync());
    for (final command in commands) {
      if (!lines.contains(command)) {
        _fail(
          '$path: no code block line is exactly the install command '
          '"$command".',
        );
      }
    }
  }
  if (homepage is String && homepage.contains('#')) {
    final anchor = homepage.split('#').last;
    if (!_headingAnchors(File('README.md').readAsStringSync())
        .contains(anchor)) {
      _fail('README.md: no heading for the manifests\' homepage "#$anchor".');
    }
  }
}

void _checkPubignore() {
  final file = File('.pubignore');
  if (!file.existsSync()) {
    _fail('.pubignore: missing; the plugin tree would leak into the archive.');
    return;
  }
  final lines = const LineSplitter()
      .convert(file.readAsStringSync())
      .map((l) => l.trim())
      .toList();
  // A leading `/` anchors a pattern to the package root; either form keeps
  // the directory out. The catalogs live in hidden directories
  // (`.claude-plugin/`, `.agents/`), which pub never archives.
  for (final required in ['tooling/', 'tool/', 'AGENTS.md', 'CLAUDE.md']) {
    if (!lines.contains(required) && !lines.contains('/$required')) {
      _fail(
        '.pubignore: missing "$required" - the pub.dev archive must not '
        'contain a partial AI plugin or maintainer-only files.',
      );
    }
    for (final line in lines.where((l) => l.startsWith('!'))) {
      final pattern = line.substring(1).replaceFirst(RegExp('^/'), '');
      if (pattern.startsWith(required)) {
        _fail('.pubignore: "$line" puts "$required" content back.');
      }
    }
  }
}

/// Entry point; see the library docs for what is validated.
void main() {
  final pubspecVersion = _readPubspecVersion();
  final rootManifest = _checkManifests(pubspecVersion);
  _checkPluginFiles();
  final marketplace = _checkCatalogs(_stringOrNull(rootManifest?['name']));
  final skills = _checkSkills();
  _checkEvals(skills);
  _checkReadmes(marketplace: marketplace, rootManifest: rootManifest);
  _checkPubignore();

  if (_errors.isEmpty) {
    stdout.writeln('Agent plugin validation passed.');
    return;
  }
  stderr.writeln('Agent plugin validation FAILED:');
  for (final error in _errors) {
    stderr.writeln('  - $error');
  }
  exitCode = 1;
}
