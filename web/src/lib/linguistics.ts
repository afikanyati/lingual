import nlp from "compromise/two";
import type { LexicalPhrase, LexicalTerm } from "../interfaces/linguistics";

const demonstratives = new Set([
  "this",
  "that",
  "these",
  "those",
  "here",
  "there",
]);
const possessives = new Set([
  "mine",
  "yours",
  "his",
  "hers",
  "its",
  "ours",
  "theirs",
]);
const cache = new Map<string, LexicalTerm[]>();
const endings = new Map<string, boolean>();
const adjectiveGaps = new Map<string, Set<number>>();

/** Local English POS tagging replaces Apple's NLTagger; retain offsets in the unchanged transcript. */
function terms(text: string): LexicalTerm[] {
  const cached = cache.get(text);
  if (cached) return cached;
  const phrases: LexicalPhrase[] = nlp(text).terms().json({ offset: true });
  const result = phrases.flatMap((phrase) => phrase.terms);
  // Keep repeated React renders inexpensive without retaining every historical transcript.
  if (cache.size >= 16) cache.delete(cache.keys().next().value!);
  cache.set(text, result);
  return result;
}

/** Port EntrySegment.isValidSentenceLastWord, including its predicate-adjective and pronoun exceptions. */
export function canEndSentence(text: string): boolean {
  const cached = endings.get(text);
  if (cached !== undefined) return cached;
  const result = sentenceEnding(text);
  if (endings.size >= 256) endings.delete(endings.keys().next().value!);
  endings.set(text, result);
  return result;
}

/** Keep the native contextual check separate from its bounded presentation cache. */
function sentenceEnding(text: string): boolean {
  // The native decision uses the final two tags. Keep sentence context for the tagger,
  // but do not retag an entire long entry for every candidate sentence boundary.
  const context = (text.match(/\S+/gu) ?? []).slice(-32).join(" ");
  const words = terms(context);
  const word = words.at(-1);
  const previous = words.at(-2);
  if (!word) return false;
  // A trailing adjective after an article can be nominalized by the browser tagger.
  // Inspect its lexical form as well, preserving the native unfinished-phrase guard.
  const has = (tag: string) =>
    word.tags.includes(tag) ||
    (tag === "Adjective" && nlp(word.normal).has("#Adjective"));
  if (has("Conjunction") || has("Preposition")) return false;
  if (has("Determiner"))
    return Boolean(
      previous &&
        (demonstratives.has(word.normal) || possessives.has(word.normal)),
    );
  if (!has("Adjective")) return true;
  return Boolean(
    previous &&
      (previous.tags.includes("Verb") ||
        previous.tags.includes("Adverb") ||
        previous.tags.includes("Negative") ||
        demonstratives.has(previous.normal)),
  );
}

/** Adjacent adjectives share a comma in the original app, unless a boundary already exists. */
export function adjacentAdjectives(text: string, gapStart: number): boolean {
  const cached = adjectiveGaps.get(text);
  if (cached) return cached.has(gapStart);
  const words = terms(text);
  const gaps = new Set<number>();
  words.forEach((word, index) => {
    if (
      word.tags.includes("Adjective") &&
      words[index + 1]?.tags.includes("Adjective")
    )
      gaps.add(word.offset.start + word.offset.length);
  });
  // Full-entry tags must not be evicted by the many sentence prefixes checked in one render.
  if (adjectiveGaps.size >= 8)
    adjectiveGaps.delete(adjectiveGaps.keys().next().value!);
  adjectiveGaps.set(text, gaps);
  return gaps.has(gapStart);
}
