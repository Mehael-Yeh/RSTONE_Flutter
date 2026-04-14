import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/obsidian_data_service.dart';
import 'services/preferences_service.dart';
import 'pages/search_page.dart';
import 'pages/product_list_page.dart';
import 'pages/product_applications_page.dart';

/// 应用入口函数
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final dataService = ObsidianDataService();
  final preferencesService = PreferencesService();

  await preferencesService.initialize();
  await dataService.initialize();

  runApp(RstoneApp(
    dataService: dataService,
    preferencesService: preferencesService,
  ));
}

/// 根组件 - 应用级 MD3 主题配置
class RstoneApp extends StatelessWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;

  const RstoneApp({
    super.key,
    required this.dataService,
    required this.preferencesService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF8A00),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: '锐石 RSTONE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
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
      ),
      home: MainScreen(
        dataService: dataService,
        preferencesService: preferencesService,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final ObsidianDataService dataService;
  final PreferencesService preferencesService;

  const MainScreen({
    super.key,
    required this.dataService,
    required this.preferencesService,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      SearchPage(dataService: widget.dataService),
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
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
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
