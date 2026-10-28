# Saved replies

## Goal
Agents can save a reply and reuse it.

## Acceptance criteria
1. A saved reply appears in the picker after saving.
2. Picking a saved reply inserts its text at the cursor.
3. An empty picker shows "No saved replies yet".

## Work units
### U1: Saved reply storage
- Depends on: none
- Covers: AC1
Model and API for saved replies.

### U2: Picker data hook
- Depends on: none
- Covers: AC2
The hook the picker reads from.

### U3: Picker UI
- Depends on: U1, U2
- Covers: AC3
The picker in the composer.

## Out of scope
- Sharing replies between users.
