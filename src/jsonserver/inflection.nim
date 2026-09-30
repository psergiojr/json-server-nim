# `pluralize` and `singularize` from the `inflection` npm package (v3), which
# json-server uses to relate `posts` to `post` and `postId`.
#
# The upstream rules are JavaScript regexes, every one of them the shape
# `^?(group)literal$`, matched case-insensitively. `std/regex` cannot express
# all of them (a DFA needs a capture on every accepting path, and
# `(?:([^f])fe|([lr])f)$` has two captures on two different paths), so each
# rule is spelled here as data: an optional start anchor, an optional group
# (a list of literal alternatives, or a character class), and a suffix. The
# replacement is `$1` + a literal, which is all the table ever uses.

import std / strutils

type
  Group = object
    alts: seq[string]      ## literal alternatives, tried left to right
    cls: string            ## a character class, if `alts` is empty
    negated: bool
    present: bool          ## whether the rule has a group at all

  Rule = object
    anchored: bool         ## `^`
    group: Group
    suffix: string
    hasRepl: bool          ## false: "matches, leave the word alone"
    repl: string           ## appended after the group's text

proc lit(alts: varargs[string]): Group =
  Group(alts: @alts, cls: "", negated: false, present: true)
proc cls(chars: string; negated = false): Group =
  Group(alts: @[], cls: chars, negated: negated, present: true)
proc none(): Group = Group(alts: @[], cls: "", negated: false, present: false)

proc r(anchored: bool; g: Group; suffix: string): Rule =
  Rule(anchored: anchored, group: g, suffix: suffix, hasRepl: false, repl: "")
proc r(anchored: bool; g: Group; suffix, repl: string): Rule =
  Rule(anchored: anchored, group: g, suffix: suffix, hasRepl: true, repl: repl)

proc apply(rule: Rule; word: string; output: var string): bool =
  ## Match `rule` against the end of `word`; on success `output` is the
  ## rewritten word (or `word` itself for a rule with no replacement).
  let w = word.toLowerAscii
  if not w.endsWith(rule.suffix): return false
  let groupEnd = w.len - rule.suffix.len
  var groupStart = groupEnd
  if rule.group.present:
    var found = false
    if rule.group.alts.len > 0:
      for alt in rule.group.alts:
        if groupEnd >= alt.len and w.substr(groupEnd - alt.len, groupEnd - 1) == alt:
          groupStart = groupEnd - alt.len
          if not rule.anchored or groupStart == 0:
            found = true
            break
    elif groupEnd >= 1:
      let c = w[groupEnd - 1]
      if (c in rule.group.cls) != rule.group.negated:
        groupStart = groupEnd - 1
        found = true
    if not found: return false
  if rule.anchored and groupStart != 0: return false
  if rule.hasRepl:
    output = word.substr(0, groupEnd - 1) & rule.repl
  else:
    output = word
  result = true

const Uncountable = [
  "accommodation", "adulthood", "advertising", "advice", "aggression", "aid",
  "air", "aircraft", "alcohol", "anger", "applause", "arithmetic",
  "assistance", "athletics", "bacon", "baggage", "beef", "biology", "blood",
  "botany", "bread", "butter", "carbon", "cardboard", "cash", "chalk", "chaos",
  "chess", "crossroads", "countryside", "dancing", "deer", "dignity", "dirt",
  "dust", "economics", "education", "electricity", "engineering", "enjoyment",
  "envy", "equipment", "ethics", "evidence", "evolution", "fame", "fiction",
  "flour", "flu", "food", "fuel", "fun", "furniture", "gallows", "garbage",
  "garlic", "genetics", "gold", "golf", "gossip", "gratitude", "grief",
  "guilt", "gymnastics", "happiness", "hardware", "harm", "hate", "hatred",
  "health", "heat", "help", "homework", "honesty", "honey", "hospitality",
  "housework", "humour", "hunger", "hydrogen", "ice", "importance",
  "inflation", "information", "innocence", "iron", "irony", "jam", "jewelry",
  "judo", "karate", "knowledge", "lack", "laughter", "lava", "leather",
  "leisure", "lightning", "linguine", "linguini", "linguistics", "literature",
  "litter", "livestock", "logic", "loneliness", "luck", "luggage", "macaroni",
  "machinery", "magic", "management", "mankind", "marble", "mathematics",
  "mayonnaise", "measles", "methane", "milk", "minus", "money", "mud",
  "music", "mumps", "nature", "news", "nitrogen", "nonsense", "nurture",
  "nutrition", "obedience", "obesity", "oxygen", "pasta", "patience",
  "physics", "poetry", "pollution", "poverty", "pride", "psychology",
  "publicity", "punctuation", "quartz", "racism", "relaxation", "reliability",
  "research", "respect", "revenge", "rice", "rubbish", "rum", "safety",
  "scenery", "seafood", "seaside", "series", "shame", "sheep", "shopping",
  "sleep", "smoke", "smoking", "snow", "soap", "software", "soil",
  "spaghetti", "species", "steam", "stuff", "stupidity", "sunshine",
  "symmetry", "tennis", "thirst", "thunder", "timber", "traffic",
  "transportation", "trust", "underwear", "unemployment", "unity", "validity",
  "veal", "vegetation", "vegetarianism", "vengeance", "violence", "vitality",
  "warmth", "wealth", "weather", "welfare", "wheat", "wildlife", "wisdom",
  "yoga", "zinc", "zoology"]

# The named regexes of inflection.ts, as (anchored, group, suffix).
template pMen: untyped = (true, lit("m", "wom"), "en")
template pPeople: untyped = (false, lit("pe"), "ople")
template pChildren: untyped = (false, lit("child"), "ren")
template pTia: untyped = (false, cls("ti"), "a")
template pAnalyses: untyped =
  (false, lit("analy", "ba", "diagno", "parenthe", "progno", "synop", "the"), "ses")
template pDatabases: untyped = (false, lit("database"), "s")
template pDrives: untyped = (false, lit("drive"), "s")
template pHives: untyped = (false, lit("hi", "ti"), "ves")
template pCurves: untyped = (false, lit("curve"), "s")
template pLrves: untyped = (false, cls("lr"), "ves")
template pAves: untyped = (false, cls("a"), "ves")
template pFoves: untyped = (false, cls("fo", negated = true), "ves")
template pMovies: untyped = (false, lit("m"), "ovies")
template pSeries: untyped = (false, lit("s"), "eries")
template pXes: untyped = (false, lit("x", "ch", "ss", "sh"), "es")
template pMice: untyped = (false, cls("m|l"), "ice")
template pBuses: untyped = (false, lit("bus"), "es")
template pOes: untyped = (false, lit("o"), "es")
template pShoes: untyped = (false, lit("shoe"), "s")
template pCrises: untyped = (false, lit("cris", "ax", "test"), "es")
template pOctopuses: untyped = (false, lit("octop", "vir"), "uses")
template pAliases: untyped = (false, lit("alias", "canvas", "status", "campus"), "es")
template pSummonses: untyped = (true, lit("summons", "bonus"), "es")
template pMatrices: untyped = (false, lit("matr"), "ices")
template pVertices: untyped = (false, lit("vert", "ind"), "ices")
template pFeet: untyped = (true, none(), "feet")
template pTeeth: untyped = (true, none(), "teeth")
template pGeese: untyped = (true, none(), "geese")
template pQuizzes: untyped = (false, lit("quiz"), "zes")
template pWhereases: untyped = (true, lit("whereas"), "es")
template pCriteria: untyped = (true, lit("criteri"), "a")
template pGenera: untyped = (true, none(), "genera")
template pSs: untyped = (false, none(), "ss")
template pS: untyped = (false, none(), "s")

template sMan: untyped = (true, lit("m", "wom"), "an")
template sPerson: untyped = (false, lit("pe"), "rson")
template sChild: untyped = (false, lit("child"), "")
template sDrive: untyped = (false, lit("drive"), "")
template sOx: untyped = (true, lit("ox"), "")
template sAxis: untyped = (false, lit("ax", "test"), "is")
template sOctopus: untyped = (false, lit("octop", "vir"), "us")
template sAlias: untyped = (false, lit("alias", "status", "canvas", "campus"), "")
template sSummons: untyped = (true, lit("summons", "bonus"), "")
template sBus: untyped = (false, lit("bu"), "s")
template sBuffalo: untyped = (false, lit("buffal", "tomat", "potat"), "o")
template sTium: untyped = (false, cls("ti"), "um")
template sSis: untyped = (false, none(), "sis")
template sFe: untyped = (false, cls("f", negated = true), "fe")   # ([^f])fe
template sLrf: untyped = (false, cls("lr"), "f")                 # ([lr])f
template sFocus: untyped = (true, lit("focus"), "")
template sHive: untyped = (false, lit("hi", "ti"), "ve")
template sAeiouyy: untyped = (false, lit("qu"), "y")             # see ySingular
template sX: untyped = (false, lit("x", "ch", "ss", "sh"), "")
template sMatrix: untyped = (false, lit("matr"), "ix")
template sVertex: untyped = (false, lit("vert", "ind"), "ex")
template sMouse: untyped = (false, cls("m|l"), "ouse")
template sFoot: untyped = (true, none(), "foot")
template sTooth: untyped = (true, none(), "tooth")
template sGoose: untyped = (true, none(), "goose")
template sQuiz: untyped = (false, lit("quiz"), "")
template sWhereas: untyped = (true, lit("whereas"), "")
template sCriterion: untyped = (true, lit("criteri"), "on")
template sGenus: untyped = (true, none(), "genus")
template sS: untyped = (false, none(), "s")
template sCommon: untyped = (false, none(), "")

template m(t: untyped): Rule =
  (let x = t; r(x[0], x[1], x[2]))
template m(t: untyped; repl: string): Rule =
  (let x = t; r(x[0], x[1], x[2], repl))

# `([^aeiouy]|qu)y$` mixes a class and a literal inside one group. Two rules,
# in the order the alternation tries them, say the same thing.
template ySingular: untyped = (false, cls("aeiouy", negated = true), "y")
template yPluralIes: untyped = (false, cls("aeiouy", negated = true), "ies")
template yPluralQuIes: untyped = (false, lit("qu"), "ies")

proc pluralRules(): seq[Rule] =
  @[
    # already plural: leave alone
    m(pMen), m(pPeople), m(pChildren), m(pTia), m(pAnalyses), m(pDatabases),
    m(pDrives), m(pHives), m(pCurves), m(pLrves), m(pFoves),
    m(yPluralIes), m(yPluralQuIes), m(pSeries), m(pMovies), m(pXes), m(pMice),
    m(pBuses), m(pOes), m(pShoes), m(pCrises), m(pOctopuses), m(pAliases),
    m(pSummonses), m((true, lit("ox"), "en")), m(pMatrices), m(pFeet),
    m(pTeeth), m(pGeese), m(pQuizzes), m(pWhereases), m(pCriteria),
    m(pGenera),
    # singular to plural
    m(sMan, "en"), m(sPerson, "ople"), m(sChild, "ren"), m(sDrive, "s"),
    m(sOx, "en"), m(sAxis, "es"), m(sOctopus, "uses"), m(sAlias, "es"),
    m(sSummons, "es"), m(sBus, "ses"), m(sBuffalo, "oes"), m(sTium, "a"),
    m(sSis, "ses"), m(sFe, "ves"), m(sLrf, "ves"), m(sFocus, "es"),
    m(sHive, "ves"), m(ySingular, "ies"), m(sAeiouyy, "ies"),
    m(sMatrix, "ices"), m(sVertex, "ices"), m(sX, "es"), m(sMouse, "ice"),
    m(sFoot, "feet"), m(sTooth, "teeth"), m(sGoose, "geese"),
    m(sQuiz, "zes"), m(sWhereas, "es"), m(sCriterion, "a"),
    m(sGenus, "genera"), m(sS, "s"), m(sCommon, "s")]

proc singularRules(): seq[Rule] =
  @[
    # already singular: leave alone
    m(sMan), m(sPerson), m(sChild), m(sDrive), m(sOx), m(sAxis), m(sOctopus),
    m(sAlias), m(sSummons), m(sBus), m(sBuffalo), m(sTium), m(sSis), m(sFe),
    m(sLrf), m(sFocus), m(sHive), m(ySingular), m(sAeiouyy), m(sX),
    m(sMatrix), m(sMouse), m(sFoot), m(sTooth), m(sGoose), m(sQuiz),
    m(sWhereas), m(sCriterion), m(sGenus),
    # plural to singular
    m(pMen, "an"), m(pPeople, "rson"), m(pChildren, ""), m(pDatabases, ""),
    m(pDrives, ""), m(pGenera, "genus"), m(pCriteria, "on"), m(pTia, "um"),
    # `((a)naly|(b)a|...)ses$` → `$1$2sis`: only the first alternative sets
    # `$2`, so inflection answers "analyasis". Kept, since the answer names
    # foreign keys (`analyasisId`) that must agree with upstream's.
    m((false, lit("analy"), "ses"), "asis"),
    m(pAnalyses, "sis"), m(pHives, "ve"), m(pCurves, ""), m(pLrves, "f"),
    m(pAves, "ve"), m(pFoves, "fe"), m(pMovies, "ovie"),
    m(yPluralIes, "y"), m(yPluralQuIes, "y"), m(pSeries, "eries"),
    m(pXes, ""), m(pMice, "ouse"), m(pBuses, ""), m(pOes, ""), m(pShoes, ""),
    m(pCrises, "is"), m(pOctopuses, "us"), m(pAliases, ""),
    m(pSummonses, ""), m((true, lit("ox"), "en"), ""), m(pMatrices, "ix"),
    m(pVertices, "ex"), m(pFeet, "foot"), m(pTeeth, "tooth"),
    m(pGeese, "goose"), m(pQuizzes, ""), m(pWhereases, ""), m(pSs, "ss"),
    m(pS, "")]

let gPlural = pluralRules()
let gSingular = singularRules()

proc applyRules(word: string; rules: seq[Rule]): string =
  let lower = word.toLowerAscii
  for u in Uncountable:
    if u == lower: return word
  for rule in rules:
    var output = ""
    if apply(rule, word, output): return output
  result = word

proc pluralize*(word: string): string = applyRules(word, gPlural)
proc singularize*(word: string): string = applyRules(word, gSingular)
