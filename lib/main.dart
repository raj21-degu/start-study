import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const StudyApp());

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Start Study',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const StudyHome(),
    );
  }
}

class StudyHome extends StatefulWidget {
  const StudyHome({super.key});

  @override
  State<StudyHome> createState() => _StudyHomeState();
}

class _StudyHomeState extends State<StudyHome> {
  final subjects = [
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
  bool ready = false;

  DateTime? started;
  Timer? ticker;
  SharedPreferences? storage;
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> saved = [];
    try {
      final decoded = jsonDecode(prefs.getString('history') ?? '[]');
      saved = (decoded as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      saved = [];
    }
    if (!mounted) return;
    setState(() {
      storage = prefs;
      history = saved;
      ready = true;
    });
  }

  int get duration =>
      (onBreak ? breakMinutes : focusMinutes) * 60;

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
      setState(() => elapsed = seconds);
    }
  }

  void start() {
    if (running || !ready) return;
    started = DateTime.now();
    setState(() => running = true);
    ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => refresh(),
    );
  }

  void pause() {
    if (!running) return;
    refresh();
    if (!running) return;
    ticker?.cancel();
    accumulated = elapsed;
    started = null;
    setState(() => running = false);
  }

  void reset() {
    ticker?.cancel();
    setState(() {
      running = false;
      onBreak = false;
      elapsed = 0;
      accumulated = 0;
      started = null;
    });
  }

  Future<void> record(int seconds) async {
    if (seconds < 1) return;
    setState(() {
      history.insert(0, {
        'subject': subject,
        'seconds': seconds,
        'date': DateTime.now().toIso8601String(),
      });
    });
    await storage?.setString('history', jsonEncode(history));
  }

  void finish() {
    ticker?.cancel();
    final wasBreak = onBreak;
    if (!wasBreak) {
      record(mode == 'Stopwatch' ? elapsed : duration);
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
              ? 'Break finished. Ready to study?'
              : 'Session saved. Well done!',
        ),
      ),
    );
  }

  int get todaySeconds {
    final now = DateTime.now();
    return history.where((entry) {
      final date = DateTime.parse(entry['date'] as String);
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).fold<int>(
      0,
      (total, entry) => total + (entry['seconds'] as int),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Study'),
        centerTitle: true,
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Small steps. Stronger focus.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('Study time today'),
                        Text(
                          clock(todaySeconds),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium,
                        ),
                        Text('${history.length} saved sessions'),
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
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: locked
                      ? null
                      : (value) => setState(() => mode = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: subject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                  items: subjects
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: locked
                      ? null
                      : (value) => setState(() => subject = value!),
                ),
                if (mode != 'Stopwatch') ...[
                  const SizedBox(height: 16),
                  Text('Focus: $focusMinutes minutes'),
                  Slider(
                    value: focusMinutes.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    label: '$focusMinutes min',
                    onChanged: locked
                        ? null
                        : (value) => setState(
                              () => focusMinutes = value.round(),
                            ),
                  ),
                ],
                if (mode == 'Pomodoro') ...[
                  Text('Break: $breakMinutes minutes'),
                  Slider(
                    value: breakMinutes.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$breakMinutes min',
                    onChanged: locked
                        ? null
                        : (value) => setState(
                              () => breakMinutes = value.round(),
                            ),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 12,
                    ),
                    child: Column(
                      children: [
                        Text(onBreak ? 'Take a break' : subject),
                        const SizedBox(height: 12),
                        Text(
                          clock(display),
                          style: Theme.of(context)
                              .textTheme
                              .displayLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: running ? pause : start,
                        icon: Icon(
                          running ? Icons.pause : Icons.play_arrow,
                        ),
                        label: Text(running ? 'Pause' : 'Start'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
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
                Text(
                  'Recent sessions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Your completed sessions will appear here.',
                    ),
                  ),
                ...history.take(20).map((entry) {
                  final date =
                      DateTime.parse(entry['date'] as String);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(entry['subject'] as String),
                    subtitle: Text(
                      '${date.day}/${date.month}/${date.year}',
                    ),
                    trailing: Text(
                      clock(entry['seconds'] as int),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Text(
                  'Free • No ads • No subscriptions
'
                  'Keep the app open while studying in this version.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}
