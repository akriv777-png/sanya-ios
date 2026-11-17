# Саня v0.2 — architecture brief (for implementers)

SwiftUI, iOS 17+, iPhone only, Russian UI, dark. XcodeGen (`project.yml`), NO Mac/Xcode available locally —
code is compiled only on GitHub Actions, so write conservative, compile-safe Swift 5 (no iOS 18-only APIs
unless wrapped in `if #available`; no macros except `@Observable` is NOT allowed — use ObservableObject/@Published;
no third-party packages). Every new .swift file under `Sanya/` or `Shared/` is picked up automatically.
`Shared/` is compiled into BOTH the app and the widget extension (SanyaWidgets) — code there must not use
UIApplication or app-only types.

## Ready-made assets (already in repo, do not regenerate)
* Fonts (OFL, bundled, in `Shared/Fonts/`): PostScript names `CormorantGaramond-Medium`, `CormorantGaramond-SemiBold`,
  `Inter-Regular`, `Inter-Medium`, `Inter-SemiBold`. Registered via `UIAppFonts` in project.yml for both targets.
  Use `Font.custom("CormorantGaramond-Medium", size: s)` etc.
* Backgrounds (app catalog `Sanya/Resources/Assets.xcassets`): `bg_sea`, `bg_forest`, `bg_ember` (portrait JPG), `cover1` (demo cover).
* Pet sprites (catalog `Shared/PetAssets.xcassets`, available in app AND widget): for each base id in
  `calm, happy, hungry, sleep, angry, music` there are 3 images, all 100×104 px, transparent, bottom-aligned on the same canvas:
  `pet_<id>` (full sprite), `pet_<id>_blink` (same but glowing eye pixels darkened = eyes closed),
  `pet_<id>_eyes` (ONLY the red eye pixels; overlay it with `.blendMode(.plusLighter)` + blurred copy for glow).
  Always render with `.interpolation(.none)` + `.resizable()` (pixel art, nearest neighbour).
* Design spec: `design/ui-kit/*.png` boards + `kit.css` (tokens below) + `icons.js` (line icons, 1.6 stroke —
  in Swift use SF Symbols with `.light`/`.regular` weight as equivalents).

## A. Design system — `Sanya/DesignSystem/DS.swift` (+ `Shared/DSColors.swift` for colors used by widget)
Tokens from kit.css:
sage #A8C5A0, sage2 #7FA384, sageDeep #3C5A45, ember #E8894A, ember2 #F2B25C, ink #EEF1EC, mute #9AA59C,
dim #6B756D, danger #D9675B, glass = rgba(22,26,24,.55), glass2 = rgba(40,46,42,.5), line = white 12%.
Radii: card 28, inner/tile 20, small 14, pill 999. Shadow 0 20 50 black 35%, inner top highlight white 6%.
Typography: display = Cormorant Garamond Medium (titles 34–64pt, big clock numbers), section header = Cormorant
uppercase-ish small caps feel (Cormorant SemiBold 20, tracking 3, + hairline rule to the right), body = Inter Regular 15,
label = Inter Medium 12 uppercase tracking 2 in `mute`, caption = Inter 12 `dim`.
Components (all public, reusable, used EVERYWHERE instead of old Theme/CardStyle):
`DS.Color.*`, `DS.Font.display(_:)`, `.ui(_:weight:)`, `.label`, `.caption`;
`GlassCard { }` (= `.ultraThinMaterial` + glass tint overlay + 1px line stroke + radius 28 + shadow), modifier `.glassCard(radius:padding:)`;
`GlassButtonStyle(kind: .primary /*sage fill, dark text*/, .secondary /*glass*/, .ember /*ember fill*/, .ghost)` 52pt pill;
`IconButton` (round 44 glass), `Chip(title, selected)` (pill 34pt, selected = sage tint 20% + sage stroke);
`SectionHeader("Модули", trailing:)`; `DSToggleStyle` (sage); `ProgressBar(value, tint)` (thin capsule);
`AtmosphereBackground(theme:)` — full-screen image (bg_sea default, also forest/ember, chosen in settings via
@AppStorage("bgTheme")) + gradient overlay rgba(14,18,16,.55)→.78→.9 (like kit.css `.bg::after`) + slight desaturation;
`ModuleTile` (88×88-ish rounded 20 glass square, icon in sage, title under it Inter 11, orange dot badge for “event”, “скоро” badge).
Keep `Theme.swift` only as a thin deprecated shim mapping to DS (or delete it once nothing uses it). Keep `Color(hex:)` in Shared.

Restyle to match boards 02–05: launcher (greeting “Доброй ночи, Егор” in Cormorant + date label, search field glass, two widgets row
(next shift / now playing), modules grid 4 columns, glass dock at the bottom with 5 icons: home, music, chat, calendar, settings);
Саня chat (board 05: glass bubbles, user bubble sage-tinted, input pill with mic + send); Смены & Таймеры (board 04:
week strip chips, shift cards with time in Cormorant, timer ring sage with ember end-cap); Плеер (board 03: big cover with soft
shadow, title in Cormorant, glass controls, sage progress); Книга Мастера wrapper (glass toolbar only); settings (glass grouped list,
themes picker with 3 background thumbnails, pet overlay toggle); Live Activity / island (sage/ember tints, see C).
Navigation bars: transparent, titles in Cormorant. Accessibility identifiers that exist today MUST keep working
(tile_<moduleid>, chip_N, shift_add, shift_save, shift_island, player_toggle, preset_N, etc.) — UI tests depend on them.

## B. Global event bus — `Sanya/Core/EventBus.swift`
```swift
enum AppEvent: Codable, Hashable {
  case moduleOpened(String)                  // ModuleID rawValue
  case trackStarted(title: String, artist: String), trackPaused
  case shiftUpcoming(minutes: Int), shiftStarted, shiftEnded(hours: Double)
  case timerStarted(minutes: Int), timerDone
  case counterAdded(kind: String, today: Int, limit: Int)   // kind: "energy" | "snus" | ...
  case vaultOpened, vaultWrongPIN
  case chatMessage(fromUser: Bool)
  case petFed(String), petPlayed, petPetted
}
final class EventBus: ObservableObject { static let shared; let subject = PassthroughSubject<AppEvent, Never>();
  func emit(_ e: AppEvent) // sends + appends {date, event} to a persisted JSON log (Application Support/events.json, keep 35 days)
  func log(since: Date) -> [LoggedEvent] }
```
Wire emits into existing modules: PlayerModel (play/pause/track change), ShiftStore/ShiftsView (island start = shiftStarted, end; and a
check on app foreground for shift within 120 min → shiftUpcoming), Timers (start/done), Assistant (each message), launcher (moduleOpened).
Add a minimal **Счётчик** module (ModuleID.counter becomes ready, wave v0.2): two counters «Энергетики» (limit 2/day) and «Снюс» (limit 5/day),
+1 / −1, today + 7-day mini bars, persisted; emits counterAdded. Vault stays «скоро» but its events exist.

## C. Pet module «Питомец» — `Sanya/Modules/Pet/`
ModuleID `.pet` (emoji 🖤, title «Питомец», tint A8C5A0, wave v0.2, ready). Add a tile on the launcher (identifier `tile_pet`).
1. `PetStore` (ObservableObject, singleton, persisted to UserDefaults/JSON): name (default «Шиза», editable), stats 0…1:
   satiety (сытость), energy (энергия), mood (настроение), bond (связь, never decays fast); xp; bornAt; lastUpdate.
   Real-time decay applied from lastUpdate on every tick/foreground (satiety −0.04/h, energy −0.03/h awake, +0.12/h asleep,
   mood −0.02/h, faster if hungry). Actions: feed(food) (foods: «Бургер», «Энергетик» (energy up, mood up, next hour jittery),
   «Тьма» (mood up)), play (mood +, energy −, bond +), pet/petting by tap (bond +, mood +, cooldown). Bond level 0…5 from bond+xp:
   names «Незнакомец», «Сосед», «Кореш», «Брат», «Тень», «Страж».
2. `EmotionRegistry` — DATA-DRIVEN, scales to ~200: bundled `Sanya/Modules/Pet/emotions.json` decoded into
   `EmotionDef { id, name (ru), sprite (base sprite id), effects: [String], priority: Int, triggers: [Trigger], minDuration, bubble: [String] }`
   where `Trigger` = `{ kind: "stat"|"event"|"time"|"bond"|"random", stat?, below?, above?, event?, fromHour?, toHour?, chance? }`.
   Ship: calm, happy, hungry, sleep, angry, music (base sprites) + derived via effects: bored «скучает» (calm + sway + "…" bubble),
   yawn «зевает» (sleep/calm + vertical stretch + "о"), mischief «вредничает» (calm mirrored + flicker + smirk bubble), tired «устал»
   (sleep sprite, droop), headbang «качает» (music + strong head bob), worker «на смену» (calm + pixel cap accessory),
   bell «дзынь» (happy + bell accessory), grumble «ворчит» (angry, small shake, bubble about energy drinks).
   `PetEngine` picks the current emotion every few seconds: transient event emotions (with duration) beat state emotions;
   otherwise highest-priority def whose triggers all match. Adding an emotion = adding a JSON entry (+ optional sprite).
3. `PetSpriteView(emotion:size:)` — the renderer: two stacked sprite layers for CROSSFADE (0.45 s) on emotion change, plus a
   squash-and-stretch spring (scale 0.9×1.08 → 1) at the switch; idle breathing (scaleY ±2 % sine 3 s, anchor bottom);
   blink: swap to `_blink` for 0.12 s every 2.5–6 s random; eye glow = `_eyes` layer with blur 3 + plusLighter, opacity pulsing;
   particles: `TimelineView(.animation)` + `Canvas` drawing rising ember dots (ember2/ember, fade) and soft dark smoke puffs;
   effects by name: sway, bob/headbang (rotation ±8° fast), shake, stretch, droop, mirror, flicker, zzz (floating «z» letters),
   notes (♪ floating), cap (pixel cap drawn with Rectangles on the head), bell. Pure SwiftUI, 60fps-safe.
4. Own life: `PetLife` — idle behaviours on a timer: wander (x position target random), sit, look around, yawn; at night
   (device hour 0–7 or energy < .15) he goes to sleep (sleep emotion, zzz) and wakes in the morning.
5. Autonomy `PetAutonomy`: from bond level ≥ 2 he makes visible suggestions (cards with his sprite + text + action button):
   playlist mood by time/emotion («Ночь, ты после смены — ставлю мрачное»), shift nudge (shift within 2 h → «Кепку надел. Через 1 ч 20 мин смена»),
   timer pick («Ставлю 25 минут, не ной») — at level ≥ 4 he does it himself (starts timer / starts player) and shows an «Отменить» chip.
6. Diary `PetDiary`: «Как я провёл неделю» — entries generated LOCALLY from EventBus log of the last 7 days + pet stats history:
   counts of shifts/hours, tracks played, feedings, timers, energy drinks; picked from many templated sarcastic-dark Russian lines
   (≥ 25 templates, first person, slang, no moralizing), e.g. «Хозяин отпахал 3 смены, 22 часа у фритюра. Я охранял тьму в его кармане.»
   Protocol `DiaryGenerator` with `LocalDiaryGenerator` (used) and `AIDiaryGenerator` stub (TODO: call OpenAI-compatible endpoint from
   Assistant settings). Keep past weeks list.
7. Integration reactions (subscribe to EventBus): trackStarted → music/headbang; trackPaused → calm; shiftUpcoming/started → worker (cap);
   shiftEnded → tired + diary note; timerDone → bell; counterAdded energy over limit → grumble; vaultWrongPIN → angry; vaultOpened → watches;
   chatMessage → occasional bubble; moduleOpened → small reaction sometimes.
8. `PetOverlayView` — floating pet (≈64 pt) added once at the app root ABOVE all module screens (and the launcher), walks along the bottom
   edge left↔right, flips direction (mirror), sits idle, speech bubbles (glass), tap = petting (happy), drag to move, double-tap opens pet module.
   Toggle `@AppStorage("petOverlay")` default true, in settings. Must not block touches outside its own frame. Hidden inside the pet module itself.
   Identifier `pet_overlay`.
9. Pet screen (`PetView`): atmosphere background, big pet (≈220 pt) on a glass «stage», name + bond level, 4 stat bars (сытость, энергия,
   настроение, связь) with ProgressBar, action buttons `pet_feed`, `pet_play`, `pet_pet`, food sheet with identifiers `food_0..2`,
   suggestions section, diary button `pet_diary` → `PetDiaryView`, «На остров» button `pet_island` (starts Live Activity kind "pet"),
   and a «Эмоции» debug chip row `emo_<id>` (all registry emotions) to preview transitions.
10. Dynamic Island (`Shared/SanyaActivity.swift` + `SanyaWidgets/SanyaWidgets.swift`, ONE extension): add to ContentState optional fields
   `petEmotion: String?`, `petSatiety/petEnergy/petMood: Double?` (optionals so old code compiles). Kind "pet": compact leading = pet sprite
   (`pet_<sprite>` 24 pt, .interpolation(.none)), compact trailing = mood heart/% in sage; minimal = sprite; expanded = sprite 56 pt + name + 3 mini bars.
   For other kinds (player/timer/shift) when petEmotion != nil, compact leading shows the pet sprite instead of the symbol, expanded shows pet next to
   content (player: pet in "music" sprite). Lock screen view restyled (glass dark, sage/ember). App updates the activity locally when emotion changes
   (throttle ≥ 15 s). Map registry emotion → base sprite id before sending (widget only knows the 6 sprite ids).
11. NOT on the iPhone home screen. No widget needed now.

## D. Test hooks
Launch arg `-uitest` already exists. Add `-petDemo`: seed pet with bond level 4, mid stats, a fake 7-day event log (3 shifts, 40 tracks, 6 feedings,
energy drinks over limit) so diary + autonomy show content. UI tests (SanyaUITests.swift) — tours, each ≤ ~70 s:
* testTour1 «launcher»: home shot `v02_01_home`, scroll, `v02_02_home_modules`, open settings (dock button `dock_settings`) shot `v02_03_settings`,
  switch theme (`theme_forest`) shot, back, open chat `tile_assistant`, chip(0), shot `v02_04_chat`, back, open shifts shot `v02_05_shifts`, back, timers shot `v02_06_timers`.
* testTour2 «pet»: `tile_pet`, shot `v02_07_pet`, tap emo chips through 5–6 emotions with ~1.5 s pauses (transitions on video), `pet_feed` → `food_0`,
  shot `v02_08_pet_fed`, `pet_play`, suggestions visible shot `v02_09_pet_suggest`, `pet_diary` shot `v02_10_diary`, back, `pet_island` → home press → shot `v02_11_island_pet`.
* testTour3 «player»: `tile_player`, `player_toggle`, wait, shot `v02_12_player` (overlay pet headbanging visible), home → shot `v02_13_island_player`, back to app,
  launcher shot `v02_14_home_pet_overlay`, counter tile `tile_counter` +1 energy ×3 → pet grumbles shot `v02_15_counter_grumble`.
Shot names must be exactly these (the `shot()` helper writes PNGs).

## UPDATE from Егор (17.11 14:23) — NO magic / fantasy theme
* Remove runes, rune icon / island style «Руна», flame style «Пламя», Skyrim vibe and any fantasy wording.
* Island/player styles become modern equalizer variants: «Столбики» (bars), «Волна» (wave), «Пульс» (pulse dots).
* Backgrounds: only moody realistic: `bg_sea` (sea/cliff fog), `bg_fog` (foggy street), `bg_city` (night city), `bg_concrete` (dark concrete).
  `bg_forest` / `bg_ember` are removed. Theme ids: sea, fog, city, concrete; identifiers `theme_<id>`.
* Sage + ember-orange are just plain accent colors.
* Pet: still sinister chibi emo boy (smoke + red eyes OK) but no magic items/spells/runes, no «Тьма» food, no Искра/Дух/Страж/Тень stage names.
  Bond levels: «Незнакомец», «Сосед», «Кореш», «Бро», «Свой», «Братан навсегда». Foods: «Бургер», «Энергетик», «Картошка фри».
* Книга Мастера module stays as-is (DnD tool).
