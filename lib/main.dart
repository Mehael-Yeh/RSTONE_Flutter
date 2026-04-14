import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/obsidian_data_service.dart';
import 'services/preferences_service.dart';
import 'pages/search_page.dart';
import 'pages/product_list_page.dart';
import 'pages/product_applications_page.dart';

/// 应用入口函数
void main() async {
  // 确保在执行异步初始化前完成 Flutter 引擎绑定。
  WidgetsFlutterBinding.ensureInitialized();

  // 统一系统状态栏样式，避免页面切换时出现亮暗不一致。
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final dataService = ObsidianDataService();
  final preferencesService = PreferencesService();

  // 应用启动阶段完成本地偏好和静态资源数据初始化。
  await preferencesService.initialize();
  await dataService.initialize();

  // 初始化完成后再挂载根组件，避免首帧出现空数据状态抖动。
  runApp(RstoneApp(
    dataService: dataService,
    preferencesService: preferencesService,
  ));
}

/// 根组件 - 应用级 MD3 主题配置
class RstoneApp extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;

  const RstoneApp({
    super.key,
    required this.dataService,
    required this.preferencesService,
  });

  @override
  State<RstoneApp> createState() => _RstoneAppState();
}

class _RstoneAppState extends State<RstoneApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeFromString(widget.preferencesService.getThemeMode());
  }

  ThemeMode _themeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _updateThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.preferencesService.saveThemeMode(_themeModeToString(mode));
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF8A00),
      brightness: brightness,
    );
    return ThemeData(
      // 启用 Material Design 3 组件行为与样式。
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      // Flutter 3.24 使用 CardTheme（而非 CardThemeData）。
      cardTheme: CardTheme(
        elevation: 0,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // 底部导航使用低层级容器色，保证与内容区域层级分离。
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '锐石 RSTONE',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: MainScreen(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const MainScreen({
    super.key,
    required this.dataService,
    required this.preferencesService,
    required this.onThemeModeChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 当前底部导航索引。
  int _currentIndex = 0;
  /// 使用 IndexedStack 保持三个主页面的状态。
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      SearchPage(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
      ProductListPage(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
      ),
      ProductApplicationsPage(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 切换 tab 时保留页面滚动位置和内部状态。
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        // MD3 导航栏：采用目的地（destination）模型。
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: '产品列表',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: '产品应用',
          ),
        ],
      ),
    );
  }
}
