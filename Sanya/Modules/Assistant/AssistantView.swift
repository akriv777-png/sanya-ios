import SwiftUI

struct AssistantView: View {
    @ObservedObject private var model = AssistantModel.shared
    @StateObject private var speech = SpeechRecognizer()
    @State private var showSettings = false
    private let chips = ["Привет, Саня!", "Что ты умеешь?", "Таймер на 1 минуту", "Когда моя смена?", "Открой смены"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { MessageBubble(msg: $0).id($0.id) }
                        if model.thinking { TypingBubble().id("typing") }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let id = model.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if speech.isRecording || speech.error != nil {
                ListeningOrb(level: speech.level, text: speech.error ?? (speech.transcript.isEmpty ? "Слушаю…" : speech.transcript))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { i, c in
                        Button(c) { model.send(c) }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.card2, in: Capsule())
                            .accessibilityIdentifier("chip_\(i)")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 6)
            inputBar
        }
        .background(Theme.background)
        .navigationTitle("🗣 Саня")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Настройки ИИ", systemImage: "gearshape") { showSettings = true }
                    Button("Очистить чат", systemImage: "trash", role: .destructive) { model.clear() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showSettings) { NavigationStack { AssistantSettingsView() } }
        .animation(.spring(duration: 0.35), value: speech.isRecording)
        .onChange(of: speech.isRecording) { _, rec in
            if !rec, !speech.transcript.isEmpty {
                model.send(speech.transcript)
                speech.transcript = ""
            }
        }
        .onDisappear { speech.stop() }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Напиши Сане…", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("chat_input")
                .onSubmit { model.send(model.input) }
            if model.input.isEmpty {
                Button { speech.toggle() } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title3.bold())
                        .frame(width: 46, height: 46)
                        .background(speech.isRecording ? Theme.accent : Theme.violet, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("chat_mic")
            } else {
                Button { model.send(model.input) } label: {
                    Image(systemName: "arrow.up").font(.title3.bold())
                        .frame(width: 46, height: 46)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("chat_send")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct MessageBubble: View {
    let msg: ChatMessage
    var body: some View {
        let mine = msg.role == "user"
        HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 50) }
            if !mine {
                Text("С").font(.caption.bold()).frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [Theme.violet, Theme.accent], startPoint: .top, endPoint: .bottom), in: Circle())
            }
            Text(msg.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    mine ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                         : AnyShapeStyle(Theme.card2),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
            if !mine { Spacer(minLength: 50) }
        }
        .transition(.move(edge: mine ? .trailing : .leading).combined(with: .opacity))
    }
}

struct TypingBubble: View {
    @State private var phase = false
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.white.opacity(0.7)).frame(width: 7, height: 7)
                        .offset(y: phase ? -4 : 2)
                        .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.card2, in: Capsule())
            Spacer()
        }
        .padding(.leading, 36)
        .onAppear { phase = true }
    }
}

struct ListeningOrb: View {
    let level: CGFloat
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle().stroke(Theme.violet.opacity(0.5 - Double(i) * 0.15), lineWidth: 2)
                        .frame(width: 60 + CGFloat(i) * 22 + level * 40, height: 60 + CGFloat(i) * 22 + level * 40)
                }
                Circle().fill(RadialGradient(colors: [Theme.accent, Theme.violet], center: .center, startRadius: 2, endRadius: 40))
                    .frame(width: 56 + level * 20, height: 56 + level * 20)
            }
            .frame(height: 130)
            .animation(.easeOut(duration: 0.1), value: level)
            Text(text).font(.callout).multilineTextAlignment(.center).padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.endpoint") private var endpoint = ""
    @AppStorage("ai.model") private var model = "gpt-4o-mini"
    @AppStorage("ai.speak") private var speak = true
    @State private var key = Keychain.get("ai.key")

    var body: some View {
        Form {
            Section {
                TextField("https://…/v1/chat/completions", text: $endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Модель", text: $model).textInputAutocapitalization(.never)
                SecureField("Ключ доступа", text: $key)
            } header: { Text("Сервер ИИ") } footer: {
                Text("OpenAI-совместимый адрес или свой прокси на боксе. Ключ хранится только в Keychain телефона. Пусто — демо-режим с локальными командами.")
            }
            Section("Голос") {
                Toggle("Озвучивать ответы", isOn: $speak)
            }
            Section("О приложении") {
                LabeledContent("Версия", value: "0.1.0 (MVP)")
                LabeledContent("Модулей готово", value: "\(Modules.ready.count) из \(Modules.all.count)")
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { Keychain.set(key, for: "ai.key"); dismiss() }
            }
        }
    }
}
