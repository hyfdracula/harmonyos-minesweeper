# saolei —— Windows 7 扫雷的 HarmonyOS 复刻

Windows 7 扫雷的 HarmonyOS（ArkTS）复刻，逐像素对齐原版：精灵图集、菜单栏、
结束对话框、帮助/关于/颜色/自定义对话框、七段数码管状态条、爆炸与胜利拆雷动画、
开局发牌动画，全部按原版的尺寸与配色画在一块 Canvas 上，不是系统浮层。

| 项 | 值 |
|---|---|
| 工程形态 | DevEco Studio 工程（HarmonyOS NEXT / API 26，ArkTS） |
| bundleName | `com.example.saolei` |
| versionName / versionCode | `1.0.0` / `1000000` |
| 设备类型 | `phone` / `tablet` / `2in1`（见 `entry/src/main/module.json5`） |
| 目录 | `entry/src/main/ets/`（逻辑与绘制）、`entry/src/main/resources/rawfile/`（原版素材） |

已实现并跑通的功能：三个难度、问号标记、长按插旗、和弦、计时与剩余雷数、
胜负判定、自定义难度、成绩统计窗口、帮助窗口、关于窗口、颜色（外观）对话框、
蓝/绿棋盘与扫雷/花园玩法、踩雷爆炸级联、胜利拆雷扫描条、开局发牌动画、
状态条七段数码管计数器。

---

## 1. 目标平台与适配

**目标机是华为 MatePad Pro 12.2 平板**（真机，序列号 `3KQYD25331202962`）。
2026-11-04 起，原来的折叠屏目标机 Pura X Max 典藏版**不再做适配**（用户决定），
下面那张表里它只作为「曾经验过什么」的记录。

| 设备 | 屏幕 | 已验内容 |
|---|---|---|
| **MatePad Pro（真机，当前目标机）** | 2800x1840（横屏）/ 1840x2650（竖屏） | 横屏四个盘面与推演逐项吻合；竖屏整轮四域回归 **85/86**（唯一那条失败是设备熄屏，不是应用问题） |
| Pura X Max（真机，**已按用户决定跳过适配**） | 内屏 2584x1824（横屏）/ 外屏 1323x1936（竖屏） | 安装、启动、布局与离线推演逐项吻合、七段读数反解一致；**真机四域回归与折叠/外屏的人工检查不再做** |
| Mate X7 / Mate 90 Pro / MatePad 12.2（模拟器） | 2210x2416 / 1280x2832 / 2800x1840 | 四域点击回归全绿 |

折叠屏的**代码**留着（折叠换屏重取密度、`windowSizeChange` 重建布局、双屏几何表）——
那是通用机制，平板的横竖屏切换走同一条路。

适配方式（都在 `entry/src/main/ets/common/GameController.ets` 里）：

- **版式现算**：`layout()` 按当前画布尺寸与密度算「适配档 n」（格边 = 18 x 2n 参考像素），
  `applyGeometry()` 算棋盘/状态条/菜单栏各矩形，`clampPan()` 夹平移范围。
- **小到点不准就抬档**：整盘装得下的那一档若格边 < 48 设备像素，宁可让棋盘纵向溢出
  也要抬到够大的一档（`MIN_CELL_PX = 48`）。
- **装不下时顶对齐 + 状态条钉底（HUD）**：棋盘顶对齐菜单栏下沿，状态条钉在画布底边，
  保证计时与雷数永远看得见；被状态条盖住的格子不参与命中判定。
- **折叠开合**：画布尺寸变化经 `onAreaChange` 重新布局；对局状态（棋盘、旗子、秒数、
  难度、已开对话框）放在模块级单例 `GameSession` 里，页面重建或折叠换屏都不丢局。

---

## 2. 构建

### 用 DevEco Studio

1. DevEco Studio 打开本工程；
2. 菜单 `Build` -> `Build Hap(s)/APP(s)` -> `Build Hap(s)`；
3. 产物：`entry/build/default/outputs/default/entry-default-signed.hap`。

### 用命令行

需要本机装 DevEco Studio（脚本用它自带的 hvigor 与 SDK）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <规格仓>\tools\build.ps1
# 产物路径写在脚本输出里；也可显式指定工程目录：
powershell -NoProfile -ExecutionPolicy Bypass -File <规格仓>\tools\build.ps1 -Project <本工程目录>
```

### 装到设备

```powershell
$hdc = 'D:\software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t <设备地址> install -r entry\build\default\outputs\default\entry-default-signed.hap
& $hdc -t <设备地址> shell aa start -a EntryAbility -b com.example.saolei
```

调试签名要在 DevEco 里对目标设备重新自动签名，否则会报
`code:9568423 device is unauthorized`。

---

## 3. 目录结构

```
entry/src/main/
|-- ets/
|   |-- common/                 逻辑与绘制（全部画在 Canvas 上）
|   |   |-- GameController.ets  总控：布局、缩放档、平移、命中、菜单、对话框
|   |   |-- MinesweeperEngine.ets 规则层（纯逻辑，由规格仓 engine/ 同步而来）
|   |   |-- SevenSeg.ets        七段数码管计数器渲染器
|   |   |-- Anim.ets            爆炸级联与胜利扫描条动画
|   |   |-- DealIn.ets          开局发牌动画
|   |   |-- Ripple.ets          展开涟漪
|   |   |-- Theme.ets           精灵坐标、状态条常量、配色
|   |   |-- SpriteAtlas.ets     精灵图集加载与按逻辑坐标绘制
|   |   |-- WinDialog.ets       结束框/帮助框/关于框的版式与命中区
|   |   |-- WinMenu.ets         菜单栏与下拉菜单
|   |   |-- StatsWindow.ets     成绩统计窗口
|   |   |-- CustomField.ets     自定义难度对话框
|   |   |-- NumKeypad.ets       画布上的数字键盘
|   |   |-- Appearance.ets      颜色（外观）对话框
|   |   |-- GameStats.ets       成绩与外观设置的持久化
|   |   `-- SoundPlayer.ets     音效播放
|   |-- components/
|   |   `-- MinefieldCanvas.ets Canvas 组件：画布、手势、触摸换算
|   |-- entryability/
|   |   `-- EntryAbility.ets    Ability 生命周期
|   `-- pages/
|       `-- Index.ets           页面（只有一个铺满的画布）
`-- resources/rawfile/          原版素材（见第 6 节声明）
```

---

## 4. 玩法

### 手势

| 操作 | 效果 |
|---|---|
| 单击 | 翻开格子 |
| 长按（约 400 ms） | 插旗 / 取消旗 |
| 双击已翻开的数字格 | 和弦：周围旗数吻合才展开 |
| 单指拖动 | 平移棋盘（棋盘比屏幕大时才可拖） |
| 双指捏合 | 缩放（8 档） |

### 菜单

顶部菜单栏画在画布上，两组：

- `游戏(G)`：新建 / 初级 / 中级 / 高级 / 自定义 / 标记(?) / 声音 / 最佳成绩 / 颜色(C) / 退出
- `帮助(H)`：帮助(H) / 关于扫雷

菜单项后面的 `F2`、`X`、`F1`、`A` 是**原版菜单的加速键写法**，本项目把它们**照原样画出来**
（为了像素对齐），但**没有实现物理键盘事件处理**（`onKeyEvent` 全仓没有）：触屏设备上
这些字母不可用，重开请用菜单里的「新建」，切换难度用菜单里的三档或「自定义」。

`标记(?)` 控制是否显示问号标记；`声音` 控制音效开关，两者都会立即生效并持久化。
`最佳成绩` 打开独立的「扫雷统计信息」窗口；`颜色(C)` 可以换蓝/绿棋盘与扫雷/花园玩法。

---

## 5. 已知偏差

如实列出目前与原版仍有差距的地方：

1. **帮助窗口的文字是我们自己写的中文措辞**。窗口形态与插图用的是原版素材
   （`helpBoard.png`），右侧 6 行说明文字不是 Win7 帮助的逐字翻译。
2. **对话框按钮文案未与原版逐字核对**。结束框现在写的是「再玩一局(P) / 退出(X)」（胜利框）
   与「退出(X) / 换个难度(D) / 再玩一局(P)」（失败框），
   这是照着一个第三方 Win7 克隆实现的对话框截图做的，而那个克隆的对话框本身是它自己设计的，
   **原版到底叫什么、怎么排，目前没有证据**。
3. **开局发牌动画不能点击跳过**。结算动画（爆炸级联、胜利扫描条）**可以**点一下立刻跳过，
   与原版行为一致；但 `DealIn.ets` 的发牌动画没有跳过实现。
4. **两处音效的归属疑似与原版对调**（标记为疑似，未改）：原版的 `firstPaint.wav` 是发牌动画的配乐，
   本项目把它挂在「首点开格」上，发牌用的是 `gameStart.wav`。
5. **键盘快捷键只有显示、没有功能**（见第 4 节）。
6. **局终关掉结算框之后，点棋盘会重开一局 —— 这是我们自己加的，不是原版行为**。
   原版 Win7 局终后棋盘是**锁死**的（Win7 保真复刻 `BoardWidget.cpp:783-793`
   把局终后的点击全部吃掉），重开只能用菜单「游戏 → 新建」或 F2；
   而 Win7 状态条上又没有笑脸按钮，所以在不碰菜单的前提下没有第二条路重开，
   容易被当成应用卡住。按项目的口径（自加的易用性单独标注为增强，
   不写进「与 Win7 一致」的清单），这个功能单列为增强。

另有一条不算「偏差」但值得知道：加速键字母（`P`、`D`、`X` 等）在菜单和对话框上
**没有画下划线**，这与参考截图一致，但与 Win7 原版的画法不同。

---

## 6. 素材声明

`entry/src/main/resources/rawfile/` 下的文件是**微软 Windows 7 扫雷（minesweeper.exe）的原始资源**，
由第三方从原版程序里提取，**逐字节原样**放在本仓库里：

- 图集 10 张：`blueSheet.png`、`greenSheet.png`、`otherSheet.png`、`minesweeperSheet.png`、
  `flowerGardenSheet.png`、`helpBoard.png`、`thumbBlue.png`、`thumbGreen.png`、
  `thumbMines.png`、`thumbFlowers.png`
- 音效 15 个：`firstPaint.wav`、`gameStart.wav`、`gameWin.wav`、`gameLose.wav`、
  `flowerLoseShort.wav`、`flowerLoseMedium.wav`、`flowerLoseLong.wav`、`mineBombStart.wav`、
  `mineBombRun.wav`、`mineBombEnd.wav`、`tileSingle.wav`、`tileMultiple.wav`、
  `zeroDevelop.wav`、`invalidMove.wav`、`dbButtonClickFlag.wav`

这些文件及其中体现的美术、音频作品**受各自权利人（微软公司）的版权保护**，
它们在这里是**逐字节原样**的，未作修改。本仓库**未获权利人授权进行分发**，
仅供**个人学习与技术研究**使用，**不作商业分发**，也不表示权利人对本项目背书。
若你是权利人并希望这些文件移除，**删除 `entry/src/main/resources/rawfile/` 下的对应文件即可**
（代码侧有 `try/catch` 兜底，缺图缺音只会打一条错误日志并相应降级，不会崩溃）。

**这 25 个文件不在本仓库的 MIT 授权范围内** —— 详见第 8 节与 `LICENSE`。
**逐个文件的清单、来源与用途**见同目录的 **`ASSETS-NOTICE.md`**。

其余代码（`entry/src/main/ets/` 下的全部 `.ets`）为原创实现，采用 MIT 许可。

---

## 7. 怎么验证这个复刻

本仓库只放应用；**客观验证工具、规格与证据在另一个仓**（扫雷规格仓）里：

| 验证手段 | 覆盖 | 当前结果 |
|---|---|---|
| 四域点击回归（菜单/棋盘/对话框/自定义，共 86 条用例） | 触摸路由、菜单动作、对话框按钮、自定义框与数字键盘 | 三台模拟器 86/86 |
| 版式离线推演（803 条断言） | 手机/平板/折叠屏各种画布与密度下的缩放档、格边、原点、溢出、平移范围 | 全过 |
| 引擎 / 七段 / 求解器单元测试 | 规则层 59 条、七段渲染器 11 条、跑测器求解器 14 条 | 全绿 |

跑测器与工具的说明见规格仓的 `README.md`，逐像素比对的记录见规格仓 `docs/` 下的
`DIALOG-PIXEL-DIFF*.md`、`MENU-PIXEL-DIFF.md`、`ANIM-PARITY.md` 等文档。

---

## 8. 许可

本仓库**有 LICENSE 文件**（MIT），授权范围与例外都写在里面。

**一句话：代码 MIT，素材不是。**

| 部分 | 授权 | 依据 |
|---|---|---|
| **代码**：`entry/src/main/ets/**` 下的全部 ArkTS 源码，以及工程配置与构建脚本 | **MIT** | `LICENSE` 第 1 节（MIT 全文） |
| **素材**：`entry/src/main/resources/rawfile/` 下的 10 个 PNG + 15 个 WAV | **不在 MIT 范围内**，著作权归**微软公司** | `LICENSE` 第 0 节（例外声明）+ `ASSETS-NOTICE.md` |

要点：

- **代码**采用 MIT：可自由使用、复制、修改、合并、发布、分发、再授权与销售，
  条件是保留版权声明与许可声明；软件按「原样」提供，不附带任何担保。
- **素材**（微软 Windows 7 扫雷原版资源）是**逐字节原样**的，**未获权利人授权进行分发**，
  仅供**个人学习与技术研究**、**不作商业分发**，也不表示权利人背书。
- **素材怎么移除**：删掉 `entry/src/main/resources/rawfile/` 下的对应文件即可；
  代码侧有 `try/catch` 兜底（缺图打 `[SpriteAtlas] … 加载失败`、缺音打 `[Sound] 播放失败`），
  相应降级而不崩溃，具体表现由维护者处理。
- **素材与代码的许可是两回事**：代码采用 MIT，不代表素材也采用 MIT；
  MIT 的授权范围里**明确排除了**这个目录。

配套文件：

- `LICENSE` —— MIT 全文 + 素材例外声明（第 0 节在前，第 1 节是 MIT 正文）。
- `ASSETS-NOTICE.md` —— 25 个素材**逐个列出**（文件名、字节数、是什么）、
  来源、权利与用途限制、移除方式。
- 规格仓（`minesweeper`）另有一份自己的 `LICENSE`：那里的代码也是 MIT，
  且**不含**微软素材；它对外部参考实现的许可另有说明。
