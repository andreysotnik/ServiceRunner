import AppKit
import SwiftUI

struct ServiceEditorView: View {
    @State var config: ServiceConfig
    let isNew: Bool
    let onSave: (ServiceConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !config.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !config.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Новый сервис" : "Редактирование").font(.title2.bold())
            Form {
                TextField("Название", text: $config.name, prompt: Text("Например, API"))
                LabeledContent("Команда") {
                    TextEditor(text: $config.command)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
                LabeledContent("Рабочая папка") {
                    HStack {
                        TextField("", text: $config.workingDirectory, prompt: Text("~/Projects/app"))
                        Button("Выбрать…", action: chooseDirectory)
                    }
                }
                Toggle("Запускать при старте приложения", isOn: $config.autoStart)
                Toggle("Перезапускать при падении", isOn: $config.autoRestart)
            }
            Text("Команда выполняется в login-shell ($SHELL -l -c), как в терминале.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Добавить" : "Сохранить") {
                    config.name = config.name.trimmingCharacters(in: .whitespaces)
                    config.command = config.command.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            config.workingDirectory = url.path
        }
    }
}
