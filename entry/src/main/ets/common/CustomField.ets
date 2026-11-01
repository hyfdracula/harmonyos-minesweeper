/**
 * CustomField.ets —— 「自定义」难度对话框（菜单 游戏 → 自定义…）
 *
 * 规格来自 Win7 原版的自定义字段对话框（IDD_CUSTOM）：三行「标签 + 数字输入框」，
 * 底部两个按钮。三个值：
 *   高度 9..24（行）    宽度 9..30（列）    雷数 10..上限
 *
 * 雷数上限按本项目引擎规则（MinesweeperEngine.maxMinesFor）：
 *   maxMines = min(668, (行-1)*(列-1)+1)
 * 该式天然满足「雷数 < 总格数」：对 h,w >= 2 有 (h-1)(w-1)+1 <= h*w-1。
 * 9x9 时上限 = 8*8+1 = 65；24x30 时上限 = 23*29+1 = 668。
 *
 * 本文件只负责**规格 + 自绘**，不碰菜单、不碰控制器；
 * 主线程（GameController / Index）负责把它接到「自定义」菜单项上。
 *
 * 单位（与 WinDialog.ets / WinMenu.ets 完全一致，2026-10-31 真机实测）：
 *   - 几何坐标用「参考像素」，绘制时乘 sVp → vp（Canvas 的坐标单位是 vp）
 *   - ctx.font 里的 "px" 是**设备像素**，字号要乘 sDev（= sVp × 密度 2.75）
 *   所以 sDev 与 sVp 差一个密度，两个都要传，不能只传一个。
 *
 * ArkTS 约束（真机踩过的坑）：
 *   - CanvasRenderingContext2D 是**全局类型**，不能从 @kit.ArkUI 导入
 *   - 静态方法里禁止出现 this（arkts-no-standalone-this）→ 一律写 CustomField.xxx
 *   - 禁止 any / unknown，所有成员显式标注类型
 *   - createLinearGradient 的返回值（CanvasGradient）在不同 SDK 版本下类型名不稳定，
 *     这里沿用 WinDialog.ets 的既有写法用推断类型（仅本文件内，不外传）
 *   - 本文件**不 import MinesweeperEngine**：那个 .ets 是同步脚本生成的产物，
 *     依赖它有被覆盖的风险；下面的常量与引擎里的 CUSTOM_* 保持一致
 */

// ============================================================================
// 布局常量（全部是「参考像素」，= 原版 1 倍像素；绘制时乘 sVp）
// 主线程要微调外观，改这几个数就行
// ============================================================================

/** 对话框参考宽 */
export const DLG_W: number = 280;
/** 对话框参考高 */
export const DLG_H: number = 200;
/** 标题栏高 */
export const TITLE_H: number = 20;
/** 标题栏右上角关闭按钮尺寸 */
export const CLOSE_W: number = 18;
export const CLOSE_H: number = 14;

/** 三个标签的文字右对齐到这条竖线（标签在左、输入框在右） */
export const LABEL_RIGHT: number = 124;
/** 输入框左边界 */
export const EDIT_X: number = 132;
/** 输入框宽 / 高 */
export const EDIT_W: number = 60;
export const EDIT_H: number = 21;
/** 三个输入框的上边界，依次是 高度 / 宽度 / 雷数 */
export const EDIT_TOP: number[] = [46, 76, 106];

/** 底部提示行（左对齐） */
export const HINT_X: number = 20;
export const HINT_Y: number = 134;
export const HINT_SIZE: number = 10;

/** 底部两个按钮 */
export const BTN_Y: number = 158;
export const BTN_W: number = 70;
export const BTN_H: number = 25;
export const BTN_OK_X: number = 116;
export const BTN_CANCEL_X: number = 194;

/** 三个输入框的标签（内容在下面「取值范围」常量之后拼，避免上下限写死两处） */

// ---- 取值范围（与 MinesweeperEngine 的 CUSTOM_* 一致） ----------------------

/** 高度（行数）范围 */
export const MIN_ROWS: number = 9;
export const MAX_ROWS: number = 24;
/** 宽度（列数）范围 */
export const MIN_COLS: number = 9;
export const MAX_COLS: number = 30;
/** 雷数下限 */
export const MIN_MINES: number = 10;
/** 雷数硬上限（24 行 × 30 列时正好 = 668） */
export const MAX_MINES: number = 668;

// ---- 三个输入框的标签 ------------------------------------------------------
/**
 * 标签**照抄 Win7 原版的写法：上下限直接写在标签里**。
 *
 * 依据（两份互相独立的 Win7 复刻）：
 *   Lmy0217 `Minesweeper.rc:106-108`：
 *     LTEXT "高度(9-24)(&H):" / "宽度(9-30)(&W):" / "雷数(10-668)(&M):"
 *   linux-minesweeper `OptionsDialog.cpp:89-91`，注释原话：
 *     "The Windows 7 custom limits, spelled out in the labels like it does."
 *     form->addRow(tr("Height (9-24):"), m_rows) 等三行
 *
 * 标签由常量拼出来，改上下限时不会和标签脱节。
 * （改之前这里是 `['高度:', '宽度:', '雷数:']`，范围只出现在底部提示行里。）
 */
export const LABELS: string[] = [
  '高度(' + MIN_ROWS.toString() + '-' + MAX_ROWS.toString() + '):',
  '宽度(' + MIN_COLS.toString() + '-' + MAX_COLS.toString() + '):',
  '雷数(' + MIN_MINES.toString() + '-' + MAX_MINES.toString() + '):'
];

// ---- 颜色（沿用 WinDialog.ets 的 Win7 观感） --------------------------------

/** 客户区底色 */
const C_CLIENT: string = '#f0f0f0';
/** 标题栏 Aero 渐变（上浅下深） */
const C_TITLE_TOP: string = '#efe6f2';
const C_TITLE_BOTTOM: string = '#ded0e4';
/** 窗口外框 */
const C_BORDER: string = '#8a7f96';
/** 正文 */
const C_TEXT: string = '#000000';
/** 按钮渐变 */
const C_BTN_TOP: string = '#f7f7f7';
const C_BTN_BOTTOM: string = '#e2e2e2';
const C_BTN_BORDER: string = '#707070';
/** 关闭按钮红底 */
const C_CLOSE: string = '#c7433b';
/** 输入框凹槽的深边（上 / 左） */
const C_EDGE_DARK: string = '#a0a0a0';
/** 输入框凹槽的亮边（下 / 右） */
const C_EDGE_LIGHT: string = '#ffffff';
/** 聚焦输入框的蓝圈 */
const C_FOCUS: string = '#0078d7';
/** 提示行的灰字 */
const C_HINT: string = '#6a6a6a';

// ============================================================================
// 编辑状态（模块级）
// ============================================================================

/**
 * 上一次 inputChar 时的焦点索引。
 * 焦点一旦变了，下一次输入就**替换**框里的旧值（而不是追加），
 * 否则默认的 9 没法直接输入 19（"1" 会被当成追加 → 91）。
 */
let lastFocus: number = -1;

/**
 * 置位后，下一次输入替换框里的旧值。
 * 模拟 Win7 输入框「获得焦点即全选」的行为：点一下框，下一位数字就覆盖旧值。
 */
let replaceNext: boolean = true;

/** 点是否落在矩形内 */
function inRect(px: number, py: number, x: number, y: number, w: number, h: number): boolean {
  return px >= x && px <= x + w && py >= y && py <= y + h;
}

// ============================================================================
// 规格
// ============================================================================

/** 自定义难度的三个输入框的值与编辑状态 */
export interface CustomSpec {
  height: number;   // 行数 9..24
  width: number;    // 列数 9..30
  mines: number;    // 雷数
  /** 当前聚焦的输入框：0=高度 1=宽度 2=雷数 */
  focus: number;
}

/**
 * 「自定义」难度对话框的规格与绘制。
 *
 * 典型用法（主线程）：
 *   打开： const spec = CustomField.defaultSpec();  // 或 CustomField.specOf(rows, cols, mines)
 *   绘制： CustomField.draw(ctx, spec, sDev, sVp, oxVp, oyVp);
 *   点击： const id = CustomField.hit(spec, sDev, sVp, oxVp, oyVp, pxVp, pyVp);
 *         if (id === 'height' || id === 'width' || id === 'mines') { CustomField.focusField(spec, id); }
 *         else if (id === 'ok') { const ok = CustomField.clampSpec(spec); startNewGame(ok.height, ok.width, ok.mines); }
 *         else if (id === 'cancel') { closeDialog(); }
 *   键盘： CustomField.inputChar(spec, ch);  /  CustomField.backspace(spec);
 */
export class CustomField {
  /**
   * 默认规格：初级 9x9、10 雷，焦点在「高度」。
   * 调用它会重置编辑状态（下次输入是「替换」而不是「追加」）。
   */
  static defaultSpec(): CustomSpec {
    lastFocus = -1;
    replaceNext = true;
    const s: CustomSpec = { height: 9, width: 9, mines: 10, focus: 0 };
    return s;
  }

  /**
   * 用当前难度的行列数预填一份规格（打开「自定义」时用）。
   * 越界的值会被夹到合法区间。
   */
  static specOf(rows: number, cols: number, mines: number): CustomSpec {
    lastFocus = -1;
    replaceNext = true;
    const s: CustomSpec = { height: rows, width: cols, mines: mines, focus: 0 };
    return CustomField.clampSpec(s);
  }

  /**
   * 校验并夹取到合法范围。
   *
   * 注意：**就地修改并返回同一个对象**（不是返回新对象），
   * 所以 `CustomField.clampSpec(spec)` 与 `const s = CustomField.clampSpec(spec)` 两种写法都对。
   *
   * 夹取规则：
   *   高度 → [9, 24]，宽度 → [9, 30]，雷数 → [10, maxMines(高度, 宽度)]，焦点 → [0, 2]
   */
  static clampSpec(s: CustomSpec): CustomSpec {
    s.height = CustomField.clampInt(Math.round(s.height), MIN_ROWS, MAX_ROWS);
    s.width = CustomField.clampInt(Math.round(s.width), MIN_COLS, MAX_COLS);
    const maxM: number = CustomField.maxMines(s.height, s.width);
    s.mines = CustomField.clampInt(Math.round(s.mines), MIN_MINES, maxM);
    s.focus = CustomField.clampInt(Math.round(s.focus), 0, 2);
    return s;
  }

  /**
   * 当前规格下的最大雷数 = min(668, (行-1)*(列-1)+1)。
   * 行列先夹到合法区间再套公式，所以传进来的非法中间值（比如正在输入的 1）也返回合法上限。
   */
  static maxMines(height: number, width: number): number {
    const h: number = CustomField.clampInt(Math.round(height), MIN_ROWS, MAX_ROWS);
    const w: number = CustomField.clampInt(Math.round(width), MIN_COLS, MAX_COLS);
    const bySize: number = (h - 1) * (w - 1) + 1;
    return bySize < MAX_MINES ? bySize : MAX_MINES;
  }

  /**
   * 键盘输入：把一个字符接到当前聚焦的输入框上（返回 false 表示非法 / 未接受）。
   *
   * 规则：
   *   - 只接受 0-9 的**单个**字符，其余返回 false
   *   - 焦点刚切换（或调用过 focusField）时，这一位数字**替换**框里的旧值；
   *     否则追加到旧值后面
   *   - 追加后超过该框上限则**拒绝这次输入**（值保持不变，返回 false）
   *     高度上限 24、宽度上限 30、雷数上限 **668**（全局，见 maxOfField）
   *   - 改了高度或宽度**不会**动雷数框：「盘面收」统一在「确定」时由 clampSpec 做
   *     （原版三个框互相独立：Win32 对话框里三个 EDITTEXT 互不影响，
   *       盘面收只在 IDOK 时用 GetDlgIntOfRange 夹一次）
   *
   * 不做「下限」夹取：正在输入的中间值（比如高度先输了个 1）要保留，
   * 下限统一由 clampSpec 在「确定」时处理。
   */
  static inputChar(s: CustomSpec, ch: string): boolean {
    if (ch.length !== 1) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    if (code < 48 || code > 57) {
      return false;   // 只接受 0-9
    }
    const idx: number = s.focus;
    if (idx < 0 || idx > 2) {
      return false;
    }
    const digit: number = code - 48;
    const replace: boolean = replaceNext || idx !== lastFocus;
    const cur: number = replace ? 0 : CustomField.valueOf(s, idx);
    const next: number = cur * 10 + digit;
    if (next > CustomField.maxOfField(s, idx)) {
      return false;   // 超过该框上限：这次输入不接受，值保持不变
    }
    CustomField.setValue(s, idx, next);
    // 改了高度/宽度**不**在这里把雷数收回来：
    //   1) 原版三个框互相独立，盘面收只在「确定」时做（见 clampSpec）；
    //   2) SPEC §5.8b 已定口径：下限与「确定时的盘面收」统一由 clampSpec 在按确定时处理。
    // 坑（2026-10-31，custom-agent 审计）：原来这里会立刻把超上限的雷数收回来，
    // 框里的数字当着用户的面偷偷变小。现在框里的数字不动，
    // 由提示行当场说清「当前 N 将按 M 布雷」（见 hintText）。
    lastFocus = idx;
    replaceNext = false;
    return true;
  }

  /** 退格：删掉当前聚焦框里最后一位数字（就地为 0） */
  static backspace(s: CustomSpec): void {
    const idx: number = s.focus;
    if (idx < 0 || idx > 2) {
      return;
    }
    const cur: number = CustomField.valueOf(s, idx);
    CustomField.setValue(s, idx, Math.floor(cur / 10));
    lastFocus = idx;
    replaceNext = false;
  }

  /**
   * 点到输入框时调用：切换焦点，并让**下一次输入替换**框里的旧值
   * （模拟 Win7 输入框获得焦点即全选）。
   * id 取 'height' / 'width' / 'mines'，其余忽略。
   */
  static focusField(s: CustomSpec, id: string): void {
    let idx: number = -1;
    if (id === 'height') {
      idx = 0;
    } else if (id === 'width') {
      idx = 1;
    } else if (id === 'mines') {
      idx = 2;
    }
    if (idx < 0) {
      return;
    }
    s.focus = idx;
    replaceNext = true;
  }

  /**
   * 底部提示行的文字（**只说动态的部分**）。
   *
   * 上下限是静态的，已经写在标签里（LABELS，照抄 Win7 原版写法），
   * 所以提示行只负责两件事：
   *   1) 这个盘面实际最多能放多少雷（与确定时的夹取用同一个 maxMines()）；
   *   2) 框里的雷数超了上限时，按确定后会变成多少 —— 不做静默替换。
   *
   * 行列越界（正在输入的中间值，或超出 9-24 / 9-30）也在这里说清楚：
   * 确定时会被夹回合法区间，这时提示的是**夹紧后**盘面的上限。
   *
   * 坑（2026-10-31，custom-agent 审计 P10）：原来的提示行把上下限又重复了一遍，
   * 并且只按夹紧后的行列报上限，用户刚敲下一个「1」提示就跳成 9 行的 65，
   * 看着像坏了。现在：越界时明说「超范围」，上限始终按确定时实际生效的盘面算。
   */
  static hintText(s: CustomSpec): string {
    const maxM: number = CustomField.maxMines(s.height, s.width);
    const rowsBad: boolean = s.height < MIN_ROWS || s.height > MAX_ROWS;
    const colsBad: boolean = s.width < MIN_COLS || s.width > MAX_COLS;
    let hint: string = (rowsBad || colsBad) ? '高度/宽度超范围，最多 ' : '本盘面最多 ';
    hint += maxM.toString() + ' 雷';
    if (s.mines > maxM) {
      hint += '，当前 ' + s.mines.toString() + ' 将按 ' + maxM.toString() + ' 布雷';
    }
    return hint;
  }

  /**
   * 绘制整个对话框。
   * @param sDev 参考像素 → 设备像素（用于字号）
   * @param sVp  参考像素 → vp（用于几何；= sDev / 密度）
   * @param oxVp 对话框左上角的画布坐标（vp）
   * @param oyVp 同上
   */
  static draw(ctx: CanvasRenderingContext2D, s: CustomSpec, sDev: number, sVp: number,
    oxVp: number, oyVp: number): void {
    const w: number = DLG_W * sVp;
    const h: number = DLG_H * sVp;
    const lw: number = Math.max(1, sVp);

    // 窗口阴影
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(oxVp + 3 * sVp, oyVp + 3 * sVp, w, h);

    // 标题栏（Aero 玻璃：上浅下深的渐变）
    const grad = ctx.createLinearGradient(oxVp, oyVp, oxVp, oyVp + TITLE_H * sVp);
    grad.addColorStop(0, C_TITLE_TOP);
    grad.addColorStop(1, C_TITLE_BOTTOM);
    ctx.fillStyle = grad;
    ctx.fillRect(oxVp, oyVp, w, TITLE_H * sVp);

    // 客户区
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(oxVp, oyVp + TITLE_H * sVp, w, h - TITLE_H * sVp);

    // 窗口外框
    ctx.strokeStyle = C_BORDER;
    ctx.lineWidth = lw;
    ctx.strokeRect(oxVp, oyVp, w, h);

    // 标题文字
    ctx.fillStyle = '#2b2b2b';
    ctx.font = `bold ${12 * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText('自定义', oxVp + 6 * sVp, oyVp + 4 * sVp);

    // 右上角关闭按钮（红底白叉）
    const cbW: number = CLOSE_W * sVp;
    const cbH: number = CLOSE_H * sVp;
    const cbX: number = oxVp + w - cbW - 4 * sVp;
    const cbY: number = oyVp + 3 * sVp;
    ctx.fillStyle = C_CLOSE;
    ctx.fillRect(cbX, cbY, cbW, cbH);
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = Math.max(1, sDev * 0.8);
    ctx.beginPath();
    ctx.moveTo(cbX + 4 * sVp, cbY + 3 * sVp);
    ctx.lineTo(cbX + cbW - 4 * sVp, cbY + cbH - 3 * sVp);
    ctx.moveTo(cbX + cbW - 4 * sVp, cbY + 3 * sVp);
    ctx.lineTo(cbX + 4 * sVp, cbY + cbH - 3 * sVp);
    ctx.stroke();

    // 三行：标签 + 可编辑的凹陷输入框
    for (let i = 0; i < 3; i++) {
      const ex: number = oxVp + EDIT_X * sVp;
      const ey: number = oyVp + EDIT_TOP[i] * sVp;
      const ew: number = EDIT_W * sVp;
      const eh: number = EDIT_H * sVp;
      const midY: number = ey + eh / 2;

      // 标签（右对齐到 LABEL_RIGHT）
      ctx.fillStyle = C_TEXT;
      ctx.font = `${12 * sDev}px sans-serif`;
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      ctx.fillText(LABELS[i], oxVp + LABEL_RIGHT * sVp, midY);

      // 聚焦的那一框：外面套一圈蓝
      if (i === s.focus) {
        ctx.strokeStyle = C_FOCUS;
        ctx.lineWidth = lw;
        ctx.strokeRect(ex - lw, ey - lw, ew + 2 * lw, eh + 2 * lw);
      }

      // 凹陷输入框：上/左深边（阴影），下/右白边（高光），内部白底
      ctx.fillStyle = C_EDGE_DARK;
      ctx.fillRect(ex, ey, ew, lw);
      ctx.fillRect(ex, ey, lw, eh);
      ctx.fillStyle = C_EDGE_LIGHT;
      ctx.fillRect(ex, ey + eh - lw, ew, lw);
      ctx.fillRect(ex + ew - lw, ey, lw, eh);
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(ex + lw, ey + lw, ew - 2 * lw, eh - 2 * lw);

      // 框里的数字
      ctx.fillStyle = C_TEXT;
      ctx.font = `${12 * sDev}px sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(CustomField.textOf(s, i), ex + 6 * sVp, midY);
    }

    // 底部提示行（把**当前盘面实际生效**的上限告诉用户）
    ctx.fillStyle = C_HINT;
    ctx.font = `${HINT_SIZE * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    // 提示行只说动态的事：上下限是静态的，已经写在标签里（LABELS，照抄 Win7）。
    // 剩下的两件：1) 这个盘面实际最多能放多少雷；2) 框里的雷数超上限时按确定会变成多少。
    //
    // 坑（2026-10-31，custom-agent 裁决）：夹取原来是**静默**的——9×9 填 500，
    // 点确定后悄悄变成 65，用户毫无察觉。原版两处参考实现都会把生效值写回
    // （Lmy `Minesweeper.cpp:234/240/246` 用 SetDlgItemInt；原版 XP 也在对话框里夹）。
    // 我们不写回输入框（框马上就关了，写回也看不见），改成**当场把生效值说清楚**。
    ctx.fillText(CustomField.hintText(s), oxVp + HINT_X * sVp, oyVp + HINT_Y * sVp);

    // 底部两个按钮
    CustomField.drawButton(ctx, '确定(O)', oxVp + BTN_OK_X * sVp, oyVp + BTN_Y * sVp,
      BTN_W * sVp, BTN_H * sVp, sDev, sVp);
    CustomField.drawButton(ctx, '取消(C)', oxVp + BTN_CANCEL_X * sVp, oyVp + BTN_Y * sVp,
      BTN_W * sVp, BTN_H * sVp, sDev, sVp);

    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /**
   * 命中测试：返回 'height' | 'width' | 'mines' | 'ok' | 'cancel' | ''。
   * 右上角的红叉关闭按钮也算 'cancel'。
   *
   * @param pxVp 点击点的画布坐标（vp）
   * @param pyVp 同上
   * 说明：s 与 sDev 在纯几何命中里用不到，保留是为了和 draw 的签名对称、方便以后扩展。
   */
  static hit(s: CustomSpec, sDev: number, sVp: number, oxVp: number, oyVp: number,
    pxVp: number, pyVp: number): string {
    // 右上角关闭按钮
    const cbW: number = CLOSE_W * sVp;
    const cbH: number = CLOSE_H * sVp;
    const cbX: number = oxVp + DLG_W * sVp - cbW - 4 * sVp;
    const cbY: number = oyVp + 3 * sVp;
    if (inRect(pxVp, pyVp, cbX, cbY, cbW, cbH)) {
      return 'cancel';
    }
    // 底部按钮
    if (inRect(pxVp, pyVp, oxVp + BTN_OK_X * sVp, oyVp + BTN_Y * sVp, BTN_W * sVp, BTN_H * sVp)) {
      return 'ok';
    }
    if (inRect(pxVp, pyVp, oxVp + BTN_CANCEL_X * sVp, oyVp + BTN_Y * sVp, BTN_W * sVp, BTN_H * sVp)) {
      return 'cancel';
    }
    // 三个输入框
    for (let i = 0; i < 3; i++) {
      const ex: number = oxVp + EDIT_X * sVp;
      const ey: number = oyVp + EDIT_TOP[i] * sVp;
      const ew: number = EDIT_W * sVp;
      const eh: number = EDIT_H * sVp;
      if (inRect(pxVp, pyVp, ex, ey, ew, eh)) {
        if (i === 0) {
          return 'height';
        }
        if (i === 1) {
          return 'width';
        }
        return 'mines';
      }
    }
    return '';
  }

  /**
   * 对话框的参考宽（参考像素）。
   * 主线程居中时按现有 WinDialog 的用法乘以缩放系数即可：
   *   ox = (canvasW - CustomField.widthVp() * scale) / 2
   * 想直接要 vp 宽度就用 widthVpAt(sVp)。
   */
  static widthVp(): number {
    return DLG_W;
  }

  /** 对话框的参考高（参考像素），同 widthVp */
  static heightVp(): number {
    return DLG_H;
  }

  /** 对话框宽（vp）：= DLG_W * sVp */
  static widthVpAt(sVp: number): number {
    return DLG_W * sVp;
  }

  /** 对话框高（vp）：= DLG_H * sVp */
  static heightVpAt(sVp: number): number {
    return DLG_H * sVp;
  }

  // ------------------------------------------------------------------ 内部工具

  /** 夹取整数到 [lo, hi] */
  static clampInt(v: number, lo: number, hi: number): number {
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }

  /** 第 index 个框（0=高度 1=宽度 2=雷数）的当前值 */
  static valueOf(s: CustomSpec, index: number): number {
    if (index === 0) {
      return s.height;
    }
    if (index === 1) {
      return s.width;
    }
    if (index === 2) {
      return s.mines;
    }
    return 0;
  }

  /** 写第 index 个框的值 */
  static setValue(s: CustomSpec, index: number, v: number): void {
    if (index === 0) {
      s.height = v;
    } else if (index === 1) {
      s.width = v;
    } else if (index === 2) {
      s.mines = v;
    }
  }

  /** 第 index 个框的上限（输入时超过它就拒绝这次输入） */
  static maxOfField(s: CustomSpec, index: number): number {
    if (index === 0) {
      return MAX_ROWS;
    }
    if (index === 1) {
      return MAX_COLS;
    }
    if (index === 2) {
      // 雷数框的**输入**上限是全局 668，不按盘面尺寸收。
      // 依据：两份独立参考都是这么写的——
      //   Lmy0217 `Minesweeper.cpp` 的自定义面板：10–668 雷
      //   linux-minesweeper `OptionsDialog.cpp:88`：`m_mines->setRange(10, 668)`
      // 面板标签也照抄这个范围（「Mines (10-668)」）。
      //
      // 坑（2026-10-31，custom-agent 审计发现）：原来这里用的是按尺寸算的上限
      // （9×9 只有 65），跟 SPEC §8-2 的决定和参考实现都不一致。
      // 按盘面收的是**最终雷数**，在 clampSpec（确定时）和引擎 reset() 里夹，
      // 用户看到的数字和实际布雷数始终一致。
      return MAX_MINES;
    }
    return 0;
  }

  /** 第 index 个框里要显示的文字 */
  static textOf(s: CustomSpec, index: number): string {
    return CustomField.valueOf(s, index).toString();
  }

  /** 画一个 Win7 按钮（坐标已是 vp） */
  static drawButton(ctx: CanvasRenderingContext2D, label: string, x: number, y: number, w: number, h: number,
    sDev: number, sVp: number): void {
    const g = ctx.createLinearGradient(x, y, x, y + h);
    g.addColorStop(0, C_BTN_TOP);
    g.addColorStop(1, C_BTN_BOTTOM);
    ctx.fillStyle = g;
    ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = C_BTN_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    ctx.strokeRect(x, y, w, h);
    ctx.fillStyle = C_TEXT;
    ctx.font = `${12 * sDev}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, x + w / 2, y + h / 2 + 1 * sVp);
  }
}
