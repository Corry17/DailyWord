# DailyWord

一款 macOS 菜单栏英语学习应用：把背单词、间隔复习和答题练习融入日常工作，还能通过修仙爬塔积累经验与装备。

使用 SwiftUI + AppKit 开发，内置 SQLite 词库。核心背词与复习可离线使用；在线翻译和部分例句查询需要联网。

## 功能

- **菜单栏学习**：点击菜单栏图标打开背词面板，空格翻面、数字键 1–4 自评；支持全局快捷键。
- **间隔重复**：默认采用艾宾浩斯阶梯调度，按到期复习与每日新词额度生成队列；核心库另提供 SM-2 实现。
- **多词库**：小学、初中、高中、四级、六级、考研、专四、专八、雅思、托福、GRE、BEC、PTE。当前预置库共 17,494 个去重词条；BEC、PTE 暂复用雅思词表，并非独立官方词表。
- **悬浮练习与无感复习**：选择、拼写等练习，以及屏幕角落的到期词卡。
- **发音与查词**：系统 TTS 英音/美音、词库搜索、释义与熟悉度管理。
- **修仙爬塔**：答题战斗、角色、装备、背包与图鉴；学习经验、成就和连续打卡联动。
- **外观与数据管理**：调整颜色、字号、透明度；按设置、词库学习记录、目标与游戏进度导出或导入 JSON。
- **在线翻译**：Google、MyMemory、百度词典依次尝试，服务可用性受网络和第三方接口影响。

## 构建与运行

### 环境要求

- macOS 13 或更高版本；不支持 Windows/Linux 运行界面应用。
- Swift 5.9 或更高版本及可用的 Xcode / Command Line Tools。
- 首次构建需要联网获取 Swift Package 依赖；当前 `Package.resolved` 固定 GRDB.swift 6.29.3。

```bash
git clone https://github.com/Corry17/DailyWord.git
cd DailyWord
swift build --product DailyWord
swift run DailyWord
```

应用启动后位于菜单栏，不显示 Dock 图标。单击菜单栏图标开始背词；右键或双击打开更多功能菜单。快捷键可在设置中查看和修改。

构建优化版本：

```bash
swift build -c release --product DailyWord
```

这里提供的是源码工程；上述命令不会生成已签名、公证的 DMG 安装包。

### 核心测试

```bash
swift run TestRunner
```

项目使用自定义测试执行器，而非 XCTest 测试目标。测试覆盖 SM-2、艾宾浩斯调度、学习队列、熟练度、统计与奖励逻辑；数据库测试使用内存数据库，不代表全部 UI 和第三方服务均已通过端到端验证。

## 项目结构

```text
Sources/
├── DailyWord/                 # 菜单栏入口、AppKit/SwiftUI 界面与应用服务
│   ├── Features/              # 学习、练习、词库、游戏、翻译、设置等
│   └── Resources/             # 例句等资源
└── DailyWordCore/             # 数据库、SRS、学习会话、奖励与发音
    └── Resources/words.sqlite # 预置只读词库来源
Tests/TestRunner/              # 轻量核心测试执行器
Tools/dict-builder/            # 从词典与考纲词表生成 SQLite
Tools/gen_items.py             # 游戏物品数据生成工具
docs/                         # 产品设计与版本记录
LICENSES/                     # 随附第三方许可
```

## 数据与隐私

- 学习数据库位于 `~/Library/Application Support/DailyWord/dailyword.sqlite`，设置与部分游戏状态保存在本机 `UserDefaults`。
- 仓库中的 `words.sqlite` 只包含预置词条、词库和词库关系，不含个人学习记录。
- JSON 备份可能包含设置、学习流水、目标和游戏进度，请勿公开上传。导入前建议先导出当前数据备份。
- 在线翻译会把待翻译内容发送给相应第三方服务；在线例句查询也会发送查询词。敏感文本请勿使用联网翻译功能。
- 本版本提供手动导入导出；设计文档中的自动文件同步等规划不等同于已实现功能。

## 词库来源与重建

仓库已附带预置 SQLite，普通构建无需重新生成词库。体积较大的原始 CSV 与下载数据不纳入 Git。

如需重建，先自行准备：

1. [ECDICT](https://github.com/skywind3000/ECDICT) 的 `ecdict.csv`，放入 `Tools/dict-builder/data/ECDICT/`。
2. [english-wordlists](https://github.com/mahavivo/english-wordlists) 的词表，放入 `Tools/dict-builder/data/wordlists/`：`xiaoxue.txt`、`zhongkao.txt`、`gaozhong.txt`、`kaoyan.txt`、`zhuansi.txt`、`zhuanba.txt`。
3. 使用 Python 3 运行以下命令（会覆盖现有预置词库）：

```bash
python3 Tools/dict-builder/build_dict.py \
  Tools/dict-builder/data/ECDICT/ecdict.csv \
  Sources/DailyWordCore/Resources/words.sqlite
```

不同上游版本可能生成不同词条数量。重新生成后请检查变更并重新构建。

## 分支与版本历史

| 分支 | 用途 |
| --- | --- |
| [`main`](https://github.com/Corry17/DailyWord/tree/main) | 用户指定的最终版 + 项目说明 + 后续修复（编译错误、翻译窗口层级） |
| [`archive/legacy-english`](https://github.com/Corry17/DailyWord/tree/archive/legacy-english) | `english` 目录的旧版源码快照 |
| [`archive/final-snapshot`](https://github.com/Corry17/DailyWord/tree/archive/final-snapshot) | `english_backup_20260814_142540` 目录的最终版原始源码快照 |

对应标签为 `snapshot-legacy`、`snapshot-final`。两份来源目录均未包含项目 `.git`；这里保存的是**本次导入的真实文件快照及其差异**，不是恢复出的逐次开发提交。提交日期为实际导入日期，版本先后以作者指定为准。

```bash
git fetch origin --tags
git log --all --graph --decorate --oneline
git diff --stat snapshot-legacy snapshot-final
git diff snapshot-legacy snapshot-final -- Sources
```

更多来源、差异与查看方法见 [版本历史](docs/版本历史.md)，也可查看 [提交列表](https://github.com/Corry17/DailyWord/commits/main/)。

## 设计文档

- [产品构思文档](docs/产品构思文档.md)
- [游戏设计文档](docs/游戏设计文档.md)
- [关卡系统重设计](docs/关卡系统重设计.md)

设计文档包含不同阶段的构思和待办，当前行为以 `main` 中的实际源码为准。

## 第三方许可

- [GRDB.swift](https://github.com/groue/GRDB.swift)：依赖库许可见上游仓库。
- ECDICT 随附许可原文保留在 [LICENSES/ECDICT.txt](LICENSES/ECDICT.txt)，复制自已有词典数据目录。
- 词表等数据的使用与再分发需分别遵守对应上游许可；不应将第三方数据许可视为所有代码的统一许可。

本项目源码尚未单独声明开源许可证；公开仓库不等于额外授予源码再分发或商业使用许可。
