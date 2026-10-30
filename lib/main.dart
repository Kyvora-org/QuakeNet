import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/device_node.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fullscreen immersive status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final realtimeEnabled = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
  if (realtimeEnabled) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  }

  // Cargar identidad anónima del nodo persistente (Fase 2B)
  final deviceNode = await DeviceNode.loadExperimental(platform: Platform.operatingSystem);

  runApp(QuakeNetApp(
    supabaseClient: realtimeEnabled ? Supabase.instance.client : null,
    deviceNode: deviceNode,
  ));
}

class QuakeNetApp extends StatelessWidget {
  final SupabaseClient? supabaseClient;
  final DeviceNode deviceNode;

  const QuakeNetApp({super.key, this.supabaseClient, required this.deviceNode});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuakeNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B2838),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF0D1117),
          primary: const Color(0xFF58A6FF),
          secondary: const Color(0xFF3FB950),
          error: const Color(0xFFFF6B6B),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF161B22),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFC9D1D9)),
          bodySmall: TextStyle(color: Color(0xFF8B949E)),
          titleMedium: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(supabaseClient: supabaseClient, deviceNode: deviceNode),
    );
  }
}
