#!/usr/bin/env python3
"""Fala: builds the Brazilian Portuguese typing model (HEXKeyboard/TypingModel/pt.hextm) that swipe
typing reads, in Hex's format v3 (written by build-typing-model.py's `write_model`).

Google Books Ngram has no Portuguese, so the counts come from two open corpora instead:
- OpenSubtitles 2018, Brazilian Portuguese (OPUS, the first 30M lines of mono/pt_br.txt.gz):
  everyday, spoken Portuguese, the register of messages.
- Leipzig Corpora Collection, por_news_2020_1M (CC BY): written Portuguese, with its accents right.
Words are lowercased runs of Portuguese letters. A word counts only if LibreOffice's pt_BR Hunspell
dictionary (VERO, LGPL/MPL) accepts it, or it is one of CHAT_WORDS (internetês the dictionary
doesn't list). Pairs are adjacent words in a line, over the kept vocabulary.

    pip install spylls
    python3 scripts/build-pt-typing-model.py <workdir> HEXKeyboard/TypingModel/pt.hextm

<workdir> holds subs.txt (the OpenSubtitles lines), por_news_2020_1M/ (the Leipzig corpus
unpacked) and pt_BR.dic / pt_BR.aff.
"""
import collections, importlib.util, multiprocessing, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("hexmodel", os.path.join(HERE, "build-typing-model.py"))
hexmodel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hexmodel)

LETTERS = "abcdefghijklmnopqrstuvwxyzáàâãçéêíóôõúü"
WORD = re.compile(f"[{LETTERS}]+")
MAX_WORDS = 110_000          # as Spanish
CANDIDATES = 400_000         # commonest runs checked against the dictionary
MIN_PAIR = 4                 # these corpora are far smaller than Google Books
PAIR_PRUNE_AT = 12_000_000   # drop pairs seen once when the table grows past this
CHAT_WORDS = ["vc", "vcs", "pq", "tb", "tbm", "blz", "vlw", "obg", "msg", "kkk", "kkkk", "kkkkk",
              "rs", "rsrs", "hj", "td", "tds", "qd", "qdo", "cmg", "ctz", "mt", "mto", "mts", "dps",
              "fds", "pfv", "pls", "sdds", "bjs", "bjo", "slk", "mn", "mano", "oxe", "eita", "uai"]


def lines(work):
    yield from open(os.path.join(work, "subs.txt"), encoding="utf-8", errors="ignore")
    for line in open(os.path.join(work, "por_news_2020_1M", "por_news_2020_1M-sentences.txt"),
                     encoding="utf-8", errors="ignore"):
        yield line.split("\t", 1)[-1]


def tokens(line):
    return WORD.findall(line.lower())


_dic = None


def check(words):
    global _dic
    if _dic is None:
        from spylls.hunspell import Dictionary
        _dic = Dictionary.from_files(os.path.join(sys.argv[1], "pt_BR"))
    return [w for w in words if _dic.lookup(w)]


def main(work, out_path):
    counts = collections.Counter()
    for line in lines(work):
        counts.update(tokens(line))
    total = sum(counts.values())
    print(f"{total:,} words, {len(counts):,} distinct")

    ranked = [w for w, _ in counts.most_common(CANDIDATES) if len(w) > 1 or w in "aeoé"]
    chunks = [ranked[i::8] for i in range(8)]
    with multiprocessing.Pool(2) as pool:
        ok = set().union(*map(set, pool.map(check, chunks)))
    kept = [w for w in ranked if w in ok or w in CHAT_WORDS][:MAX_WORDS]
    vocab = {w: counts[w] for w in kept}
    for w in CHAT_WORDS:
        vocab.setdefault(w, max(1, counts.get(w, 0)))
    print(f"{len(vocab):,} words kept")

    pairs = collections.Counter()
    for line in lines(work):
        ts = [t for t in tokens(line)]
        for a, b in zip(ts, ts[1:]):
            if a in vocab and b in vocab:
                pairs[a + " " + b] += 1
        if len(pairs) > PAIR_PRUNE_AT:
            pairs = collections.Counter({k: c for k, c in pairs.items() if c > 1})
    print(f"{len(pairs):,} pairs")
    hexmodel.write_model("pt", vocab, total, {k.encode("utf-8"): c for k, c in pairs.items()},
                         out_path, min_pair=MIN_PAIR)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
