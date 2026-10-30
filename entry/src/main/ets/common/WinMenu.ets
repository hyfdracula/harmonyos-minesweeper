/**
 * WinMenu.ets —— Windows 7 风格的菜单栏（游戏 / 帮助）
 *
 * 原版扫雷窗口顶部就是一条 Win7 菜单栏：
 *   游戏：新建(F2) / 初级 / 中级 / 高级 / 自定义 / 标记(?) / 颜色 / 声音 / 最佳成绩 / 退出
 *   帮助：帮助(H) / 关于扫雷(A)
 * 本实现把菜单栏直接画在画布顶部（原版菜单栏也在窗口内，不是系统浮层），
 * 下拉菜单同样是画布绘制，命中测试用几何矩形。
 *
 * 单位（与 WinDialog 一致）：
 *   几何坐标用 vp；font 里的 "px" 是设备像素，所以字号要传设备像素值。
 *   下面的 API 直接传「字号(设备像素)」+「密度」，内部换算，避免再踩单位坑。
 *
 * 颜色按 Win7 观感取：菜单栏底 #f0f0f0，下拉面板 #f0f0f0 + 1px 灰边，
 * 选中项高亮 #0078d7 蓝底白字。
 */

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

const C_BAR: string = '#f0f0f0';
const C_BAR_LINE: string = '#c9c9c9';
const C_TEXT: string = '#000000';
const C_HILITE: string = '#0078d7';
const C_PANEL_BORDER: string = '#9a9a9a';
const C_DISABLED: string = '#a0a0a0';

/** 菜单栏高度（vp） */
export const MENU_BAR_H: number = 26;
/** 下拉菜单项高（vp） */
const ITEM_H: number = 24;
/** 下拉菜单宽（vp） */
const DROP_W: number = 168;

export class WinMenuPainter {
  /** 顶层项的宽度（vp）：字宽估算 + 左右留白 */
  static topItemWidth(label: string, fontPx: number, density: number): number {
    const fontVp = fontPx / density;
    return label.length * fontVp * 0.55 + 16;
  }

  /** 画菜单栏 */
  static drawBar(ctx: CanvasRenderingContext2D, spec: MenuSpec, fontPx: number, density: number,
    oxVp: number, oyVp: number, wVp: number, hVp: number, openId: string): void {
    // 菜单栏底 + 下边线
    ctx.fillStyle = C_BAR;
    ctx.fillRect(oxVp, oyVp, wVp, hVp);
    ctx.strokeStyle = C_BAR_LINE;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(oxVp, oyVp + hVp);
    ctx.lineTo(oxVp + wVp, oyVp + hVp);
    ctx.stroke();

    // 顶层项
    let x = oxVp + 8;
    for (const top of spec.tops) {
      const itemW = WinMenuPainter.topItemWidth(top.label, fontPx, density);
      if (top.id === openId) {
        ctx.fillStyle = C_HILITE;
        ctx.fillRect(x, oyVp + 2, itemW, hVp - 4);
        ctx.fillStyle = '#ffffff';
      } else {
        ctx.fillStyle = C_TEXT;
      }
      ctx.font = `${fontPx}px sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(top.label, x + 8, oyVp + hVp / 2);
      x += itemW;
    }
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /** 画下拉菜单；返回它的实际高度（vp） */
  static drawDrop(ctx: CanvasRenderingContext2D, entries: MenuEntry[], fontPx: number,
    xVp: number, yVp: number): number {
    const pad = 4;
    let h = pad * 2;
    for (const e of entries) {
      h += e.separator ? 7 : ITEM_H;
    }
    const w = DROP_W;

    // 面板
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.fillRect(xVp + 2, yVp + 2, w, h);
    ctx.fillStyle = C_BAR;
    ctx.fillRect(xVp, yVp, w, h);
    ctx.strokeStyle = C_PANEL_BORDER;
    ctx.lineWidth = 1;
    ctx.strokeRect(xVp, yVp, w, h);

    // 条目
    let y = yVp + pad;
    for (const e of entries) {
      if (e.separator) {
        ctx.strokeStyle = '#d5d5d5';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(xVp + 6, y + 3);
        ctx.lineTo(xVp + w - 6, y + 3);
        ctx.stroke();
        y += 7;
        continue;
      }
      const label = (e.checked ? '✓ ' : '') + e.label;
      ctx.fillStyle = e.disabled ? C_DISABLED : C_TEXT;
      ctx.font = `${fontPx}px sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(label, xVp + 10, y + ITEM_H / 2);
      if (e.accelerator !== undefined && e.accelerator.length > 0) {
        ctx.fillStyle = C_DISABLED;
        ctx.textAlign = 'right';
        ctx.fillText(e.accelerator, xVp + w - 10, y + ITEM_H / 2);
        ctx.textAlign = 'left';
      }
      y += ITEM_H;
    }
    ctx.textBaseline = 'alphabetic';
    return h;
  }

  /** 顶层项的命中（返回顶层项 id，空串表示没点到） */
  static topHit(spec: MenuSpec, fontPx: number, density: number, oxVp: number, oyVp: number,
    hVp: number, pxVp: number, pyVp: number): string {
    let x = oxVp + 8;
    for (const top of spec.tops) {
      const itemW = WinMenuPainter.topItemWidth(top.label, fontPx, density);
      if (pxVp >= x && pxVp <= x + itemW && pyVp >= oyVp && pyVp <= oyVp + hVp) {
        return top.id;
      }
      x += itemW;
    }
    return '';
  }

  /** 下拉条目的命中（返回动作标识，空串表示没点到） */
  static entryHit(entries: MenuEntry[], xVp: number, yVp: number, pxVp: number, pyVp: number): string {
    const pad = 4;
    if (pxVp < xVp || pxVp > xVp + DROP_W) {
      return '';
    }
    let y = yVp + pad;
    for (const e of entries) {
      if (e.separator) {
        y += 7;
        continue;
      }
      if (pyVp >= y && pyVp <= y + ITEM_H) {
        return e.disabled ? '' : e.id;
      }
      y += ITEM_H;
    }
    return '';
  }

  /** 下拉菜单左上角 x（跟 drawBar 的排版一致） */
  static dropX(spec: MenuSpec, topId: string, fontPx: number, density: number, oxVp: number): number {
    let x = oxVp + 8;
    for (const top of spec.tops) {
      if (top.id === topId) {
        return x;
      }
      x += WinMenuPainter.topItemWidth(top.label, fontPx, density);
    }
    return x;
  }
}
