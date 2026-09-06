import { expect, it } from "vitest";
import { canEndSentence, adjacentAdjectives } from "./linguistics";

it.each([
  "it is a",
  "we went to",
  "I bought a beautiful",
  "this and",
  "we walked with",
])("does not terminate an unfinished phrase: %s", (text) => {
  expect(canEndSentence(text)).toBe(false);
});
it.each([
  "it is beautiful",
  "it is not beautiful",
  "it is that beautiful",
  "I am doing this",
  "the choice is mine",
  "we arrived home",
])("allows a completed phrase: %s", (text) => {
  expect(canEndSentence(text)).toBe(true);
});
it("detects the native adjacent-adjective comma without tagging unrelated words", () => {
  expect(adjacentAdjectives("a beautiful quiet place", 11)).toBe(true);
  expect(adjacentAdjectives("a long road", 6)).toBe(false);
});
