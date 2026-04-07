import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/obsidian_data_service.dart';
import 'services/preferences_service.dart';
import 'pages/search_page.dart';
import 'pages/product_list_page.dart';
import 'pages/product_applications_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 初始化服务
  final dataService = ObsidianDataService();
  final preferencesService = PreferencesService();
  
  await preferencesService.initialize();
  await dataService.initialize();

  runApp(RstoneApp(
    dataService: dataService,
    preferencesService: preferencesService,
  ));
}

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
    return MaterialApp(
      title: '锐石 RSTONE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          foregroundColor: Colors.white,
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF2D2D2D),
        ),
        colorScheme: ColorScheme.dark(
          primary: Colors.orange,
          secondary: Colors.orange[700]!,
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF2D2D2D),
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              activeIcon: Icon(Icons.search, color: Colors.orange),
              label: '搜索',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2, color: Colors.orange),
              label: '产品列表',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.apps_outlined),
              activeIcon: Icon(Icons.apps, color: Colors.orange),
              label: '产品应用',
            ),
          ],
        ),
      ),
    );
  }
}
