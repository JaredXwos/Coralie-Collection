# Boggle Multiplayer Interface Contract

- Status: **FROZEN**
- Contract version: **1.0.0**
- Protocol version: **1**
- Frozen: **2026-07-29**

This document is the single source of truth for the parallel implementation of
multiplayer Boggle. Workstreams may implement behind these interfaces
independently, but they must not change identifiers, message fields, callback
signatures, state meanings, or behavioral rules without first revising this
contract.

## 1. Product rules

The following behavior is fixed:

1. The existing solo game remains available and retains its existing board,
   input, solver, timer, result categories, and scoring rules.
2. Solo mode must work when Coralie is unavailable and must not initialize or
   call the Coralie host.
3. Multiplayer is a separate mode entered explicitly by the user.
4. Multiplayer uses Coralie API v2 mesh and storage capabilities only. It does
   not require the HTTP capability.
5. The multiplayer room shows the local player and all currently connected
   mesh peers. Each row shows a username or shortened public key and the
   player's last reported room score.
6. A multiplayer game has no participant list, roster snapshot, readiness
   barrier, or completion barrier.
7. A game is identified by its board, start time, duration, and rules version.
8. The initiator generates the board. Every receiver uses that exact board and
   solves it locally.
9. Timer expiry and pressing Finish now invoke the same idempotent completion
   action.
10. A completion result contains only the player's unique correct words and
    final score. Wrong words and duplicates never leave the device.
11. Common words are aesthetic only. They never add, remove, or otherwise
    change points.
12. Every unique remote result causes exactly one common-word broadcast from
    the receiver, including when the intersection is empty.
13. Receiving a common-word broadcast updates local common-word state and
    rendering only. It causes no network effect.
14. Pressing Back to Room broadcasts a room-score message.
15. If no valid result from another public key has been accepted for the active
    game when Back to Room is pressed, the local room score is forced to zero.
16. Username is persisted through Coralie storage under the key `username`.
    Room scores are session-only and are not persisted.
17. Messages are trusted only after structural validation. Remote result scores
    are reported values and cannot be independently reconstructed because
    wrong words are intentionally private.

## 2. Parallel ownership boundaries

Parallel work must be produced as isolated modules or fragments. Only the
integration owner may edit `boggle.html` while the workstreams are active.

### UI and Render

Owns markup, CSS, element caching, screen selection, accessibility, and the
`Render` implementation. It may read state and invoke `Actions`. It must not
call Coralie, encode messages, solve boards, calculate scores, or mutate
`AppState`.

### Boggle Engine

Owns board creation, deterministic solving of a supplied board, submitted-word
normalization, result classification, and the existing scoring rules. It must
not access the DOM, Coralie, peer state, or protocol messages.

### Coralie Port and Protocol

Owns lazy host loading, API validation, storage, peer/message normalization,
subscriptions, UTF-8 transport, protocol encoding/decoding, structural
validation, and direct sending. It must not access the DOM, calculate game
scores, or mutate `AppState`.

### Controller, Reducers, and Effects

Owns `AppState`, phase transitions, message applicability, local dispatch,
network effects, start conflict resolution, completion, result deduplication,
common-word intersections, and Back-to-Room behavior. This is the only
workstream allowed to mutate `AppState`.

### Integration

Owns embedding the accepted outputs into the portable HTML, adapting the
existing gesture and keyboard input to `Actions`, updating page metadata and
`pages.json`, and removing temporary artifacts.

### Parallel artifact format

Workstreams write only to this shared temporary directory:

```text
C:\tmp\coralie-boggle-contract-v1\
```

Owned outputs are:

```text
UI:
  ui.fragment.html
  ui.css
  render.js
  ui-fixture.html

Engine:
  engine.js
  engine.test.js

Protocol:
  protocol.js
  protocol.test.js
  port.js
  fake-coralie-host.js

Controller:
  controller.js
  controller.test.js
  multipeer.test.js
```

No workstream creates or edits another workstream's files. The integration
owner alone reads these artifacts into `boggle.html`.

JavaScript artifacts are UTF-8 classic-script IIFEs without imports, exports,
bootstrap side effects, or DOM-ready listeners. Each publishes exactly its
contracted global:

```js
globalThis.BoggleEngine;
globalThis.BoggleProtocol;
globalThis.createMultiplayerPort;
globalThis.createBoggleRender;
globalThis.wireBoggleUi;
globalThis.createBoggleController;
```

Factories compose as:

```js
const port = createMultiplayerPort({
  window,
  document,
  protocol: BoggleProtocol,
});

const render = createBoggleRender(document);

const controller = createBoggleController({
  engine: BoggleEngine,
  protocol: BoggleProtocol,
  port,
  render,
  clock: {
    wallNow: () => Date.now(),
    monotonicNow: () => performance.now(),
  },
  timers: {
    setTimeout: window.setTimeout.bind(window),
    clearTimeout: window.clearTimeout.bind(window),
    setInterval: window.setInterval.bind(window),
    clearInterval: window.clearInterval.bind(window),
  },
  clipboard: {
    writeText: (value) => navigator.clipboard.writeText(value),
  },
});

const removeUiListeners = wireBoggleUi({
  root: document,
  actions: controller.Actions,
});
```

`createBoggleController` returns:

```js
{
  state: AppState,
  Actions,
  start(): void,
  destroy(): Promise<void>
}
```

`start()` performs initial Solo-safe rendering only. It does not initialize
Coralie. `destroy()` is idempotent, removes active Coralie subscriptions and
timers, and delegates browser-host closure to the port.

The integration owner creates the only bootstrap entry point after all
artifacts and the existing lexicon are embedded. Dependency order is:

```text
lexicon
→ engine.js
→ protocol.js
→ port.js
→ render.js
→ controller.js
→ integration input adapter
→ bootstrap
```

The bootstrap composes the factories, installs the existing board gesture and
keyboard adapters, calls `controller.start()`, and installs one `pagehide`
listener. No workstream artifact installs its own bootstrap or `pagehide`
listener.

## 3. Shared constants

```js
const BOGGLE_PROTOCOL_VERSION = 1;
const BOGGLE_RULES_VERSION = "csw24-boggle-v1";
const BOGGLE_DURATION_MS = 180_000;
const BOGGLE_START_ARBITRATION_MS = 1_000;
const BOGGLE_LOCAL_START_LEAD_MS = 500;
const BOGGLE_MAX_USERNAME_LENGTH = 40;
const BOGGLE_MAX_SUBMISSIONS = 256;
const BOGGLE_MAX_RESULT_WORDS = 256;
const BOGGLE_MAX_MESSAGE_BYTES = 32 * 1024;
const BOGGLE_WORD_PATTERN = /^[A-Z]{3,15}$/;
const BOGGLE_PUBKEY_PATTERN = /^[0-9a-f]{64}$/;
const BOGGLE_ID_PATTERN = /^[0-9a-f]{64}$/;
```

The board wire representation is a 16-character uppercase string. Each
character represents one die. A `Q` die is represented by the single character
`Q`; the existing engine remains responsible for `Q`/`QU` word interpretation.

## 4. Application state

The controller owns this logical state. Implementations may add private cached
fields, but the named fields and their meanings are fixed.

```js
const AppState = {
  mode: "select",
  // "select" | "solo" | "multiplayer"

  phase: "mode",
  // "mode" | "ready" | "room" | "scheduled" | "playing" |
  // "finishing" | "results"

  uiError: null,
  // string | null; user-facing action/host/terminal-failure feedback

  busyAction: null,
  // null | "multiplayer-init" | "save-username" | "add-peer" |
  // "copy-pubkey" | "start" | "finish" | "back-to-room"

  myPubkeyHex: null,
  myUsername: "",
  roomScore: 0,
  roomScoreGameId: null,
  gameGeneration: 0,
  lastOutboundTs: 0,
  timerNowMonoMs: 0,
  // Updated by controller-owned cosmetic timer ticks; Render never reads a
  // global clock.

  peers: new Map(),
  // pubkeyHex -> {
  //   connected: boolean,
  //   username: string | null,
  //   profileTs: number | null,
  //   score: number,
  //   scoreGameId: string | null,
  //   scoreTs: number | null
  // }
  //
  // Disconnected entries may remain cached for the current session so result
  // screens retain names. Room rendering includes connected entries only.

  activeGame: null,
  // {
  //   kind: "solo" | "multiplayer",
  //   gameId: string | null, // null only for Solo
  //   board: string,
  //   issuedAtMs: number | null, // null only for Solo
  //   durationMs: number,
  //   arbitrationEndsAtMonoMs: number | null,
  //   selectionFrozen: boolean,
  //   localStartsAtMonoMs: number | null,
  //   localDeadlineMonoMs: number | null,
  //   rulesVersion: string,
  //   generation: number,
  //   solverPromise: Promise<Set<string>>,
  //   participantPubkeys: string[] // Multiplayer only; local delivery cache
  // }

  seenStartGameIds: new Set(),
  // Start candidates already relayed or deliberately ignored this session.

  submittedWords: [],

  localResult: null,
  // {
  //   correct: string[],
  //   missed: string[],
  //   wrong: string[],
  //   duplicates: string[],
  //   score: number,
  //   digest: string | null, // null only for Solo
  //   sent: boolean // true immediately before Multiplayer sendToMany
  // }

  resultsByPeer: new Map(),
  // pubkeyHex -> {
  //   words: string[],
  //   score: number,
  //   digest: string,
  //   ts: number // copied from the accepted boggle/result message
  // }

  pendingCommonMessages: [],
  // Structurally valid common messages waiting for their referenced result or
  // local completion.

  commonWords: new Set(),
  // Only locally correct words are promoted into this set.

  commonResponsesSent: new Set(),
  // Result keys for which this peer has locally dispatched and broadcast its
  // one required common response. Keys use `${fromPubkeyHex}:${digest}`.
};
```

`phase` belongs to the selected mode:

- Solo uses `ready`, `playing`, `finishing`, and `results`. It enters `ready`
  after mode selection so its existing Start interaction is preserved.
- Multiplayer uses `room`, `scheduled`, `playing`, `finishing`, and `results`.
- `mode` is used only while the initial mode-selection screen is visible.

## 5. DOM contract

The UI must provide the following stable IDs.

```js
const El = {
  screens: {
    mode: document.getElementById("mode-screen"),
    room: document.getElementById("room-screen"),
    game: document.getElementById("game-screen"),
    results: document.getElementById("results-screen"),
  },

  mode: {
    soloButton: document.getElementById("solo-mode-btn"),
    multiplayerButton: document.getElementById("multiplayer-mode-btn"),
    error: document.getElementById("multiplayer-error"),
  },

  room: {
    pubkey: document.getElementById("my-pubkey"),
    copyButton: document.getElementById("copy-pubkey-btn"),
    usernameInput: document.getElementById("username-input"),
    saveUsernameButton: document.getElementById("save-username-btn"),
    peerInput: document.getElementById("peer-input"),
    addPeerButton: document.getElementById("add-peer-btn"),
    playerList: document.getElementById("player-list"),
    playerCount: document.getElementById("player-count"),
    startButton: document.getElementById("multiplayer-start-btn"),
    changeModeButton: document.getElementById("room-change-mode-btn"),
    status: document.getElementById("room-status"),
  },

  game: {
    board: document.getElementById("board"),
    timer: document.getElementById("timer"),
    selector: document.getElementById("selector"),
    paper: document.getElementById("paper"),
    modeLabel: document.getElementById("game-mode-label"),
    changeModeButton: document.getElementById("game-change-mode-btn"),
  },

  results: {
    score: document.getElementById("results-score"),
    correctWords: document.getElementById("correct-words"),
    commonWords: document.getElementById("common-words"),
    wrongWords: document.getElementById("wrong-words"),
    duplicateWords: document.getElementById("duplicate-words"),
    peerReports: document.getElementById("peer-result-list"),
    backButton: document.getElementById("back-room-btn"),
    soloPlayAgainButton: document.getElementById("solo-play-again-btn"),
    changeModeButton: document.getElementById("results-change-mode-btn"),
  },
};
```

The following existing structural assumptions remain fixed:

1. `#board` has exactly 16 direct tile children.
2. Every tile has one direct button child.
3. `#selector` has the existing two direct input children used for `Q`/`QU`.
4. `#paper` has three direct columns with ten word slots each.
5. Rendering a state update must not rebuild the active board, selector inputs,
   or word-entry elements unless a new game is being entered. This preserves
   focus, the swipe path, and keyboard selection.
6. Remote usernames and words must be inserted with `textContent`, `append`, or
   equivalent safe DOM APIs, never `innerHTML`.

## 6. Actions and rendering interfaces

UI listeners invoke only these public actions:

```js
const Actions = {
  chooseSolo(): void,
  startSoloGame(): Promise<void>,
  resetSoloGame(): void,
  enterMultiplayer(): Promise<void>,
  returnToModeSelection(): Promise<void>,
  copyPubkey(): Promise<void>,
  saveUsername(name: string): Promise<void>,
  addPeer(pubkeyHex: string): Promise<void>,
  startMultiplayerGame(): Promise<void>,
  submitWord(word: string): void,
  finishGame(reason: "manual" | "timeout"): Promise<void>,
  backToRoom(): Promise<void>,
};
```

`finishGame` is idempotent. Repeated calls for the same active game return the
same completion promise and never send a second result.

Action phase rules:

1. `chooseSolo` enters Solo `ready` without touching Coralie.
2. `startSoloGame` is accepted only from Solo `ready`.
3. `resetSoloGame` is accepted only from Solo `results` and returns to `ready`.
4. `returnToModeSelection` is accepted only from Solo `ready`, Solo `results`,
   or Multiplayer `room`. It never abandons an active game. Leaving a
   Multiplayer room removes Coralie event subscriptions but does not close the
   host; entering Multiplayer again resubscribes before taking a fresh peer
   snapshot.
5. `copyPubkey` is accepted only after Multiplayer initialization.
6. `startMultiplayerGame` is accepted only from Multiplayer `room`.
7. `backToRoom` is accepted only from Multiplayer `results`.

Action failure behavior is fixed:

1. An action invoked from an inapplicable phase is an idempotent no-op. Async
   actions return a resolved promise.
2. Async actions set the matching `busyAction` before work and clear it in a
   `finally` block. Rendering disables conflicting controls while busy.
3. Expected clipboard, host initialization, storage, Add Peer, and send errors
   are caught by the controller, copied into `uiError`, rendered through
   `#multiplayer-error` or `#room-status`, and do not become unhandled promise
   rejections.
4. A successful retry clears the relevant prior `uiError`.
5. `onTerminalFailure` sets a room-visible `uiError` naming the shortened
   failing public key and reason. It does not alter game state.
6. Invariant violations inside pure engine, protocol, reducer, or renderer
   code may still throw in development/tests; they are not converted into
   user-facing transport errors.

Rendering exposes:

```js
const Render = {
  draw(state: typeof AppState): void,
  mode(state: typeof AppState): void,
  room(state: typeof AppState): void,
  game(state: typeof AppState): void,
  results(state: typeof AppState): void,
  showMultiplayerError(message: string): void,
};
```

`Render.draw` selects one specialized renderer from `mode` and `phase`.
Specialized renderers are state-to-DOM operations and do not mutate state.

Screen mapping is fixed:

| State | Visible screen |
|---|---|
| `phase === "mode"` | `#mode-screen` |
| Multiplayer `room` | `#room-screen` |
| `ready`, `scheduled`, `playing`, or `finishing` | `#game-screen` |
| `results` | `#results-screen` |

The shared `#timer` control maps by state:

| State | Label/content | Callback | Enabled |
|---|---|---|---|
| Solo `ready` | `Start` | `Actions.startSoloGame()` | Yes |
| Multiplayer `scheduled`, arbitration open | `Choosing game…` | None | No |
| Multiplayer `scheduled`, selection frozen | `Starts in N…`, derived from state timestamps below | None | No |
| Either mode `playing` | Remaining time plus `Finish now` affordance | `Actions.finishGame("manual")` | Yes |
| Either mode `finishing` | `Checking…` | None | No |

Mode-specific controls are also fixed:

1. `#back-room-btn` is visible only for Multiplayer `results`.
2. `#solo-play-again-btn` is visible only for Solo `results` and invokes
   `Actions.resetSoloGame()`.
3. A mode-change button is visible only in Solo `ready`, Solo `results`, or
   Multiplayer `room`. It invokes `Actions.returnToModeSelection()`.
4. Result controls that do not apply to the selected mode are hidden, not just
   disabled.

`Render` never reads `Date.now()`, `performance.now()`, or another global
clock. The controller updates `AppState.timerNowMonoMs` on cosmetic timer
ticks. Scheduled and playing displays derive respectively:

```js
Math.max(
  0,
  activeGame.localStartsAtMonoMs - state.timerNowMonoMs,
)

Math.max(
  0,
  activeGame.localDeadlineMonoMs - state.timerNowMonoMs,
)
```

The first expression is used only after `selectionFrozen` is true and
`localStartsAtMonoMs` is non-null. Before that, the fixed `Choosing game…`
label is shown.

The multiplayer results view contains:

1. Final local score.
2. Correct local words not presently known as common.
3. Locally correct words present in `commonWords`.
4. Wrong local words.
5. Duplicate local submissions.
6. Accepted remote result reports showing cached username/short public key and
   the peer-reported score.
7. Back to Room.

Moving a word between the Correct and Common sections never changes the score.

## 7. Boggle engine interface

```js
const BoggleEngine = {
  createBoard(): string,

  solve(board: string): Promise<Set<string>>,

  evaluate(
    submittedWords: string[],
    solutions: Set<string>
  ): {
    correct: string[],
    missed: string[],
    wrong: string[],
    duplicates: string[],
    score: number
  },
};
```

Engine rules:

1. `createBoard` returns a valid 16-character board string.
2. `solve` is deterministic for a supplied board and has no DOM side effects.
3. `evaluate` normalizes submissions to uppercase.
4. `correct` contains unique correct words in first-submission order.
5. `missed` contains board solutions absent from the submitted correct set.
6. `duplicates` contains repeated submissions after their first occurrence.
7. `wrong` contains unique non-solutions in first-submission order.
8. `score` preserves the current Boggle scoring and wrong-word penalty rules.
9. Common-word state is not accepted by or visible to the engine.
10. The controller accepts at most `BOGGLE_MAX_SUBMISSIONS` submissions per
   game. Further local submissions are ignored, keeping result payload bounds
   deterministic.

## 8. Coralie port interface

Coralie is initialized lazily only from `Actions.enterMultiplayer`.

If `window.Coralie` is absent, the port loads
`./Coralie/v2/host.js` and waits for it. It then validates API v2 and the
following methods:

```text
apiVersion
hostKind
getPubkey
addPeer
sendMessage
getPeersJson
storageGetItem
storageSetItem
storageRemoveItem
close
```

The port exposes:

```js
const MultiplayerPort = {
  open(): Promise<{
    myPubkeyHex: string,
    storedUsername: string | null,
    hostKind: string
  }>,

  subscribe(handlers: {
    onPeers(peers: Array<{
      pubkeyHex: string,
      connectedAt: number | null
    }>): void,

    onMessage(envelope: {
      fromPubkeyHex: string,
      toPubkeyHex: string,
      timestamp: number,
      payload: Uint8Array
    }): void,

    onTerminalFailure(failure: {
      pubkeyHex: string,
      attemptCount: number,
      reason: string | null
    }): void,
  }): () => void,

  getPeers(): Promise<Array<{
    pubkeyHex: string,
    connectedAt: number | null
  }>>,

  addPeer(pubkeyHex: string): Promise<void>,
  saveUsername(name: string): Promise<void>,
  sendTo(pubkeyHex: string, message: ProtocolMessage): Promise<void>,
  sendToMany(
    pubkeyHexes: Iterable<string>,
    message: ProtocolMessage
  ): Promise<PromiseSettledResult<void>[]>,
  close(): Promise<void>,
};
```

Controller initialization order is fixed:

1. `open()`.
2. `subscribe(handlers)`.
3. While initialization is pending, `onPeers` stores the latest full peer
   event snapshot and increments a local `peerEventRevision` without mutating
   `AppState`.
4. Capture the current revision and await `getPeers()`.
5. If the revision changed during that await, discard the fetched snapshot and
   repeat step 4. Peer events are full snapshots, not deltas.
6. When one fetch completes without an intervening peer event, reconcile that
   fetched snapshot, mark peer initialization complete, and thereafter
   reconcile every `onPeers` snapshot immediately.

This subscribe-and-stabilize loop prevents both a missed event and a stale
`getPeers()` response from overwriting a newer event.

`open()` is idempotent and shares one in-flight initialization promise across
repeated calls. A successful result is cached. A rejected initialization
clears the cached promise so a later `enterMultiplayer` action can retry.

The cleanup function returned by `subscribe` is idempotent. The controller owns
and invokes it when leaving the Multiplayer room or destroying the page.

`sendToMany` snapshots and deduplicates the supplied public keys before
sending. It does not read `AppState`.

The integration bootstrap owns the only `pagehide` listener. If
`event.persisted` is false, it removes UI listeners and invokes
`controller.destroy()`. The port's `close()` closes only a browser host; it is
an idempotent no-op for a native host. A back-forward-cache transition leaves
the controller and subscriptions intact.

## 9. Protocol envelope and validation

Every application payload is UTF-8 JSON with:

```js
{
  type: string,
  version: 1,
  ts: number,
  // message-specific fields
}
```

General validation:

1. Decoded payload must be a non-array object.
2. Encoded payload must not exceed `BOGGLE_MAX_MESSAGE_BYTES`.
3. `version` must equal `BOGGLE_PROTOCOL_VERSION`.
4. `ts` must be a finite safe integer.
5. Unknown, malformed, oversized, or inapplicable messages are dropped without
   throwing into the event loop.
6. The Coralie envelope's `fromPubkeyHex` is authoritative. Payload fields
   never override sender identity.
7. Public keys and IDs are normalized to lowercase.
8. Local messages are dispatched before being sent. Coralie `sendMessage` is
   not expected to echo messages to their sender.
9. Before protocol dispatch, normalized envelope `fromPubkeyHex` and
   `toPubkeyHex` must match `BOGGLE_PUBKEY_PATTERN`, and `toPubkeyHex` must
   equal `AppState.myPubkeyHex`.

The protocol module exposes this exact public interface:

```js
const BoggleProtocol = {
  profile(fields: {
    name: string,
    ts: number
  }): ProfileMessage,

  score(fields: {
    score: number,
    gameId: string | null,
    ts: number
  }): ScoreMessage,

  start(fields: {
    gameId: string,
    board: string,
    issuedAtMs: number,
    durationMs: number,
    rulesVersion: string,
    ts: number
  }): StartMessage,

  result(fields: {
    gameId: string,
    words: string[],
    score: number,
    digest: string,
    ts: number
  }): ResultMessage,

  common(fields: {
    gameId: string,
    sourceResultSender: string,
    sourceResultDigest: string,
    words: string[],
    ts: number
  }): CommonMessage,

  encode(message: ProtocolMessage): Uint8Array,
  decode(payload: Uint8Array): ProtocolMessage | null,

  computeGameId(descriptor: {
    board: string,
    issuedAtMs: number,
    durationMs: number,
    rulesVersion: string
  }): Promise<string>,

  computeResultDigest(result: {
    gameId: string,
    score: number,
    words: string[]
  }): Promise<string>,
};
```

Factories validate outgoing field structure and return plain immutable objects.
They add exactly the contracted `type` and `version` fields, reject unknown
input fields, and require callers to provide every listed field.
`decode` performs protocol-version and structural validation only. The
controller owns sender checks, active-game applicability, local-solution
verification, timestamp ordering, and state mutation.

Every outgoing message timestamp is obtained from:

```js
function nextProtocolTs() {
  AppState.lastOutboundTs = Math.max(
    Math.trunc(clock.wallNow()),
    AppState.lastOutboundTs + 1,
  );
  return AppState.lastOutboundTs;
}
```

No outgoing factory call uses `Date.now()` directly. This makes timestamps
strictly increasing within a page session even when multiple messages are
created in one millisecond or the wall clock moves backward.

### `boggle/profile`

```js
{
  type: "boggle/profile",
  version: 1,
  name: string,
  ts: number
}
```

`name` is trimmed, non-empty, and at most 40 Unicode code points. The message is
not game-scoped. A profile is sent when the local username changes and to each
newly connected peer.

For one sender, a profile with `ts` less than or equal to the stored
`profileTs` is ignored. The first accepted message wins an equal-timestamp
tie.

### `boggle/score`

```js
{
  type: "boggle/score",
  version: 1,
  score: number,
  gameId: string | null,
  ts: number
}
```

`score` must be a finite safe integer and must not be negative zero. `gameId`
must be null or match `BOGGLE_ID_PATTERN`. The message is not game-scoped. It
is sent:

1. When Back to Room is pressed.
2. To each newly connected peer, using the current local room score.

For one sender, a score with `ts` less than or equal to the stored `scoreTs` is
ignored. The first accepted message wins an equal-timestamp tie.

### `boggle/start`

```js
{
  type: "boggle/start",
  version: 1,
  gameId: string,
  board: string,
  issuedAtMs: number,
  durationMs: 180000,
  rulesVersion: "csw24-boggle-v1",
  ts: number
}
```

Validation additionally requires:

1. `gameId` matches `BOGGLE_ID_PATTERN`.
2. `board` matches `/^[A-Z]{16}$/`.
3. `issuedAtMs` is a finite safe integer used for identity and deduplication,
   not as a receiver's wall-clock deadline.
4. `durationMs` equals `BOGGLE_DURATION_MS`.
5. `rulesVersion` equals `BOGGLE_RULES_VERSION`.
6. `gameId` equals the locally recomputed game ID.

The message contains no participant list.

### `boggle/result`

```js
{
  type: "boggle/result",
  version: 1,
  gameId: string,
  words: string[],
  score: number,
  digest: string,
  ts: number
}
```

Validation additionally requires:

1. The message matches the active game.
2. The envelope sender is not the local public key.
3. `words` has at most `BOGGLE_MAX_RESULT_WORDS` entries.
4. `words` is sorted, unique, and every item matches `BOGGLE_WORD_PATTERN`.
5. After the local solver resolves, every word is a valid solution for the
   active board. A result received earlier remains pending until this check can
   run.
6. `score` is a finite safe integer and is normalized so negative zero is
   rejected.
7. `digest` matches `BOGGLE_ID_PATTERN` and equals the locally recomputed
   result digest.

The score is final and immutable. Later common-word messages do not change it.

### `boggle/common`

```js
{
  type: "boggle/common",
  version: 1,
  gameId: string,
  sourceResultSender: string,
  sourceResultDigest: string,
  words: string[],
  ts: number
}
```

Validation additionally requires:

1. The message matches the active game.
2. `sourceResultSender` is a valid lowercase public key.
3. `sourceResultDigest` matches `BOGGLE_ID_PATTERN`.
4. `words` has at most `BOGGLE_MAX_RESULT_WORDS` entries.
5. `words` is sorted, unique, and every item matches `BOGGLE_WORD_PATTERN`.
6. An empty `words` array is valid.
7. The Coralie envelope sender differs from `sourceResultSender`; common
   messages are created only in response to another player's result.

Receiving this message never produces another message. Before local completion,
or before the referenced result is available, structurally valid messages are
held in `pendingCommonMessages`.

The referenced result is resolved as follows:

1. If `sourceResultSender` is the local public key, `localResult.digest` must
   equal `sourceResultDigest`.
2. Otherwise, `resultsByPeer.get(sourceResultSender)?.digest` must equal
   `sourceResultDigest`.
3. Every common word must be present in that referenced result's correct-word
   list.
4. After local completion, only referenced words also present in
   `localResult.correct` enter `commonWords`.

A message failing these semantic checks is dropped. A message whose referenced
result has not arrived remains pending and is re-evaluated when a local or
remote result is accepted.

## 10. Canonical IDs and digests

SHA-256 output is encoded as 64 lowercase hexadecimal characters.

Canonical numbers are finite safe integers, negative zero is rejected, and
their wire/hash representation is JavaScript `String(value)` decimal form with
no leading plus sign, leading zero padding, fraction, or exponent. Canonical
strings are UTF-8 encoded before hashing.

The canonical game-ID input is:

```text
boggle-game-v1
<board>
<issuedAtMs>
<durationMs>
<rulesVersion>
```

Each placeholder is replaced with its canonical decimal or string value and
each line, including the prefix, is separated by `\n` with no trailing newline.

The canonical result-digest input is:

```text
boggle-result-v1
<gameId>
<score>
<word-1>
<word-2>
...
```

Words are already sorted and unique. The lines are separated by `\n` with no
trailing newline. An empty correct-word list ends after the score line.

The result-response key is:

```js
`${fromPubkeyHex}:${digest}`
```

Identical word lists reported by different peers are therefore processed
independently.

Frozen hash fixtures:

```js
const GAME_ID_FIXTURE = {
  descriptor: {
    board: "ABCDEFGHIJKLMNOP",
    issuedAtMs: 1722222222000,
    durationMs: 180000,
    rulesVersion: "csw24-boggle-v1",
  },
  expected:
    "3f2a4c98a29d4126fca80ace0039760383acac399d4783a50cb07a19766c4985",
};

const RESULT_DIGEST_FIXTURE = {
  result: {
    gameId:
      "3f2a4c98a29d4126fca80ace0039760383acac399d4783a50cb07a19766c4985",
    score: 12,
    words: ["CAT", "DOG"],
  },
  expected:
    "b707861e4ed72ce288968b05e57264ca8ee8a0fcfa68564908f514ad5141c99a",
};
```

## 11. Start and timing algorithm

### Solo Start

`Actions.startSoloGame()`:

1. Is accepted only from Solo `ready`.
2. Clears submitted words and all prior local round/result state.
3. Generates one board with `BoggleEngine.createBoard()`.
4. Creates an `activeGame` with `kind: "solo"`, `gameId: null`, the fixed
   duration and rules version, `arbitrationEndsAtMonoMs: null`,
   `selectionFrozen: true`, and local monotonic start/deadline values beginning
   at the current `clock.monotonicNow()`.
5. Begins `BoggleEngine.solve(board)` once and stores its promise.
6. Enters `playing`.
7. Performs no protocol, storage, port, peer, or other Coralie operation.

`Actions.resetSoloGame()` clears active-game, submission, result, and visual
round state and returns to Solo `ready`. `returnToModeSelection` from Solo
`results` performs the same cleanup before entering `mode`.

### Local Start

1. Start is enabled only in multiplayer `room`.
2. Generate one board with `BoggleEngine.createBoard()`.
3. Generate `issuedAtMs` with the controller's strictly increasing
   `nextProtocolTs()` helper. This value identifies the start but is never used
   as a receiver's wall-clock deadline.
4. Set `durationMs = BOGGLE_DURATION_MS`.
5. Compute `gameId` from the canonical descriptor.
6. Pass the candidate through the same local acceptance path used for remote
   starts.
7. The acceptance path records its `gameId` in `seenStartGameIds` and performs
   the candidate's one initial send. Local Start does not send it a second
   time.

### Accepting Start

1. Solo mode ignores every protocol message.
2. Multiplayer accepts a valid start candidate only while in `room` or in the
   open arbitration portion of `scheduled`.
3. The first candidate begins a local arbitration window lasting
   `BOGGLE_START_ARBITRATION_MS`, stores its exact
   `arbitrationEndsAtMonoMs`, and sets `selectionFrozen: false`.
4. A newly seen candidate is relayed once to the current connected-peer
   snapshot, excluding the Coralie envelope sender, and its ID is added to
   `seenStartGameIds`. Relaying improves propagation through non-clique mesh
   topologies without creating loops.
5. During arbitration, the lexicographically lower `gameId` is the current
   winner.
6. Selecting or replacing the winner increments `gameGeneration`, clears all
   prior submitted/result/common/common-response state, cancels the losing
   candidate's timers, and causes its eventual solver result to be ignored.
7. Begin `BoggleEngine.solve(board)` for the selected winner and capture its
   `gameGeneration`.
8. When arbitration closes, set `selectionFrozen: true` and freeze the winner.
   Set:

```js
localStartsAtMonoMs =
  clock.monotonicNow() + BOGGLE_LOCAL_START_LEAD_MS;
localDeadlineMonoMs =
  localStartsAtMonoMs + BOGGLE_DURATION_MS;
```

9. Enter `playing` when the local monotonic clock reaches
   `localStartsAtMonoMs`.
10. Starts received after local arbitration freezes are ignored unless their
    `gameId` equals the selected game, in which case they are idempotent
    no-ops.
11. Starts received in `playing`, `finishing`, or `results` are ignored unless
    they match the active game, in which case they are idempotent no-ops.

### Simultaneous Start

All candidates delivered during the arbitration window converge on the
lexicographically lowest `gameId`. Start relaying is best-effort; without a
participant list, acknowledgements, or a central coordinator, convergence
across a network partition cannot be guaranteed. Peers that did not receive
the same winning candidate simply occupy different game IDs, and their
game-scoped messages do not apply to each other.

The required convergence test therefore supplies the same candidate set to all
simulated peers before their arbitration windows close. It does not claim
consensus for candidates withheld beyond the arbitration boundary.

### Timer

The remaining duration is always derived from:

```js
Math.max(0, activeGame.localDeadlineMonoMs - clock.monotonicNow())
```

Interval ticks are cosmetic only. Reaching zero invokes
`Actions.finishGame("timeout")`. Every controller-owned tick first writes its
current monotonic value to `AppState.timerNowMonoMs` and then calls
`Render.draw(AppState)`.

## 12. Completion and result propagation

`Actions.finishGame(reason)` performs these steps once per active game:

1. Cache and return one completion promise per game.
2. Capture the active game's `kind`, `gameId`, `generation`, and solver
   promise.
3. Enter `finishing`, stop accepting local words, and disable active controls.
4. Await the captured solver promise.
5. Immediately after the await, verify that the active game still has the same
   `kind`, `gameId`, and `generation`. If not, end the stale continuation
   without mutating state or sending.
6. Evaluate `submittedWords` through `BoggleEngine.evaluate`.

For Solo:

7. Store `localResult` with the engine's correct, missed, wrong, duplicate, and
   score values, `digest: null`, and `sent: false`.
8. Enter Solo `results`.
9. Perform no protocol, port, peer, storage, or other Coralie operation.

For Multiplayer:

7. Create a sorted copy of the unique correct words for the wire
   representation.
8. Compute the result digest and store `localResult`.
9. Construct and locally dispatch one `boggle/result`.
10. Set `localResult.sent = true` synchronously before starting network work.
11. Invoke `sendToMany` for the union of the locally retained round
    participants and the current connected-peer snapshot. A transient empty
    peer event must not erase the round's result recipients.
12. For every stored remote result without an entry in
    `commonResponsesSent`, produce its one required common response.
13. Re-evaluate pending common messages against the completed local result.
14. Enter Multiplayer `results`.

The promise is cached. Manual completion and timeout racing each other cannot
evaluate, dispatch, or send twice.

## 13. Remote result and common-word algorithm

For each structurally valid result:

1. Capture the active `gameId`, `gameGeneration`, and solver promise.
2. Wait for the captured solver if it is unresolved.
3. Immediately after the await, verify that the page is still in Multiplayer
   with the same active `gameId` and `gameGeneration`. Otherwise end the stale
   continuation without mutating state or sending.
4. Reject the result if any reported word is not a local solution.
5. If `resultsByPeer` already contains the envelope sender for this game, do
   nothing. A player's first valid result is immutable; later results from that
   sender are ignored even if they carry a different digest.
6. Form the result key from envelope sender and result digest.
7. Store the result in `resultsByPeer`.
8. Re-evaluate pending common messages that reference this result.
9. If local completion is pending, stop here. Completion will revisit every
   stored result not present in `commonResponsesSent`.
10. If the key is already in `commonResponsesSent`, do nothing.
11. Compute the sorted intersection between the
   remote words and `localResult.correct`.
12. Construct one `boggle/common`, dispatch it locally so the computed
   intersection is immediately reflected in local aesthetic state. This occurs
   even when the intersection is empty. Local dispatch does not invoke another
   network effect.
13. Add the key to `commonResponsesSent` synchronously before starting network
    work.
14. Send the common response directly to the player whose result it
    acknowledges. Do not gate this direct response on the cached connected
    flag.
15. Refresh rendering.

For each valid common message:

1. Do not send, reply, acknowledge, or rebroadcast anything.
2. If local completion or the referenced result is unavailable, append the
   message to `pendingCommonMessages` unless an identical
   `(envelopeSender, sourceResultSender, sourceResultDigest, words)` tuple is
   already pending.
3. Once both results exist, require the referenced digest to match and every
   word to be present in the referenced correct list.
4. Add only words also present in `localResult.correct` to `commonWords`.
5. Remove the resolved message from `pendingCommonMessages`.
6. Refresh rendering.
7. Do not recalculate the score.

## 14. Back-to-Room algorithm

Back to Room is available only from multiplayer `results`.

1. Let `remoteResultCount` be the number of accepted `resultsByPeer` entries
   for the active game.
2. Set the effective room score to:

```js
remoteResultCount === 0 ? 0 : localResult.score
```

3. Update `roomScore` to the effective score and set `roomScoreGameId` to the
   active multiplayer `gameId`.
4. Dispatch and send one `boggle/score` to the current connected-peer
   snapshot.
5. Clear active-game, submitted-word, local-result, remote-result, common-word,
   and common-response state.
6. Enter multiplayer `room`.

A result arriving after this transition is inapplicable because there is no
matching active game. It does not retroactively change the room score.

## 15. Peer reconciliation and room rendering

Peer snapshots determine connectivity, not game membership.

1. Newly observed keys are inserted or marked `connected: true`.
2. A transition from disconnected to connected clears that peer's
   `profileTs` and `scoreTs` before new announcements are accepted. Cached
   display values may remain until replacements arrive. This prevents a new
   page session using the same public key from being blocked by timestamps
   cached from its prior connection.
3. Missing keys are marked `connected: false`; cached identity and score may
   remain for the session.
4. For each newly connected key, send the current non-empty profile and the
   current room score.
5. Room rows consist of the local player followed by connected peers only.
6. The local row displays `roomScore`.
7. Remote rows display their latest accepted reported score, defaulting to
   zero until a score announcement arrives.
8. No peer is marked invited, ready, playing, finished, or required.

## 16. Integration metadata

When multiplayer is implemented:

1. `boggle.html` declares a Coralie page build matching `pages.json`.
2. It contains `Coralie Android capabilities: mesh, storage`.
3. It lazily loads `./Coralie/v2/host.js` only when Multiplayer is entered and
   `window.Coralie` is absent.
4. The Boggle `pages.json` entry uses capabilities:

```json
[
  "mesh",
  "storage"
]
```

5. The final deliverable remains a portable, self-contained HTML page apart
   from the shared Coralie host bootstrap already distributed by the project.

## 17. Required contract tests

Before integration is accepted, the following must pass:

1. The frozen descriptor fixture generates its exact documented game ID.
2. The frozen result fixture generates its exact documented digest.
3. Two peers use the same transmitted board and solve it independently.
4. Manual finish and timeout racing produce one result.
5. A result received before local completion is processed afterward.
6. A duplicate result produces no second common broadcast.
7. The same digest from two different public keys produces two independent
   common broadcasts.
8. An empty intersection still produces one empty common broadcast.
9. Receiving common words changes categories but not score.
10. A multiplayer game with no accepted remote result returns a room score of
    zero.
11. A multiplayer game with at least one accepted remote result returns the
    unchanged local final score.
12. A late result after Back to Room is ignored.
13. Simulated peers receiving the same start-candidate set during arbitration
    converge on the lexicographically lowest `gameId`.
14. Malformed, unknown, oversized, wrong-version, wrong-game, and stale
    messages are dropped without changing state.
15. Solo mode completes without loading or calling Coralie.
16. UI fixture callbacks invoke `Actions` and never mutate state directly.
17. Remote text is never interpreted as HTML.
18. Solo `ready → playing → finishing → results → ready` preserves current
    scoring and never constructs a protocol message.
19. Two peers with deliberately skewed wall clocks each receive the full local
    monotonic game duration and retain the same game ID.
20. Replacing a scheduled candidate clears round-scoped state and an old
    solver/result continuation cannot mutate the winning game.
21. A result handler awaiting a solver cannot mutate state after Back to Room.
22. A result sender's second valid-but-different result is ignored.
23. A common message cannot promote a word unless its referenced local/remote
    result and digest exist and contain that word.
24. Equal-timestamp profile/score messages are ignored after the first, and
    locally generated timestamps remain strictly increasing.
25. A peer event arriving during `getPeers()` causes the stale fetch to be
    discarded and retried.
26. Every temporary JavaScript artifact publishes only its contracted global
    and installs no bootstrap or `pagehide` listener.

## 18. Change control

This contract is frozen for the first multiplayer implementation.

- Clarifications that do not alter observable behavior may increment the patch
  version.
- Compatible field or callback additions require a minor version.
- Changes to message meanings, canonical hashes, required fields, IDs, action
  signatures, state semantics, scoring, or lifecycle behavior require a major
  contract version and coordinated updates to every active workstream.
- Workstream code that conflicts with this document must be changed; the
  contract must not be silently adapted during integration.
