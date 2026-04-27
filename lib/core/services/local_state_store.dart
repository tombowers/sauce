import 'package:shared_preferences/shared_preferences.dart';

class LocalStateStore {
  LocalStateStore._(this._preferences);

  static const _consoleCollapsedKey = 'workbench.console.collapsed';
  static const _consoleHeightKey = 'workbench.console.height';

  final SharedPreferences _preferences;

  static Future<LocalStateStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LocalStateStore._(preferences);
  }

  bool readBool(String key, {required bool fallback}) {
    return _preferences.getBool(key) ?? fallback;
  }

  double readDouble(String key, {required double fallback}) {
    return _preferences.getDouble(key) ?? fallback;
  }

  List<String> readStringList(String key) {
    return List<String>.from(_preferences.getStringList(key) ?? const []);
  }

  String readString(String key, {required String fallback}) {
    return _preferences.getString(key) ?? fallback;
  }

  Future<void> writeBool(String key, bool value) async {
    await _preferences.setBool(key, value);
  }

  Future<void> writeDouble(String key, double value) async {
    await _preferences.setDouble(key, value);
  }

  Future<void> writeStringList(String key, List<String> value) async {
    await _preferences.setStringList(key, value);
  }

  Future<void> writeString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  WorkbenchConsoleState readWorkbenchConsoleState({
    required bool defaultCollapsed,
    required double defaultHeight,
  }) {
    return WorkbenchConsoleState(
      isCollapsed: readBool(_consoleCollapsedKey, fallback: defaultCollapsed),
      height: readDouble(_consoleHeightKey, fallback: defaultHeight),
    );
  }

  Future<void> writeWorkbenchConsoleState({
    required bool isCollapsed,
    required double height,
  }) async {
    await writeBool(_consoleCollapsedKey, isCollapsed);
    await writeDouble(_consoleHeightKey, height);
  }
}

class WorkbenchConsoleState {
  const WorkbenchConsoleState({
    required this.isCollapsed,
    required this.height,
  });

  final bool isCollapsed;
  final double height;
}
