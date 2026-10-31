/**
 * WinDialog.ets —— Windows 7 风格的三个对话框：失败 / 胜利 / 关于
 *
 * 版式全部来自参考图实测。量化脚本留在工程外，可复算：
 *   D:\software\harmony\projects\minesweeper\docs\dlg_measure.py   （整体版式）
 *   D:\software\harmony\projects\minesweeper\docs\dlg_measure2.py  （about 细节）
 *   D:\software\harmony\projects\minesweeper\docs\dlg_measure3.py  （右上角红按钮）
 * 参考图（版式依据，1 倍像素）：
 *   loss.jpg   483x288  失败框整框（Aero 玻璃标题栏）
 *   win.jpg    396x340  胜利框整框（Aero 玻璃标题栏）
 *   about.jpg  615x408  整窗截图，「关于扫雷」对话框在整窗 x=152..465 / y=101..297
 *
 * 单位约定：
 *   * 几何一律用「参考像素」（参考图 1 倍像素）；
 *   * 绘制时几何乘 sVp（vp / 参考像素），字号乘 sDev（设备像素 / 参考像素）；
 *   * DlgLine.y 是**文字墨迹顶**（实测墨迹范围的上沿），draw 时统一上移
 *     TEXT_INK_DY，抵消字体自身的 ascent 留白。
 *
 * 坑（2026-10-31 实测）：Canvas 的**坐标是 vp**，但 font 里的 "px" 是**设备像素**。
 *    所以几何用 sVp（vp / 参考像素），字号用 sDev（设备像素 / 参考像素），两者差一个密度。
 *
 * 坑：CanvasRenderingContext2D / CanvasGradient 是 ArkTS 的全局类型，不能从 @kit.ArkUI 导入；
 *    而且 createLinearGradient 的返回值类型名在不同 SDK 版本下不稳定，故不写显式类型。
 */

/** 对话框里的一行文字 */
export interface DlgLine {
  text: string;
  /** 参考像素：相对对话框左上角 */
  x: number;
  /** 参考像素：文字**墨迹顶**（实测值） */
  y: number;
  /** 字号（参考像素） */
  size: number;
  /** left = 左对齐；center = 以 x 为中心 */
  align: 'left' | 'center';
  /** 覆盖默认的黑色 */
  color?: string;
}

/** 对话框里的一个按钮 */
export interface DlgButton {
  /** 点击后返回的动作标识 */
  id: string;
  label: string;
  x: number;
  y: number;
  w: number;
  h: number;
  /** 覆盖默认的边框色（about.jpg 的「确定」是蓝色默认按钮） */
  borderColor?: string;
}

/** 一个对话框的全部描述 */
export interface DlgSpec {
  title: string;
  /** 参考像素尺寸 */
  width: number;
  height: number;
  lines: DlgLine[];
  buttons: DlgButton[];
  /** 可选：左侧图标（源矩形，画在 gameSheet 上） */
  icon?: number[];
  /** 图标位置与尺寸（参考像素） */
  iconPos?: number[];
  /** 标题栏风格：'aero'（loss/win 的玻璃标题栏，默认）| 'classic'（about 的经典蓝灰标题栏） */
  chrome?: string;
}

// ==========================================================================
//  窗口骨架（全部来自 loss.jpg / win.jpg 实测；about.jpg 结构一致）
// ==========================================================================

/** 玻璃边框宽度：外沿到客户区。loss.jpg x=0 外框 / x=1..6 玻璃 / x=7 暗线 / x=8 起客户区 */
const FRAME_X: number = 8;
/** 底部边框宽度。loss.jpg y=280 暗线 / y=281..286 玻璃 / y=287 外框 */
const FRAME_Y: number = 8;
/** 标题栏总高。loss.jpg y=0 外框 / y=1..27 渐变 / y=28 亮线 / y=29 分隔暗线 */
const TITLE_H: number = 29;
/** 标题文字起始 x。loss.jpg 标题墨迹 x=9..55；about.jpg 墨迹 x=161(局部 9)..251 */
const TITLE_TEXT_X: number = 9;
/** 标题文字墨迹顶。loss.jpg 标题墨迹 y=9..19（字高 11）；about.jpg 同为 y=110(局部 9)..120 */
const TITLE_TEXT_Y: number = 9;
/** 标题字号。12px（loss.jpg 标题墨迹高 11） */
const TITLE_FONT: number = 12;
/** 按钮字号。12px（loss.jpg 按钮内文字墨迹高 12，y=243..254） */
const BTN_FONT: number = 12;
/**
 * 墨迹顶 -> 绘制位置的补偿：12px 中文在 textBaseline='top' 下墨迹从 y+1 起，
 * 故绘制 y = 墨迹顶 - 1。loss.jpg 行1 墨迹顶 51 -> 绘制 50。
 */
const TEXT_INK_DY: number = -1;

/** 右上角关闭按钮：loss.jpg 红块 x=430..474（w=45）、y=2..18（h=17），右缘距窗口 9px */
const CLOSE_W_AERO: number = 45;
const CLOSE_RIGHT_AERO: number = 9;
/** about.jpg 红块 x=412..457（w=46）、y=103..119（h=17），右缘距窗口 8px */
const CLOSE_W_CLASSIC: number = 46;
const CLOSE_RIGHT_CLASSIC: number = 8;
/** 关闭按钮顶 y。loss/win y=2；about.jpg y=103（局部 2） */
const CLOSE_TOP: number = 2;
/** 关闭按钮高。loss/win y=2..18；about.jpg y=103..119，均为 17 */
const CLOSE_H: number = 17;
/** 白叉尺寸（参考像素）。loss.jpg 白叉约 x=450..456 / y=5..13 */
const CLOSE_X_HALF_W: number = 3.5;
const CLOSE_X_HALF_H: number = 4.5;
/** 白叉描边粗（参考像素）。loss.jpg 白叉笔画约 1.5px */
const CLOSE_X_THICK: number = 1.5;

// ==========================================================================
//  颜色（全部实测自 loss.jpg；about.jpg 的另列一组）
// ==========================================================================

/** 客户区底色。loss.jpg (200,32) = #f0f0f0 */
const C_CLIENT: string = '#f0f0f0';
/** 玻璃边框。loss.jpg (3,150) = #c9c1d6 */
const C_FRAME_GLASS: string = '#c9c1d6';
/** 客户区内侧暗线。loss.jpg x=7 = #524f58 */
const C_FRAME_LINE: string = '#524f58';
/** 窗口最外沿 1px。loss.jpg x=0 = #222025 */
const C_OUTER_LINE: string = '#222025';
/** 标题栏底部分隔线。loss.jpg y=29 = #484655 */
const C_TITLE_SEP: string = '#484655';
/** 标题栏渐变顶。loss.jpg y=1 = #fbf3fe */
const C_TITLE_TOP: string = '#fbf3fe';
/** 标题栏渐变平台。loss.jpg y=5 = #e1d0e8 */
const C_TITLE_MID: string = '#e1d0e8';
/** 标题栏渐变下段。loss.jpg y=27 = #8d87b4 */
const C_TITLE_BOTTOM: string = '#8d87b4';
/** 标题栏底亮线（分隔线上方 1px）。loss.jpg y=28 = #cdc9e7 */
const C_TITLE_EDGE: string = '#cdc9e7';
/** 正文文字色。loss.jpg 行1 墨迹近黑 */
const C_TEXT: string = '#000000';
/** 按钮填充上沿。loss.jpg 按钮 (23,238) = #f2f2f2 */
const C_BTN_TOP: string = '#f2f2f2';
/** 按钮填充下沿。loss.jpg 按钮 (23,259) = #d1d1d1 */
const C_BTN_BOTTOM: string = '#d1d1d1';
/** 按钮边框。loss.jpg 按钮四边 = #707070 */
const C_BTN_BORDER: string = '#707070';
/** 默认按钮（about.jpg「确定」）的蓝色边框。about.jpg (358..445,254..278) 众数 = #4f7c93 */
const C_BTN_ACCENT: string = '#4f7c93';
/** 关闭按钮红（上）。loss.jpg (431,3) = #dfaeaa */
const C_CLOSE_TOP: string = '#dfaeaa';
/** 关闭按钮红（中）。loss.jpg (435,10) = #b04a40 */
const C_CLOSE_MID: string = '#b04a40';
/** 关闭按钮红（下）。loss.jpg (435,17) = #d88671 */
const C_CLOSE_BOTTOM: string = '#d88671';

// ---- classic（about.jpg）----
/** 玻璃边框。about.jpg (155,140) = #a09dc4 */
const C_C_FRAME_GLASS: string = '#a09dc4';
/** 客户区内侧暗线。about.jpg x=159 = #444351 */
const C_C_FRAME_LINE: string = '#444351';
/** 窗口最外沿 1px。about.jpg x=152 = #15192c */
const C_C_OUTER_LINE: string = '#15192c';
/** 标题栏分隔线。about.jpg y=130 = #403f50 */
const C_C_TITLE_SEP: string = '#403f50';
/** 标题栏渐变顶。about.jpg y=102 = #ebebff */
const C_C_TITLE_TOP: string = '#ebebff';
/** 标题栏渐变中。about.jpg y=105 = #a6a4cc */
const C_C_TITLE_MID: string = '#a6a4cc';
/** 标题栏渐变中段。about.jpg y=113 = #9593b6 */
const C_C_TITLE_MID2: string = '#9593b6';
/** 标题栏渐变下段。about.jpg y=114 = #8b89b0 */
const C_C_TITLE_LOW: string = '#8b89b0';
/** 标题栏渐变底。about.jpg y=128 = #8c8ab1 */
const C_C_TITLE_BOTTOM: string = '#8c8ab1';
/** 标题栏底亮线。about.jpg y=129 = #cac9e5 */
const C_C_TITLE_EDGE: string = '#cac9e5';
/** 关闭按钮红（上）。about.jpg (420,104) 附近 = #e0948a */
const C_C_CLOSE_TOP: string = '#e0948a';
/** 关闭按钮红（中）。about.jpg (430,110) = #c1655b */
const C_C_CLOSE_MID: string = '#c1655b';
/** 关闭按钮红（下）。about.jpg (420,118) 附近 = #d99187 */
const C_C_CLOSE_BOTTOM: string = '#d99187';

export class WinDialogPainter {
  /**
   * 失败对话框（实测自 loss.jpg，参考尺寸 483x288）
   *
   * 与原版唯一差别：中间那个按钮原版是「重新开始这个游戏(R)」，
   * 与右边的「再玩一局(P)」功能重复；手机端改成「换个难度(D)」更实用。
   */
  static loseSpec(seconds: number, played: number, won: number, percent: number): DlgSpec {
    return {
      title: '游戏失败',
      width: 483,
      height: 288,
      chrome: 'aero',
      lines: [
        // loss.jpg 客户区行1：墨迹 y=51..62，x=161..311（居中 236）
        { text: '不好意思，您输了！下次走运!', x: 236, y: 51, size: 14, align: 'center' },
        // loss.jpg 行2：墨迹 y=93..104，x=22..74
        { text: '时间: ' + seconds + '秒', x: 22, y: 93, size: 12, align: 'left' },
        // loss.jpg 行3：墨迹 y=140..151，x=23..87
        { text: '已玩游戏: ' + played, x: 23, y: 140, size: 12, align: 'left' },
        // loss.jpg 行4：墨迹 y=164..175，x=23..87
        { text: '已胜游戏: ' + won, x: 23, y: 164, size: 12, align: 'left' },
        // loss.jpg 行4 右半：墨迹 y=164..175，x=203..267
        { text: '百分比: ' + percent + '%', x: 203, y: 164, size: 12, align: 'left' }
      ],
      // loss.jpg 按钮行 y=236..261（h=26），三块各 w=144：x=17..160 / 170..313 / 323..466
      buttons: [
        { id: 'exit', label: '退出(X)', x: 17, y: 236, w: 144, h: 26 },
        { id: 'menu', label: '换个难度(D)', x: 170, y: 236, w: 144, h: 26 },
        { id: 'again', label: '再玩一局(P)', x: 323, y: 236, w: 144, h: 26 }
      ]
    };
  }

  /**
   * 胜利对话框（实测自 win.jpg，参考尺寸 396x340）
   */
  static winSpec(seconds: number, played: number, won: number, percent: number,
    bestText: string, bestDate: string, isNewBest: boolean): DlgSpec {
    const lines: DlgLine[] = [];
    // win.jpg 客户区行1：墨迹 y=44..55，x=160..228（居中 194）
    lines.push({ text: '恭喜！您赢了！', x: 194, y: 44, size: 14, align: 'center' });
    if (isNewBest) {
      // win.jpg 行2：墨迹 y=77..88，x=89..306（居中 197）
      lines.push({
        text: '您所用的时间是这个难度级别的最短时间!',
        x: 197, y: 77, size: 12, align: 'center'
      });
    }
    // win.jpg 行3：墨迹 y=127..138，x=22..80
    lines.push({ text: '时间: ' + seconds + '秒', x: 22, y: 127, size: 12, align: 'left' });
    if (bestText.length > 0) {
      // win.jpg 行4 左：墨迹 y=161..172，x=22..104
      lines.push({ text: '最快时间: ' + bestText, x: 22, y: 161, size: 12, align: 'left' });
      // win.jpg 行4 右：墨迹 y=161..172，x=210..370
      lines.push({ text: '日期: ' + bestDate, x: 210, y: 161, size: 12, align: 'left' });
    }
    // win.jpg 行5：墨迹 y=185..196，x=23..87
    lines.push({ text: '已玩游戏: ' + played, x: 23, y: 185, size: 12, align: 'left' });
    // win.jpg 行6 左：墨迹 y=210..221，x=23..87
    lines.push({ text: '已胜游戏: ' + won, x: 23, y: 210, size: 12, align: 'left' });
    // win.jpg 行6 右：墨迹 y=210..221，x=209..279
    lines.push({ text: '百分比: ' + percent + '%', x: 209, y: 210, size: 12, align: 'left' });
    return {
      title: '游戏胜利',
      width: 396,
      height: 340,
      chrome: 'aero',
      lines: lines,
      // win.jpg 按钮：① x=23..158 y=252..278  ② x=23..158 y=286..312（w=136 h=27）
      buttons: [
        { id: 'again', label: '再玩一局(P)', x: 23, y: 252, w: 136, h: 27 },
        { id: 'exit', label: '退出(Q)', x: 23, y: 286, w: 136, h: 27 }
      ]
    };
  }

  /**
   * 「最佳成绩」对话框（菜单 游戏 → 最佳成绩）
   *
   * 原版 Win7 的这个框叫 Winners，列出**每个难度各自的最快时间与日期**，
   * 所以这里三行（初级/中级/高级）各一档。
   *
   * @param rows 每行文字，形如 '初级    12秒    2026-10-31 10:20'
   */
  static bestSpec(seconds: number, played: number, won: number, percent: number,
    rows: string[]): DlgSpec {
    const lines: DlgLine[] = [];
    lines.push({ text: '最佳成绩', x: 190, y: 44, size: 14, align: 'center' });
    let y: number = 88;
    for (const r of rows) {
      lines.push({ text: r, x: 30, y: y, size: 12, align: 'left' });
      y += 22;
    }
    lines.push({ text: '已玩游戏: ' + played, x: 30, y: y + 10, size: 12, align: 'left' });
    lines.push({ text: '已胜游戏: ' + won, x: 30, y: y + 34, size: 12, align: 'left' });
    lines.push({ text: '百分比: ' + percent + '%', x: 30, y: y + 58, size: 12, align: 'left' });
    return {
      title: '最佳成绩',
      width: 400,
      height: 320,
      chrome: 'aero',
      lines: lines,
      buttons: [
        { id: 'close', label: '确定', x: 160, y: 268, w: 100, h: 26 }
      ]
    };
  }

  /**
   * 「关于扫雷」对话框（菜单 帮助 → 关于扫雷）
   *
   * 版式按 about.jpg 实测（整窗截图 615x408 里的一个对话框，
   * 外框在整窗 x=152..465 / y=101..297 => 对话框本身 314x197）：
   *   标题栏  y=0..29（经典蓝灰渐变，不是 Aero 玻璃）
   *   客户区  x=8..305 / y=30..187
   *   雷图标  整窗 x=189..216 / y=177..207 => 局部 x=37..64 / y=76..106（取 25x25 居中放）
   *   三行说明 整窗 x 起 238，局部 x=86；墨迹顶 y=165 / 193 / 221 => 局部 64 / 92 / 120
   *   确定按钮 整窗 x=358..445 / y=254..278 => 局部 x=206 / y=153，w=88 h=25
   */
  static aboutSpec(): DlgSpec {
    return {
      title: '关于 扫雷',
      width: 314,
      height: 197,
      chrome: 'classic',
      icon: [0, 0, 25, 25],
      iconPos: [38, 78, 25, 25],
      lines: [
        { text: 'HarmonyOS 移植版', x: 86, y: 64, size: 12, align: 'left' },
        { text: '原版：Windows 7 扫雷', x: 86, y: 92, size: 12, align: 'left' },
        { text: '适配：华为 Pura X Max 折叠屏', x: 86, y: 120, size: 12, align: 'left' }
      ],
      buttons: [
        { id: 'close', label: '确定', x: 206, y: 153, w: 88, h: 25, borderColor: C_BTN_ACCENT }
      ]
    };
  }

  /**
   * 帮助对话框（Win7 的「帮助(H)」菜单项）。
   *
   * 原版点「帮助(H)」会弹出一个独立的帮助窗口（helpBoard.png 就是那个窗口的插图），
   * 本项目没有独立窗口，用一个同风格的对话框承载同样的文字内容。
   */
  static helpSpec(): DlgSpec {
    return {
      title: '扫雷 帮助',
      width: 320,
      height: 210,
      chrome: 'aero',
      lines: [
        { text: '目标：把地雷全部标出来，别踩到雷。', x: 16, y: 44, size: 12, align: 'left' },
        { text: '左键翻开格子；右键插旗，再右键变问号。', x: 16, y: 66, size: 12, align: 'left' },
        { text: '数字表示周围 8 格里的雷数。', x: 16, y: 88, size: 12, align: 'left' },
        { text: '数字够了就双击它（和弦），其余邻格会自动翻开。', x: 16, y: 110, size: 12, align: 'left' },
        { text: '开局第一下保证不是雷，周围也会空出一片。', x: 16, y: 132, size: 12, align: 'left' },
        { text: '双指可以缩放棋盘，单指拖动可以平移。', x: 16, y: 154, size: 12, align: 'left' }
      ],
      buttons: [
        { id: 'close', label: '确定', x: 110, y: 170, w: 100, h: 25 }
      ]
    };
  }

  /**
   * 标题栏右上角关闭按钮的矩形（参考像素）：[x, y, w, h]。
   * draw 与 hitButton 共用它，保证画出来的位置和命中区严格一致。
   */
  static closeRect(spec: DlgSpec): number[] {
    const classic: boolean = spec.chrome === 'classic';
    const cw: number = classic ? CLOSE_W_CLASSIC : CLOSE_W_AERO;
    const cr: number = classic ? CLOSE_RIGHT_CLASSIC : CLOSE_RIGHT_AERO;
    return [spec.width - cr - cw, CLOSE_TOP, cw, CLOSE_H];
  }

  /**
   * 画一个对话框。
   * @param sDev 参考像素 → 设备像素（用于字号）
   * @param sVp  参考像素 → vp（用于几何；= sDev / density）
   * @param oxVp 对话框左上角的画布坐标（vp）
   * @param oyVp 同上
   */
  static draw(ctx: CanvasRenderingContext2D, spec: DlgSpec, sDev: number, sVp: number,
    oxVp: number, oyVp: number): void {
    const classic: boolean = spec.chrome === 'classic';
    const w: number = spec.width * sVp;
    const h: number = spec.height * sVp;
    // 客户区（loss.jpg x=8..474 / y=30..279）
    const cw: number = (spec.width - FRAME_X * 2) * sVp;
    const ch: number = (spec.height - TITLE_H - FRAME_Y - 1) * sVp;
    const cx: number = oxVp + FRAME_X * sVp;
    const cy: number = oyVp + TITLE_H * sVp;

    // 窗口阴影
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(oxVp + 3 * sVp, oyVp + 3 * sVp, w, h);

    // 玻璃边框底色（loss.jpg x=2..5 / about.jpg x=154..157）
    ctx.fillStyle = classic ? C_C_FRAME_GLASS : C_FRAME_GLASS;
    ctx.fillRect(oxVp, oyVp, w, h);

    // 标题栏渐变
    const grad = ctx.createLinearGradient(oxVp, oyVp, oxVp, oyVp + TITLE_H * sVp);
    if (classic) {
      // about.jpg y=102 #ebebff / y=103..113 #a9a6c2->#9593b6 / y=114..128 #8b89b0->#8c8ab1 / y=129 #cac9e5
      grad.addColorStop(0, C_C_TITLE_TOP);
      grad.addColorStop(0.035, C_C_TITLE_TOP);
      grad.addColorStop(0.07, C_C_TITLE_MID);
      grad.addColorStop(0.45, C_C_TITLE_MID2);
      grad.addColorStop(0.55, C_C_TITLE_LOW);
      grad.addColorStop(0.93, C_C_TITLE_BOTTOM);
      grad.addColorStop(0.965, C_C_TITLE_EDGE);
    } else {
      // loss.jpg y=1 #fbf3fe / y=2..15 #e1d0e8 / y=16..27 渐暗到 #8d87b4 / y=28 #cdc9e7
      grad.addColorStop(0, C_TITLE_TOP);
      grad.addColorStop(0.04, C_TITLE_TOP);
      grad.addColorStop(0.07, C_TITLE_MID);
      grad.addColorStop(0.55, C_TITLE_MID);
      grad.addColorStop(0.93, C_TITLE_BOTTOM);
      grad.addColorStop(0.965, C_TITLE_EDGE);
    }
    ctx.fillStyle = grad;
    ctx.fillRect(oxVp, oyVp, w, TITLE_H * sVp);

    // 客户区底色
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(cx, cy, cw, ch);

    // 客户区内侧暗线（loss.jpg x=7 / x=475 / y=280）
    ctx.fillStyle = classic ? C_C_FRAME_LINE : C_FRAME_LINE;
    ctx.fillRect(cx - 1 * sVp, cy, 1 * sVp, ch);
    ctx.fillRect(cx + cw, cy, 1 * sVp, ch);
    ctx.fillRect(cx - 1 * sVp, cy + ch, cw + 2 * sVp, 1 * sVp);

    // 标题栏底部分隔线（loss.jpg y=29，整行通宽）
    ctx.fillStyle = classic ? C_C_TITLE_SEP : C_TITLE_SEP;
    ctx.fillRect(oxVp, oyVp + (TITLE_H - 1) * sVp, w, 1 * sVp);

    // 窗口最外沿 1px（loss.jpg x=0 / x=482 / y=0 / y=287）
    ctx.fillStyle = classic ? C_C_OUTER_LINE : C_OUTER_LINE;
    ctx.fillRect(oxVp, oyVp, w, 1 * sVp);
    ctx.fillRect(oxVp, oyVp + h - 1 * sVp, w, 1 * sVp);
    ctx.fillRect(oxVp, oyVp, 1 * sVp, h);
    ctx.fillRect(oxVp + w - 1 * sVp, oyVp, 1 * sVp, h);

    // 标题文字（loss.jpg 墨迹 x=9..55 / y=9..19）
    ctx.fillStyle = C_TEXT;
    ctx.font = `bold ${TITLE_FONT * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(spec.title, oxVp + TITLE_TEXT_X * sVp,
      oyVp + (TITLE_TEXT_Y + TEXT_INK_DY) * sVp);

    // 右上角关闭按钮（红块 + 白叉）
    const cr: number[] = WinDialogPainter.closeRect(spec);
    const cbX: number = oxVp + cr[0] * sVp;
    const cbY: number = oyVp + cr[1] * sVp;
    const cbW: number = cr[2] * sVp;
    const cbH: number = cr[3] * sVp;
    const cg = ctx.createLinearGradient(cbX, cbY, cbX, cbY + cbH);
    if (classic) {
      cg.addColorStop(0, C_C_CLOSE_TOP);
      cg.addColorStop(0.5, C_C_CLOSE_MID);
      cg.addColorStop(1, C_C_CLOSE_BOTTOM);
    } else {
      cg.addColorStop(0, C_CLOSE_TOP);
      cg.addColorStop(0.5, C_CLOSE_MID);
      cg.addColorStop(1, C_CLOSE_BOTTOM);
    }
    ctx.fillStyle = cg;
    ctx.fillRect(cbX, cbY, cbW, cbH);
    const ccx: number = cbX + cbW / 2;
    const ccy: number = cbY + cbH / 2;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = Math.max(1, CLOSE_X_THICK * sVp);
    ctx.beginPath();
    ctx.moveTo(ccx - CLOSE_X_HALF_W * sVp, ccy - CLOSE_X_HALF_H * sVp);
    ctx.lineTo(ccx + CLOSE_X_HALF_W * sVp, ccy + CLOSE_X_HALF_H * sVp);
    ctx.moveTo(ccx + CLOSE_X_HALF_W * sVp, ccy - CLOSE_X_HALF_H * sVp);
    ctx.lineTo(ccx - CLOSE_X_HALF_W * sVp, ccy + CLOSE_X_HALF_H * sVp);
    ctx.stroke();

    // 文字（y 是实测墨迹顶，绘制时上移 TEXT_INK_DY）
    for (const line of spec.lines) {
      if (line.text.length === 0) {
        continue;
      }
      ctx.fillStyle = line.color ?? C_TEXT;
      ctx.font = `${line.size * sDev}px sans-serif`;
      ctx.textBaseline = 'top';
      const ly: number = oyVp + (line.y + TEXT_INK_DY) * sVp;
      if (line.align === 'center') {
        ctx.textAlign = 'center';
        ctx.fillText(line.text, oxVp + line.x * sVp, ly);
      } else {
        ctx.textAlign = 'left';
        ctx.fillText(line.text, oxVp + line.x * sVp, ly);
      }
    }

    // 按钮（loss.jpg 边框 #707070，填充 #f2f2f2 -> #d1d1d1，文字墨迹垂直居中）
    for (const b of spec.buttons) {
      const bx: number = oxVp + b.x * sVp;
      const by: number = oyVp + b.y * sVp;
      const bw: number = b.w * sVp;
      const bh: number = b.h * sVp;
      const bg = ctx.createLinearGradient(bx, by, bx, by + bh);
      bg.addColorStop(0, C_BTN_TOP);
      bg.addColorStop(1, C_BTN_BOTTOM);
      ctx.fillStyle = bg;
      ctx.fillRect(bx, by, bw, bh);
      ctx.strokeStyle = b.borderColor ?? C_BTN_BORDER;
      ctx.lineWidth = Math.max(1, sVp);
      ctx.strokeRect(bx, by, bw, bh);
      ctx.fillStyle = C_TEXT;
      ctx.font = `${BTN_FONT * sDev}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(b.label, bx + bw / 2, by + bh / 2);
    }
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /** 点到哪个按钮上（设备像素坐标）；没点到返回 null */
  static hitButton(spec: DlgSpec, scale: number, ox: number, oy: number, px: number, py: number): string | null {
    for (const b of spec.buttons) {
      const bx: number = ox + b.x * scale;
      const by: number = oy + b.y * scale;
      if (px >= bx && px <= bx + b.w * scale && py >= by && py <= by + b.h * scale) {
        return b.id;
      }
    }
    // 标题栏右上角的关闭按钮也要能点（它画出来了，就得能点）
    // 矩形与 draw() 共用 WinDialogPainter.closeRect，保证严格一致（Codex 复审 P2）
    const cr: number[] = WinDialogPainter.closeRect(spec);
    const cbX: number = ox + cr[0] * scale;
    const cbY: number = oy + cr[1] * scale;
    if (px >= cbX && px <= cbX + cr[2] * scale && py >= cbY && py <= cbY + cr[3] * scale) {
      return 'close';
    }
    return null;
  }
}
