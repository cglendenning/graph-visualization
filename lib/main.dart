import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/graph_screen.dart';
import 'services/graph_repository.dart';
import 'theme/hud_palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const ConstellationApp());
}

class ConstellationApp extends StatefulWidget {
  const ConstellationApp({super.key});

  @override
  State<ConstellationApp> createState() => _ConstellationAppState();
}

class _ConstellationAppState extends State<ConstellationApp> {
  late final Future<GraphRepository> _repository = GraphRepository.load();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Constellation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: HudPalette.voidBlack,
        useMaterial3: true,
      ),
      home: FutureBuilder<GraphRepository>(
        future: _repository,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootMessage(
              text: 'GRAPH FAILED TO LOAD\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const _BootMessage(text: 'LOADING GRAPH');
          }
          return GraphScreen(repository: snapshot.requireData);
        },
      ),
    );
  }
}

class _BootMessage extends StatelessWidget {
  const _BootMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HudPalette.voidBlack,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: HudPalette.telemetry,
          ),
        ),
      ),
    );
  }
}
