# Demo spec

## 1. Schema
- **BM-DEMO-01:** the schema has one table.
- **BM-DEMO-02:** consumers read it.

## 2. State (continuation form)
BM-STATE-1 (a closed enum) · -2 (one writer) · -3 (every change mints a version)

## 3. Engine (range form)
**Spec requirements — `BM-ENG-1…4`:**
1. CI runs the check.
2. The resolver is pinned.
3. The build covers every target.
4. The model is fetched at boot.

## 4. Hypotheses (short-label form)
**Spec requirements (`BM-HYP`):**
- **HYP-1:** a hypothesis binds to one property.
- **HYP-2:** sign-off is required.

## 5. Lists (numbered form)
**Spec requirements (`BM-LIST`, owner T3):**
1. A list renders inline.
2. A list never hides a count.

Unrelated numbered steps after a paragraph are not requirements:
1. open the file
