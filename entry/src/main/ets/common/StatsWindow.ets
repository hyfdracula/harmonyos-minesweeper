/**
 * StatsWindow.ets —— 「扫雷统计信息」窗口（对应原版菜单 游戏 → 最佳成绩）
 *
 * 参考截图：Minesweeper-master/jpg/information.jpg（702x254，整窗就是这张统计窗口）。
 * 量化脚本（工程外，可复算）：
 *   D:\software\harmony\projects\minesweeper\docs\dlg_stats.py    （整体版式）
 *   D:\software\harmony\projects\minesweeper\docs\dlg_stats2.py   （分区文字）
 *   D:\software\harmony\projects\minesweeper\docs\dlg_stats3.py   （列表框/表格/按钮颜色）
 * 参考实现：
 *   ReversingMinesweeper-master/Minesweeper/resource.h
 *       ID_DIALOG_WINNERS 700
 *       ID_DIALOG_WINNERS_TIME_BEGINNER/INTERMIDIATE/EXPERT   0x2BD / 0x2BF / 0x2C1
 *       ID_DIALOG_WINNERS_NAME_BEGINNER/INTERMIDIATE/EXPERT   0x2BE / 0x2C0 / 0x2C2
 *       ID_DIALOG_WINNERS_BTN_RESET_SCORES 707
 *
 * 窗口版式（全部为 information.jpg 实测值）：
 *   左栏   难度列表框（白底 sunken 边框），初级/中级/高级，首项蓝底选中
 *   中栏   「最快纪录」group box：Win7 原版「最佳成绩」表的四行
 *           （最快用时 / 最快百分比 / 最慢百分比 / 最慢用时，取左栏选中那一档）
 *   右栏   已玩游戏 / 已胜游戏 / 获胜率 / 最多连胜 / 最多连败 / 当前连局
 *   底部   关闭(C)（默认按钮，蓝框）/ 重置(R)
 *
 * 单位约定（与 WinDialog.ets 保持一致）：
 *   * 几何一律用「参考像素」（= information.jpg 的 1 倍像素）；
 *   * 绘制时几何乘 sVp（vp / 参考像素），字号乘 sDev（设备像素 / 参考像素）；
 *   * 文字 y 一律是**墨迹顶**（实测值），绘制时统一上移 TEXT_INK_DY。
 *
 * 坑：CanvasRenderingContext2D 是 ArkTS 全局类型，不能 import；
 *      createLinearGradient 的返回值类型名在不同 SDK 版本下不稳定，故不写显式类型。
 */

import { GameStats, LevelRecord } from './GameStats';

/** 一个难度的最快纪录 */
export interface StatsLevel {
  /** 难度名，如 '初级' */
  level: string;
  /** 最快用时（秒）；没有纪录时为 -1 */
  best: number;
  /** 达成日期文本；没有纪录时为空串 */
  date: string;
}

/** 统计窗口需要的数据（由主线程从 GameStats 组装） */
export interface StatsData {
  /** 最好成绩：最快用时（秒）；没有纪录时为 -1 */
  bestSeconds: number;
  /** 最好成绩的日期文本 */
  bestDate: string;
  /** 游戏总局数 */
  played: number;
  /** 获胜局数 */
  won: number;
  /** 当前连胜（连续获胜局数） */
  currentStreak: number;
  /** 最多连胜 */
  maxStreak: number;
  /** 最多连败 */
  maxLoseStreak: number;
  /** 各难度的最快纪录（供左栏列表显示） */
  perLevel: StatsLevel[];
  /**
   * 左栏列表当前选中的项下标（0=初级 / 1=中级 / 2=高级）。
   * 原版这个列表是可以点的，选中哪一项，中栏「最佳时间」就显示那一档的纪录。
   */
  selected: number;
}

// ==========================================================================
//  窗口骨架（information.jpg 实测）
// ==========================================================================

/** 玻璃边框宽度：x=0 外框 / x=1..6 玻璃 / x=7 暗线 / x=8 起客户区 */
const FRAME_X: number = 8;
/** 底部边框宽度：y=246 暗线 / y=247..252 玻璃 / y=253 外框 */
const FRAME_Y: number = 8;
/** 标题栏总高：y=0 外框 / y=1..27 渐变 / y=28 亮线 / y=29 分隔暗线 */
const TITLE_H: number = 29;
/** 标题文字墨迹 x=8..79（「扫雷统计信息」6 字） */
const TITLE_TEXT_X: number = 8;
/** 标题文字墨迹顶 y=9 */
const TITLE_TEXT_Y: number = 9;
/** 标题文字 */
const TITLE_TEXT: string = '扫雷统计信息';
/** 标题字号（墨迹高 12） */
const TITLE_FONT: number = 12;
/** 正文/按钮字号（墨迹高 12） */
const BTN_FONT: number = 12;
/** 墨迹顶 -> 绘制位置的补偿（与 WinDialog.ets 同一个约定） */
const TEXT_INK_DY: number = -1;

// ---- 颜色（information.jpg 实测）----
/** 客户区底色 (460,190) */
const C_CLIENT: string = '#f0f0f0';
/** 玻璃边框 x=5 */
const C_FRAME_GLASS: string = '#ebd7e8';
/** 客户区内侧暗线 x=7 */
const C_FRAME_LINE: string = '#6b646b';
/** 窗口最外沿 1px x=0 */
const C_OUTER_LINE: string = '#302c30';
/** 标题栏分隔线 y=29 */
const C_TITLE_SEP: string = '#796f77';
/** 标题栏渐变顶 y=1 */
const C_TITLE_TOP: string = '#fbf2fb';
/** 标题栏渐变最暗处 y=6 */
const C_TITLE_DARK: string = '#dec6dc';
/** 标题栏渐变中段 y=9 */
const C_TITLE_MID: string = '#e4cbe1';
/** 标题栏渐变下段 y=16..26 */
const C_TITLE_LOW: string = '#f7ddf6';
/** 标题栏底亮线 y=28 */
const C_TITLE_EDGE: string = '#fdeefb';
/** 正文文字色 */
const C_TEXT: string = '#000000';
/** 列表框选中项上的白字 */
const C_TEXT_ON_SEL: string = '#ffffff';
/** 关闭按钮的红 x=655..686 y=2..18 */
const C_CLOSE_RED: string = '#d67868';
/** 列表框 sunken 边框 x=20 */
const C_LIST_BORDER: string = '#86878b';
/** 列表框选中条渐变上 y=45 */
const C_SEL_TOP: string = '#5c8fc4';
/** 列表框选中条渐变下 y=56 */
const C_SEL_BOTTOM: string = '#4096eb';
/** group box 细边框 x=193 */
const C_GB_BORDER: string = '#dadedf';
/** 普通按钮边框 (501,210) */
const C_BTN_BORDER: string = '#707070';
/** 普通按钮填充上 (504,206) */
const C_BTN_FILL_TOP: string = '#fcfcfc';
/** 普通按钮填充下 (504,229) */
const C_BTN_FILL_BOTTOM: string = '#d1d1d1';
/** 默认按钮（关闭）的边框 (336,210) */
const C_DEF_BTN_BORDER: string = '#5e7680';
/** 默认按钮外圈的淡蓝晕 (340,206) */
const C_DEF_BTN_RING: string = '#d8ebf1';

// ---- 右上角关闭按钮（红）----
/** 红块 x=649..693（w=45）、y=2..18（h=17），右缘距窗口 9px */
const CLOSE_W: number = 45;
const CLOSE_RIGHT: number = 9;
const CLOSE_TOP: number = 2;
const CLOSE_H: number = 17;
/** 白叉尺寸（参考像素），约 x=666..672 / y=6..14 */
const CLOSE_X_HALF_W: number = 3.5;
const CLOSE_X_HALF_H: number = 4.5;
/** 白叉描边粗 */
const CLOSE_X_THICK: number = 1.5;

// ---- 左栏：难度列表框 ----
/** 列表框外框 x=20..177 / y=43..122 */
const LIST_X: number = 20;
const LIST_Y: number = 43;
const LIST_W: number = 158;
const LIST_H: number = 80;
/** 选中条 y=44..57 */
const LIST_SEL_Y: number = 44;
const LIST_SEL_H: number = 14;
/** 条目文字墨迹 x=24..46 */
const LIST_ITEM_X: number = 24;
/** 列表条目文字的命中宽度（参考像素）：「初级/中级/高级」三个字放得下 */
const LIST_ITEM_TEXT_W: number = 42;
/** 条目墨迹顶：初级 46 / 中级 59 / 高级 72（间距 13） */
const LIST_ITEM_Y0: number = 46;
const LIST_ITEM_DY: number = 13;
/** 列表框最多显示几条（(80 - 3) / 13） */
const LIST_MAX_ITEMS: number = 6;

// ---- 中栏：「最快纪录」group box ----
/** group box 外框 x=193..429 / y=49..155 */
const GB_X: number = 193;
const GB_Y: number = 49;
const GB_W: number = 237;
const GB_H: number = 107;
/** 标题「最快纪录」墨迹 x=202..248 / y=44..55 */
const GB_TITLE_X: number = 202;
const GB_TITLE_Y: number = 44;
/** 标题在边框上留的缺口 x=200..251 */
const GB_TITLE_GAP_X: number = 200;
const GB_TITLE_GAP_W: number = 52;
/** 数据行：数字墨迹 x=212..222、日期墨迹 x=251..376、墨迹顶 y=66 */
const GB_TIME_X: number = 212;
const GB_DATE_X: number = 251;
const GB_ROW_Y: number = 66;
/** 没有纪录时显示的占位 */
const GB_NO_RECORD: string = '---';

/**
 * Win7 原版「最佳成绩」表的四行（当前选中那一档难度）：
 * 最快用时 / 最快百分比 / 最慢百分比 / 最慢用时。
 *
 * 版式：标签左对齐（x=202），数值右对齐（右缘 x=420），行距 22。
 * 百分比保留一位小数（2/3 局是 66.7%，别抹成 67）。
 */
const GB4_LABEL_X: number = 202;
const GB4_VALUE_RIGHT: number = 420;
const GB4_Y0: number = 66;
const GB4_DY: number = 22;

// ---- 右栏：统计数字 ----
/** 右栏文字左缘（墨迹 x=443） */
const RC_X: number = 443;
/** 六行的墨迹顶（实测）：44 / 67 / 90 / 112 / 135 / 158 */
const RC_Y: number[] = [44, 67, 90, 112, 135, 158];

// ---- 底部按钮 ----
/** 关闭(C)：x=336..489 / y=205..231 */
const BTN_CLOSE_X: number = 336;
const BTN_CLOSE_Y: number = 205;
const BTN_CLOSE_W: number = 154;
const BTN_CLOSE_H: number = 27;
/** 重置(R)：x=502..653 / y=205..231 */
const BTN_RESET_X: number = 502;
const BTN_RESET_Y: number = 205;
const BTN_RESET_W: number = 152;
const BTN_RESET_H: number = 27;

export class StatsWindowPainter {
  /** 窗口宽度（参考像素） */
  static width(): number {
    return 702;
  }

  /** 窗口高度（参考像素） */
  static height(): number {
    return 254;
  }

  /** 获胜率（百分比，整数；与 GameStats.percent 同算法） */
  static percent(data: StatsData): number {
    if (data.played <= 0) {
      return 0;
    }
    return Math.round((data.won * 100) / data.played);
  }

  /**
   * 百分比文本（保留一位小数）。
   *
   * 原版把胜率写成整数（Lmy 克隆 io.h:271 是 `(int)(win/played*100)`），
   * 但 2/3 这种除不尽的会被抹掉 0.7，四项纪录里用一位小数更准。
   */
  static percentText(v: number): string {
    return v.toFixed(1) + '%';
  }

  /** 重置按钮的矩形（参考像素）[x, y, w, h]，draw 与 hitReset 共用 */
  static resetRect(): number[] {
    return [BTN_RESET_X, BTN_RESET_Y, BTN_RESET_W, BTN_RESET_H];
  }

  /** 关闭按钮的矩形（参考像素）[x, y, w, h]，draw 与 hitClose 共用 */
  static closeButtonRect(): number[] {
    return [BTN_CLOSE_X, BTN_CLOSE_Y, BTN_CLOSE_W, BTN_CLOSE_H];
  }

  /**
   * 标题栏右上角红叉按钮的矩形（参考像素）[x, y, w, h]。
   * draw 与 hitTitleClose 共用，保证「画在哪儿就能点到哪儿」。
   */
  static titleCloseRect(): number[] {
    return [StatsWindowPainter.width() - CLOSE_RIGHT - CLOSE_W, CLOSE_TOP, CLOSE_W, CLOSE_H];
  }

  /**
   * 左栏难度列表第 index 行的矩形（参考像素）[x, y, w, h]。
   * 命中区取文字行的位置，和 draw 画文字的位置共用同一组常量。
   */
  static listItemRect(index: number): number[] {
    return [LIST_ITEM_X, LIST_ITEM_Y0 + LIST_ITEM_DY * index, LIST_ITEM_TEXT_W, LIST_ITEM_DY];
  }

  /**
   * 点到左栏难度列表的哪一行？返回 0/1/2，没点到返回 -1。
   *
   * 原版这个列表是个真的列表框：选中哪一档，中栏「最佳时间」就显示哪一档的纪录。
   * 之前它只画不点（docs-agent 静态审计发现），现在补上。
   */
  static hitListItem(sDev: number, ox: number, oy: number, px: number, py: number): number {
    for (let i: number = 0; i < LIST_MAX_ITEMS; i++) {
      const r: number[] = StatsWindowPainter.listItemRect(i);
      const bx: number = ox + r[0] * sDev;
      const by: number = oy + r[1] * sDev;
      if (px >= bx && px <= bx + r[2] * sDev && py >= by && py <= by + r[3] * sDev) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 画统计信息窗口。
   * @param sDev 参考像素 → 设备像素（用于字号、命中换算）
   * @param sVp  参考像素 → vp（用于几何）
   * @param oxVp 窗口左上角的画布坐标（vp）
   * @param oyVp 同上
   */
  static draw(ctx: CanvasRenderingContext2D, data: StatsData, sDev: number, sVp: number,
    oxVp: number, oyVp: number): void {
    const w: number = StatsWindowPainter.width() * sVp;
    const h: number = StatsWindowPainter.height() * sVp;

    // ---- 阴影 ----
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(oxVp + 3 * sVp, oyVp + 3 * sVp, w, h);

    // ---- 玻璃边框底色 ----
    ctx.fillStyle = C_FRAME_GLASS;
    ctx.fillRect(oxVp, oyVp, w, h);

    // ---- 标题栏渐变（information.jpg y=1..28 逐行实测）----
    const grad = ctx.createLinearGradient(oxVp, oyVp, oxVp, oyVp + TITLE_H * sVp);
    grad.addColorStop(0, C_TITLE_TOP);
    grad.addColorStop(0.07, C_TITLE_DARK);
    grad.addColorStop(0.31, C_TITLE_MID);
    grad.addColorStop(0.55, C_TITLE_LOW);
    grad.addColorStop(0.90, C_TITLE_LOW);
    grad.addColorStop(0.965, C_TITLE_EDGE);
    ctx.fillStyle = grad;
    ctx.fillRect(oxVp, oyVp, w, TITLE_H * sVp);

    // ---- 客户区 ----
    const cx: number = oxVp + FRAME_X * sVp;
    const cy: number = oyVp + TITLE_H * sVp;
    const cw: number = (StatsWindowPainter.width() - FRAME_X * 2) * sVp;
    const ch: number = (StatsWindowPainter.height() - TITLE_H - FRAME_Y - 1) * sVp;
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(cx, cy, cw, ch);

    // ---- 客户区内侧暗线（x=7 / x=694 / y=246）----
    ctx.fillStyle = C_FRAME_LINE;
    ctx.fillRect(cx - 1 * sVp, cy, 1 * sVp, ch);
    ctx.fillRect(cx + cw, cy, 1 * sVp, ch);
    ctx.fillRect(cx - 1 * sVp, cy + ch, cw + 2 * sVp, 1 * sVp);

    // ---- 标题栏底部分隔线（y=29，整行通宽）----
    ctx.fillStyle = C_TITLE_SEP;
    ctx.fillRect(oxVp, oyVp + (TITLE_H - 1) * sVp, w, 1 * sVp);

    // ---- 窗口最外沿 1px ----
    ctx.fillStyle = C_OUTER_LINE;
    ctx.fillRect(oxVp, oyVp, w, 1 * sVp);
    ctx.fillRect(oxVp, oyVp + h - 1 * sVp, w, 1 * sVp);
    ctx.fillRect(oxVp, oyVp, 1 * sVp, h);
    ctx.fillRect(oxVp + w - 1 * sVp, oyVp, 1 * sVp, h);

    // ---- 标题文字（墨迹 x=8..79 / y=9..19）----
    ctx.fillStyle = C_TEXT;
    ctx.font = `bold ${TITLE_FONT * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(TITLE_TEXT, oxVp + TITLE_TEXT_X * sVp,
      oyVp + (TITLE_TEXT_Y + TEXT_INK_DY) * sVp);

    // ---- 右上角关闭按钮（红块 + 白叉）----
    const tr: number[] = StatsWindowPainter.titleCloseRect();
    const cbX: number = oxVp + tr[0] * sVp;
    const cbY: number = oyVp + tr[1] * sVp;
    const cbW: number = tr[2] * sVp;
    const cbH: number = tr[3] * sVp;
    const cg = ctx.createLinearGradient(cbX, cbY, cbX, cbY + cbH);
    cg.addColorStop(0, '#e3b0a8');
    cg.addColorStop(0.5, C_CLOSE_RED);
    cg.addColorStop(1, '#e0a49c');
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

    // ---- 左栏：难度列表框 ----
    const lx: number = oxVp + LIST_X * sVp;
    const ly: number = oyVp + LIST_Y * sVp;
    const lw: number = LIST_W * sVp;
    const lh: number = LIST_H * sVp;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(lx, ly, lw, lh);
    ctx.strokeStyle = C_LIST_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    ctx.strokeRect(lx, ly, lw, lh);
    // 选中条（第 selected 项；选中条 y=44..57，列表框上边框在 y=43）
    const cnt: number = Math.min(data.perLevel.length, LIST_MAX_ITEMS);
    const sel: number = Math.max(0, Math.min(cnt - 1, data.selected));
    const sg = ctx.createLinearGradient(lx, ly + (LIST_SEL_Y - LIST_Y) * sVp, lx,
      ly + (LIST_SEL_Y - LIST_Y + LIST_SEL_H) * sVp);
    sg.addColorStop(0, C_SEL_TOP);
    sg.addColorStop(1, C_SEL_BOTTOM);
    ctx.fillStyle = sg;
    ctx.fillRect(lx + 1 * sVp, ly + (LIST_SEL_Y - LIST_Y + LIST_ITEM_DY * sel) * sVp,
      lw - 2 * sVp, LIST_SEL_H * sVp);
    // 条目文字
    ctx.font = `${BTN_FONT * sDev}px sans-serif`;
    ctx.textBaseline = 'top';
    ctx.textAlign = 'left';
    for (let i: number = 0; i < cnt; i++) {
      const it: StatsLevel = data.perLevel[i];
      if (it.level.length === 0) {
        continue;
      }
      ctx.fillStyle = i === sel ? C_TEXT_ON_SEL : C_TEXT;
      ctx.fillText(it.level, oxVp + LIST_ITEM_X * sVp,
        oyVp + (LIST_ITEM_Y0 + LIST_ITEM_DY * i + TEXT_INK_DY) * sVp);
    }

    // ---- 中栏：「最佳时间」group box ----
    const gx: number = oxVp + GB_X * sVp;
    const gy: number = oyVp + GB_Y * sVp;
    const gw: number = GB_W * sVp;
    const gh: number = GB_H * sVp;
    ctx.strokeStyle = C_GB_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    // 上边框留出标题的缺口
    ctx.beginPath();
    ctx.moveTo(gx, gy);
    ctx.lineTo(gx + (GB_TITLE_GAP_X - GB_X) * sVp, gy);
    ctx.moveTo(gx + (GB_TITLE_GAP_X - GB_X + GB_TITLE_GAP_W) * sVp, gy);
    ctx.lineTo(gx + gw, gy);
    ctx.moveTo(gx, gy);
    ctx.lineTo(gx, gy + gh);
    ctx.moveTo(gx + gw, gy);
    ctx.lineTo(gx + gw, gy + gh);
    ctx.moveTo(gx, gy + gh);
    ctx.lineTo(gx + gw, gy + gh);
    ctx.stroke();
    // 缺口填回客户区底色
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(gx + (GB_TITLE_GAP_X - GB_X) * sVp, gy - 1 * sVp,
      GB_TITLE_GAP_W * sVp, 3 * sVp);
    // 标题「最快纪录」
    ctx.fillStyle = C_TEXT;
    ctx.font = `${BTN_FONT * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText('最快纪录', oxVp + GB_TITLE_X * sVp,
      oyVp + (GB_TITLE_Y + TEXT_INK_DY) * sVp);

    // 数据行：Win7 原版「最佳成绩」表的四行（取左栏当前选中的那一档难度）
    //
    // 四项的含义与出处见 docs/DIALOG-PIXEL-DIFF-3.md §1：
    //   最快用时   获胜局里最短的一次（秒）
    //   最快百分比 历史胜率的最大值（分母 = 该难度已玩局数）
    //   最慢百分比 历史胜率的最小值
    //   最慢用时   获胜局里最长的一次（秒）
    const selIdx: number = Math.max(0, Math.min(data.perLevel.length - 1, data.selected));
    const levelName: string = data.perLevel.length > 0 ? data.perLevel[selIdx].level : '';
    const rec: LevelRecord = GameStats.levelRecord(levelName);
    const fastText: string = data.bestSeconds >= 0 ? data.bestSeconds.toString() + '秒' : GB_NO_RECORD;
    const slowText: string = rec.slowest >= 0 ? rec.slowest.toString() + '秒' : GB_NO_RECORD;
    const bestPctText: string =
      rec.bestPercent >= 0 ? StatsWindowPainter.percentText(rec.bestPercent) : GB_NO_RECORD;
    const worstPctText: string =
      rec.worstPercent >= 0 ? StatsWindowPainter.percentText(rec.worstPercent) : GB_NO_RECORD;
    const fourLabels: string[] = ['最快用时', '最快百分比', '最慢百分比', '最慢用时'];
    const fourValues: string[] = [fastText, bestPctText, worstPctText, slowText];
    for (let i: number = 0; i < fourLabels.length; i++) {
      const ry: number = GB4_Y0 + GB4_DY * i;
      ctx.fillStyle = C_TEXT;
      ctx.textAlign = 'left';
      ctx.fillText(fourLabels[i] + ': ', oxVp + GB4_LABEL_X * sVp,
        oyVp + (ry + TEXT_INK_DY) * sVp);
      ctx.textAlign = 'right';
      ctx.fillText(fourValues[i], oxVp + GB4_VALUE_RIGHT * sVp,
        oyVp + (ry + TEXT_INK_DY) * sVp);
    }
    ctx.textAlign = 'left';

    // ---- 右栏：统计数字 ----
    const pct: number = StatsWindowPainter.percent(data);
    // 说明：information.jpg 最后一行的文案实测是「当前连局」，
    // 若要改成「当前连胜」只需要改这一行。
    const rows: string[] = [
      '已玩游戏: ' + data.played.toString(),
      '已胜游戏: ' + data.won.toString(),
      '获胜率: ' + pct.toString() + '%',
      '最多连胜: ' + data.maxStreak.toString(),
      '最多连败: ' + data.maxLoseStreak.toString(),
      '当前连局: ' + data.currentStreak.toString()
    ];
    ctx.fillStyle = C_TEXT;
    ctx.font = `${BTN_FONT * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    for (let i: number = 0; i < rows.length; i++) {
      ctx.fillText(rows[i], oxVp + RC_X * sVp, oyVp + (RC_Y[i] + TEXT_INK_DY) * sVp);
    }

    // ---- 底部：关闭(C) / 重置(R) ----
    // 默认按钮（关闭）：1px 蓝灰边框 + 边框内侧 1px 淡蓝晕 + 客户区同色填充
    const cbx: number = oxVp + BTN_CLOSE_X * sVp;
    const cby: number = oyVp + BTN_CLOSE_Y * sVp;
    const cbw: number = BTN_CLOSE_W * sVp;
    const cbh: number = BTN_CLOSE_H * sVp;
    ctx.fillStyle = C_DEF_BTN_RING;
    ctx.fillRect(cbx, cby, cbw, cbh);
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(cbx + 1 * sVp, cby + 1 * sVp, cbw - 2 * sVp, cbh - 2 * sVp);
    ctx.strokeStyle = C_DEF_BTN_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    ctx.strokeRect(cbx, cby, cbw, cbh);
    // 普通按钮（重置）
    const rbx: number = oxVp + BTN_RESET_X * sVp;
    const rby: number = oyVp + BTN_RESET_Y * sVp;
    const rbw: number = BTN_RESET_W * sVp;
    const rbh: number = BTN_RESET_H * sVp;
    const bg = ctx.createLinearGradient(rbx, rby, rbx, rby + rbh);
    bg.addColorStop(0, C_BTN_FILL_TOP);
    bg.addColorStop(1, C_BTN_FILL_BOTTOM);
    ctx.fillStyle = bg;
    ctx.fillRect(rbx, rby, rbw, rbh);
    ctx.strokeStyle = C_BTN_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    ctx.strokeRect(rbx, rby, rbw, rbh);
    // 按钮文字（墨迹 y=213..224，垂直居中于 205..231）
    ctx.fillStyle = C_TEXT;
    ctx.font = `${BTN_FONT * sDev}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('关闭(C)', cbx + cbw / 2, cby + cbh / 2);
    ctx.fillText('重置(R)', rbx + rbw / 2, rby + rbh / 2);
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /**
   * 是否点在「重置(R)」按钮上。
   * @param sDev 参考像素 → 设备像素（ox/oy/px/py 都是设备像素）
   */
  static hitReset(sDev: number, ox: number, oy: number, px: number, py: number): boolean {
    const r: number[] = StatsWindowPainter.resetRect();
    const bx: number = ox + r[0] * sDev;
    const by: number = oy + r[1] * sDev;
    return px >= bx && px <= bx + r[2] * sDev && py >= by && py <= by + r[3] * sDev;
  }

  /**
   * 是否点在「关闭(C)」按钮上（附加接口：关闭按钮画出来了，就得能点）。
   * @param sDev 参考像素 → 设备像素（ox/oy/px/py 都是设备像素）
   */
  static hitClose(sDev: number, ox: number, oy: number, px: number, py: number): boolean {
    const r: number[] = StatsWindowPainter.closeButtonRect();
    const bx: number = ox + r[0] * sDev;
    const by: number = oy + r[1] * sDev;
    return px >= bx && px <= bx + r[2] * sDev && py >= by && py <= by + r[3] * sDev;
  }

  /**
   * 是否点在标题栏右上角的红叉上。
   *
   * 坑（2026-10-31，docs-agent 静态审计发现）：这个叉是**画出来的**，但一直没有
   * 命中区——hitClose 测的是底部「关闭(C)」大按钮，红叉点它没反应。
   * 现在把矩形抽成 titleCloseRect()，画与点共用同一组常量。
   */
  static hitTitleClose(sDev: number, ox: number, oy: number, px: number, py: number): boolean {
    const r: number[] = StatsWindowPainter.titleCloseRect();
    const bx: number = ox + r[0] * sDev;
    const by: number = oy + r[1] * sDev;
    return px >= bx && px <= bx + r[2] * sDev && py >= by && py <= by + r[3] * sDev;
  }
}
