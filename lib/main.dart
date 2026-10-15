import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const StartStudyApp());

class StartStudyApp extends StatelessWidget {
  const StartStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00C896),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0F14),
      cardTheme: const CardTheme(
        color: Color(0xFF141A21),
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'Start Study',
      debugShowCheckedModeBanner: false,
      theme: dark,
      darkTheme: dark,
      themeMode: ThemeMode.dark,
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: page,
        children: const [
          FocusScreen(),
          StatsScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) {
          setState(() {
            page = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Focus',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}

class StudySession {
  StudySession({
    required this.subject,
    required this.seconds,
    required this.date,
    required this.strict,
  });

  final String subject;
  final int seconds;
  final DateTime date;
  final bool strict;

  Map<String, dynamic> toMap() {
    return {
      'subject': subject,
      'seconds': seconds,
      'date': date.toIso8601String(),
      'strict': strict,
    };
  }

  static StudySession fromMap(Map<String, dynamic> map) {
    return StudySession(
      subject: map['subject'] as String? ?? 'Other',
      seconds: map['seconds'] as int? ?? 0,
      date: DateTime.tryParse(map['date'] as String? ?? '') ??
          DateTime.now(),
      strict: map['strict'] as bool? ?? false,
    );
  }
}

class StudyStore {
  StudyStore(this._prefs);

  final SharedPreferences _prefs;

  List<StudySession> load() {
    try {
      final raw = _prefs.getString('sessions') ?? '[]';
      final decoded = jsonDecode(raw) as List;

      return decoded
          .map(
            (item) => StudySession.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<StudySession> sessions) async {
    final encoded = jsonEncode(
      sessions.map((session) => session.toMap()).toList(),
    );

    await _prefs.setString('sessions', encoded);
  }

  int get dailyGoalMinutes {
    return _prefs.getInt('dailyGoalMinutes') ?? 180;
  }

  Future<void> setDailyGoalMinutes(int minutes) async {
    await _prefs.setInt('dailyGoalMinutes', minutes);
  }
}

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final List<String> subjects = [
    'History',
    'Political Science',
    'Geography',
    'English',
    'Hindi',
    'Physics',
    'Chemistry',
    'Maths',
    'Biology',
    'Other',
  ];

  String subject = 'History';
  String mode = 'Pomodoro';
  int focusMinutes = 25;
  int breakMinutes = 5;
  int elapsed = 0;
  int accumulated = 0;
  bool running = false;
  bool onBreak = false;
  bool strictMode = false;
  bool ready = false;

  DateTime? started;
  Timer? ticker;
  StudyStore? store;
  List<StudySession> sessions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final studyStore = StudyStore(prefs);

    if (!mounted) return;

    setState(() {
      store = studyStore;
      sessions = studyStore.load();
      ready = true;
    });
  }

  int get duration {
    return (onBreak ? breakMinutes : focusMinutes) * 60;
  }

  int get todaySeconds {
    final now = DateTime.now();

    return sessions
        .where(
          (session) =>
              session.date.year == now.year &&
              session.date.month == now.month &&
              session.date.day == now.day,
        )
        .fold<int>(0, (total, session) => total + session.seconds);
  }

  int get streak {
    int count = 0;
    final today = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final day = today.subtract(Duration(days: i));

      final seconds = sessions
          .where(
            (session) =>
                session.date.year == day.year &&
                session.date.month == day.month &&
                session.date.day == day.day,
          )
          .fold<int>(0, (total, session) => total + session.seconds);

      if (seconds > 0) {
        count++;
      } else if (i > 0) {
        break;
      }
    }

    return count;
  }

  String clock(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    final result =
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';

    return hours > 0 ? '$hours:$result' : result;
  }

  void refresh() {
    final anchor = started;

    if (!running || anchor == null) return;

    final seconds =
        accumulated + DateTime.now().difference(anchor).inSeconds;

    if (mode != 'Stopwatch' && seconds >= duration) {
      finish();
    } else {
      setState(() {
        elapsed = seconds;
      });
    }
  }

  void start() {
    if (running || !ready) return;

    if (strictMode && elapsed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Strict Mode is on. Complete the session or reset before leaving.',
          ),
        ),
      );
    }

    started = DateTime.now();

    setState(() {
      running = true;
    });

    ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        refresh();
      },
    );
  }

  void pause() {
    if (!running) return;

    refresh();

    if (!running) return;

    ticker?.cancel();
    accumulated = elapsed;
    started = null;

    setState(() {
      running = false;
    });
  }

  void reset() {
    if (strictMode && running && elapsed > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Strict session abandoned. Try a shorter focus round next time.',
          ),
        ),
      );
    }

    ticker?.cancel();

    setState(() {
      running = false;
      onBreak = false;
      elapsed = 0;
      accumulated = 0;
      started = null;
    });
  }

  Future<void> saveSession(int seconds) async {
    if (seconds < 1 || store == null) return;

    final session = StudySession(
      subject: subject,
      seconds: seconds,
      date: DateTime.now(),
      strict: strictMode,
    );

    setState(() {
      sessions.insert(0, session);
    });

    await store!.save(sessions);
  }

  void finish() {
    ticker?.cancel();

    final wasBreak = onBreak;

    if (!wasBreak) {
      final seconds = mode == 'Stopwatch' ? elapsed : duration;
      saveSession(seconds);
    }

    setState(() {
      running = false;
      elapsed = 0;
      accumulated = 0;
      started = null;
      onBreak = mode == 'Pomodoro' && !wasBreak;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasBreak
              ? 'Break complete. Start your next focus round.'
              : 'Session saved. Keep the streak alive!',
        ),
      ),
    );
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = running || elapsed > 0 || onBreak;

    final display = mode == 'Stopwatch'
        ? elapsed
        : (duration - elapsed).clamp(0, duration).toInt();

    final goalSeconds = (store?.dailyGoalMinutes ?? 180) * 60;
    final goalProgress =
        goalSeconds == 0 ? 0.0 : todaySeconds / goalSeconds;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus mode',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      'Take back your study time.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    Theme.of(context).colorScheme.primary,
                child: Text(
                  '$streak',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('Today'),
                            Text(
                              clock(todaySeconds),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: goalProgress.clamp(0.0, 1.0),
                              strokeWidth: 7,
                              backgroundColor: Colors.white12,
                            ),
                            Text(
                              '${(goalProgress.clamp(0.0, 1.0) * 100).round()}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Strict Mode'),
                    subtitle: const Text(
                      'Discourage quitting a focus session early.',
                    ),
                    value: strictMode,
                    onChanged: running
                        ? null
                        : (value) {
                            setState(() {
                              strictMode = value;
                            });
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 40,
                horizontal: 20,
              ),
              child: Column(
                children: [
                  Text(
                    onBreak ? 'BREAK' : subject.toUpperCase(),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          letterSpacing: 2,
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    clock(display),
                    style: Theme.of(context)
                        .textTheme
                        .displayLarge
                        ?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mode == 'Stopwatch'
                        ? 'Stopwatch running'
                        : onBreak
                            ? 'Rest and recover'
                            : '$focusMinutes minute focus round',
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: mode,
            decoration: const InputDecoration(
              labelText: 'Mode',
              border: OutlineInputBorder(),
            ),
            items: ['Pomodoro', 'Timer', 'Stopwatch']
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(),
            onChanged: locked
                ? null
                : (value) {
                    setState(() {
                      mode = value!;
                    });
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: subject,
            decoration: const InputDecoration(
              labelText: 'Subject',
              border: OutlineInputBorder(),
            ),
            items: subjects
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(),
            onChanged: locked
                ? null
                : (value) {
                    setState(() {
                      subject = value!;
                    });
                  },
          ),
          if (mode != 'Stopwatch') ...[
            const SizedBox(height: 16),
            Text('Focus length: $focusMinutes minutes'),
            Slider(
              value: focusMinutes.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              label: '$focusMinutes min',
              onChanged: locked
                  ? null
                  : (value) {
                      setState(() {
                        focusMinutes = value.round();
                      });
                    },
            ),
          ],
          if (mode == 'Pomodoro') ...[
            Text('Break length: $breakMinutes minutes'),
            Slider(
              value: breakMinutes.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '$breakMinutes min',
              onChanged: locked
                  ? null
                  : (value) {
                      setState(() {
                        breakMinutes = value.round();
                      });
                    },
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    backgroundColor:
                        Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: running ? pause : start,
                  icon: Icon(
                    running ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(
                    running ? 'Pause' : 'Start focus',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                  ),
                  onPressed: reset,
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
          if (mode == 'Stopwatch')
            TextButton(
              onPressed: elapsed == 0
                  ? null
                  : () {
                      pause();
                      finish();
                    },
              child: const Text('Save stopwatch session'),
            ),
          const SizedBox(height: 24),
          const Text(
            'Strict Mode records abandoned sessions. Full distraction blocking needs native Android permissions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatsView();
  }
}

class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  List<StudySession> sessions = [];
  bool ready = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final studyStore = StudyStore(prefs);

    if (!mounted) return;

    setState(() {
      sessions = studyStore.load();
      ready = true;
    });
  }

  int secondsForDay(DateTime day) {
    return sessions
        .where(
          (session) =>
              session.date.year == day.year &&
 
