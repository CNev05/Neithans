import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'services/db_service.dart';
import 'services/sms_service.dart';
import 'screens/login_screen.dart';
import 'screens/owner_home.dart';
import 'screens/superadmin_dashboard.dart';
import 'screens/tenants_list.dart';
import 'screens/violations_dashboard.dart';
import 'firebase_options.dart';

const String automatedReminderTask = "com.neithans.automatedReminderTask";

int? _reminderDayFor(DateTime dueDate, DateTime today) {
  final daysUntilDue = dueDate.difference(today).inDays;
  if (daysUntilDue == 0) return 0;
  if (daysUntilDue > 0 && daysUntilDue <= 3) return 3;
  if (daysUntilDue > 3 && daysUntilDue <= 7) return 7;
  return null;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("Background Task Started: $task");

    try {
      final owners = await (await DBService.db).query('owner_profile');

      for (var owner in owners) {
        final ownerId = owner['ownerId'] as String;
        final tenants = await DBService.getTenants(ownerId);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        for (var t in tenants) {
          final phone = t['phone'] as String?;
          final name = t['name'] as String?;
          final tenantId = t['id'] as String;
          if (phone == null || name == null) continue;

          // 1. Rent Due Date Reminders (7-3-0 days)
          final nextDueStr = t['nextDueDate'] as String?;
          if (nextDueStr != null && nextDueStr != 'Not set') {
            try {
              final dueDate = DateFormat('yyyy-MM-dd').parseStrict(nextDueStr);
              final reminderDay = _reminderDayFor(dueDate, today);

              String? rentMsg;
              String? rentReminderType;

              final cycleKey = "${dueDate.year}_${dueDate.month}";
              if (reminderDay == 7) {
                rentMsg =
                    "Dear $name, this is a friendly reminder from Neithans that your rent is due on $nextDueStr. Please coordinate your payment directly with your landlord. Important: Neithans does not collect payments online. Never send money to unknown accounts. Thank you for your continued trust.";
                rentReminderType = "rent_7_$cycleKey";
              } else if (reminderDay == 3) {
                rentMsg =
                    "Dear $name, this is a reminder that your rent is due on $nextDueStr. Kindly prepare your payment and settle it directly with your landlord. Reminder: Neithans has no online payment system. If anyone requests online payment on our behalf, please treat it as a scam. Thank you.";
                rentReminderType = "rent_3_$cycleKey";
              } else if (reminderDay == 0) {
                rentMsg =
                    "Dear $name, your rent is due today ($nextDueStr). Please settle your payment with your landlord at your earliest convenience. Note: Neithans does not process payments online. Do not send money to any online account claiming to represent us. Thank you.";
                rentReminderType = "rent_0_$cycleKey";
              }

              if (rentMsg != null && rentReminderType != null) {
                final alreadySent =
                    await DBService.wasReminderSent(tenantId, rentReminderType);
                if (!alreadySent) {
                  final success =
                      await SmsService.sendSms(to: phone, message: rentMsg);
                  if (success) {
                    await DBService.markReminderSent(
                        tenantId, rentReminderType);
                    debugPrint(
                        "Rent SMS to $name ($reminderDay-day reminder): SUCCESS");
                  }
                }
              }
            } catch (e) {
              debugPrint("Error processing rent reminder for $name: $e");
            }
          }

          // 2. Contract End (Endo) Reminders (7-3-0 days)
          final endoStr = t['endoDate'] as String?;
          if (endoStr != null && endoStr != 'Not set') {
            try {
              final endoDate = DateFormat('yyyy-MM-dd').parseStrict(endoStr);
              final reminderDay = _reminderDayFor(endoDate, today);

              String? endoMsg;
              String? endoReminderType;

              final endoCycleKey =
                  "${endoDate.year}_${endoDate.month}_${endoDate.day}";
              if (reminderDay == 7) {
                endoMsg =
                    "Dear $name, this is a courtesy notice from Neithans. Your lease contract is set to end on $endoStr. Please coordinate with your landlord regarding renewal or move-out arrangements at your earliest convenience. We sincerely appreciate your stay with us.";
                endoReminderType = "endo_7_$endoCycleKey";
              } else if (reminderDay == 3) {
                endoMsg =
                    "Dear $name, a gentle reminder that your lease contract expires on $endoStr. Please finalize your arrangements with your landlord for renewal or unit turnover. We value your tenancy and hope to continue serving you. Thank you.";
                endoReminderType = "endo_3_$endoCycleKey";
              } else if (reminderDay == 0) {
                endoMsg =
                    "Dear $name, this is to inform you that your lease contract with Neithans concludes today, $endoStr. We sincerely thank you for your stay and hope your experience has been a pleasant one. Should you wish to renew, please do not hesitate to reach out to your landlord. Take care and all the best.";
                endoReminderType = "endo_0_$endoCycleKey";
              }

              if (endoMsg != null && endoReminderType != null) {
                final alreadySent =
                    await DBService.wasReminderSent(tenantId, endoReminderType);
                if (!alreadySent) {
                  final success =
                      await SmsService.sendSms(to: phone, message: endoMsg);
                  if (success) {
                    await DBService.markReminderSent(
                        tenantId, endoReminderType);
                    debugPrint(
                        "Endo SMS to $name ($reminderDay-day reminder): SUCCESS");
                  }
                }
              }
            } catch (e) {
              debugPrint("Error processing endo reminder for $name: $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Background Task Error: $e");
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return Material(
      child: Container(
        alignment: Alignment.center,
        color: const Color(0xFF8B6E5C),
        padding: const EdgeInsets.all(32),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 64),
            SizedBox(height: 20),
            Text(
              'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none),
            ),
            SizedBox(height: 12),
            Text(
              'Please restart the app. If the problem persists, contact support.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  decoration: TextDecoration.none),
            ),
          ],
        ),
      ),
    );
  };

  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

  if (!kIsWeb) {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      "1",
      automatedReminderTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  runApp(NeithansApp(firebaseInitialized: firebaseInitialized));
}

class NeithansApp extends StatelessWidget {
  final bool firebaseInitialized;
  const NeithansApp({super.key, required this.firebaseInitialized});

  @override
  Widget build(BuildContext context) {
    if (!firebaseInitialized) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Database initialization failed.'),
                ElevatedButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Close')),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        Provider(
            create: (_) => AuthService(),
            dispose: (_, AuthService auth) => auth.dispose()),
        Provider(create: (_) => SyncService()),
      ],
      child: MaterialApp(
        title: 'Neithans',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFFF5F2),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6E5C)),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFFF5F2),
            centerTitle: true,
            titleTextStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF2D1F1D)),
          ),
        ),
        home: const Root(),
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          final data =
              MediaQueryData.fromView(PlatformDispatcher.instance.views.first);
          return MediaQuery(
            data: data.copyWith(textScaler: TextScaler.noScaling),
            child: child,
          );
        },
        routes: {
          '/owner': (_) => const OwnerHomeScreen(),
          '/superadmin': (_) => const SuperadminDashboard(),
          '/tenants': (_) => const TenantsListScreen(),
          '/violations': (_) => const ViolationsDashboard(),
        },
      ),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String? _lastSyncedUid;

  void _triggerSync(BuildContext context, String uid) {
    if (_lastSyncedUid == uid) return;
    _lastSyncedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sync = Provider.of<SyncService>(context, listen: false);
      sync.syncAll(uid).then((_) {
        sync.startRealtimeSync(uid);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<AuthState>(
      stream: auth.authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final authState = snapshot.data;
        if (authState == null || !authState.signedIn) {
          if (_lastSyncedUid != null) {
            final sync = Provider.of<SyncService>(context, listen: false);
            sync.stopAllListeners();
          }
          _lastSyncedUid = null;
          return const LoginScreen();
        }

        if (authState.uid != null) _triggerSync(context, authState.uid!);

        if (authState.role == 'superadmin') {
          return const SuperadminDashboard();
        } else {
          return const OwnerHomeScreen();
        }
      },
    );
  }
}
