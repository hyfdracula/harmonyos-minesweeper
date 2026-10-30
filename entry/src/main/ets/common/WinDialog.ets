/**
 * WinDialog.ets —— Windows 7 风格的结束对话框（输 / 赢）
 *
 * 规格全部来自原版截图实测（Minesweeper-master/jpg/loss.jpg 与 win.jpg，1 倍像素）：
 *   失败框 483×288；胜利框 396×340
 *   客户区底色 #f0f0f0；标题栏为 Aero 玻璃质感（浅紫白渐变，随桌面背景变化）
 *   按钮：1px 灰边 + 上浅下深的渐变，文字黑色居中
 *   坐标一律用「参考像素」（= 原版 1 倍像素），绘制时乘以缩放系数换算。
 *
 * 坑（2026-10-31 实测）：Canvas 的**坐标是 vp**，但 font 里的 "px" 是**设备像素**。
 *    所以几何用 sVp（vp / 参考像素），字号用 sDev（设备像素 / 参考像素），两者差一个密度。
 *
 * 坑：CanvasRenderingContext2D 是 ArkTS 的全局类型，不能从 @kit.ArkUI 导入。
 */

/** 对话框里的一行文字 */
export interface DlgLine {
  text: string;
  /** 参考像素：相对对话框左上角 */
  x: number;
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
}

/** 一个对话框的全部描述 */
export interface DlgSpec {
  title: string;
  /** 参考像素尺寸 */
  width: number;
  height: number;
  lines: DlgLine[];
  buttons: DlgButton[];
}

/** 颜色（实测自 loss.jpg） */
const C_CLIENT: string = '#f0f0f0';
const C_TITLE_TOP: string = '#efe6f2';
const C_TITLE_BOTTOM: string = '#ded0e4';
const C_BORDER: string = '#8a7f96';
const C_TEXT: string = '#000000';
const C_BTN_TOP: string = '#f7f7f7';
const C_BTN_BOTTOM: string = '#e2e2e2';
const C_BTN_BORDER: string = '#707070';
const C_CLOSE: string = '#c7433b';

export class WinDialogPainter {
  /**
   * 失败对话框（实测自 loss.jpg，参考尺寸 483×288）
   * 与原版唯一差别：中间那个按钮原版是「重新开始这个游戏(R)」，
   * 与右边的「再玩一局(P)」功能重复；手机端改成「换个难度(D)」更实用。
   */
  static loseSpec(seconds: number, played: number, won: number, percent: number): DlgSpec {
    return {
      title: '游戏失败',
      width: 483,
      height: 288,
      lines: [
        { text: '不好意思，您输了！下次走运!', x: 236, y: 51, size: 14, align: 'center' },
        { text: '时间: ' + seconds + '秒', x: 22, y: 93, size: 12, align: 'left' },
        { text: '已玩游戏: ' + played, x: 23, y: 140, size: 12, align: 'left' },
        { text: '已胜游戏: ' + won, x: 23, y: 164, size: 12, align: 'left' },
        { text: '百分比: ' + percent + '%', x: 205, y: 164, size: 12, align: 'left' }
      ],
      buttons: [
        { id: 'exit', label: '退出(X)', x: 17, y: 236, w: 140, h: 25 },
        { id: 'menu', label: '换个难度(D)', x: 170, y: 236, w: 146, h: 25 },
        { id: 'again', label: '再玩一局(P)', x: 325, y: 236, w: 141, h: 25 }
      ]
    };
  }

  /**
   * 胜利对话框（实测自 win.jpg，参考尺寸 396×340）
   */
  static winSpec(seconds: number, played: number, won: number, percent: number,
    bestText: string, bestDate: string, isNewBest: boolean): DlgSpec {
    const lines: DlgLine[] = [];
    lines.push({ text: '恭喜！您赢了！', x: 194, y: 44, size: 14, align: 'center' });
    if (isNewBest) {
      lines.push({ text: '您所用的时间是这个难度级别的最短时间!', x: 197, y: 77, size: 12, align: 'center' });
    }
    lines.push({ text: '时间: ' + seconds + '秒', x: 22, y: 127, size: 12, align: 'left' });
    if (bestText.length > 0) {
      lines.push({ text: '最快时间: ' + bestText, x: 22, y: 161, size: 12, align: 'left' });
      lines.push({ text: '日期: ' + bestDate, x: 220, y: 161, size: 12, align: 'left' });
    }
    lines.push({ text: '已玩游戏: ' + played, x: 23, y: 185, size: 12, align: 'left' });
    lines.push({ text: '已胜游戏: ' + won, x: 23, y: 210, size: 12, align: 'left' });
    lines.push({ text: '百分比: ' + percent + '%', x: 210, y: 210, size: 12, align: 'left' });
    return {
      title: '游戏胜利',
      width: 396,
      height: 340,
      lines: lines,
      buttons: [
        { id: 'again', label: '再玩一局(P)', x: 23, y: 252, w: 135, h: 26 },
        { id: 'exit', label: '退出(Q)', x: 23, y: 288, w: 135, h: 24 }
      ]
    };
  }

  /**
   * 「最佳成绩」对话框（菜单 游戏 → 最佳成绩）
   */
  static bestSpec(seconds: number, played: number, won: number, percent: number,
    bestText: string): DlgSpec {
    const lines: DlgLine[] = [];
    lines.push({ text: '最佳成绩', x: 190, y: 44, size: 14, align: 'center' });
    lines.push({ text: '最快时间: ' + (bestText.length > 0 ? bestText : '暂无纪录'), x: 30, y: 92, size: 12, align: 'left' });
    lines.push({ text: '本次用时: ' + seconds + '秒', x: 30, y: 120, size: 12, align: 'left' });
    lines.push({ text: '已玩游戏: ' + played, x: 30, y: 148, size: 12, align: 'left' });
    lines.push({ text: '已胜游戏: ' + won, x: 30, y: 176, size: 12, align: 'left' });
    lines.push({ text: '百分比: ' + percent + '%', x: 30, y: 204, size: 12, align: 'left' });
    return {
      title: '最佳成绩',
      width: 380,
      height: 290,
      lines: lines,
      buttons: [
        { id: 'close', label: '确定', x: 140, y: 238, w: 100, h: 26 }
      ]
    };
  }

  /**
   * 「关于扫雷」对话框（菜单 帮助 → 关于扫雷）
   */
  static aboutSpec(): DlgSpec {
    return {
      title: '关于扫雷',
      width: 360,
      height: 250,
      lines: [
        { text: '扫雷', x: 180, y: 44, size: 16, align: 'center' },
        { text: 'Windows 7 扫雷的 HarmonyOS 移植版', x: 180, y: 86, size: 12, align: 'center' },
        { text: '单指点击开格，长按插旗，双击和弦，', x: 180, y: 116, size: 12, align: 'center' },
        { text: '双指捏合缩放，单指拖动平移', x: 180, y: 138, size: 12, align: 'center' }
      ],
      buttons: [
        { id: 'close', label: '确定', x: 130, y: 196, w: 100, h: 26 }
      ]
    };
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
    const w = spec.width * sVp;
    const h = spec.height * sVp;

    // 窗口阴影
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.fillRect(oxVp + 3 * sVp, oyVp + 3 * sVp, w, h);

    // 标题栏（Aero 玻璃：上浅下深的渐变）
    const grad = ctx.createLinearGradient(oxVp, oyVp, oxVp, oyVp + 20 * sVp);
    grad.addColorStop(0, C_TITLE_TOP);
    grad.addColorStop(1, C_TITLE_BOTTOM);
    ctx.fillStyle = grad;
    ctx.fillRect(oxVp, oyVp, w, 20 * sVp);

    // 客户区
    ctx.fillStyle = C_CLIENT;
    ctx.fillRect(oxVp, oyVp + 20 * sVp, w, h - 20 * sVp);

    // 窗口外框
    ctx.strokeStyle = C_BORDER;
    ctx.lineWidth = Math.max(1, sVp);
    ctx.strokeRect(oxVp, oyVp, w, h);

    // 标题文字
    ctx.fillStyle = '#2b2b2b';
    ctx.font = `bold ${12 * sDev}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(spec.title, oxVp + 6 * sVp, oyVp + 4 * sVp);

    // 右上角关闭按钮（红底白叉）
    const cbW = 18 * sVp;
    const cbH = 14 * sVp;
    const cbX = oxVp + w - cbW - 4 * sVp;
    const cbY = oyVp + 3 * sVp;
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

    // 文字
    for (const line of spec.lines) {
      if (line.text.length === 0) {
        continue;
      }
      ctx.fillStyle = line.color ?? C_TEXT;
      ctx.font = `${line.size * sDev}px sans-serif`;
      ctx.textBaseline = 'top';
      if (line.align === 'center') {
        ctx.textAlign = 'center';
        ctx.fillText(line.text, oxVp + line.x * sVp, oyVp + line.y * sVp);
      } else {
        ctx.textAlign = 'left';
        ctx.fillText(line.text, oxVp + line.x * sVp, oyVp + line.y * sVp);
      }
    }

    // 按钮
    for (const b of spec.buttons) {
      const bx = oxVp + b.x * sVp;
      const by = oyVp + b.y * sVp;
      const bw = b.w * sVp;
      const bh = b.h * sVp;
      const bg = ctx.createLinearGradient(bx, by, bx, by + bh);
      bg.addColorStop(0, C_BTN_TOP);
      bg.addColorStop(1, C_BTN_BOTTOM);
      ctx.fillStyle = bg;
      ctx.fillRect(bx, by, bw, bh);
      ctx.strokeStyle = C_BTN_BORDER;
      ctx.lineWidth = Math.max(1, sVp);
      ctx.strokeRect(bx, by, bw, bh);
      ctx.fillStyle = C_TEXT;
      ctx.font = `${12 * sDev}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(b.label, bx + bw / 2, by + bh / 2 + 1 * sVp);
    }
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /** 点到哪个按钮上（设备像素坐标）；没点到返回 null */
  static hitButton(spec: DlgSpec, scale: number, ox: number, oy: number, px: number, py: number): string | null {
    for (const b of spec.buttons) {
      const bx = ox + b.x * scale;
      const by = oy + b.y * scale;
      if (px >= bx && px <= bx + b.w * scale && py >= by && py <= by + b.h * scale) {
        return b.id;
      }
    }
    // 标题栏右上角的关闭按钮也要能点（它画出来了，就得能点）
    // （Codex 复审 P2）
    const cbW = 18 * scale;
    const cbH = 14 * scale;
    const cbX = ox + spec.width * scale - cbW - 4 * scale;
    const cbY = oy + 3 * scale;
    if (px >= cbX && px <= cbX + cbW && py >= cbY && py <= cbY + cbH) {
      return 'close';
    }
    return null;
  }
}
