/**
 * NumKeypad.ets —— 画在画布上的数字键盘
 *
 * 「自定义」对话框要填高度/宽度/雷数，手机上不能靠系统输入法（画布上的输入框
 * 拿不到软键盘输入），所以在对话框旁边画一个数字键盘，用手指点。
 *
 * 排布（Win7 风格，按钮浅灰渐变 + 1px 灰边）：
 *     1 2 3
 *     4 5 6
 *     7 8 9
 *     ⌫ 0
 *
 * 单位：几何用 vp，字号用设备像素（见 SPEC §5.7）。
 */

/** 按键排布：'1'..'9'、'0'、'del' */
const KEYS: string[] = [
  '1', '2', '3',
  '4', '5', '6',
  '7', '8', '9',
  'del', '0'
];

/** 键宽 / 键高 / 间距（参考像素） */
const KEY_W: number = 34;
const KEY_H: number = 30;
const GAP: number = 4;

const C_BTN_TOP: string = '#f7f7f7';
const C_BTN_BOTTOM: string = '#e2e2e2';
const C_BTN_BORDER: string = '#707070';
const C_TEXT: string = '#000000';

export class NumKeypad {
  /** 键盘整体宽度（参考像素） */
  static width(): number {
    return 3 * KEY_W + 2 * GAP;
  }

  /** 键盘整体高度（参考像素） */
  static height(): number {
    return 4 * KEY_H + 3 * GAP;
  }

  /** 画键盘 */
  static draw(ctx: CanvasRenderingContext2D, sDev: number, sVp: number, oxVp: number, oyVp: number): void {
    for (let i = 0; i < KEYS.length; i++) {
      const col = i % 3;
      const row = Math.floor(i / 3);
      const x = oxVp + col * (KEY_W + GAP) * sVp;
      const y = oyVp + row * (KEY_H + GAP) * sVp;
      const w = KEY_W * sVp;
      const h = KEY_H * sVp;
      const g = ctx.createLinearGradient(x, y, x, y + h);
      g.addColorStop(0, C_BTN_TOP);
      g.addColorStop(1, C_BTN_BOTTOM);
      ctx.fillStyle = g;
      ctx.fillRect(x, y, w, h);
      ctx.strokeStyle = C_BTN_BORDER;
      ctx.lineWidth = Math.max(1, sVp);
      ctx.strokeRect(x, y, w, h);
      ctx.fillStyle = C_TEXT;
      ctx.font = `${16 * sDev}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const label = KEYS[i] === 'del' ? '⌫' : KEYS[i];
      ctx.fillText(label, x + w / 2, y + h / 2 + 1 * sVp);
    }
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
  }

  /** 命中测试：返回按键标识（'0'..'9' / 'del'），没点到返回空串 */
  static hit(sVp: number, oxVp: number, oyVp: number, pxVp: number, pyVp: number): string {
    for (let i = 0; i < KEYS.length; i++) {
      const col = i % 3;
      const row = Math.floor(i / 3);
      const x = oxVp + col * (KEY_W + GAP) * sVp;
      const y = oyVp + row * (KEY_H + GAP) * sVp;
      const w = KEY_W * sVp;
      const h = KEY_H * sVp;
      if (pxVp >= x && pxVp <= x + w && pyVp >= y && pyVp <= y + h) {
        return KEYS[i];
      }
    }
    return '';
  }
}
