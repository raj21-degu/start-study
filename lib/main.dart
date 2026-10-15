import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const StartStudyApp());
}

class StartStudyApp extends StatelessWidget {
  const StartStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00C896),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0F14),
            cardTheme: const CardThemeData(
        color: Color(0xFF141A21),
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'Start Study',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
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
  StudyStore(this.prefs);

  final SharedPreferences prefs;

  List<StudySession> loadSessions() {
    try {
      final raw = prefs.getString('sessions') ?? '[]';
      final decoded = jsonDecode(raw) as List;

      final sessions = <StudySession>[];

      for (final item in decoded) {
        sessions.add(
          StudySession.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        );
      }

      return sessions;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSessions(List<StudySession> sessions) async {
    final list = <Map<String, dynamic>>[];

    for (final session in sessions) {
      list.add(session.toMap());
    }

    await prefs.setString('sessions', jsonEncode(list));
  }

  int getDailyGoalMinutes() {
    return prefs.getInt('dailyGoalMinutes') ?? 180;
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
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final studyStore = StudyStore(prefs);

    if (!mounted) return;

    setState(() {
      store = studyStore;
      sessions = studyStore.loadSessions();
      ready = true;
    });
  }

  int getDuration() {
    if (onBreak) {
      return breakMinutes * 60;
    }

    return focusMinutes * 60;
  }

  int getTodaySeconds() {
    final now = DateTime.now();
    int total = 0;

    for (final session in sessions) {
      if (session.date.year == now.year &&
          session.date.month == now.month &&
          session.date.day == now.day) {
        total = total + session.seconds;
      }
    }

    return total;
  }

  int getStreak() {
    int count = 0;
    final today = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      int daySeconds = 0;

      for (final session in sessions) {
        if (session.date.year == day.year &&
            session.date.month == day.month &&
            session.date.day == day.day) {
          daySeconds = daySeconds + session.seconds;
        }
      }

      if (daySeconds > 0) {
        count++;
      } else if (i > 0) {
        break;
      }
    }

    return count;
  }

  String formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    final twoDigits =
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';

    if (hours > 0) {
      return '$hours:$twoDigits';
    }

    return twoDigits;
  }

  void updateTimer() {
    if (!running || started == null) return;

    final now = DateTime.now();
    final seconds =
        accumulated + now.difference(started!).inSeconds;

    if (mode != 'Stopwatch' && seconds >= getDuration()) {
      finishSession();
    } else {
      setState(() {
        elapsed = seconds;
      });
    }
  }

  void startTimer() {
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
        updateTimer();
      },
    );
  }

  void pauseTimer() {
    if (!running) return;

    updateTimer();

    if (!running) return;

    ticker?.cancel();
    accumulated = elapsed;
    started = null;

    setState(() {
      running = false;
    });
  }

  void resetTimer() {
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

    await store!.saveSessions(sessions);
  }

  void finishSession() {
    ticker?.cancel();

    final wasBreak = onBreak;

    if (!wasBreak) {
      int seconds;

      if (mode == 'Stopwatch') {
        seconds = elapsed;
      } else {
        seconds = getDuration();
      }

      saveSession(seconds);
    }

    setState(() {
      running = false;
      elapsed = 0;
      accumulated = 0;
      started = null;

      if (mode == 'Pomodoro' && !wasBreak) {
        onBreak = true;
      } else {
        onBreak = false;
      }
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

    int displaySeconds;

    if (mode == 'Stopwatch') {
      displaySeconds = elapsed;
    } else {
      final remaining = getDuration() - elapsed;

      if (remaining < 0) {
        displaySeconds = 0;
      } else {
        displaySeconds = remaining;
      }
    }

    final goalMinutes = store?.getDailyGoalMinutes() ?? 180;
    final goalSeconds = goalMinutes * 60;
    final todaySeconds = getTodaySeconds();

    double progress = 0;

    if (goalSeconds > 0) {
      progress = todaySeconds / goalSeconds;
    }

    if (progress > 1) {
      progress = 1;
    }

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
                  '${getStreak()}',
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
                              formatTime(todaySeconds),
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
                              value: progress,
                              strokeWidth: 7,
                              backgroundColor: Colors.white12,
                            ),
                            Text(
                              '${(progress * 100).round()}%',
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
                    formatTime(displaySeconds),
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
            items: const [
              DropdownMenuItem(
                value: 'Pomodoro',
                child: Text('Pomodoro'),
              ),
              DropdownMenuItem(
                value: 'Timer',
                child: Text('Timer'),
              ),
              DropdownMenuItem(
                value: 'Stopwatch',
                child: Text('Stopwatch'),
              ),
            ],
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
            items: subjects.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item),
              );
            }).toList(),
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
                  onPressed: running ? pauseTimer : startTimer,
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
                  onPressed: resetTimer,
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
                      pauseTimer();
                      finishSession();
                    },
              child: const Text('Save stopwatch session'),
            ),
          const SizedBox(height: 24),
          const Text(
            'Strict Mode records completed focus sessions and helps you stay accountable.',
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
    loadData();
  }

    Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final studyStore = StudyStore(prefs);

    if (!mounted) return;

    setState(() {
      sessions = studyStore.loadSessions();
      ready = true;
    });
  }

  int getSecondsForDay(DateTime day) {
    int total = 0;

    for (final session in sessions) {
      if (session.date.year == day.year &&
          session.date.month == day.month &&
          session.date.day == day.day) {
        total = total + session.seconds;
      }
    }

    return total;
  }

  String formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    final twoDigits =
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';

    if (hours > 0) {
      return '$hours:$twoDigits';
    }

    return twoDigits;
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final today = DateTime.now();
    final days = <DateTime>[];
    final values = <int>[];

    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      days.add(day);
      values.add(getSecondsForDay(day));
    }

    int maxValue = 1;

    for (final value in values) {
      if (value > maxValue) {
        maxValue = value;
      }
    }

    final totals = <String, int>{};

    for (final session in sessions) {
      totals[session.subject] =
          (totals[session.subject] ?? 0) + session.seconds;
    }

    final subjectNames = totals.keys.toList();

    subjectNames.sort((a, b) {
      return (totals[b] ?? 0).compareTo(totals[a] ?? 0);
    });

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your progress',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last 7 days'),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (int i = 0; i < 7; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: 20 +
                                        values[i] / maxValue * 90,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ][days[i].weekday - 1],
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subject totals'),
                  const SizedBox(height: 12),
                  if (subjectNames.isEmpty)
                    const Text('No study data yet.'),
                  for (final name in subjectNames.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.school_outlined),
                      title: Text(name),
                      trailing: Text(
                        formatTime(totals[name] ?? 0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HistoryView();
  }
}

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  List<StudySession> sessions = [];
  bool ready = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final studyStore = StudyStore(prefs);

    if (!mounted) return;

    setState(() {
      sessions = studyStore.loadSessions();
      ready = true;
    });
  }

  String formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    final twoDigits =
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';

    if (hours > 0) {
      return '$hours:$twoDigits';
    }

    return twoDigits;
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Session history',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 20),
          if (sessions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No sessions yet. Start a focus session to build your history.',
                ),
              ),
            ),
          for (final session in sessions.take(100))
            Card(
              child: ListTile(
                leading: Icon(
                  session.strict
                      ? Icons.lock_outline
                      : Icons.menu_book_outlined,
                ),
                title: Text(session.subject),
                subtitle: Text(
                  '${session.date.day}/${session.date.month}/${session.date.year}'
                  '${session.strict ? ' • Strict' : ''}',
                ),
                trailing: Text(
                  formatTime(session.seconds),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
