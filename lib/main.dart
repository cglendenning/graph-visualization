import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/graph_screen.dart';
import 'services/wikidata_service.dart';
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
  /// One instance each for the session, so their caches survive navigation.
  final WikidataService _wikidata = WikidataService();
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
      home: GraphScreen(
        wikidata: _wikidata,
        wikipediaService: _wikipedia,
      ),
    );
  }
}

