/**
 * WinMenu.ets —— Windows 7 风格的菜单栏（游戏 / 帮助）
 *
 * 原版扫雷窗口顶部就是一条 Win7 菜单栏：
 *   游戏：新建(F2) / 初级 / 中级 / 高级 / 自定义 / 标记(?) / 声音 / 最佳成绩 / 外观(F7) / 退出
 *   帮助：帮助(H) / 关于扫雷(A)
 * 本实现把菜单栏直接画在画布顶部（原版菜单栏也在窗口内，不是系统浮层），
 * 下拉菜单同样是画布绘制，命中测试用几何矩形。
 *
 * 「外观」项的条目由 appearanceEntry() 提供，文案见 Appearance.ets。
 *
 * 单位（与 WinDialog 一致）：
 *   几何坐标用 vp；font 里的 "px" 是设备像素，所以字号要传设备像素值。
 *   下面的 API 直接传「字号(设备像素)」+「密度」，内部换算，避免再踩单位坑。
 *
 * ============================================================================
 * 参考图实测（1 倍像素）
 *   参考图 = Minesweeper-master/jpg/about.jpg（615×408 整窗截图）。
 *   三张整窗参考图（about / gaming / initializing）在菜单栏区域的实测关系
 *   （2026-11-01 逐像素复核，区域 = 行 30..48 × 列 8..250）：
 *     · initializing.jpg 与 about.jpg **逐像素一致**
 *       （最大通道差 3，差异>12 的像素 0 个 / 13794）；
 *     · gaming.jpg 的**背景与 about 不一致**（最大通道差 114，差异>12 的像素 1337 个）——
 *       原因是 Aero 玻璃透出的桌面底色不同，属正常现象；
 *     · 但三张图的**文字位置完全一致**（墨迹都在行 34..45，列组相同），
 *       所以文字几何仍可三图交叉验证。
 *
 * 整窗的纵向结构（截图行号）：
 *   行  0..28  标题栏（Aero 玻璃），不在本文件范围
 *   行  29     标题栏下的 1px 分隔线（约 #73737b）
 *   行 30..47  菜单栏本体，共 18 行（本文件负责的部分）
 *   行  48     菜单栏下的 1px 分隔线（#b9bcc5）
 *   行 49..    客户区（扫雷棋盘外框）
 *
 * 菜单栏底色是竖向渐变（不是纯色）。实测 18 行（about/gaming/initializing 取平均）：
 *   行30 #fefeff → 行32 #f7f8fc → 行34 #eff2f9 → 行36 #e4eaf6 → 行37 #d5dbeb
 *   → 行38 #d4dbed → 行40 #d8ddf0 → 行43 #dce1f4 → 行47 #e1e6f4
 *   （下半段那点偏蓝是 Aero 玻璃透出的桌面底色，属参考图当时的桌面环境；
 *     本实现按原样复刻，不做去蓝处理）
 *
 * 文字实测：
 *   字号 12px（大写 G/H 的 cap height = 9px，落在行 35..43；
 *              汉字字面高 11px，落在行 34..44）
 *   字色 #000000（ClearType 子像素渲染，所以字边缘带彩边）
 *   基线在行 43.5，即栏顶往下 13.5px
 *   「游戏(G)」墨迹 x=15..54：游 15..26、戏 28..38、( 40..42、G 44..50、) 52..54
 *   「帮助(H)」墨迹 x=71..109：帮 71..80、助 82..92、( 95..97、H 99..105、) 107..109
 *   窗口内容左边在 x=7 的 1px 边框之后，即 x=8
 *     → 第一个菜单项的文字起点距内容左边 7px
 *     → 「游戏(G)」与「帮助(H)」之间的空白 16px
 *     → 文字前进宽（12px 字号下）：汉字 12、'(' 4、')' 4、'G' 8、'H' 7
 *
 * ============================================================================
 * 未实测（参考图里没有展开的下拉菜单，以下按 Win7 通用观感设计）：
 *   下拉面板配色/阴影、条目高亮色、分隔线样式、勾选标记、快捷键右对齐位置。
 *   菜单栏的「已展开」高亮态参考图同样没有。**实现现状**（2026-11-01 实测更正：
 *   先前注释写「淡蓝圆角块」与代码不符，实际画出来的是直角）：
 *     · 高亮块 = 淡蓝竖向渐变（#eaf4fd → #cfe6fa）+ #7fb2dd 边框，
 *       用 fillRect + strokeRect 画出，**四角为直角**。Win7 真机是圆角，
 *       但原版资产里没有展开态截图，判定不了该用多大的圆角，故暂按现状保留；
 *     · 下拉面板阴影 = 右下偏移 2vp 的 **25% 黑硬边矩形**（Win7 真机是柔和投影，
 *       同样没有参考图可依，暂按现状保留）。
 *
 * 复检记录（2026-11-01，5555 与 5557 实拍 vs 上述参考图）：
 *   栏底渐变与分隔线**逐像素 100% 一致**（容差 12）；栏高 21vp、基线 13.5 参考px、
 *   两个标题的横向步进与参考图逐字对齐；文字区 66%~69% 的差异来自
 *   设备字体 ≠ Win7 Segoe UI 的**字形**差异，不是排版偏差。
 *   完整数据与跨设备对比见规格仓 docs/MENU-PIXEL-DIFF.md。
 * ============================================================================
 */

import { MENU_APPEARANCE_LABEL } from './Appearance';

/** 菜单里的一项 */
export interface MenuEntry {
  /** 选中后回传的动作标识 */
  id: string;
  /** 显示文字 */
  label: string;
  /** 右对齐的快捷键提示，例如 F2 */
  accelerator?: string;
  /** 是否是分隔线 */
  separator?: boolean;
  /** 是否打勾（当前难度） */
  checked?: boolean;
  /** 是否灰掉 */
  disabled?: boolean;
}

/** 一个顶层菜单 */
export interface MenuTop {
  id: string;
  label: string;
  entries: MenuEntry[];
}

/** 菜单栏规格 */
export interface MenuSpec {
  tops: MenuTop[];
}

// ============================================================================
// 参考图实测常量（单位：参考像素，即参考截图 1 倍像素）
// ============================================================================

/** 参考图里的字号（实测：大写 cap height 9px、汉字字面高 11px） */
const REF_FONT_PX: number = 12;

/** 本工程菜单栏用的字号（vp）——主线程 GameController.drawMenu 里写死的是 14vp */
const APP_FONT_VP: number = 14;

/** 菜单栏高度（实测：占截图第 30..47 行，共 18 行） */
const BAR_H_REF: number = 18;

/** 文字基线相对栏顶的偏移（实测：基线在截图第 43.5 行） */
const TEXT_BASE_REF: number = 13.5;

/** 内容左边缘 → 第一个菜单项文字起点的距离（实测：内容左边 x=8，「游」墨迹 x=15） */
const BAR_INSET_REF: number = 7;

/** 相邻两个菜单项之间的空白（实测：「游戏(G)」墨迹止于 x=54，「帮助(H)」起于 x=71） */
const ITEM_GAP_REF: number = 16;

/** 菜单项命中框/高亮框相对文字的左右留白（参考图未实测高亮态，按 Win7 观感取） */
const ITEM_PAD_REF: number = 4;

// ============================================================================
// 颜色（实测）
// ============================================================================

/** 菜单栏渐变的色标位置（0..1，对应 18 行里的相对位置） */
const BAR_GRAD_POS: number[] = [0.0, 0.1176, 0.2353, 0.3529, 0.4118, 0.4706, 0.5882, 0.7647, 1.0];
/** 菜单栏渐变的色标颜色（实测行 30/32/34/36/37/38/40/43/47） */
const BAR_GRAD_COL: string[] = [
  '#fefeff', '#f7f8fc', '#eff2f9', '#e4eaf6', '#d5dbeb',
  '#d4dbed', '#d8ddf0', '#dce1f4', '#e1e6f4'
];
/** 菜单栏下的 1px 分隔线（实测截图第 48 行） */
const C_BAR_SEP: string = '#b9bcc5';
/** 菜单文字颜色（实测 #000000） */
const C_TEXT: string = '#000000';
/** 已展开/高亮的菜单项底色（未实测，Win7 观感：上浅下深的淡蓝） */
const C_HILITE_TOP: string = '#eaf4fd';
const C_HILITE_BOTTOM: string = '#cfe6fa';
/** 已展开/高亮的菜单项边框（未实测，Win7 观感） */
const C_HILITE_BORDER: string = '#7fb2dd';

// ============================================================================
// 下拉菜单（未实测，按 Win7 通用观感；几何尺寸被主线程 GameController 硬编码，
//            必须与那边一致：面板宽 168vp、条目高 24vp、分隔线 7vp、上下留白各 4vp）
// ============================================================================

/** 下拉面板底色（Win7 菜单底色） */
const C_PANEL: string = '#f0f0f0';
/** 下拉面板边框（Win7 观感） */
const C_PANEL_BORDER: string = '#adadad';
/** 分隔线颜色（Win7 观感） */
const C_SEPARATOR: string = '#d9d9d9';
/** 灰掉（禁用）项的文字颜色 */
const C_DISABLED: string = '#a0a0a0';
/** 下拉菜单项高（vp）——与 GameController.isOnMenuBar 里的 24 一致 */
const ITEM_H: number = 24;
/** 下拉菜单分隔线高（vp）——与 GameController.isOnMenuBar 里的 7 一致 */
const SEP_H: number = 7;
/** 下拉面板上下留白（vp）——与 GameController.isOnMenuBar 里的 8 (=4+4) 一致 */
const DROP_PAD: number = 4;
/** 下拉菜单宽（vp）——与 GameController.isOnMenuBar 里的 168 一致 */
const DROP_W: number = 168;
/** 下拉菜单里：勾选标记的 x（相对面板左边，vp） */
const DROP_CHECK_X: number = 10;
/** 下拉菜单里：条目文字的 x（相对面板左边，vp） */
const DROP_TEXT_X: number = 26;
/** 下拉菜单里：快捷键右对齐的右边距（vp） */
const DROP_ACC_RIGHT: number = 12;

/**
 * 菜单栏高度（vp）。
 *
 * 参考图实测菜单栏 18 个参考像素（行 30..47）。本工程的菜单字号是 14vp，
 * 而参考图里的字号是 12 参考像素，所以换算系数 = 14 / 12，
 * 菜单栏高 = 18 × (14 / 12) = 21vp。
 *
 * 坑：这里是常量，跟不上字号变化。改字号时必须同步改这个值，
 *     否则 GameController.isOnMenuBar / menuActionAt 的命中区会和画出来的不一致。
 */
export const MENU_BAR_H: number = BAR_H_REF * (APP_FONT_VP / REF_FONT_PX);

/**
 * 「外观」菜单项的显示文字与条目。
 *
 * 名字常量本体在 Appearance.ets（外观功能的模块自己拥有它的名字），
 * 这里只把它包成一条菜单项给 GameController.buildMenu() 用。
 *
 * 文案是**占位名，待定**（2026-10-31）：refs 里找不到任何中文证据 ——
 * 原版 Win7 只有英文串 "Change Appearance"（F7），详见
 * Appearance.ets 里 MENU_APPEARANCE_LABEL 的注释与 docs\APPEARANCE-DIALOG.md。
 */
export function appearanceEntry(): MenuEntry {
  return { id: 'appearance', label: MENU_APPEARANCE_LABEL, accelerator: 'F7' };
}

export class WinMenuPainter {
  // ------------------------------------------------------------------ 换算

  /**
   * 参考像素 → vp 的换算系数。
   * 字号是设备像素，几何是 vp，所以要先用字号把「参考像素」拉到「设备像素」，
   * 再除以密度回到 vp。density = 每 vp 的设备像素数。
   */
  static scaleVp(fontPx: number, density: number): number {
    return fontPx / (REF_FONT_PX * density);
  }

  // -------------------------------------------------------------- 顶层菜单

  /**
   * 顶层菜单的完整文字。
   *
   * 参考图里写的是「游戏(G)」「帮助(H)」，而主线程 GameController.buildMenu()
   * 只给了「游戏」「帮助」，所以这里按顶层项补上快捷键括号。
   * label 里已经带括号时不再重复添加（以后主线程改成「游戏(G)」也不会叠成两个）。
   */
  static topText(label: string): string {
    if (label.indexOf('(') >= 0) {
      return label;
    }
    if (label === '游戏') {
      return '游戏(G)';
    }
    if (label === '帮助') {
      return '帮助(H)';
    }
    return label;
  }

  /** 单个字符的前进宽度（参考像素，12px 字号下实测） */
  static charAdvanceRef(ch: string): number {
    const code = ch.charCodeAt(0);
    if (code >= 0x4e00 && code <= 0x9fff) {
      return 12;                       // 汉字（全角）= 1 em
    }
    if (ch === '(' || ch === ')') {
      return 4;
    }
    if (ch === 'G') {
      return 8;
    }
    if (ch === 'H') {
      return 7;
    }
    return 7;                          // 其它 ASCII 兜底
  }

  /** 一串文字的前进宽度（参考像素） */
  static textAdvanceRef(text: string): number {
    let w = 0;
    for (let i = 0; i < text.length; i++) {
      w += WinMenuPainter.charAdvanceRef(text.charAt(i));
    }
    return w;
  }

  /**
   * 顶层项的宽度（vp）：文字前进宽 + 与下一项之间的空白。
   * 语义是「本项文字起点 → 下一项文字起点」的距离，排版与命中都用它。
   */
  static topItemWidth(label: string, fontPx: number, density: number): number {
    const sVp = WinMenuPainter.scaleVp(fontPx, density);
    const advRef = WinMenuPainter.textAdvanceRef(WinMenuPainter.topText(label));
    return (advRef + ITEM_GAP_REF) * sVp;
  }

  /** 顶层项文字的起点 x（vp）——与 drawBar 的排版一致 */
  static topItemX(spec: MenuSpec, topId: string, fontPx: number, density: number, oxVp: number): number {
    const sVp = WinMenuPainter.scaleVp(fontPx, density);
    let x = oxVp + BAR_INSET_REF * sVp;
    for (const top of spec.tops) {
      if (top.id === topId) {
        return x;
      }
      x += WinMenuPainter.topItemWidth(top.label, fontPx, density);
    }
    return x;
  }

  // ------------------------------------------------------------------ 绘制

  /** 画菜单栏 */
  static drawBar(ctx: CanvasRenderingContext2D, spec: MenuSpec, fontPx: number, density: number,
    oxVp: number, oyVp: number, wVp: number, hVp: number, openId: string): void {
    const sVp = WinMenuPainter.scaleVp(fontPx, density);

    // 菜单栏底：竖向渐变（实测 18 行的渐变，见文件头）
    const grad = ctx.createLinearGradient(oxVp, oyVp, oxVp, oyVp + hVp);
    for (let i = 0; i < BAR_GRAD_POS.length; i++) {
      grad.addColorStop(BAR_GRAD_POS[i], BAR_GRAD_COL[i]);
    }
    ctx.fillStyle = grad;
    ctx.fillRect(oxVp, oyVp, wVp, hVp);

    // 菜单栏下的 1px 分隔线（实测截图第 48 行）
    ctx.fillStyle = C_BAR_SEP;
    ctx.fillRect(oxVp, oyVp + hVp, wVp, Math.max(1, sVp));

    // 顶层项
    const padVp = ITEM_PAD_REF * sVp;
    const baseY = oyVp + TEXT_BASE_REF * sVp;
    let x = oxVp + BAR_INSET_REF * sVp;
    for (const top of spec.tops) {
      const text = WinMenuPainter.topText(top.label);
      const advRef = WinMenuPainter.textAdvanceRef(text);
      const advVp = advRef * sVp;
      if (top.id === openId) {
        // 展开态：淡蓝**直角**块（未实测；原版资产里没有展开态截图，
        // 判定不了 Win7 真机的圆角半径，故按现状保留直角）
        const hx = x - padVp;
        const hy = oyVp + 2 * sVp;
        const hw = advVp + padVp * 2;
        const hh = hVp - 4 * sVp;
        const g2 = ctx.createLinearGradient(0, hy, 0, hy + hh);
        g2.addColorStop(0, C_HILITE_TOP);
        g2.addColorStop(1, C_HILITE_BOTTOM);
        ctx.fillStyle = g2;
        ctx.fillRect(hx, hy, hw, hh);
        ctx.strokeStyle = C_HILITE_BORDER;
        ctx.lineWidth = Math.max(1, sVp);
        ctx.strokeRect(hx, hy, hw, hh);
      }
      ctx.fillStyle = C_TEXT;
      ctx.font = `${Math.round(fontPx)}px sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'alphabetic';
      ctx.fillText(text, x, baseY);
      x += advVp + ITEM_GAP_REF * sVp;
    }
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /** 画下拉菜单；返回它的实际高度（vp） */
  static drawDrop(ctx: CanvasRenderingContext2D, entries: MenuEntry[], fontPx: number,
    xVp: number, yVp: number): number {
    const h = WinMenuPainter.dropHeight(entries);
    const w = DROP_W;

    // 阴影：右下偏移 2vp 的 25% 黑**硬边**矩形（Win7 真机是柔和投影，
    // 但原版资产里没有展开态截图可依，暂按现状保留）
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.fillRect(xVp + 2, yVp + 2, w, h);
    // 面板
    ctx.fillStyle = C_PANEL;
    ctx.fillRect(xVp, yVp, w, h);
    ctx.strokeStyle = C_PANEL_BORDER;
    ctx.lineWidth = 1;
    ctx.strokeRect(xVp, yVp, w, h);

    // 条目
    let y = yVp + DROP_PAD;
    for (const e of entries) {
      if (e.separator) {
        // 分隔线：一条浅灰线（Win7 观感）
        ctx.strokeStyle = C_SEPARATOR;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(xVp + 6, y + 3);
        ctx.lineTo(xVp + w - 6, y + 3);
        ctx.stroke();
        y += SEP_H;
        continue;
      }
      if (e.checked) {
        // 勾选标记：画在固定的左侧栏里，文字不跟着挪（Win7 观感）
        const cx = xVp + DROP_CHECK_X;
        const cy = y + ITEM_H / 2;
        ctx.strokeStyle = e.disabled ? C_DISABLED : C_TEXT;
        ctx.lineWidth = Math.max(1, 1.4);
        ctx.beginPath();
        ctx.moveTo(cx - 3.5, cy);
        ctx.lineTo(cx - 0.5, cy + 3);
        ctx.lineTo(cx + 4, cy - 3);
        ctx.stroke();
      }
      ctx.fillStyle = e.disabled ? C_DISABLED : C_TEXT;
      ctx.font = `${Math.round(fontPx)}px sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(e.label, xVp + DROP_TEXT_X, y + ITEM_H / 2);
      if (e.accelerator !== undefined && e.accelerator.length > 0) {
        ctx.fillStyle = e.disabled ? C_DISABLED : C_TEXT;
        ctx.textAlign = 'right';
        ctx.fillText(e.accelerator, xVp + w - DROP_ACC_RIGHT, y + ITEM_H / 2);
        ctx.textAlign = 'left';
      }
      y += ITEM_H;
    }
    ctx.textBaseline = 'alphabetic';
    return h;
  }

  /** 下拉面板的总高（vp）——与 drawDrop / entryHit / GameController 保持一致 */
  static dropHeight(entries: MenuEntry[]): number {
    let h = DROP_PAD * 2;
    for (const e of entries) {
      h += e.separator ? SEP_H : ITEM_H;
    }
    return h;
  }

  // ------------------------------------------------------------------ 命中

  /** 顶层项的命中（返回顶层项 id，空串表示没点到） */
  static topHit(spec: MenuSpec, fontPx: number, density: number, oxVp: number, oyVp: number,
    hVp: number, pxVp: number, pyVp: number): string {
    const sVp = WinMenuPainter.scaleVp(fontPx, density);
    const padVp = ITEM_PAD_REF * sVp;
    let x = oxVp + BAR_INSET_REF * sVp;
    for (const top of spec.tops) {
      const advVp = WinMenuPainter.textAdvanceRef(WinMenuPainter.topText(top.label)) * sVp;
      // 命中框 = 文字起点左右各留 ITEM_PAD_REF 个参考像素（与 drawBar 的高亮块一致）
      if (pxVp >= x - padVp && pxVp <= x + advVp + padVp &&
        pyVp >= oyVp && pyVp <= oyVp + hVp) {
        return top.id;
      }
      x += advVp + ITEM_GAP_REF * sVp;
    }
    return '';
  }

  /** 下拉条目的命中（返回动作标识，空串表示没点到） */
  static entryHit(entries: MenuEntry[], xVp: number, yVp: number, pxVp: number, pyVp: number): string {
    if (pxVp < xVp || pxVp > xVp + DROP_W) {
      return '';
    }
    let y = yVp + DROP_PAD;
    for (const e of entries) {
      if (e.separator) {
        y += SEP_H;
        continue;
      }
      if (pyVp >= y && pyVp <= y + ITEM_H) {
        return e.disabled ? '' : e.id;
      }
      y += ITEM_H;
    }
    return '';
  }

  /** 下拉菜单左上角 x（跟 drawBar 的排版一致；左边对齐顶层项的高亮块） */
  static dropX(spec: MenuSpec, topId: string, fontPx: number, density: number, oxVp: number): number {
    const sVp = WinMenuPainter.scaleVp(fontPx, density);
    return WinMenuPainter.topItemX(spec, topId, fontPx, density, oxVp) - ITEM_PAD_REF * sVp;
  }
}
