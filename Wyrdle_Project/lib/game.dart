import 'dart:collection';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

const defaultNumGuesses = 6;
enum HitType { none, hit, partial, miss, removed }
typedef Letter = ({String char, HitType type});

class Game {
  Map<String, HitType> letterStatus = {};
  int streak = 0;
  int bestStreak = 0;
  int totalGuessedCount = 0;
  Set<String> solvedWords = {};
  String lastPlayedWord = "";

  // Persistence fields
  List<String> currentGuessStrings = []; // New: Stores just the words guessed so far

  List<String> easyLibrary = [];
  List<String> hardLibrary = [];
  late final int numAllowedGuesses;
  late List<Word> _guesses;
  Word _wordToGuess = Word.empty();

  Game({this.numAllowedGuesses = defaultNumGuesses}) {
    _guesses = List<Word>.filled(numAllowedGuesses, Word.empty());
  }

  // --- STORAGE & LOADING ---

  Future<void> loadLibrary() async {
    final String easyData = await rootBundle.loadString('assets/easy_words.txt');
    easyLibrary = easyData.split('\n')
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length == 5)
        .toList();

    final String hardData = await rootBundle.loadString('assets/hard_words.txt');
    hardLibrary = hardData.split('\n')
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.length == 5)
        .toList();

    // After library is loaded, check if we have a game to resume
    await loadGameState();
  }

  Future<void> saveGameState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_streak', streak);
    await prefs.setInt('best_streak', bestStreak);
    await prefs.setStringList('solved_words', solvedWords.toList());

    // Save active game state
    // If the game is over (win or lose), we save empty values to clear progress on next boot
    if (didWin || didLose) {
      await prefs.remove('active_word');
      await prefs.remove('active_guesses');
    } else {
      await prefs.setString('active_word', _wordToGuess.toString());
      await prefs.setStringList('active_guesses', currentGuessStrings);
    }
  }

  Future<void> loadGameState() async {
    final prefs = await SharedPreferences.getInstance();
    streak = prefs.getInt('user_streak') ?? 0;
    bestStreak = prefs.getInt('best_streak') ?? 0;
    solvedWords = (prefs.getStringList('solved_words') ?? []).toSet();
    totalGuessedCount = solvedWords.length;

    String? savedWord = prefs.getString('active_word');
    List<String> savedGuesses = prefs.getStringList('active_guesses') ?? [];

    if (savedWord != null && savedWord.isNotEmpty) {
      // RESUME GAME
      _wordToGuess = Word.fromString(savedWord);
      _guesses = List.filled(numAllowedGuesses, Word.empty());
      currentGuessStrings = []; // Clear and rebuild
      letterStatus = {};

      for (String g in savedGuesses) {
        // Re-run the guess logic to populate UI and keyboard colors
        _internalGuess(g);
      }
    } else {
      // START FRESH
      resetGame();
    }
  }

  // --- GAME LOGIC ---

  void resetGame() {
    if (_wordToGuess.isNotEmpty) {
      lastPlayedWord = _wordToGuess.toString();
    }

    if (didLose) {
      streak = 0;
    }

    letterStatus = {};
    currentGuessStrings = []; // Clear for new game
    _guesses = List.filled(numAllowedGuesses, Word.empty());

    bool shouldBeHard = (streak >= 300) || (streak > 0 && streak % 10 == 0);
    String chosen = "";
    int attempts = 0;

    if (shouldBeHard && hardLibrary.isNotEmpty) {
      do {
        chosen = hardLibrary[Random().nextInt(hardLibrary.length)];
        attempts++;
      } while ((solvedWords.contains(chosen) || chosen == lastPlayedWord) && attempts < 100);
    } else if (easyLibrary.isNotEmpty) {
      do {
        chosen = easyLibrary[Random().nextInt(easyLibrary.length)];
        attempts++;
      } while ((solvedWords.contains(chosen) || chosen == lastPlayedWord) && attempts < 100);
    }

    if (chosen.isEmpty && easyLibrary.isNotEmpty) {
      chosen = easyLibrary[Random().nextInt(easyLibrary.length)];
    }

    _wordToGuess = Word.fromString(chosen);
    saveGameState(); // Save that a new word was picked
  }

  // This handles the logic without calling saveGameState to avoid loops during loading
  void _internalGuess(String guessText) {
    final result = matchGuessOnly(guessText);
    for (var letter in result) {
      String char = letter.char.toLowerCase();
      if (letter.type == HitType.hit) {
        letterStatus[char] = HitType.hit;
      } else if (letter.type == HitType.partial) {
        if (letterStatus[char] != HitType.hit) {
          letterStatus[char] = HitType.partial;
        }
      } else if (letter.type == HitType.miss) {
        if (!letterStatus.containsKey(char)) {
          letterStatus[char] = HitType.miss;
        }
      }
    }
    addGuessToList(result);
    currentGuessStrings.add(guessText);
  }

  Word guess(String guessText) {
    _internalGuess(guessText);

    if (didWin) {
      streak++;
      solvedWords.add(_wordToGuess.toString());
      totalGuessedCount = solvedWords.length;
    }

    saveGameState(); // Persist every guess
    return _guesses[activeIndex - 1];
  }

  bool isLegalGuess(String guess) {
    String g = guess.toLowerCase().trim();
    return easyLibrary.contains(g) || hardLibrary.contains(g);
  }

  Word get hiddenWord => _wordToGuess;
  UnmodifiableListView<Word> get guesses => UnmodifiableListView(_guesses);
  Word get previousGuess {
    final index = _guesses.lastIndexWhere((word) => word.isNotEmpty);
    return index == -1 ? Word.empty() : _guesses[index];
  }
  int get activeIndex => _guesses.indexWhere((word) => word.isEmpty);
  int get guessesRemaining => activeIndex == -1 ? 0 : numAllowedGuesses - activeIndex;
  bool get didWin => _guesses.any((w) => w.isNotEmpty && w.every((l) => l.type == HitType.hit));
  bool get didLose => guessesRemaining == 0 && !didWin;

  Word matchGuessOnly(String guess) {
    var hiddenCopy = Word.fromString(_wordToGuess.toString());
    return Word.fromString(guess).evaluateGuess(hiddenCopy);
  }

  void addGuessToList(Word guess) {
    final i = _guesses.indexWhere((word) => word.isEmpty);
    if (i != -1) _guesses[i] = guess;
  }
}

// ... (Word and WordUtils classes remain the same)
class Word with IterableMixin<Letter> {
  Word(this._letters);
  factory Word.empty() => Word(List.filled(5, (char: '', type: HitType.none)));
  factory Word.fromString(String guess) {
    var list = guess.toLowerCase().split('');
    var letters = list.map((String char) => (char: char, type: HitType.none)).toList();
    return Word(letters);
  }
  final List<Letter> _letters;
  @override
  Iterator<Letter> get iterator => _letters.iterator;
  @override
  bool get isEmpty => every((letter) => letter.char.isEmpty);
  @override
  bool get isNotEmpty => !isEmpty;
  Letter operator [](int i) => _letters[i];
  operator []=(int i, Letter value) => _letters[i] = value;
  @override
  String toString() => _letters.map((Letter c) => c.char).join().trim();
}

extension WordUtils on Word {
  Word evaluateGuess(Word other) {
    for (var i = 0; i < length; i++) {
      if (other[i].char == this[i].char) {
        this[i] = (char: this[i].char, type: HitType.hit);
        other[i] = (char: other[i].char, type: HitType.removed);
      }
    }
    for (var i = 0; i < other.length; i++) {
      Letter targetLetter = other[i];
      if (targetLetter.type != HitType.none) continue;
      for (var j = 0; j < length; j++) {
        Letter guessedLetter = this[j];
        if (guessedLetter.type != HitType.none) continue;
        if (guessedLetter.char == targetLetter.char) {
          this[j] = (char: guessedLetter.char, type: HitType.partial);
          other[i] = (char: targetLetter.char, type: HitType.removed);
          break;
        }
      }
    }
    for (var i = 0; i < length; i++) {
      if (this[i].type == HitType.none) this[i] = (char: this[i].char, type: HitType.miss);
    }
    return this;
  }
}