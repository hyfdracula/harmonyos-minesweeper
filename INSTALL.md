# 安装说明（HarmonyOS / ArkTS 版 Win7 扫雷）

本文给**从 release 下载安装包**的人。仓库里的源码在 `entry/`，
自带完整的 DevEco Studio 工程。

---

## 1. 你需要什么

| 东西 | 说明 |
|---|---|
| 一台 HarmonyOS 设备 | 手机或平板都行；本项目的验收目标机是 **华为 MatePad Pro 12.2** |
| 华为开发者账号 | 免费注册，用来自动生成你自己的签名材料 |
| DevEco Studio | [官方下载](https://developer.huawei.com/consumer/cn/deveco-studio/)（也带 hdc 命令行工具） |
| release 附件 | `harmonyos-minesweeper-unsigned.hap`（**未签名**，下面要自己签一次） |

> **为什么附件是未签名的**：HarmonyOS 的安装包必须签名才能装。
> 我们发布的是**未签名**包，你用自己的签名材料签出来的包，
> 装到**你自己的设备**上不会有任何限制。
> （反过来，我们那个已经签过名的调试包只对开发者本人那两台设备有效，
> 别人直接装会报 `9568423 device is unauthorized`。）

---

## 2. 办法一：用 DevEco Studio 签（推荐）

1. **连上设备**：USB 连电脑，在设备上打开「开发者选项 → USB 调试」，
   并接受调试授权。DevEco Studio 会自动认出这台设备。
2. **生成你自己的签名材料**：
   DevEco Studio 打开任意工程 → 菜单 **File → Project Structure → Signing Configs**
   → 勾选 **Automatically generate signature**（自动签名），
   登录华为开发者账号 → 勾选刚才那台设备 → **OK**。
   DevEco 会在 `C:\Users\<你>\.ohos\config\` 下生成三个文件：
   `<bundle>.cer` / `<bundle>.p12` / `<bundle>.p7b`。
3. **签这个 HAP**：
   同一个 **Signing Configs** 面板里，把签名材料填好之后，
   把 release 附件 `harmonyos-minesweeper-unsigned.hap` 拖进 DevEco，
   或者在 **Build → Build Hap(s)/APP(s) → Build HAP(s)** 里，
   用本仓库的工程直接编一份（效果一样，编出来的是已签名的）。
4. **装到设备**：

```bash
hdc list targets                                   # 确认设备在列
hdc install -r entry-default-signed.hap
```

（`hdc` 在 DevEco Studio 的 `sdk/default/openharmony/toolchains/` 目录下，
需要把它加进 PATH，或者直接写全路径。）

---

## 3. 办法二：命令行签名（不用 DevEco 编译）

SDK 自带签名工具 `hap-sign-tool.jar`（在
`sdk/default/openharmony/toolchains/lib/` 下），
配合 DevEco 自动签名生成的那三个材料就能签：

```bash
java -jar hap-sign-tool.jar sign-app \
  -mode localSign \
  -keyAlias "debugKey" \
  -keyPwd <你的密钥口令> \
  -appCertFile "<bundle>.cer" \
  -profileFile "<bundle>.p7b" \
  -signAlg SHA256withECDSA \
  -keystoreFile "<bundle>.p12" \
  -keystorePwd <你的密钥库口令> \
  -inFile harmonyos-minesweeper-unsigned.hap \
  -outFile harmonyos-minesweeper-signed.hap
```

然后：

```bash
hdc install -r harmonyos-minesweeper-signed.hap
```

> 参数含义（SDK 自带 `java -jar hap-sign-tool.jar -h` 有完整说明）：
> `-mode localSign` = 本地签名；`-keyAlias` = 密钥别名（DevEco 默认是 `debugKey`）；
> `-appCertFile` = 证书；`-profileFile` = 描述文件（p7b）；
> `-keystoreFile`/`-keystorePwd` = 密钥库及口令；`-signAlg` = 签名算法。

---

## 4. 从源码自己编（想改代码的人）

```bash
git clone https://github.com/hyfdracula/harmonyos-minesweeper.git
```

用 DevEco Studio 打开这个目录 → 按上面第 2 步配好签名 →
**Build → Build Hap(s)/APP(s) → Build HAP(s)** →
产物在 `entry/build/default/outputs/default/entry-default-signed.hap`。

命令行构建（本项目用的脚本，在规格仓里）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
```

> 注意：`build-profile.json5` 里的签名路径指向**本机**的
> `C:\Users\19161\.ohos\config\...`，你要改成自己的路径，
> 或者直接用 DevEco 的「自动签名」（它会改写这个文件）。

---

## 5. 设备要求与已知限制

| 项目 | 值 |
|---|---|
| 目标 SDK | API 26（HarmonyOS 5 / NEXT） |
| 最低兼容 | API 26 |
| bundle name | `com.example.saolei` |
| 验收目标机 | 华为 MatePad Pro 12.2（画布 1840×2650 竖屏 / 2800×1840 横屏，密度 3.5） |
| 折叠屏 | 代码层面支持（折叠换屏重取密度、重建布局），但**未针对华为 Pura X Max 做适配与验收** |

**已知限制**（与 README §5 一致）：

1. 帮助窗口的文字是**我们自己写的中文措辞**，不是 Win7 帮助的逐字翻译。
2. 对话框按钮文案**未与原版逐字核对**。
3. 开局发牌动画**不能点击跳过**（结算动画可以，与原版一致）。
4. 两处音效的归属疑似与原版对调（`firstPaint` 与 `gameStart`），已标注未改。
5. 键盘快捷键只有显示、没有功能。

另外有一条是**我们自己加的增强**（原版没有）：
局终关掉结算框之后，再点棋盘会**同盘面重开一局**；
原版 Win7 局终后棋盘是锁死的，重开只能用菜单「游戏 → 新建」或 F2。

---

## 6. 授权

- **代码**：MIT，见 `LICENSE`。
- **素材**：`entry/src/main/resources/rawfile/` 下的 10 个 PNG 与 15 个 WAV
  是从原版 `minesweeper.exe` 里提取的**微软原始资源**，
  **不在 MIT 授权范围内**，仅供个人学习研究使用，详见 `ASSETS-NOTICE.md`。
  发布这个安装包等于把这些素材一并分发，请自行确认用途合规。
