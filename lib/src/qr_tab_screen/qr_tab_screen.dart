import 'package:flutter/material.dart';
import '../../src/qr/qr_screen.dart';

class QRTabsScreen extends StatefulWidget {

  const QRTabsScreen({super.key});

  @override
  _QRTabsScreenState createState() => _QRTabsScreenState();
}

class _QRTabsScreenState extends State<QRTabsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // 3 tabs
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: TabBar(
        controller: _tabController,
        tabs: [
          Tab(text: 'QR Scanner', icon: Icon(Icons.qr_code_scanner)),
          Tab(text: 'Tasks', icon: Icon(Icons.list_alt)),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const QRScreen(key: Key('qr_scanner')),
          Center(child: Text('Content for Tab 2')),
        ],
      ),
    );
  }
}