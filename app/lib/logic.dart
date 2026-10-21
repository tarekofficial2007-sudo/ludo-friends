import 'dart:math';

const List<int> startIdx = [0, 13, 26, 39];
const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};
const List<String> seatNames = ['Red', 'Green', 'Yellow', 'Blue'];
const List<int> bagBase = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6];

/// Logical ring cell (0..51) of a token at relative position [r] (0..50) for seat [p].
int ringIdx(int p, int r) => (startIdx[p] + r) % 52;

/// Token position: -1 = in yard, 0..50 = ring, 51..55 = home column, 56 = home.
class GameState {
  List<List<int>> t;
  List<int> act;
  int turn;
  int dice; // rolled value waiting for a token choice, 0 = none
  int win;
  int sixes;
  int lastSeat;
  int lastRoll;
  String msg;
  Map<int, List<int>> bag;
  Map<int, int> miss;
  Map<int, List<int>> hist;

  GameState({
    required this.t,
    required this.act,
    required this.turn,
    this.dice = 0,
    this.win = -1,
    this.sixes = 0,
    this.lastSeat = -1,
    this.lastRoll = 0,
    this.msg = '',
    Map<int, List<int>>? bag,
    Map<int, int>? miss,
    Map<int, List<int>>? hist,
  })  : bag = bag ?? {},
        miss = miss ?? {},
        hist = hist ?? {};

  GameState copy() => GameState(
        t: [for (final r in t) List<int>.from(r)],
        act: List<int>.from(act),
        turn: turn,
        dice: dice,
        win: win,
        sixes: sixes,
        lastSeat: lastSeat,
        lastRoll: lastRoll,
        msg: msg,
        bag: {for (final e in bag.entries) e.key: List<int>.from(e.value)},
        miss: Map<int, int>.from(miss),
        hist: {for (final e in hist.entries) e.key: List<int>.from(e.value)},
      );
}

GameState newGame(List<int> act, Random rnd) {
  final seats = List<int>.from(act)..sort();
  final s = GameState(
    t: List.generate(4, (_) => [-1, -1, -1, -1]),
    act: seats,
    turn: seats[rnd.nextInt(seats.length)], // random first player: no built-in advantage
    msg: 'Game started',
  );
  for (final p in s.act) {
    s.bag[p] = List<int>.from(bagBase)..shuffle(rnd);
  }
  return s;
}

int nextSeat(GameState s) => s.act[(s.act.indexOf(s.turn) + 1) % s.act.length];

List<int> legalMoves(GameState s, int p, int d) {
  final out = <int>[];
  for (var i = 0; i < 4; i++) {
    final r = s.t[p][i];
    if (r == -1) {
      if (d == 6) out.add(i);
    } else if (r < 56 && r + d <= 56) {
      out.add(i);
    }
  }
  return out;
}

/// Fair dice: each player draws from a shuffled bag with three of every number.
/// A player with all tokens in the yard who missed 3 times in a row gets a 6.
(int, GameState) pull(GameState st, Random rnd) {
  final s = st.copy();
  final p = s.turn;
  var b = List<int>.from(s.bag[p] ?? <int>[]);
  if (b.isEmpty) b = List<int>.from(bagBase)..shuffle(rnd);
  int d;
  if (s.t[p].every((r) => r == -1) && (s.miss[p] ?? 0) >= 3) {
    d = 6;
    final k = b.indexOf(6);
    if (k >= 0) b.removeAt(k);
  } else {
    d = b.removeAt(0);
  }
  s.bag[p] = b;
  return (d, s);
}

GameState move(GameState st, int p, int i, int d) {
  final s = st.copy();
  var r = s.t[p][i];
  var extra = d == 6;
  var hit = 0;
  r = r == -1 ? 0 : r + d;
  s.t[p][i] = r;
  if (r <= 50 && !safeCells.contains(ringIdx(p, r))) {
    for (final q in s.act) {
      if (q == p) continue;
      for (var j = 0; j < 4; j++) {
        final qr = s.t[q][j];
        if (qr >= 0 && qr <= 50 && ringIdx(q, qr) == ringIdx(p, r)) {
          s.t[q][j] = -1;
          hit++;
        }
      }
    }
  }
  if (hit > 0 || r == 56) extra = true;
  final name = seatNames[p];
  s.msg = hit > 0
      ? '$name moved $d and captured $hit token${hit > 1 ? 's' : ''}! Roll again'
      : r == 56
          ? '$name moved $d and reached home! Roll again'
          : '$name moved $d';
  if (s.t[p].every((x) => x == 56)) {
    s.win = p;
    s.msg = '$name wins!';
  } else if (!extra) {
    s.turn = nextSeat(s);
    s.sixes = 0;
  }
  s.dice = 0;
  return s;
}

GameState roll(GameState st, int d) {
  final s = st.copy();
  final p = s.turn;
  final name = seatNames[p];
  s.lastSeat = p;
  s.lastRoll = d;
  final h = [...(s.hist[p] ?? <int>[]), d];
  s.hist[p] = h.length > 3 ? h.sublist(h.length - 3) : h;
  s.miss[p] = (s.t[p].every((r) => r == -1) && d != 6) ? (s.miss[p] ?? 0) + 1 : 0;
  s.sixes = d == 6 ? s.sixes + 1 : 0;
  if (s.sixes >= 3) {
    s.sixes = 0;
    s.dice = 0;
    s.turn = nextSeat(s);
    s.msg = '$name rolled three 6s in a row, turn lost';
    return s;
  }
  final l = legalMoves(s, p, d);
  if (l.isEmpty) {
    s.dice = 0;
    s.sixes = 0;
    s.turn = nextSeat(s);
    s.msg = '$name rolled $d, no move';
    return s;
  }
  if (l.map((i) => s.t[p][i]).toSet().length == 1) return move(s, p, l.first, d);
  s.dice = d;
  s.msg = '$name rolled $d, tap a glowing token';
  return s;
}

/// Simple computer player: capture > reach home > leave yard > advance safely.
int botPick(GameState s, int p, int d) {
  var best = -1;
  var bs = -1e9;
  for (final i in legalMoves(s, p, d)) {
    final r = s.t[p][i];
    final n = r == -1 ? 0 : r + d;
    final m = move(s, p, i, d);
    var sc = n * 0.3;
    var cap = 0;
    for (final q in m.act) {
      if (q == p) continue;
      cap += m.t[q].where((x) => x == -1).length - s.t[q].where((x) => x == -1).length;
    }
    if (cap > 0) sc += 100;
    if (n == 56) sc += 80;
    if (r == -1) sc += 50;
    if (n <= 50 && safeCells.contains(ringIdx(p, n))) sc += 15;
    if (n > 50) sc += 10;
    if (r >= 0 && r <= 50 && safeCells.contains(ringIdx(p, r))) sc -= 8;
    if (sc > bs) {
      bs = sc;
      best = i;
    }
  }
  return best;
}
