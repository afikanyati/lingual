export interface LexicalTerm {
  normal: string;
  tags: string[];
  offset: { start: number; length: number };
}
export interface LexicalPhrase {
  terms: LexicalTerm[];
}
