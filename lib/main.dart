import 'package:ymapper/layouts/home.dart';
import 'package:ymapper/presets/preset_manager.dart';
import 'package:ymapper/shared/map_provider.dart';
import 'package:ymapper/shared/theme_manager.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ymapper/theme/origen_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  PresetManager.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ValueListenables()),
        ChangeNotifierProvider(create: (context) => ThemeManager()),
        ChangeNotifierProvider(create: (context) => MapProvider()),
      ],
      child: MaterialApp(
        title: 'OrigenLabs Mapper',
        debugShowCheckedModeBanner: false,
        theme: OrigenTheme.dark,
        darkTheme: OrigenTheme.dark,
        themeMode: ThemeMode.dark,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeLayout(),
      ),
    );
  }
}
