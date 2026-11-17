// PetAutonomy.swift — suggestions + autonomous actions at higher bond levels
// Sanya/Modules/Pet/PetAutonomy.swift

import Foundation
import Combine

// MARK: - Suggestion Model

struct PetSuggestion: Identifiable {
    let id: UUID
    let text: String
    let actionTitle: String
    let canAutoExecute: Bool    // bond ≥ 4 → he does it himself
    let onAccept: () -> Void
    let onCancel: (() -> Void)?

    init(id: UUID = UUID(), text: String, actionTitle: String,
         canAutoExecute: Bool = false,
         onAccept: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {
        self.id = id
        self.text = text
        self.actionTitle = actionTitle
        self.canAutoExecute = canAutoExecute
        self.onAccept = onAccept
        self.onCancel = onCancel
    }
}

// MARK: - PetAutonomy

final class PetAutonomy: ObservableObject {
    static let shared = PetAutonomy()

    @Published var suggestions: [PetSuggestion] = []
    @Published var autoMessage: String? = nil

    private var store: PetStore { PetStore.shared }
    private var engine: PetEngine { PetEngine.shared }
    private var checkTimer: Timer? = nil
    private var cancellables = Set<AnyCancellable>()
    private var lastShiftMinutes: Int? = nil

    private init() {
        startCheckTimer()
        subscribeToEvents()
    }

    // MARK: - Timer

    private func startCheckTimer() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.evaluateSuggestions() }
        }
        // Initial check after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.evaluateSuggestions()
        }
    }

    // MARK: - Event Subscriptions

    private func subscribeToEvents() {
        EventBus.shared.subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleEvent(_ event: AppEvent) {
        switch event {
        case .shiftUpcoming(let minutes):
            lastShiftMinutes = minutes
            evaluateShiftSuggestion(minutes: minutes)
        case .shiftStarted, .shiftEnded:
            lastShiftMinutes = nil
        default:
            break
        }
    }

    // MARK: - Evaluation

    private func evaluateSuggestions() {
        guard store.bondLevel.rawValue >= 2 else {
            suggestions = []
            return
        }
        evaluateMoodPlaylist()
        evaluateTimerSuggestion()
    }

    private func evaluateMoodPlaylist() {
        let hour = Calendar.current.component(.hour, from: Date())
        let emotion = PetEngine.shared.currentEmotion

        let moodText: String
        switch emotion.sprite {
        case "sleep", "hungry": moodText = "мрачное"
        case "angry":           moodText = "злое"
        case "happy", "music":  moodText = "бодрое"
        default:
            switch hour {
            case 0..<6:  moodText = "ночное атмосферное"
            case 6..<12: moodText = "утреннее"
            case 18..<24: moodText = "вечернее тёмное"
            default:     return
            }
        }

        // Add once per session for this mood
        guard !suggestions.contains(where: { $0.id.uuidString.contains("playlist") }) else { return }

        let level = store.bondLevel.rawValue
        let canAuto = level >= 4

        let text = level >= 4
            ? "Слушай, я сам запустил \(moodText). Не благодари."
            : "Ночь, ты после смены — ставлю \(moodText)?"

        let suggestion = PetSuggestion(
            id: UUID(),
            text: text,
            actionTitle: canAuto ? "Отменить" : "Включить",
            canAutoExecute: canAuto,
            onAccept: {
                EventBus.shared.emit(.moduleOpened("player"))
            }
        )
        addSuggestion(suggestion)
    }

    private func evaluateShiftSuggestion(minutes: Int) {
        guard store.bondLevel.rawValue >= 2 else { return }

        let level = store.bondLevel.rawValue
        let canAuto = level >= 4

        let hm = formatMinutes(minutes)
        let text = level >= 4
            ? "Кепку надел. Через \(hm) смена. Лучше бы выспался."
            : "Через \(hm) смена. Одеться не забудь."

        let suggestion = PetSuggestion(
            id: UUID(),
            text: text,
            actionTitle: canAuto ? "Понял" : "Открыть смены",
            canAutoExecute: false,
            onAccept: {
                EventBus.shared.emit(.moduleOpened("shifts"))
            }
        )
        addSuggestion(suggestion)
    }

    private func evaluateTimerSuggestion() {
        guard store.bondLevel.rawValue >= 2 else { return }
        guard !suggestions.contains(where: { $0.text.contains("25 минут") }) else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 10 && hour < 22 else { return }  // Only suggest during day

        // Suggest occasionally (20% chance per check)
        guard Double.random(in: 0...1) < 0.2 else { return }

        let level = store.bondLevel.rawValue
        let canAuto = level >= 4

        let text = level >= 4
            ? "Поставил 25 минут. Работай."
            : "Ставлю 25 минут, не ной."

        let suggestion = PetSuggestion(
            id: UUID(),
            text: text,
            actionTitle: canAuto ? "Отменить" : "Запустить",
            canAutoExecute: canAuto,
            onAccept: {
                EventBus.shared.emit(.timerStarted(minutes: 25))
            }
        )

        if canAuto {
            // Auto-execute and show cancel message
            autoMessage = text
            EventBus.shared.emit(.timerStarted(minutes: 25))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.autoMessage = nil
            }
        } else {
            addSuggestion(suggestion)
        }
    }

    // MARK: - Helpers

    private func addSuggestion(_ s: PetSuggestion) {
        guard suggestions.count < 3 else { return }
        guard !suggestions.contains(where: { $0.text == s.text }) else { return }
        suggestions.append(s)
    }

    func dismiss(_ id: UUID) {
        suggestions.removeAll { $0.id == id }
    }

    func accept(_ suggestion: PetSuggestion) {
        suggestion.onAccept()
        dismiss(suggestion.id)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }
}
