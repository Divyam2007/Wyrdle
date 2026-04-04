import 'package:flutter/material.dart';
import 'game.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isDarkMode = true;
  final Game _game = Game();

  // --- Music Setup ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playerSubscription;
  final List<String> _playlist = [
    'music/The_Sunday_Pattern.mp3',
    'music/The_Unresolved_Room.mp3',
    'music/The_Geometry_Of_Focus.mp3',
  ];
  int _currentTrackIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPlaylist();
  }

  void _startPlaylist() {
    // Listen for the end of a track to trigger the next one
    _playerSubscription = _audioPlayer.onPlayerComplete.listen((_) => _playNext());
    _playTrack(_currentTrackIndex);
  }

  Future<void> _playTrack(int index) async {
    // In audioplayers 6.x, AssetSource automatically looks in the assets folder
    await _audioPlayer.play(AssetSource(_playlist[index]));
  }

  void _playNext() {
    _currentTrackIndex = (_currentTrackIndex + 1) % _playlist.length;
    _playTrack(_currentTrackIndex);
  }

  // --- Background/Foreground Logic ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _audioPlayer.pause(); // Stop music when in background
    } else if (state == AppLifecycleState.resumed) {
      _audioPlayer.resume(); // Continue from where it left off
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: SplashScreen(
        game: _game,
        isDarkMode: _isDarkMode,
        onThemeToggle: () => setState(() => _isDarkMode = !_isDarkMode),
      ),
    );
  }
}

class MainPager extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final Game game;

  const MainPager({super.key, required this.isDarkMode, required this.onThemeToggle, required this.game});

  @override
  Widget build(BuildContext context) {
    return PageView(
      children: [
        GamePage(game: game, isDarkMode: isDarkMode, onThemeToggle: onThemeToggle),
        SolvedPage(game: game),
      ],
    );
  }
}

class GamePage extends StatefulWidget {
  final Game game;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  const GamePage({super.key, required this.game, required this.isDarkMode, required this.onThemeToggle});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  void _handleGuess() {
    final guess = _controller.text;
    if (widget.game.isLegalGuess(guess)) {
      setState(() {
        widget.game.guess(guess);
        _controller.clear();
        if (widget.game.didWin || widget.game.didLose) _showGameEndPopup();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not in word list!"), duration: Duration(seconds: 1)));
    }
  }

  void _showGameEndPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(widget.game.didWin ? "You Won! 🥳" : "Game Over 🥺"),
        content: Text("Word: ${widget.game.hiddenWord.toString().toUpperCase()}"),
        actions: [TextButton(onPressed: () { setState(() => widget.game.resetGame()); Navigator.pop(context); }, child: const Text("Play Again"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    bool isBoss = widget.game.streak > 0 && widget.game.streak % 10 == 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 45,
        title: const Text('Wyrdle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline, size: 20), onPressed: () => _showInfoDialog(context)),
          IconButton(icon: Icon(widget.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round, size: 20), onPressed: widget.onThemeToggle),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScoreCol("STREAK", "${widget.game.streak}", Colors.orange.shade700),
                _ScoreCol("BEST", "${widget.game.bestStreak}", Colors.blueAccent),
                _ScoreCol("SOLVED", "${widget.game.totalGuessedCount}", Colors.green.shade600),
              ],
            ),
            if (isBoss) const Padding(padding: EdgeInsets.only(top: 8.0), child: Text("🔥 BOSS LEVEL 🔥", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 14))),
            const SizedBox(height: 12),
            ...widget.game.guesses.map((guess) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: guess.map((l) => Padding(padding: const EdgeInsets.all(1.5), child: Tile(l.char, l.type, isDarkMode: widget.isDarkMode))).toList(),
            )),
            const Spacer(),
            GuessInput(controller: _controller),
            const SizedBox(height: 12),
            VirtualKeyboard(
              isDarkMode: widget.isDarkMode,
              letterStatus: widget.game.letterStatus,
              onKeyTap: (key) {
                if (key == 'ENTER' && _controller.text.length == 5) _handleGuess();
                else if (key == 'BACK' && _controller.text.isNotEmpty) _controller.text = _controller.text.substring(0, _controller.text.length - 1);
                else if (_controller.text.length < 5 && !['ENTER', 'BACK'].contains(key)) _controller.text += key;
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("How to Play"),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Guess the word in 6 tries."),
            _InfoRow(Colors.green, "Correct spot."),
            _InfoRow(Colors.yellow.shade700, "Wrong spot."),
            _InfoRow(Colors.grey, "Not in word."),
            const Divider(),
            const Text("🏆 Every 10th win is a Boss Level!", style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Got it!"))],
      ),
    );
  }
}

class _ScoreCol extends StatelessWidget {
  final String label, value; final Color color;
  const _ScoreCol(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey)),
    Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
  ]);
}

class _InfoRow extends StatelessWidget {
  final Color color; final String text;
  const _InfoRow(this.color, this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(children: [
      Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 12)),
    ]),
  );
}

class SolvedPage extends StatefulWidget {
  final Game game;
  const SolvedPage({super.key, required this.game});
  @override
  State<SolvedPage> createState() => _SolvedPageState();
}

class _SolvedPageState extends State<SolvedPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _highlightedWord = "";

  void _locateWord() {
    final search = _searchController.text.toLowerCase().trim();
    final list = widget.game.solvedWords.toList()..sort();
    int index = list.indexOf(search);
    setState(() => _highlightedWord = index != -1 ? search : "");
    if (index != -1) _scrollController.animateTo(index * 60.0, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCirc);
  }

  @override
  Widget build(BuildContext context) {
    final solvedList = widget.game.solvedWords.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text("Solved History", style: TextStyle(fontSize: 18))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(hintText: "Locate word...", suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _locateWord), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              onSubmitted: (_) => _locateWord(),
            ),
          ),
          Expanded(
            child: solvedList.isEmpty ? const Center(child: Text("No words solved yet!")) : ListView.builder(
              controller: _scrollController, itemCount: solvedList.length, itemExtent: 60.0,
              itemBuilder: (context, index) {
                final word = solvedList[index];
                bool isTarget = word == _highlightedWord;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: isTarget ? Colors.green.withOpacity(0.8) : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isTarget ? Colors.green : Colors.grey.shade700)),
                  child: ListTile(title: Text(word.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: isTarget ? Colors.white : null))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class Tile extends StatelessWidget {
  final String letter; final HitType hitType; final bool isDarkMode;
  const Tile(this.letter, this.hitType, {super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final colors = {
      HitType.hit: Colors.green,
      HitType.partial: Colors.yellow.shade700,
      HitType.miss: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade600,
      HitType.none: isDarkMode ? Colors.grey.shade900 : Colors.white,
    };

    return Container(
      height: 44, width: 44,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300), color: colors[hitType]),
      child: Center(child: Text(letter.toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (isDarkMode || hitType != HitType.none) ? Colors.white : Colors.black))),
    );
  }
}

class GuessInput extends StatelessWidget {
  final TextEditingController controller;
  const GuessInput({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20.0),
    child: Container(
      height: 40, alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
      child: Text(controller.text.isEmpty ? "TYPE..." : controller.text.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 10)),
    ),
  );
}

class VirtualKeyboard extends StatelessWidget {
  final Map<String, HitType> letterStatus;
  final Function(String) onKeyTap;
  final bool isDarkMode;
  const VirtualKeyboard({super.key, required this.letterStatus, required this.onKeyTap, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final rows = ['qwertyuiop'.split(''), 'asdfghjkl'.split(''), ['ENTER', ...'zxcvbnm'.split(''), 'BACK']];
    return Column(
      children: rows.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((char) {
          Color color = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
          if (letterStatus[char] == HitType.hit) color = Colors.green;
          else if (letterStatus[char] == HitType.partial) color = Colors.yellow.shade700;
          else if (letterStatus[char] == HitType.miss) color = isDarkMode ? Colors.black45 : Colors.grey.shade600;

          return GestureDetector(
            onTap: () => onKeyTap(char),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
              width: (char == 'ENTER' || char == 'BACK') ? 50 : 28, height: 42,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              child: Center(child: char == 'BACK' ? Icon(Icons.backspace_outlined, size: 16) : Text(char.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final Game game; final bool isDarkMode; final VoidCallback onThemeToggle;
  const SplashScreen({super.key, required this.game, required this.isDarkMode, required this.onThemeToggle});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([widget.game.loadLibrary(), Future.delayed(const Duration(milliseconds: 2200))]);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainPager(isDarkMode: widget.isDarkMode, onThemeToggle: widget.onThemeToggle, game: widget.game)));
  }

  @override
  Widget build(BuildContext context) {
    final word = "WYRDLE".split("");
    return Scaffold(
      backgroundColor: widget.isDarkMode ? Colors.black : Colors.white,
      body: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(word.length, (i) => RotatingTile(letter: word[i], delay: Duration(milliseconds: i * 200))))),
    );
  }
}

class RotatingTile extends StatefulWidget {
  final String letter;
  final Duration delay;
  const RotatingTile({super.key, required this.letter, required this.delay});

  @override
  State<RotatingTile> createState() => _RotatingTileState();
}

class _RotatingTileState extends State<RotatingTile> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  late Color _tileColor; // Variable to store the selected random color

  @override
  void initState() {
    super.initState();

    // 1. Define the possible colors
    final List<Color> colorOptions = [
      Colors.green,
      Colors.yellow.shade700,
      Colors.black,
    ];

    // 2. Pick one randomly using the math import already in your file
    _tileColor = colorOptions[math.Random().nextInt(colorOptions.length)];

    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _anim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.785).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: -0.785, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 50),
    ]).animate(_ctrl);

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, _) => Transform.rotate(
      angle: _anim.value,
      alignment: Alignment.bottomLeft,
      child: Container(
        width: 50,
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: _tileColor, // 3. Use the random color here
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            widget.letter,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}