// PetModuleView.swift — full pet module screen (C9)
// Sanya/Modules/Pet/PetModuleView.swift

import SwiftUI
import Combine

public struct PetModuleView: View {
    @ObservedObject private var store = PetStore.shared
    @ObservedObject private var engine = PetEngine.shared
    @ObservedObject private var autonomy = PetAutonomy.shared
    @ObservedObject private var registry_obs = RegistryWrapper.shared

    @State private var showFoodSheet: Bool = false
    @State private var showDiary: Bool = false
    @State private var editingName: Bool = false
    @State private var nameInput: String = ""
    @State private var petFeedback: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackground()
                content
            }
            .navigationTitle("Питомец")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showDiary) { PetDiaryView() }
            .sheet(isPresented: $showFoodSheet) { foodSheet }
        }
        // Start bridge + autonomy on appear
        .onAppear {
            _ = PetBridge.shared
            _ = PetAutonomy.shared
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                petStageSection
                statsSection
                actionButtons
                if !autonomy.suggestions.isEmpty {
                    suggestionsSection
                }
                emotionDebugRow
                bottomButtons
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Pet Stage

    private var petStageSection: some View {
        ZStack(alignment: .bottom) {
            // Stage background
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
                .frame(height: 300)

            // Pet sprite (220pt)
            PetSpriteView(emotion: engine.currentEmotion, size: 220)
                .padding(.bottom, 16)

            // Speech bubble
            if let bubble = engine.bubbleText {
                Text(bubble)
                    .font(DS.Font.ui(14, weight: .medium))
                    .foregroundStyle(Color(hex: "EEF1EC"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .offset(y: -240)
            }

            // Name + bond tag (top of stage)
            VStack(alignment: .leading, spacing: 2) {
                if editingName {
                    nameField
                } else {
                    nameLabel
                }
                Text(store.bondLevel.name)
                    .font(DS.Font.ui(11, weight: .medium))
                    .foregroundStyle(Color(hex: "9AA59C"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "A8C5A0").opacity(0.15), in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nameLabel: some View {
        Button {
            nameInput = store.name
            editingName = true
        } label: {
            Text(store.name)
                .font(DS.Font.display(28))
                .foregroundStyle(Color(hex: "EEF1EC"))
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        HStack {
            TextField("Имя", text: $nameInput)
                .font(DS.Font.display(28))
                .foregroundStyle(Color(hex: "EEF1EC"))
                .submitLabel(.done)
                .onSubmit {
                    if !nameInput.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.name = nameInput.trimmingCharacters(in: .whitespaces)
                    }
                    editingName = false
                }
            Button("Готово") {
                if !nameInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.name = nameInput.trimmingCharacters(in: .whitespaces)
                }
                editingName = false
            }
            .font(DS.Font.ui(13))
            .foregroundStyle(Color(hex: "A8C5A0"))
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Состояние")
            statRow(label: "Сытость", value: store.stats.satiety, tint: Color(hex: "E8894A"), icon: "fork.knife")
            statRow(label: "Энергия", value: store.stats.energy, tint: Color(hex: "F2B25C"), icon: "bolt.fill")
            statRow(label: "Настроение", value: store.stats.mood, tint: Color(hex: "A8C5A0"), icon: "heart.fill")
            statRow(label: "Связь", value: store.stats.bond, tint: Color(hex: "7FA384"), icon: "link")
        }
        .glassCard()
    }

    private func statRow(label: String, value: Double, tint: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(DS.Font.ui(13))
                .foregroundStyle(Color(hex: "9AA59C"))
                .frame(width: 90, alignment: .leading)
            ProgressBar(value: value, tint: tint)
            Text("\(Int(value * 100))%")
                .font(DS.Font.ui(11))
                .foregroundStyle(Color(hex: "6B756D"))
                .frame(width: 34, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            actionBtn(label: "Покормить", icon: "fork.knife", id: "pet_feed") {
                showFoodSheet = true
            }
            actionBtn(label: "Играть", icon: "figure.play", id: "pet_play") {
                store.play()
            }
            actionBtn(label: "Почесать", icon: "hand.point.up.left.fill", id: "pet_pet") {
                store.pet()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { petFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { petFeedback = false }
                }
            }
        }
    }

    private func actionBtn(label: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color(hex: "A8C5A0"))
                Text(label)
                    .font(DS.Font.ui(11, weight: .medium))
                    .foregroundStyle(Color(hex: "9AA59C"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
        }
        .buttonStyle(GlassButtonStyle(kind: .secondary))
        .accessibilityIdentifier(id)
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Предложения")
            ForEach(Array(autonomy.suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                suggestionCard(suggestion, index: idx)
            }
        }
    }

    private func suggestionCard(_ suggestion: PetSuggestion, index: Int) -> some View {
        HStack(spacing: 12) {
            PetStaticSprite(sprite: engine.currentSprite, size: 36)

            Text(suggestion.text)
                .font(DS.Font.ui(13))
                .foregroundStyle(Color(hex: "EEF1EC"))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button(suggestion.actionTitle) {
                    autonomy.accept(suggestion)
                }
                .buttonStyle(GlassButtonStyle(kind: .ember))
                .font(DS.Font.ui(11, weight: .medium))
                .accessibilityIdentifier("pet_suggestion_\(index)")

                Button {
                    autonomy.dismiss(suggestion.id)
                } label: {
                    Text("Нет")
                        .font(DS.Font.ui(11))
                        .foregroundStyle(Color(hex: "6B756D"))
                }
            }
        }
        .glassCard(radius: 20, padding: 14)
        .accessibilityIdentifier("pet_suggestion_\(index)")
    }

    // MARK: - Emotion debug chips

    private var emotionDebugRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Эмоции")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(registry_obs.emotions) { def in
                        Button {
                            engine.forceEmotion(id: def.id)
                        } label: {
                            Chip(title: def.name, selected: engine.currentEmotion.id == def.id)
                        }
                        .accessibilityIdentifier("emo_\(def.id)")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            Button {
                showDiary = true
            } label: {
                Label("Дневник", systemImage: "book.closed.fill")
                    .font(DS.Font.ui(14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(kind: .secondary))
            .accessibilityIdentifier("pet_diary")

            Button {
                PetIsland.shared.start()
            } label: {
                Label("На остров", systemImage: "square.on.square")
                    .font(DS.Font.ui(14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(kind: .primary))
            .accessibilityIdentifier("pet_island")
        }
    }

    // MARK: - Food Sheet

    private var foodSheet: some View {
        NavigationStack {
            ZStack {
                AtmosphereBackground()
                VStack(spacing: 16) {
                    SectionHeader("Выбери еду")
                        .padding(.horizontal, 20)

                    ForEach(Array(PetFood.menu.enumerated()), id: \.element.id) { idx, food in
                        Button {
                            store.feed(food: food)
                            showFoodSheet = false
                        } label: {
                            foodRow(food: food)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("food_\(idx)")
                    }
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Покормить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showFoodSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func foodRow(food: PetFood) -> some View {
        HStack(spacing: 14) {
            Text(food.emoji)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(DS.Font.ui(15, weight: .medium))
                    .foregroundStyle(Color(hex: "EEF1EC"))
                HStack(spacing: 8) {
                    statDelta(label: "сытость", value: food.satietyDelta, tint: Color(hex: "E8894A"))
                    statDelta(label: "энергия", value: food.energyDelta, tint: Color(hex: "F2B25C"))
                    statDelta(label: "настр.", value: food.moodDelta, tint: Color(hex: "A8C5A0"))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Color(hex: "6B756D"))
        }
        .glassCard(radius: 20, padding: 14)
        .padding(.horizontal, 16)
    }

    private func statDelta(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text("+\(Int(value * 100))%")
                .font(DS.Font.ui(10, weight: .medium))
                .foregroundStyle(tint)
            Text(label)
                .font(DS.Font.ui(10))
                .foregroundStyle(Color(hex: "6B756D"))
        }
    }
}

// MARK: - RegistryWrapper (ObservableObject wrapping EmotionRegistry for SwiftUI)

final class RegistryWrapper: ObservableObject {
    static let shared = RegistryWrapper()
    let emotions: [EmotionDef]
    private init() { emotions = EmotionRegistry.shared.all }
}
