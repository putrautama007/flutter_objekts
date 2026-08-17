import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Objekts example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  int _selectedIndex = 0;
  int _counter = 0;

  static const List<String> _titles = <String>[
    'Overview',
    'Activity',
    'Settings',
  ];

  void _incrementCounter() {
    setState(() {
      _counter += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          _OverviewScreen(
            counter: _counter,
            onIncrement: _incrementCounter,
          ),
          const _ActivityScreen(),
          const _SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('main-navigation'),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            key: Key('overview-tab'),
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            key: Key('activity-tab'),
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'Activity',
          ),
          NavigationDestination(
            key: Key('settings-tab'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _OverviewScreen extends StatelessWidget {
  const _OverviewScreen({
    required this.counter,
    required this.onIncrement,
  });

  final int counter;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.photo_camera_outlined, size: 64),
            const SizedBox(height: 24),
            Text(
              'Widget screenshots',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Counter: $counter'),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('increment-button'),
              onPressed: onIncrement,
              icon: const Icon(Icons.add),
              label: const Text('Increment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityScreen extends StatelessWidget {
  const _ActivityScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const <Widget>[
        ListTile(
          leading: CircleAvatar(child: Icon(Icons.photo_camera)),
          title: Text('Home screenshot captured'),
          subtitle: Text('Just now'),
        ),
        Divider(),
        ListTile(
          leading: CircleAvatar(child: Icon(Icons.devices)),
          title: Text('Device variants ready'),
          subtitle: Text('Portrait and landscape'),
        ),
      ],
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Screenshot settings'),
          subtitle: Text('Configure how your captures are generated.'),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: true,
          onChanged: (_) {},
          title: const Text('Include device frame'),
          subtitle: const Text('Show the simulated device bezel'),
        ),
      ],
    );
  }
}
