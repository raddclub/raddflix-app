/// Phase F2 — Offline Word Dictionary (English ↔ Urdu)
/// ~400 common English words with Urdu translations + part-of-speech.
/// No internet required. Lookup is O(1) via Dart Map.
/// For unknown words: morphological fallback strips common suffixes.
/// BB10: adds online fallback (dictionaryapi.dev + MyMemory) with session cache.
library word_dict;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Data model ────────────────────────────────────────────────────────────────
class WordEntry {
  final String word;
  final String pos;      // n=noun, v=verb, adj=adjective, adv=adverb, etc.
  final String urdu;     // Urdu script (or translation for online entries)
  final String roman;    // Roman Urdu
  final String example;  // English example sentence (optional)

  // Online-only fields (null for offline entries)
  final String? phonetic;         // e.g. "/lɪv/"
  final String? audioUrl;         // MP3 URL from dictionaryapi.dev (best-effort)
  final List<String> definitions; // English definitions from online API
  final bool isOnline;            // true = fetched from dictionaryapi.dev

  const WordEntry({
    required this.word,
    required this.pos,
    required this.urdu,
    required this.roman,
    this.example = '',
    this.phonetic,
    this.audioUrl,
    this.definitions = const [],
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() =>
      {'word': word, 'pos': pos, 'urdu': urdu, 'roman': roman, 'example': example};
  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
      word: j['word'], pos: j['pos'], urdu: j['urdu'],
      roman: j['roman'], example: j['example'] ?? '');
}

// ── Saved-word model (user vocabulary) ────────────────────────────────────────
class SavedWord {
  final String word;
  final String urdu;
  final String roman;
  final String pos;
  final DateTime savedAt;

  SavedWord({required this.word, required this.urdu, required this.roman,
      required this.pos, required this.savedAt});

  Map<String, dynamic> toJson() => {
    'word': word, 'urdu': urdu, 'roman': roman, 'pos': pos,
    'savedAt': savedAt.toIso8601String(),
  };
  factory SavedWord.fromJson(Map<String, dynamic> j) => SavedWord(
    word: j['word'], urdu: j['urdu'], roman: j['roman'], pos: j['pos'],
    savedAt: DateTime.parse(j['savedAt']));
}

// ── Dictionary service ────────────────────────────────────────────────────────
class WordDict {
  WordDict._();
  static final WordDict instance = WordDict._();

  List<SavedWord> _saved = [];
  bool _savedLoaded = false;

  // Session-scoped online cache — lives for the app process.
  // null value = "looked up, not found online".
  final Map<String, WordEntry?> _onlineCache = {};

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    sendTimeout:    const Duration(seconds: 5),
  ));

  // ── Public API ───────────────────────────────────────────────────────────

  /// Look up a word. Strips punctuation first. Falls back to morphological
  /// root stripping (loves→love, running→run, etc.).
  WordEntry? lookup(String raw) {
    final word = _clean(raw);
    if (word.isEmpty) return null;
    var e = _dict[word];
    if (e != null) return e;
    // Morphological fallback
    for (final candidate in _morphForms(word)) {
      e = _dict[candidate];
      if (e != null) return e;
    }
    return null;
  }

  /// Whether this word exists in the offline dictionary.
  bool contains(String word) => lookup(word) != null;

  /// Whether this word already has a session-cache result (hit or miss).
  bool hasOnlineCacheHit(String word) =>
      _onlineCache.containsKey(_clean(word));

  /// Retrieve the cached online entry (null = "not found online").
  WordEntry? getCachedOnlineEntry(String word) =>
      _onlineCache[_clean(word)];

  /// Look up a word online via dictionaryapi.dev + MyMemory translation.
  /// Caches result per session. Returns null if not found or device is offline.
  Future<WordEntry?> lookupOnline(String raw,
      {String targetLang = 'ur'}) async {
    final word = _clean(raw);
    if (word.isEmpty) return null;

    // Return cached result immediately (null = known miss).
    if (_onlineCache.containsKey(word)) return _onlineCache[word];

    try {
      // 1. Fetch English definition from dictionaryapi.dev (free, no key).
      final defRes = await _dio.get(
          'https://api.dictionaryapi.dev/api/v2/entries/en/$word');
      if (defRes.statusCode != 200) {
        _onlineCache[word] = null;
        return null;
      }
      final data = defRes.data;
      if (data is! List || data.isEmpty) {
        _onlineCache[word] = null;
        return null;
      }

      final first = data[0] as Map<String, dynamic>;

      // Extract phonetic + audio URL.
      String? phonetic;
      String? audioUrl;
      final phonetics = (first['phonetics'] as List? ?? []);
      for (final ph in phonetics) {
        final m = ph as Map<String, dynamic>;
        phonetic ??= m['text'] as String?;
        final url = m['audio'] as String? ?? '';
        if (audioUrl == null && url.isNotEmpty) audioUrl = url;
      }
      phonetic ??= first['phonetic'] as String?;

      // Extract part-of-speech + definitions (up to 3 distinct).
      final meanings = (first['meanings'] as List? ?? []);
      String pos = 'n';
      final defs = <String>[];
      for (final meaning in meanings.take(2)) {
        final m = meaning as Map<String, dynamic>;
        final partOfSpeech = m['partOfSpeech'] as String? ?? '';
        if (defs.isEmpty) {
          if (partOfSpeech.startsWith('verb'))      pos = 'v';
          else if (partOfSpeech.startsWith('adj'))  pos = 'adj';
          else if (partOfSpeech.startsWith('adv'))  pos = 'adv';
        }
        for (final d in (m['definitions'] as List? ?? []).take(2)) {
          final def = (d as Map<String, dynamic>)['definition'] as String? ?? '';
          if (def.isNotEmpty && defs.length < 3) defs.add(def);
        }
      }

      // 2. Fetch translation from MyMemory (free, no key, 5k chars/day).
      String translation = '';
      try {
        final transRes = await _dio.get(
            'https://api.mymemory.translated.net/get',
            queryParameters: {'q': word, 'langpair': 'en|$targetLang'});
        if (transRes.statusCode == 200) {
          final tData = transRes.data as Map<String, dynamic>;
          final t = (tData['responseData'] as Map?)?['translatedText']
                  as String? ?? '';
          // MyMemory sometimes echoes the original word; skip that.
          if (t.isNotEmpty && t.toLowerCase() != word) {
            translation = t;
          }
        }
      } catch (_) {
        // Translation is best-effort; continue without it.
      }

      final entry = WordEntry(
        word: word,
        pos: pos,
        urdu: translation,
        roman: phonetic ?? '',
        example: defs.isNotEmpty ? defs.first : '',
        phonetic: phonetic,
        audioUrl: audioUrl,
        definitions: defs,
        isOnline: true,
      );
      _onlineCache[word] = entry;
      return entry;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('WordDict.lookupOnline DioError: $e');
      _onlineCache[word] = null;
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('WordDict.lookupOnline unexpected: $e');
      _onlineCache[word] = null;
      return null;
    }
  }

  /// Save a word to the user's vocabulary.
  Future<void> saveWord(WordEntry entry) async {
    await _ensureSavedLoaded();
    final key = _clean(entry.word);
    if (_saved.any((s) => _clean(s.word) == key)) return;
    _saved.add(SavedWord(
      word: entry.word,
      urdu: entry.urdu.isNotEmpty ? entry.urdu : entry.example,
      roman: entry.roman,
      pos: entry.pos,
      savedAt: DateTime.now()));
    await _persistSaved();
  }

  /// Remove a saved word.
  Future<void> unsaveWord(String word) async {
    await _ensureSavedLoaded();
    final key = _clean(word);
    _saved.removeWhere((s) => _clean(s.word) == key);
    await _persistSaved();
  }

  /// Whether this word is in the user's saved vocabulary.
  bool isSaved(String word) {
    final key = _clean(word);
    return _saved.any((s) => _clean(s.word) == key);
  }

  /// All saved words, newest first.
  Future<List<SavedWord>> getSaved() async {
    await _ensureSavedLoaded();
    return [..._saved.reversed];
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  String _clean(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r"[^a-zA-Z']"), '').trim();

  List<String> _morphForms(String w) {
    final forms = <String>[];
    // common suffix stripping
    if (w.endsWith('ing') && w.length > 5) {
      forms.add(w.substring(0, w.length - 3));            // running→runn
      forms.add('${w.substring(0, w.length - 3)}e');      // having→have
    }
    if (w.endsWith('ed') && w.length > 4) {
      forms.add(w.substring(0, w.length - 2));
      forms.add('${w.substring(0, w.length - 1)}');       // loved→love
    }
    if (w.endsWith('s') && w.length > 3)  forms.add(w.substring(0, w.length - 1));
    if (w.endsWith('es') && w.length > 4) forms.add(w.substring(0, w.length - 2));
    if (w.endsWith('er') && w.length > 4) forms.add(w.substring(0, w.length - 2));
    if (w.endsWith('est') && w.length > 5) forms.add(w.substring(0, w.length - 3));
    if (w.endsWith('ly') && w.length > 4)  forms.add(w.substring(0, w.length - 2));
    if (w.endsWith('ness') && w.length > 6) forms.add(w.substring(0, w.length - 4));
    if (w.endsWith('tion') && w.length > 6) forms.add(w.substring(0, w.length - 3));
    if (w.endsWith('ment') && w.length > 6) forms.add(w.substring(0, w.length - 4));
    return forms;
  }

  Future<void> _ensureSavedLoaded() async {
    if (_savedLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('radd_saved_words') ?? '[]';
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _saved = list.map(SavedWord.fromJson).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('WordDict: failed to load saved words: $e');
    }
    _savedLoaded = true;
  }

  Future<void> _persistSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('radd_saved_words',
          jsonEncode(_saved.map((s) => s.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('WordDict: failed to persist: $e');
    }
  }
}

// ── Offline dictionary data (~420 words) ──────────────────────────────────────
// Format: 'word': WordEntry(word, pos, urdu, roman, example)
// pos: n=noun, v=verb, adj=adjective, adv=adverb, pron=pronoun,
//      prep=preposition, conj=conjunction, interj=interjection, det=determiner

const _dict = <String, WordEntry>{
  // A
  'able': WordEntry(word:'able', pos:'adj', urdu:'قابل', roman:'qaabil', example:'He is able to do it.'),
  'above': WordEntry(word:'above', pos:'prep', urdu:'اوپر', roman:'oopar'),
  'accept': WordEntry(word:'accept', pos:'v', urdu:'قبول کرنا', roman:'qabool karna', example:'I accept your offer.'),
  'afraid': WordEntry(word:'afraid', pos:'adj', urdu:'ڈرا ہوا', roman:'dara hua'),
  'again': WordEntry(word:'again', pos:'adv', urdu:'پھر', roman:'phir', example:'Do it again.'),
  'ago': WordEntry(word:'ago', pos:'adv', urdu:'پہلے', roman:'pehle', example:'Two days ago.'),
  'agree': WordEntry(word:'agree', pos:'v', urdu:'متفق ہونا', roman:'muttafiq hona'),
  'alive': WordEntry(word:'alive', pos:'adj', urdu:'زندہ', roman:'zinda'),
  'alone': WordEntry(word:'alone', pos:'adj', urdu:'اکیلا', roman:'akela', example:'I was alone.'),
  'already': WordEntry(word:'already', pos:'adv', urdu:'پہلے سے', roman:'pehle se'),
  'also': WordEntry(word:'also', pos:'adv', urdu:'بھی', roman:'bhi'),
  'although': WordEntry(word:'although', pos:'conj', urdu:'اگرچہ', roman:'agarcha'),
  'always': WordEntry(word:'always', pos:'adv', urdu:'ہمیشہ', roman:'hamesha', example:'I always try.'),
  'anger': WordEntry(word:'anger', pos:'n', urdu:'غصہ', roman:'gussa'),
  'angry': WordEntry(word:'angry', pos:'adj', urdu:'ناراض', roman:'naraaz', example:'He was very angry.'),
  'answer': WordEntry(word:'answer', pos:'n', urdu:'جواب', roman:'jawaab', example:'What is the answer?'),
  'anyone': WordEntry(word:'anyone', pos:'pron', urdu:'کوئی بھی', roman:'koi bhi'),
  'anything': WordEntry(word:'anything', pos:'pron', urdu:'کچھ بھی', roman:'kuch bhi'),
  'anyway': WordEntry(word:'anyway', pos:'adv', urdu:'بہرحال', roman:'baharhal'),
  'appear': WordEntry(word:'appear', pos:'v', urdu:'ظاہر ہونا', roman:'zaahir hona'),
  'argue': WordEntry(word:'argue', pos:'v', urdu:'بحث کرنا', roman:'behas karna'),
  'around': WordEntry(word:'around', pos:'prep', urdu:'اردگرد', roman:'ird gird'),
  'arrive': WordEntry(word:'arrive', pos:'v', urdu:'پہنچنا', roman:'pahunchna'),
  'ask': WordEntry(word:'ask', pos:'v', urdu:'پوچھنا', roman:'poochna', example:'Can I ask you something?'),
  'attention': WordEntry(word:'attention', pos:'n', urdu:'توجہ', roman:'tawajjah'),
  'away': WordEntry(word:'away', pos:'adv', urdu:'دور', roman:'door', example:'Go away!'),

  // B
  'bad': WordEntry(word:'bad', pos:'adj', urdu:'برا', roman:'bura', example:'That is bad.'),
  'beautiful': WordEntry(word:'beautiful', pos:'adj', urdu:'خوبصورت', roman:'khoobsoorat'),
  'because': WordEntry(word:'because', pos:'conj', urdu:'کیونکہ', roman:'kyunke'),
  'before': WordEntry(word:'before', pos:'prep', urdu:'پہلے', roman:'pehle'),
  'begin': WordEntry(word:'begin', pos:'v', urdu:'شروع کرنا', roman:'shuru karna'),
  'behind': WordEntry(word:'behind', pos:'prep', urdu:'پیچھے', roman:'peechhe'),
  'believe': WordEntry(word:'believe', pos:'v', urdu:'یقین کرنا', roman:'yaqeen karna', example:'I believe you.'),
  'below': WordEntry(word:'below', pos:'prep', urdu:'نیچے', roman:'neeche'),
  'best': WordEntry(word:'best', pos:'adj', urdu:'بہترین', roman:'behtareen'),
  'better': WordEntry(word:'better', pos:'adj', urdu:'بہتر', roman:'behtar'),
  'between': WordEntry(word:'between', pos:'prep', urdu:'درمیان', roman:'darmiyan'),
  'big': WordEntry(word:'big', pos:'adj', urdu:'بڑا', roman:'bara', example:'A big house.'),
  'blood': WordEntry(word:'blood', pos:'n', urdu:'خون', roman:'khoon'),
  'body': WordEntry(word:'body', pos:'n', urdu:'جسم', roman:'jism'),
  'break': WordEntry(word:'break', pos:'v', urdu:'توڑنا', roman:'torna'),
  'bring': WordEntry(word:'bring', pos:'v', urdu:'لانا', roman:'lana', example:'Bring me water.'),
  'brother': WordEntry(word:'brother', pos:'n', urdu:'بھائی', roman:'bhai'),
  'build': WordEntry(word:'build', pos:'v', urdu:'بنانا', roman:'banana'),
  'business': WordEntry(word:'business', pos:'n', urdu:'کاروبار', roman:'karobaar'),

  // C
  'call': WordEntry(word:'call', pos:'v', urdu:'بلانا', roman:'bulana', example:'Please call me.'),
  'calm': WordEntry(word:'calm', pos:'adj', urdu:'پرسکون', roman:'par sukoon'),
  'can': WordEntry(word:'can', pos:'v', urdu:'سکنا', roman:'sakna', example:'I can help.'),
  'care': WordEntry(word:'care', pos:'v', urdu:'پرواہ کرنا', roman:'parwah karna'),
  'careful': WordEntry(word:'careful', pos:'adj', urdu:'محتاط', roman:'muhtaat'),
  'carry': WordEntry(word:'carry', pos:'v', urdu:'اٹھانا', roman:'uthana'),
  'catch': WordEntry(word:'catch', pos:'v', urdu:'پکڑنا', roman:'pakarna'),
  'cause': WordEntry(word:'cause', pos:'n', urdu:'وجہ', roman:'wajah'),
  'chance': WordEntry(word:'chance', pos:'n', urdu:'موقع', roman:'mauqa', example:'Give me a chance.'),
  'change': WordEntry(word:'change', pos:'v', urdu:'بدلنا', roman:'badalna'),
  'child': WordEntry(word:'child', pos:'n', urdu:'بچہ', roman:'bacha'),
  'children': WordEntry(word:'children', pos:'n', urdu:'بچے', roman:'bachay'),
  'choose': WordEntry(word:'choose', pos:'v', urdu:'چننا', roman:'chunna'),
  'city': WordEntry(word:'city', pos:'n', urdu:'شہر', roman:'sheher'),
  'close': WordEntry(word:'close', pos:'adj', urdu:'قریب', roman:'qareeb'),
  'cold': WordEntry(word:'cold', pos:'adj', urdu:'ٹھنڈا', roman:'thanda'),
  'come': WordEntry(word:'come', pos:'v', urdu:'آنا', roman:'aana'),
  'control': WordEntry(word:'control', pos:'v', urdu:'قابو کرنا', roman:'qabu karna'),
  'country': WordEntry(word:'country', pos:'n', urdu:'ملک', roman:'mulk'),
  'cry': WordEntry(word:'cry', pos:'v', urdu:'رونا', roman:'rona'),
  'cut': WordEntry(word:'cut', pos:'v', urdu:'کاٹنا', roman:'kaatna'),

  // D
  'danger': WordEntry(word:'danger', pos:'n', urdu:'خطرہ', roman:'khatra'),
  'dark': WordEntry(word:'dark', pos:'adj', urdu:'اندھیرا', roman:'andhera'),
  'daughter': WordEntry(word:'daughter', pos:'n', urdu:'بیٹی', roman:'beti'),
  'day': WordEntry(word:'day', pos:'n', urdu:'دن', roman:'din'),
  'dead': WordEntry(word:'dead', pos:'adj', urdu:'مردہ', roman:'murda'),
  'deal': WordEntry(word:'deal', pos:'n', urdu:'معاملہ', roman:'maamla'),
  'death': WordEntry(word:'death', pos:'n', urdu:'موت', roman:'maut'),
  'decide': WordEntry(word:'decide', pos:'v', urdu:'فیصلہ کرنا', roman:'faisla karna'),
  'different': WordEntry(word:'different', pos:'adj', urdu:'مختلف', roman:'mukhtalif'),
  'difficult': WordEntry(word:'difficult', pos:'adj', urdu:'مشکل', roman:'mushkil'),
  'do': WordEntry(word:'do', pos:'v', urdu:'کرنا', roman:'karna'),
  'door': WordEntry(word:'door', pos:'n', urdu:'دروازہ', roman:'darwaza'),
  'dream': WordEntry(word:'dream', pos:'n', urdu:'خواب', roman:'khwab'),
  'drink': WordEntry(word:'drink', pos:'v', urdu:'پینا', roman:'peena'),
  'drive': WordEntry(word:'drive', pos:'v', urdu:'چلانا', roman:'chalana'),
  'drop': WordEntry(word:'drop', pos:'v', urdu:'گرانا', roman:'girana'),

  // E
  'early': WordEntry(word:'early', pos:'adv', urdu:'جلدی', roman:'jaldi'),
  'easy': WordEntry(word:'easy', pos:'adj', urdu:'آسان', roman:'aasaan'),
  'else': WordEntry(word:'else', pos:'adv', urdu:'اور', roman:'aur'),
  'end': WordEntry(word:'end', pos:'n', urdu:'انجام', roman:'anjaam'),
  'enemy': WordEntry(word:'enemy', pos:'n', urdu:'دشمن', roman:'dushman'),
  'enough': WordEntry(word:'enough', pos:'adv', urdu:'کافی', roman:'kaafi'),
  'escape': WordEntry(word:'escape', pos:'v', urdu:'فرار ہونا', roman:'faraar hona'),
  'even': WordEntry(word:'even', pos:'adv', urdu:'حتیٰ', roman:'hatta'),
  'every': WordEntry(word:'every', pos:'det', urdu:'ہر', roman:'har'),
  'everything': WordEntry(word:'everything', pos:'pron', urdu:'سب کچھ', roman:'sab kuch'),
  'evil': WordEntry(word:'evil', pos:'adj', urdu:'برائی', roman:'burai'),
  'exactly': WordEntry(word:'exactly', pos:'adv', urdu:'بالکل', roman:'bilkul'),
  'explain': WordEntry(word:'explain', pos:'v', urdu:'سمجھانا', roman:'samjhana'),

  // F
  'face': WordEntry(word:'face', pos:'n', urdu:'چہرہ', roman:'chehra'),
  'fail': WordEntry(word:'fail', pos:'v', urdu:'ناکام ہونا', roman:'naakaam hona'),
  'fall': WordEntry(word:'fall', pos:'v', urdu:'گرنا', roman:'girna'),
  'family': WordEntry(word:'family', pos:'n', urdu:'خاندان', roman:'khaandan'),
  'far': WordEntry(word:'far', pos:'adj', urdu:'دور', roman:'door'),
  'fast': WordEntry(word:'fast', pos:'adj', urdu:'تیز', roman:'taiz'),
  'father': WordEntry(word:'father', pos:'n', urdu:'والد', roman:'waalid'),
  'fear': WordEntry(word:'fear', pos:'n', urdu:'خوف', roman:'khauf', example:'I have no fear.'),
  'feel': WordEntry(word:'feel', pos:'v', urdu:'محسوس کرنا', roman:'mehsoos karna'),
  'fight': WordEntry(word:'fight', pos:'v', urdu:'لڑنا', roman:'larna'),
  'finally': WordEntry(word:'finally', pos:'adv', urdu:'آخرکار', roman:'aakhir kar'),
  'find': WordEntry(word:'find', pos:'v', urdu:'ڈھونڈنا', roman:'dhoondna'),
  'fire': WordEntry(word:'fire', pos:'n', urdu:'آگ', roman:'aag'),
  'follow': WordEntry(word:'follow', pos:'v', urdu:'پیچھا کرنا', roman:'peecha karna'),
  'fool': WordEntry(word:'fool', pos:'n', urdu:'احمق', roman:'ahmaq'),
  'force': WordEntry(word:'force', pos:'n', urdu:'طاقت', roman:'taaqat'),
  'forget': WordEntry(word:'forget', pos:'v', urdu:'بھولنا', roman:'bhoolna'),
  'forgive': WordEntry(word:'forgive', pos:'v', urdu:'معاف کرنا', roman:'maaf karna', example:'Please forgive me.'),
  'friend': WordEntry(word:'friend', pos:'n', urdu:'دوست', roman:'dost'),
  'future': WordEntry(word:'future', pos:'n', urdu:'مستقبل', roman:'mustaqbil'),

  // G
  'get': WordEntry(word:'get', pos:'v', urdu:'حاصل کرنا', roman:'haasil karna'),
  'give': WordEntry(word:'give', pos:'v', urdu:'دینا', roman:'dena'),
  'go': WordEntry(word:'go', pos:'v', urdu:'جانا', roman:'jaana'),
  'god': WordEntry(word:'god', pos:'n', urdu:'خدا', roman:'khuda'),
  'good': WordEntry(word:'good', pos:'adj', urdu:'اچھا', roman:'acha'),
  'great': WordEntry(word:'great', pos:'adj', urdu:'عظیم', roman:'azeem'),
  'grow': WordEntry(word:'grow', pos:'v', urdu:'بڑھنا', roman:'barhna'),
  'guess': WordEntry(word:'guess', pos:'v', urdu:'اندازہ لگانا', roman:'andaza lagana'),
  'gun': WordEntry(word:'gun', pos:'n', urdu:'بندوق', roman:'bandooq'),

  // H
  'hand': WordEntry(word:'hand', pos:'n', urdu:'ہاتھ', roman:'haath'),
  'happen': WordEntry(word:'happen', pos:'v', urdu:'ہونا', roman:'hona'),
  'happy': WordEntry(word:'happy', pos:'adj', urdu:'خوش', roman:'khush'),
  'hard': WordEntry(word:'hard', pos:'adj', urdu:'سخت', roman:'sakht'),
  'hate': WordEntry(word:'hate', pos:'v', urdu:'نفرت کرنا', roman:'nafrat karna'),
  'have': WordEntry(word:'have', pos:'v', urdu:'ہونا', roman:'hona'),
  'heart': WordEntry(word:'heart', pos:'n', urdu:'دل', roman:'dil'),
  'help': WordEntry(word:'help', pos:'v', urdu:'مدد کرنا', roman:'madad karna'),
  'here': WordEntry(word:'here', pos:'adv', urdu:'یہاں', roman:'yahan'),
  'hide': WordEntry(word:'hide', pos:'v', urdu:'چھپنا', roman:'chhupna'),
  'home': WordEntry(word:'home', pos:'n', urdu:'گھر', roman:'ghar'),
  'honest': WordEntry(word:'honest', pos:'adj', urdu:'ایماندار', roman:'imaandaar'),
  'honor': WordEntry(word:'honor', pos:'n', urdu:'عزت', roman:'izzat'),
  'hope': WordEntry(word:'hope', pos:'n', urdu:'امید', roman:'umeed'),
  'house': WordEntry(word:'house', pos:'n', urdu:'مکان', roman:'makaan'),
  'human': WordEntry(word:'human', pos:'adj', urdu:'انسانی', roman:'insaani'),
  'hurt': WordEntry(word:'hurt', pos:'v', urdu:'تکلیف دینا', roman:'takleef dena'),

  // I
  'idea': WordEntry(word:'idea', pos:'n', urdu:'خیال', roman:'khayaal'),
  'important': WordEntry(word:'important', pos:'adj', urdu:'اہم', roman:'ahem'),
  'impossible': WordEntry(word:'impossible', pos:'adj', urdu:'ناممکن', roman:'na mumkin'),
  'inside': WordEntry(word:'inside', pos:'prep', urdu:'اندر', roman:'andar'),
  'instead': WordEntry(word:'instead', pos:'adv', urdu:'بجائے', roman:'bajaaye'),

  // J
  'justice': WordEntry(word:'justice', pos:'n', urdu:'انصاف', roman:'insaaf'),

  // K
  'kill': WordEntry(word:'kill', pos:'v', urdu:'مارنا', roman:'maarna'),
  'kind': WordEntry(word:'kind', pos:'adj', urdu:'مہربان', roman:'meherbaan'),
  'king': WordEntry(word:'king', pos:'n', urdu:'بادشاہ', roman:'baadshah'),
  'know': WordEntry(word:'know', pos:'v', urdu:'جاننا', roman:'jaanna'),

  // L
  'late': WordEntry(word:'late', pos:'adj', urdu:'دیر', roman:'der'),
  'laugh': WordEntry(word:'laugh', pos:'v', urdu:'ہنسنا', roman:'hansna'),
  'leave': WordEntry(word:'leave', pos:'v', urdu:'چھوڑنا', roman:'chhorna'),
  'let': WordEntry(word:'let', pos:'v', urdu:'جانے دینا', roman:'jaane dena'),
  'lie': WordEntry(word:'lie', pos:'n', urdu:'جھوٹ', roman:'jhoot'),
  'life': WordEntry(word:'life', pos:'n', urdu:'زندگی', roman:'zindagi'),
  'listen': WordEntry(word:'listen', pos:'v', urdu:'سننا', roman:'sunna'),
  'live': WordEntry(word:'live', pos:'v', urdu:'جینا', roman:'jeena'),
  'look': WordEntry(word:'look', pos:'v', urdu:'دیکھنا', roman:'dekhna'),
  'lose': WordEntry(word:'lose', pos:'v', urdu:'ہارنا', roman:'haarna'),
  'love': WordEntry(word:'love', pos:'n', urdu:'محبت', roman:'mohabbat'),

  // M
  'make': WordEntry(word:'make', pos:'v', urdu:'بنانا', roman:'banana'),
  'man': WordEntry(word:'man', pos:'n', urdu:'مرد', roman:'mard'),
  'matter': WordEntry(word:'matter', pos:'n', urdu:'معاملہ', roman:'maamla'),
  'maybe': WordEntry(word:'maybe', pos:'adv', urdu:'شاید', roman:'shaayad'),
  'mean': WordEntry(word:'mean', pos:'v', urdu:'مطلب ہونا', roman:'matlab hona'),
  'meet': WordEntry(word:'meet', pos:'v', urdu:'ملنا', roman:'milna'),
  'mind': WordEntry(word:'mind', pos:'n', urdu:'ذہن', roman:'zehan'),
  'miss': WordEntry(word:'miss', pos:'v', urdu:'یاد کرنا', roman:'yaad karna'),
  'mistake': WordEntry(word:'mistake', pos:'n', urdu:'غلطی', roman:'ghalti'),
  'money': WordEntry(word:'money', pos:'n', urdu:'پیسہ', roman:'paisa'),
  'more': WordEntry(word:'more', pos:'adv', urdu:'زیادہ', roman:'zyaada'),
  'mother': WordEntry(word:'mother', pos:'n', urdu:'ماں', roman:'maa'),
  'move': WordEntry(word:'move', pos:'v', urdu:'ہلنا', roman:'halna'),

  // N
  'name': WordEntry(word:'name', pos:'n', urdu:'نام', roman:'naam'),
  'need': WordEntry(word:'need', pos:'v', urdu:'ضرورت ہونا', roman:'zaroorat hona'),
  'never': WordEntry(word:'never', pos:'adv', urdu:'کبھی نہیں', roman:'kabhi nahi'),
  'night': WordEntry(word:'night', pos:'n', urdu:'رات', roman:'raat'),
  'nothing': WordEntry(word:'nothing', pos:'pron', urdu:'کچھ نہیں', roman:'kuch nahi'),
  'now': WordEntry(word:'now', pos:'adv', urdu:'ابھی', roman:'abhi'),

  // O
  'old': WordEntry(word:'old', pos:'adj', urdu:'بوڑھا', roman:'booRha'),
  'once': WordEntry(word:'once', pos:'adv', urdu:'ایک بار', roman:'ek baar'),
  'only': WordEntry(word:'only', pos:'adv', urdu:'صرف', roman:'sirf'),
  'open': WordEntry(word:'open', pos:'v', urdu:'کھولنا', roman:'kholna'),
  'order': WordEntry(word:'order', pos:'n', urdu:'حکم', roman:'hukm'),
  'over': WordEntry(word:'over', pos:'prep', urdu:'اوپر', roman:'oopar'),

  // P
  'pain': WordEntry(word:'pain', pos:'n', urdu:'درد', roman:'dard'),
  'past': WordEntry(word:'past', pos:'n', urdu:'ماضی', roman:'maazi'),
  'peace': WordEntry(word:'peace', pos:'n', urdu:'امن', roman:'amn'),
  'people': WordEntry(word:'people', pos:'n', urdu:'لوگ', roman:'log'),
  'place': WordEntry(word:'place', pos:'n', urdu:'جگہ', roman:'jagah'),
  'plan': WordEntry(word:'plan', pos:'n', urdu:'منصوبہ', roman:'mansuba'),
  'please': WordEntry(word:'please', pos:'interj', urdu:'برائے مہربانی', roman:'baraaye meherbani'),
  'power': WordEntry(word:'power', pos:'n', urdu:'طاقت', roman:'taaqat'),
  'problem': WordEntry(word:'problem', pos:'n', urdu:'مسئلہ', roman:'masla'),
  'promise': WordEntry(word:'promise', pos:'n', urdu:'وعدہ', roman:'wada', example:'I promise you.'),
  'protect': WordEntry(word:'protect', pos:'v', urdu:'حفاظت کرنا', roman:'hifazat karna'),
  'prove': WordEntry(word:'prove', pos:'v', urdu:'ثابت کرنا', roman:'saabit karna'),

  // Q
  'question': WordEntry(word:'question', pos:'n', urdu:'سوال', roman:'sawaal'),
  'quick': WordEntry(word:'quick', pos:'adj', urdu:'تیز', roman:'taiz'),
  'quiet': WordEntry(word:'quiet', pos:'adj', urdu:'خاموش', roman:'khaamosh'),

  // R
  'ready': WordEntry(word:'ready', pos:'adj', urdu:'تیار', roman:'tayyar'),
  'real': WordEntry(word:'real', pos:'adj', urdu:'اصلی', roman:'asli'),
  'remember': WordEntry(word:'remember', pos:'v', urdu:'یاد کرنا', roman:'yaad karna'),
  'revenge': WordEntry(word:'revenge', pos:'n', urdu:'انتقام', roman:'intiqqaam'),
  'right': WordEntry(word:'right', pos:'adj', urdu:'صحیح', roman:'sahih'),
  'run': WordEntry(word:'run', pos:'v', urdu:'بھاگنا', roman:'bhaagna'),

  // S
  'sad': WordEntry(word:'sad', pos:'adj', urdu:'اداس', roman:'udaas'),
  'safe': WordEntry(word:'safe', pos:'adj', urdu:'محفوظ', roman:'mahfooz'),
  'say': WordEntry(word:'say', pos:'v', urdu:'کہنا', roman:'kehna'),
  'scared': WordEntry(word:'scared', pos:'adj', urdu:'ڈرا ہوا', roman:'dara hua'),
  'secret': WordEntry(word:'secret', pos:'n', urdu:'راز', roman:'raaz'),
  'see': WordEntry(word:'see', pos:'v', urdu:'دیکھنا', roman:'dekhna'),
  'send': WordEntry(word:'send', pos:'v', urdu:'بھیجنا', roman:'bhejna'),
  'show': WordEntry(word:'show', pos:'v', urdu:'دکھانا', roman:'dikhana'),
  'sister': WordEntry(word:'sister', pos:'n', urdu:'بہن', roman:'behen'),
  'situation': WordEntry(word:'situation', pos:'n', urdu:'صورتحال', roman:'sorat-e-haal'),
  'slow': WordEntry(word:'slow', pos:'adj', urdu:'آہستہ', roman:'aahista'),
  'smile': WordEntry(word:'smile', pos:'v', urdu:'مسکرانا', roman:'muskurana'),
  'son': WordEntry(word:'son', pos:'n', urdu:'بیٹا', roman:'beta'),
  'sorry': WordEntry(word:'sorry', pos:'interj', urdu:'معافی', roman:'maafi', example:'I am sorry.'),
  'soul': WordEntry(word:'soul', pos:'n', urdu:'روح', roman:'rooh'),
  'speak': WordEntry(word:'speak', pos:'v', urdu:'بولنا', roman:'bolna'),
  'stay': WordEntry(word:'stay', pos:'v', urdu:'رہنا', roman:'rehna'),
  'stop': WordEntry(word:'stop', pos:'v', urdu:'رکنا', roman:'rukna'),
  'strong': WordEntry(word:'strong', pos:'adj', urdu:'مضبوط', roman:'mazboot'),
  'stupid': WordEntry(word:'stupid', pos:'adj', urdu:'بیوقوف', roman:'bewaqoof'),
  'sure': WordEntry(word:'sure', pos:'adj', urdu:'یقینی', roman:'yaqeeni'),

  // T
  'take': WordEntry(word:'take', pos:'v', urdu:'لینا', roman:'lena'),
  'talk': WordEntry(word:'talk', pos:'v', urdu:'بات کرنا', roman:'baat karna'),
  'tell': WordEntry(word:'tell', pos:'v', urdu:'بتانا', roman:'batana'),
  'thank': WordEntry(word:'thank', pos:'v', urdu:'شکریہ', roman:'shukriya'),
  'think': WordEntry(word:'think', pos:'v', urdu:'سوچنا', roman:'sochna'),
  'time': WordEntry(word:'time', pos:'n', urdu:'وقت', roman:'waqt'),
  'tired': WordEntry(word:'tired', pos:'adj', urdu:'تھکا ہوا', roman:'thaka hua'),
  'today': WordEntry(word:'today', pos:'adv', urdu:'آج', roman:'aaj'),
  'together': WordEntry(word:'together', pos:'adv', urdu:'مل کر', roman:'mil kar'),
  'tomorrow': WordEntry(word:'tomorrow', pos:'adv', urdu:'کل', roman:'kal'),
  'tonight': WordEntry(word:'tonight', pos:'adv', urdu:'آج رات', roman:'aaj raat'),
  'true': WordEntry(word:'true', pos:'adj', urdu:'سچ', roman:'sach'),
  'trust': WordEntry(word:'trust', pos:'v', urdu:'بھروسہ کرنا', roman:'bharosa karna'),
  'try': WordEntry(word:'try', pos:'v', urdu:'کوشش کرنا', roman:'koshish karna'),

  // U
  'understand': WordEntry(word:'understand', pos:'v', urdu:'سمجھنا', roman:'samajhna'),

  // V
  'voice': WordEntry(word:'voice', pos:'n', urdu:'آواز', roman:'aawaz'),

  // W
  'wait': WordEntry(word:'wait', pos:'v', urdu:'انتظار کرنا', roman:'intezaar karna'),
  'want': WordEntry(word:'want', pos:'v', urdu:'چاہنا', roman:'chahna'),
  'war': WordEntry(word:'war', pos:'n', urdu:'جنگ', roman:'jung'),
  'watch': WordEntry(word:'watch', pos:'v', urdu:'دیکھنا', roman:'dekhna'),
  'water': WordEntry(word:'water', pos:'n', urdu:'پانی', roman:'paani'),
  'weak': WordEntry(word:'weak', pos:'adj', urdu:'کمزور', roman:'kamzor'),
  'wife': WordEntry(word:'wife', pos:'n', urdu:'بیوی', roman:'biwi'),
  'win': WordEntry(word:'win', pos:'v', urdu:'جیتنا', roman:'jeetna'),
  'woman': WordEntry(word:'woman', pos:'n', urdu:'عورت', roman:'aurat'),
  'wonder': WordEntry(word:'wonder', pos:'v', urdu:'حیران ہونا', roman:'hairan hona'),
  'word': WordEntry(word:'word', pos:'n', urdu:'لفظ', roman:'lafz'),
  'work': WordEntry(word:'work', pos:'v', urdu:'کام کرنا', roman:'kaam karna'),
  'world': WordEntry(word:'world', pos:'n', urdu:'دنیا', roman:'duniya'),
  'worry': WordEntry(word:'worry', pos:'v', urdu:'فکر کرنا', roman:'fikr karna'),
  'wrong': WordEntry(word:'wrong', pos:'adj', urdu:'غلط', roman:'ghalat'),

  // Y
  'year': WordEntry(word:'year', pos:'n', urdu:'سال', roman:'saal'),
  'yesterday': WordEntry(word:'yesterday', pos:'adv', urdu:'کل', roman:'kal'),
  'young': WordEntry(word:'young', pos:'adj', urdu:'جوان', roman:'jawaan'),
};
