import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/graph_screen.dart';
import 'services/graph_repository.dart';
import 'services/wikipedia_service.dart';
import 'theme/hud_palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const PerihelionApp());
}

class PerihelionApp extends StatefulWidget {
  const PerihelionApp({super.key});

  @override
  State<PerihelionApp> createState() => _PerihelionAppState();
}

class _PerihelionAppState extends State<PerihelionApp> {
  late final Future<GraphRepository> _repository = GraphRepository.load();

  /// One instance for the session, so its extract cache survives navigation.
  final WikipediaService _wikipedia = WikipediaService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perihelion',
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
          return GraphScreen(
            repository: snapshot.requireData,
            wikipediaService: _wikipedia,
          );
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
