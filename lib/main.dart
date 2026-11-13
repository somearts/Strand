import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth/auth_scope.dart';
import 'auth/auth_service.dart';
import 'data/storage.dart';
import 'health/health_connect_provisioner.dart';
import 'health/hive_strand_store.dart';
import 'health/sleep_controller.dart';
import 'health/analytics/sleep_analytics.dart';
import 'social/cloud_store.dart';
import 'ui/theme.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/screens/health_connect_screen.dart';
import 'ui/screens/create_account_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.init();
  // Firebase is prepared before the first frame so a restored session already
  // has its profile when the greeting is built. A build without Firebase values
  // is handled inside: auth reports itself unconfigured and the app opens.
  await StrandAuth.instance.init();
  final sleep = StrandHealth.controller(HiveStrandStore());
  // Local history only. Health Connect is not touched here: on Android the
  // platform's own health service is contacted only when the person opens the
  // connection flow, so a cold start can never block on it or crash with it.
  await sleep.bindUser('local', checkHealth: false);
  // If an account is already signed in on this device, publish its nights so
  // friends can see them. Best-effort and offline-safe.
  if (StrandAuth.instance.isConfigured && StrandAuth.instance.signedIn) {
    // ignore: unawaited_futures
    CloudStore.uploadNights(
      SleepAnalytics.canonicalNights(sleep.records),
    ).catchError((Object _) {});
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(StrandApp(sleep: sleep));
}

class StrandApp extends StatelessWidget {
  const StrandApp({super.key, this.sleep});

  final SleepController? sleep;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'STRAND',
      debugShowCheckedModeBanner: false,
      theme: WaterTheme.light(),
      initialRoute: Storage.onboarded ? '/main' : '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/intro': (_) => const WelcomeScreen(),
        '/health': (_) => const HealthConnectScreen(),
        '/account': (_) => const CreateAccountScreen(),
        '/login': (_) => const LoginScreen(),
        '/main': (_) => const MainShell(),
      },
    );
    final Widget scoped = AuthScope(auth: StrandAuth.instance, child: app);
    if (sleep == null) return scoped;
    return SleepScope(controller: sleep!, child: scoped);
  }
}