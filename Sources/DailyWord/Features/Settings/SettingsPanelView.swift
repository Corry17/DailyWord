import SwiftUI
import DailyWordCore

/// 独立设置窗口内容：每日词量 / 发音 / 题库 / 测试浮层 / 弹卡 / 自定义快捷键
/// 用独立窗口承载（而非 popover），避免系统颜色面板与 popover 的窗口层级冲突
struct SettingsPanelView: View {
    @ObservedObject var session: StudySession
    @ObservedObject private var settings = AppSettings.shared

    /// 全部词库（首次加载缓存）
    private var collections: [WordCollection] {
        (try? AppServices.shared.database.collections()) ?? []
    }

    /// 词库选择绑定：切换时保存并重建队列
    private var collectionBinding: Binding<String> {
        Binding(
            get: { settings.currentCollectionKey },
            set: { newValue in
                AppServices.shared.switchCollection(newValue)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // 词库选择
                Picker("词库", selection: collectionBinding) {
                    ForEach(collections, id: \.key) { c in
                        Text(c.name).tag(c.key)
                    }
                }
                Text("切换词库后，今日队列会按新词库重建；熟练度按单词全局同步，两词库重叠的词会共享熟练状态")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Stepper(value: Binding(
                    get: { session.dailyNewLimit },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: AppServices.dailyNewLimitKey)
                        session.updateDailyNewLimit(newValue)
                    }
                ), in: 5...100, step: 5) {
                    Text("每日新词：\(session.dailyNewLimit) 个")
                        .font(.callout)
                }

                Picker("发音", selection: $settings.accent) {
                    Text("🇺🇸 美音").tag(SpeechService.Accent.american)
                    Text("🇬🇧 英音").tag(SpeechService.Accent.british)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()
                Text("学习面板")
                    .font(.callout.weight(.medium))
                Text("菜单栏图标点击弹出的面板 与 ⌥W 浮动面板为同一界面，外观设置共用")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Text("背景 \(Int(settings.studyOpacity * 100))%")
                        .font(.caption)
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $settings.studyOpacity, in: 0...1.0)
                }
                FavoriteColorRow(label: "背景颜色", color: $settings.studyBackgroundColor,
                                 defaultColor: Color(nsColor: .windowBackgroundColor),
                                 favoriteKey: "studyBackground",
                                 onReset: { settings.studyBackgroundColor = nil })
                HStack {
                    Text("字号 \(Int(settings.wordFontSize))")
                        .font(.caption)
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $settings.wordFontSize, in: 20...44, step: 1)
                }
                FavoriteColorRow(label: "单词颜色", color: $settings.wordColor,
                                 defaultColor: Color(nsColor: .labelColor),
                                 favoriteKey: "studyWord",
                                 onReset: { settings.wordColor = nil })
                FavoriteColorRow(label: "释义颜色", color: $settings.definitionColor,
                                 defaultColor: Color(nsColor: .labelColor),
                                 favoriteKey: "studyDefinition",
                                 onReset: { settings.definitionColor = nil })
                HStack {
                    Text("透明度只影响背景，文字始终清晰；快捷键可调背景，⌃⌥方向键可移动面板")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("恢复默认") { settings.resetStudyAppearance() }
                        .controlSize(.small)
                }

                Divider()
                Text("测试面板")
                    .font(.callout.weight(.medium))
                HStack {
                    Text("背景 \(Int(settings.quizOpacity * 100))%")
                        .font(.caption)
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $settings.quizOpacity, in: 0...0.85)
                }
                FavoriteColorRow(label: "背景颜色", color: $settings.quizBackgroundColor,
                                 defaultColor: .black,
                                 favoriteKey: "quizBackground",
                                 onReset: { settings.quizBackgroundColor = nil })
                HStack {
                    Text("字号 \(Int(settings.quizFontSize))")
                        .font(.caption)
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $settings.quizFontSize, in: 14...32, step: 1)
                }
                FavoriteColorRow(label: "词语颜色", color: $settings.quizWordColor,
                                 defaultColor: .white,
                                 favoriteKey: "quizWord",
                                 onReset: { settings.quizWordColor = nil })
                FavoriteColorRow(label: "释义颜色", color: $settings.quizDefinitionColor,
                                 defaultColor: .white,
                                 favoriteKey: "quizDefinition",
                                 onReset: { settings.quizDefinitionColor = nil })
                HStack {
                    Text("恢复默认")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("恢复默认") { settings.resetQuizAppearance() }
                        .controlSize(.small)
                }

                Divider()
                Text("题库")
                    .font(.callout.weight(.medium))
                Text("词库列表界面，外观设置独立于学习面板")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Text("字号 \(Int(settings.libraryFontSize))")
                        .font(.caption)
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $settings.libraryFontSize, in: 14...44, step: 1)
                }
                FavoriteColorRow(label: "单词颜色", color: $settings.libraryWordColor,
                                 defaultColor: Color(nsColor: .labelColor),
                                 favoriteKey: "libraryWord",
                                 onReset: { settings.libraryWordColor = nil })
                FavoriteColorRow(label: "释义颜色", color: $settings.libraryDefinitionColor,
                                 defaultColor: Color(nsColor: .secondaryLabelColor),
                                 favoriteKey: "libraryDefinition",
                                 onReset: { settings.libraryDefinitionColor = nil })
                HStack {
                    Text("恢复默认")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("恢复默认") { settings.resetLibraryAppearance() }
                        .controlSize(.small)
                }

                Divider()
                Text("复习提示弹卡")
                    .font(.callout.weight(.medium))
                HStack {
                    Text("位置")
                        .font(.caption)
                    Spacer()
                    Picker("", selection: $settings.ambientPosition) {
                        ForEach(AmbientPosition.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .onChange(of: settings.ambientPosition) { _ in
                        AppServices.shared.ambient.reposition()
                    }
                }
                HStack(spacing: 6) {
                    TextField("", value: $settings.ambientIntervalMinutes, formatter: NumberFormatter())
                        .frame(width: 50)
                    Stepper(value: $settings.ambientIntervalMinutes, in: 1...120, step: 1) {
                        Text("")
                    }
                    .labelsHidden()
                    Text("分钟弹卡一次")
                        .font(.caption)
                }
                .onChange(of: settings.ambientIntervalMinutes) { _ in
                    AppServices.shared.ambient.checkNow()
                }

                Divider()
                HStack {
                    Text("快捷键（点击后直接按组合键）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("全部恢复默认") { settings.resetAllHotKeys() }
                        .controlSize(.small)
                }
                ForEach(HotKeyAction.allCases) { action in
                    HStack(spacing: 4) {
                        Text(action.title)
                            .font(.caption)
                        Spacer()
                        HotKeyRecorder(binding: settings.hotKeys[action] ?? .none) { newBinding in
                            settings.setHotKey(newBinding, for: action)
                        }
                        Button {
                            settings.resetHotKey(for: action)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("恢复默认：\(action.defaultBinding.label)")
                    }
                }
                Text("不带 ⌘⌥⌃⇧ 的按键（如空格）仅在 DailyWord 面板内生效")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()
                Text("翻译")
                    .font(.callout.weight(.medium))
                Toggle("划词翻译整句（关闭则仅翻译选中的部分）",
                       isOn: $settings.translateWholeSentence)
                    .font(.caption)
                Text("开启：选中句子的一部分时，翻译包含它的完整句子；关闭：只翻译选中的文字")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Text("划词翻译需要辅助功能权限")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("重新申请权限") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                    .controlSize(.small)
                    .help("如果之前拒绝了权限，点击重新弹出系统授权窗口")
                }

                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("测试浮层：选择题可用 1234 或 ABCD；双击浮层关闭")
                    Text("学习界面：三连击空白处可快速关闭")
                    Button("重看上手引导") {
                        AppServices.shared.closeSettingsWindow()
                        AppServices.shared.showOnboarding()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()
                Text("数据管理")
                    .font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Button("导出数据…") { AppServices.shared.showExportDataDialog() }
                        .controlSize(.small)
                    Button("导入数据…") { AppServices.shared.showImportDataDialog() }
                        .controlSize(.small)
                }
                Text("导出时勾选要备份的部分；生成 JSON 文件，可在其他电脑导入，词库熟练度按单词合并")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 300, height: 500)
    }
}
