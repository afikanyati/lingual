import type { TextSelection } from "./entry";
import type { SelectionScale } from "../enums/selection";

export interface ReviewSession {
  entryId: string;
  selection: TextSelection;
  selectionScale?: SelectionScale;
}
