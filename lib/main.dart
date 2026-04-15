import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/obsidian_data_service.dart';
import 'services/preferences_service.dart';
import 'pages/search_page.dart';
import 'pages/product_list_page.dart';
import 'pages/product_applications_page.dart';
import 'widgets/product_detail_sheet.dart';

/// 应用入口函数
void main() async {
  // 确保 Flutter 绑定已初始化（异步操作的前置条件）
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置状态栏样式：透明背景、白色图标
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 初始化数据服务
  // - dataService: 负责从 Asset 加载产品/应用/配方数据
  // - preferencesService: 负责用户偏好设置（如列排序、列顺序）的持久化
  final dataService = ObsidianDataService();
  final preferencesService = PreferencesService();
  
  await preferencesService.initialize();
  await dataService.initialize();

  // 启动应用
  runApp(RstoneApp(
    dataService: dataService,
    preferencesService: preferencesService,
  ));
}

/// 根组件 - 应用级主题配置
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
      // 深色主题配置
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.orange,
        // 整体背景色：深灰黑色
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        // 导航栏背景色
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          foregroundColor: Colors.white,
        ),
        // 卡片背景色
        cardTheme: const CardTheme(
          color: Color(0xFF2D2D2D),
        ),
        // 颜色方案：主色调橙色
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

/// 主屏幕 - 底部导航容器
/// 包含三个主要页面：搜索、产品列表、产品应用
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
  /// 当前选中的导航索引
  int _currentIndex = 0;

  /// 页面列表（延迟初始化，避免在 initState 中创建复杂的 StatefulWidget）
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      // 搜索页面（首页）
      SearchPage(dataService: widget.dataService),
      // 产品列表页面
      ProductListPage(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
      ),
      // 产品应用页面
      ProductApplicationsPage(
        dataService: widget.dataService,
        preferencesService: widget.preferencesService,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保持页面状态，只切换显示而不重建
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // 底部导航栏
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF3D3D3D), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          // 切换导航时更新索引，重建 UI
          onTap: (index) {
            ProductDetailSheet.hideIfOpen(context);
            setState(() => _currentIndex = index);
          },
          backgroundColor: const Color(0xFF2D2D2D),
          selectedItemColor: Colors.orange,   // 选中项：橙色
          unselectedItemColor: Colors.grey,   // 未选中项：灰色
          type: BottomNavigationBarType.fixed, // 固定类型，所有标签都显示
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
