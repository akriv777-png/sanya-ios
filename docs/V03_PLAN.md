# Саня v0.3 — brief for implementers

Same rules as V02_PLAN.md (read it, incl. the NO-fantasy update): SwiftUI, iOS 17+, XcodeGen, compiled ONLY in CI
(Xcode 16) — no compiler here, so write very careful, compile-safe Swift 5 (ObservableObject, no @Observable, no packages,
split big view bodies, explicit types, every referenced symbol must exist; grep before using). Russian UI. Keep all existing
accessibility identifiers. Do not touch project.yml, .github/, asset catalogs, fonts, design/.
NO videos. Bundle names stay ASCII (already set in project.yml).

## 1. Dynamic Island / Live Activity (SanyaWidgets/SanyaWidgets.swift + Shared/)
New island-optimised sprites exist in Shared/PetAssets.xcassets: `pet_head_<id>` (id ∈ calm,happy,hungry,sleep,angry,music),
40×40 px head+eyes crops, already brightened for black backgrounds, with baked sage rim light and red eye glow.
Render ALWAYS with `.interpolation(.none).resizable().frame(width:height:)` (square). Add `PetHeadSprite(sprite:size:)` in Shared.
* Compact leading: `PetHeadSprite` 24 pt + a subtle red radial glow behind the eyes (RadialGradient ember/danger, opacity .35)
  so he reads on pure black. Compact trailing: depends on kind —
  pet: mood as small ring/heart + short emotion word (e.g. «злой», max 5 chars) in sage/ember;
  player: animated-looking equalizer (`EqualizerBars`, tinted ember) ; timer: `Text(timerInterval:)` monospaced digits, ember;
  shift: countdown to end/start monospaced, sage. Keep widths tight (max ~52 pt), never truncate digits.
* Minimal: `PetHeadSprite` 20 pt (pet kind) or symbol for others with pet head small overlay.
* Expanded: leading = pet head 52 pt in a dark rounded square with sage hairline; center = name + bond level + emotion name;
  trailing = mood %; bottom = 3 thin stat bars (сытость/энергия/настроение) with icons OR for player: title/artist + progress
  + the pet head bobbing (static image is fine); timer: big countdown + progress bar; shift: shift time range + progress.
  Use DSColors (sage A8C5A0, ember E8894A, ink EEF1EC, mute 9AA59C). Fonts: Inter via `.custom("Inter-SemiBold", size:)`.
* Lock screen banner: glass-dark rounded background (black 0.75 + hairline), pet head 44 pt + same info.
* App side (`PetIsland` in Sanya/Modules/Pet/PetBridge.swift): send `petEmotion` = BASE sprite id (registry emotion → its `sprite`),
  stats, and keep updating on emotion change (throttle 15 s). Player/timer/shift activities also carry petEmotion so the head shows.

## 2. Polish + stability
* Pet screen must not crash/hang: audit PetModuleView, PetEngine, PetLife, PetAutonomy, PetDiary for force unwraps, index out of range,
  Dictionary(uniqueKeysWithValues:) with duplicates, timers created per view instance, main-thread heavy work. PetSpriteView in
  Shared is already rewritten (TimelineView, no timers) — keep it.
* Haptics: add `Haptics.tap()`, `.success()`, `.warning()`, `.soft()` (UIImpactFeedbackGenerator/UINotificationFeedbackGenerator) in
  Sanya/DesignSystem/Haptics.swift; use on tile tap, dock, buttons (GlassButtonStyle), feeding, counters, timer start/done, chat send.
* Animations: spring presses on GlassButtonStyle & tiles (scale .96, `.spring(response: 0.3, dampingFraction: 0.7)`), staggered
  appear of launcher sections (opacity+offset), smooth `.contentTransition(.numericText())` for counters/stats/clock, matched
  transitions where cheap, sheet presentation detents. No layout overflow: every screen must fit 393 pt width (iPhone 15);
  backgrounds use `AtmosphereBackground` (already safe). Avoid fixed widths > 360.
* Settings: section «ИИ» (see 3) + «Питомец на экране» toggle + background themes.

## 3. AI (no secrets in the app)
Backend: any OpenAI-compatible `POST {base}/chat/completions` endpoint. DEFAULT base = `https://text.pollinations.ai/openai`
(public, free, anonymous, NO key; model "openai"; rate-limited ≈1 request / 15 s, may return 429 → retry once after 16 s, then fall back
to local logic). The user may override base URL + optional key in Settings → «ИИ» (key stored in Keychain via existing `Keychain` helper;
default empty → no Authorization header). Also a deep link `sanya://ai?url=<urlencoded>&key=<k>` that fills these settings (Router/onOpenURL).
Implement `Sanya/Core/AIClient.swift`:
```swift
final class AIClient { static let shared
  var baseURL: URL; var apiKey: String; var enabled: Bool (@AppStorage "aiEnabled" default true)
  func chat(system: String, messages: [(role: String, content: String)], temperature: Double = 0.8, maxTokens: Int = 600) async throws -> String
  func json<T: Decodable>(_ type: T.Type, system: String, user: String) async throws -> T  // strips ```json fences, finds first [ or {
  func ping() async -> Bool }
```
A serial queue/actor so only ONE request is in flight (rate limit), 45 s timeout, `URLSession.shared`. Strip any `reasoning` fields.
Features:
a) Саня chat (AssistantModel): replace/route current AI call to AIClient with a system prompt: Саня — дерзкий, тёплый, на «ты»,
   short answers, knows user's shifts (pass next 3 shifts summary) and pet state; keep existing local commands first; demo/offline fallback.
b) Pet weekly diary: implement `AIDiaryGenerator` (exists as stub in PetDiary.swift) — prompt with the week stats JSON + pet name + bond level,
   «пиши от лица мрачного эмо-питомца-чиби, 5–7 коротких строк, сарказм, сленг, без морали, без магии», returns lines; fallback LocalDiaryGenerator.
   Diary screen: button «Переписать с ИИ» (identifier `diary_ai`) + loading shimmer.
c) Shift screenshots: after on-device Vision OCR (already in Shifts), send OCR text to AIClient.json → `[{date:"yyyy-MM-dd", start:"HH:mm", end:"HH:mm", note?}]`
   (end past midnight allowed), show a preview list sheet to confirm before saving; fallback to existing local parser.
d) Pet autonomy flavour: PetAutonomy suggestions get an AI one-liner (cache per suggestion kind per hour; fallback template). Pet bubbles
   occasionally (≤ 1 per 10 min) get AI lines too.
All AI calls must be optional, non-blocking UI, cancellable, and never crash on errors.

## 4. UI tests (screenshots only, no video)
Tours write PNG via `shot()`. Names (exact): testTour1: `v03_launcher`, `v03_settings_ai`; testTour2: `v03_pet`, `v03_pet_fed`, `v03_diary`,
`v03_island_compact` (after `pet_island` + home press), then `XCUIDevice.shared.press(.home)` and long-press is impossible → for expanded use
a launch arg hook instead: skip; testTour3: `v03_player`, `v03_island_player`, `v03_counter`. Use only identifiers that exist.
