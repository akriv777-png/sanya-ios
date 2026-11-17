// PetDiaryView.swift — weekly diary screen
// Sanya/Modules/Pet/PetDiaryView.swift

import SwiftUI

struct PetDiaryView: View {
    @ObservedObject private var diary = PetDiary.shared
    @ObservedObject private var store = PetStore.shared

    var body: some View {
        ZStack {
            AtmosphereBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader("Как я провёл неделю")
                        .padding(.horizontal, 16)

                    // Generate button
                    Button {
                        Haptics.tap()
                        diary.generateCurrentWeek()
                    } label: {
                        HStack {
                            if diary.isGenerating {
                                ProgressView()
                                    .tint(Color(hex: "A8C5A0"))
                                    .padding(.trailing, 4)
                            }
                            Text(diary.isGenerating ? "Пишу..." : "Сгенерировать эту неделю")
                                .font(DS.Font.ui(15, weight: .medium))
                                .foregroundStyle(Color(hex: "0B0E0C"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .primary))
                    .padding(.horizontal, 16)
                    .disabled(diary.isGenerating)

                    Button {
                        Haptics.soft()
                        diary.generateCurrentWeek(useAI: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Переписать с ИИ")
                                .font(DS.Font.ui(15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .secondary))
                    .padding(.horizontal, 16)
                    .disabled(diary.isGenerating || !AIClient.isConfigured)
                    .accessibilityIdentifier("diary_ai")

                    if diary.entries.isEmpty && !diary.isGenerating {
                        emptyState
                    }

                    ForEach(diary.entries) { entry in
                        entryCard(entry)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Дневник")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pet_diary_screen")
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            PetStaticSprite(sprite: "calm", size: 80)
            Text("Пока нечего читать.")
                .font(DS.Font.ui(15))
                .foregroundStyle(Color(hex: "9AA59C"))
            Text("Нажми кнопку — я расскажу про неделю.")
                .font(DS.Font.ui(13))
                .foregroundStyle(Color(hex: "6B756D"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(radius: 28, padding: 16)
        .padding(.horizontal, 16)
    }

    private func entryCard(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.weekLabel)
                    .font(DS.Font.ui(13, weight: .medium))
                    .foregroundStyle(Color(hex: "9AA59C"))
                Spacer()
                Text(entryDateFormatted(entry.generatedAt))
                    .font(DS.Font.ui(11))
                    .foregroundStyle(Color(hex: "6B756D"))
            }

            Divider().overlay(Color(hex: "EEF1EC").opacity(0.08))

            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                Text("— \(line)")
                    .font(DS.Font.ui(14))
                    .foregroundStyle(Color(hex: "EEF1EC"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard(radius: 28, padding: 20)
        .padding(.horizontal, 16)
    }

    private func entryDateFormatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }
}
