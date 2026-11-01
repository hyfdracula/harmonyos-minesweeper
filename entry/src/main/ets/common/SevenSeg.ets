/**
 * SevenSeg.ets —— 状态条计数器的七段数码管渲染
 *
 * 原版 Win7 扫雷的两个计数器（计时 / 剩余雷数）是**深蓝凹槽 + 七段数码管**，
 * 不是普通字体。权威证据：微软自己的帮助窗口插图 `helpBoard.png`，
 * 其状态条里左边的「18」是七段、右边的「-40」带**独立负号段**。
 *
 * ## 几何是怎么定的（详见 docs\SEVEN-SEG-COUNTER.md）
 *
 * - **槽位布局（高置信，来自 XP 版扫雷的二进制逆向重建）**
 *   `ReversingMinesweeper-master\Minesweeper\drawing.c`：
 *     `#define NUMBER_WIDTH 13` / `NUMBER_HEIGHT 23` / `NUMBER_Y 16`
 *     `#define POINT_BIG_NUM_X 17` / `POINT_MID_NUM_X 30` / `POINT_LOW_NUM_X 43`
 *     `#define NUM_MINUS 11`
 *   即：**3 个槽位、槽距 13 像素、负号是同一张位图里的第 11 个字形**。
 *   本项目的凹槽面板 `Theme.RECT_COUNTER = [0,580,40,21]` 正好也是 **40 宽**，
 *   与 XP 版的面板（left=16, right=56）**同宽**，
 *   于是槽位自然落在面板内 x = 1 / 14 / 27，每槽 13 宽（1+13*3 = 40，正好填满）。
 *
 * - **右对齐（高置信）**
 *   `helpBoard.png` 左边的计时显示「18」：若按 XP 那样的**补零**三位显示，
 *   左边那个槽会亮着一个「0」。实测该槽**一个亮点都没有** → 原版是**右对齐、不补零**。
 *   右边的「-40」则正好占满三槽（负号在最左槽）。
 *
 * - **段的形状与比例（从 helpBoard.png 反推）**
 *   该插图里「8」可以分解成正好 7 根独立的段（a/b/c/d/e/f/g），
 *   逐像素量得（在插图的尺度下）：格子 5 宽 × 7 高，竖段 1 像素、横段 1 像素，
 *   半高竖段 2 像素，横段横跨两根竖段之间。
 *   把这组比例套进本项目的 13 宽 × 21 高的槽位：
 *     竖段粗 tv = 3、横段粗 th = 3、半高竖段 hl = 6
 *     （校验：3*th + 2*hl = 3*3 + 2*6 = 21 = 槽高）
 *     横段长度 = 13 - 2*tv = 7
 *
 * - **亮段颜色**：从 helpBoard.png 的段芯像素量得，RGB ≈ (250,250,252)。
 *   **灭的段不画** —— 原版凹槽里看不到暗段。
 *
 * ## 坐标系
 * - `xVp, yVp`：**凹槽面板左上角在 vp（Canvas 单位）里的位置**。
 * - `sVp`：**一个参考像素等于多少 vp**。
 * - `sDev`：**一个参考像素等于多少设备像素**（本例只用来把段边对齐到设备像素）。
 *
 * 调用方必须保证 `xVp / (sVp/sDev)` 是整数设备像素（否则段的边会落在半个像素上，
 * 看起来发虚）。面板是用整数设备像素画的，所以只要把面板原点按设备像素算好传进来即可。
 *
 * 所有几何都以**参考像素**表达，最后乘缩放系数落到 vp 上。
 */

/** 段位掩码：a 上、b 右上、c 右下、d 下、e 左下、f 左上、g 中 */
const SEG_A: number = 1;
const SEG_B: number = 2;
const SEG_C: number = 4;
const SEG_D: number = 8;
const SEG_E: number = 16;
const SEG_F: number = 32;
const SEG_G: number = 64;

/**
 * 0..9 的段组合（**标准七段编码**，位序 a,b,c,d,e,f,g）。
 *
 * 2026-11-02 定案：液晶屏就那七根杠，数字 = 这七根杠的组合，
 * **不给任何数字加额外装饰**（用户原话：「一个液晶屏就 7 个地方能显示，
 * 规定好七个杠杠必须一起显示就行了」）。
 *
 * 「1」就是标准的 **b + c 两根小竖杠**（中间有缝，和计算器液晶屏一样），
 * 不连成一根、不加旗、不加衬线 —— 之前两种画法（连成一根、
 * 连成一根再加旗和衬线）都被否掉了。
 */
const DIGIT_MASKS: number[] = [
  0x3F, // 0: a b c d e f
  0x06, // 1: b c（两根小竖杠，中间有缝）
  0x5B, // 2: a b g e d
  0x4F, // 3: a b g c d
  0x66, // 4: f g b c
  0x6D, // 5: a f g c d
  0x7D, // 6: a f g e c d
  0x07, // 7: a b c
  0x7F, // 8: 全部
  0x6F  // 9: a b c d f g
];

/** 负号：只亮中段 g（与 helpBoard 里「-40」的横杠位置一致） */
const MASK_MINUS: number = SEG_G;

export class SevenSeg {
  /** 凹槽面板的参考像素尺寸（与 Theme.RECT_COUNTER 的逻辑尺寸一致） */
  static readonly PANEL_W: number = 40;
  static readonly PANEL_H: number = 21;

  /** 槽位数（原版三位：百位/十位/个位，负号占最左槽） */
  static readonly SLOT_COUNT: number = 3;
  /** 槽距（参考像素）。原来照抄 XP 版 drawing.c 的 NUMBER_WIDTH = 13，
   *  但那是 40 宽面板且没有斜角的时代；本项目的面板内区只有 33 宽，
   *  13 的槽距会让三格溢出 → 改成 12（2026-11-02 真机实测）。 */
  static readonly SLOT_PITCH: number = 12;
  /**
   * 槽位起点。
   *
   * 2026-11-02 真机实测修正：把面板精灵（RECT_COUNTER）放大 8 倍看，
   * **绿色内区只占 3..36 个参考单位（33 宽）**，而原来的三格占 0..38（38 宽）——
   * 最后一位的右竖笔正好压在面板右缘的斜角高光上，看起来像「数字被面板切掉一截」。
   * 真机截图实测：面板蓝底到 x=1672，数字白到 x=1675，压边 3 px（su=8 时 ≈1 个单位）。
   * 现在起点移到 3、槽距 12、格宽 10 → 三格占 3..13 / 15..25 / 27..37，
   * 完全落在内区里，右缘留 1 个单位空。
   */
  static readonly SLOT_X0: number = 3;
  /**
   * 2026-11-02 真机实拍对比修正：**原来的数字太大太粗**。
   *
   * 面板（RECT_COUNTER）是 40×21。原版帮助图 helpBoard.png 的状态条里，
   * 数字只占面板高度的 4~5 成，笔画约为格宽的 20%；
   * 而原来是 16/21 = 76% 高、笔画 3/12 = 25% 宽 —— 数字几乎撑满面板，
   * 视觉上「又大又粗、挤在面板里」。
   *
   * 现在：格 9×12（占面板高度 57%），笔画 2，纵向居中（(21-12)/2 取 4）。
   */
  static readonly CELL_W: number = 9;
  static readonly CELL_H: number = 11;
  /** 数字格在面板内的 y 偏移（(21 - 11) / 2 = 5） */
  static readonly CELL_Y: number = 5;

  /**
   * 竖段粗细（参考像素）。
   *
   * 2026-11-02 与 Win7 原版 helpBoard.png 的「18」逐像素对照后改成 **1**：
   * 原版数字的笔画只有面板宽度的 1/31 ≈ 1 个参考单位（14 倍放大看是单像素线），
   * 我们用 2 个单位（占格宽 22%）画出来是厚重的方块，「1」上那面小旗和竖笔
   * 还会连成一坨，玩家看起来像「0 的右半边」。
   */
  static readonly TV: number = 1;
  /** 横段粗细（参考像素），同样取 1（原版是细线） */
  static readonly TH: number = 1;
  /** 半高竖段长度（参考像素），3*TH + 2*HL = CELL_H  →  3*1 + 2*4 = 11 */
  static readonly HL: number = 4;

  /** 显示下限：三位放不下更小的负数，钳到 -99（最多插 99 面旗的真实极值） */
  static readonly MIN_VALUE: number = -99;
  /** 显示上限：三位最多 999 */
  static readonly MAX_VALUE: number = 999;

  /** 亮段颜色：从 helpBoard.png 段芯像素量得 (250,250,252) */
  static readonly COLOR_LIT: string = '#FAFAFC';

  /**
   * 把一个整数画成七段数码管（负数带独立负号段）。
   *
   * @param ctx   Canvas 上下文
   * @param value 要显示的整数（可负；小数会被截断）
   * @param xVp   凹槽面板左上角的 vp 坐标
   * @param yVp   凹槽面板左上角的 vp 坐标
   * @param sVp   一个参考像素等于多少 vp
   * @param sDev  一个参考像素等于多少设备像素
   */
  static draw(ctx: CanvasRenderingContext2D, value: number, xVp: number, yVp: number,
    sVp: number, sDev: number): void {
    if (sVp <= 0 || sDev <= 0) {
      return;
    }
    const pxScale: number = sDev > 0 ? sVp / sDev : 1;   // vp / 设备像素
    // 面板原点换算到设备像素并取整，保证段的边落在整数设备像素上
    const devX0: number = Math.round(xVp / pxScale);
    const devY0: number = Math.round(yVp / pxScale);

    ctx.fillStyle = SevenSeg.COLOR_LIT;

    const slots: number[] = SevenSeg.slotsFor(value);
    for (let i = 0; i < slots.length; i++) {
      const mask: number = slots[i];
      if (mask === 0) {
        continue;
      }
      const cellX: number = SevenSeg.SLOT_X0 + i * SevenSeg.SLOT_PITCH;
      const cellY: number = SevenSeg.CELL_Y;
      // 段位是固定的 7 个，用显式判断而不是查表，省一次索引
      if ((mask & SEG_A) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX + SevenSeg.TV, cellY,
          SevenSeg.CELL_W - 2 * SevenSeg.TV, SevenSeg.TH, sDev, pxScale);
      }
      if ((mask & SEG_B) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX + SevenSeg.CELL_W - SevenSeg.TV, cellY + SevenSeg.TH,
          SevenSeg.TV, SevenSeg.HL, sDev, pxScale);
      }
      if ((mask & SEG_C) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX + SevenSeg.CELL_W - SevenSeg.TV,
          cellY + SevenSeg.TH + SevenSeg.HL + SevenSeg.TH, SevenSeg.TV, SevenSeg.HL, sDev, pxScale);
      }
      if ((mask & SEG_D) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX + SevenSeg.TV,
          cellY + SevenSeg.CELL_H - SevenSeg.TH, SevenSeg.CELL_W - 2 * SevenSeg.TV, SevenSeg.TH, sDev, pxScale);
      }
      if ((mask & SEG_E) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX, cellY + SevenSeg.TH + SevenSeg.HL + SevenSeg.TH,
          SevenSeg.TV, SevenSeg.HL, sDev, pxScale);
      }
      if ((mask & SEG_F) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX, cellY + SevenSeg.TH, SevenSeg.TV, SevenSeg.HL, sDev, pxScale);
      }
      if ((mask & SEG_G) !== 0) {
        SevenSeg.rect(ctx, devX0, devY0, cellX + SevenSeg.TV,
          cellY + SevenSeg.TH + SevenSeg.HL, SevenSeg.CELL_W - 2 * SevenSeg.TV, SevenSeg.TH, sDev, pxScale);
      }
    }
  }

  /**
   * 把整数拆成「槽位掩码」数组，长度 ≤ 3。
   *
   * 规则（依据 helpBoard.png）：
   * - 绝对值的十进制数字**右对齐**放进 3 个槽（不补零，「18」就占右两槽）；
   * - 负数时，负号占**紧挨着数字左边的那一槽**（「-40」= [负号][4][0]）；
   * - 三位装不下的值**钳到区间端点**：上界 999（计时器上限），
   *   下界 -99（最多插 99 面旗的真实极值）。
   *   不能只丢高位显示 -381 的低三位，那会显示成一个错的数。
   */
  static slotsFor(value: number): number[] {
    const out: number[] = [0, 0, 0];
    if (!Number.isFinite(value)) {
      // NaN / Infinity：什么都不画（Infinity 会让下面的取模循环停不下来）
      return out;
    }
    let n: number = Math.trunc(value);
    if (n > SevenSeg.MAX_VALUE) {
      n = SevenSeg.MAX_VALUE;
    } else if (n < SevenSeg.MIN_VALUE) {
      n = SevenSeg.MIN_VALUE;
    }
    const negative: boolean = n < 0;
    if (negative) {
      n = -n;
    }
    const digits: number[] = [];
    if (n === 0) {
      digits.push(0);
    }
    while (n > 0) {
      digits.push(n % 10);
      n = Math.floor(n / 10);
    }
    // digits 是低位在前，反转成高位在前
    const text: number[] = [];
    for (let i = digits.length - 1; i >= 0; i--) {
      text.push(digits[i]);
    }
    let start: number = 0;
    let count: number = text.length;
    // 上面的钳位已经保证 |n| <= 99（负数）或 n <= 999（正数），
    // 所以这两个分支正常不会走到；留着当保险，改 MIN/MAX 时也不会画到槽外。
    if (negative && count >= SevenSeg.SLOT_COUNT) {
      count = SevenSeg.SLOT_COUNT - 1;
      start = text.length - count;
    } else if (count > SevenSeg.SLOT_COUNT) {
      start = text.length - SevenSeg.SLOT_COUNT;
      count = SevenSeg.SLOT_COUNT;
    }
    for (let i = 0; i < count; i++) {
      out[SevenSeg.SLOT_COUNT - count + i] = DIGIT_MASKS[text[start + i]];
    }
    if (negative) {
      const minusSlot: number = SevenSeg.SLOT_COUNT - count - 1;
      if (minusSlot >= 0) {
        out[minusSlot] = MASK_MINUS;
      } else {
        out[0] = MASK_MINUS;
      }
    }
    return out;
  }

  /**
   * 画一段（内部用）：参考像素坐标 → 设备像素 → vp。
   *
   * **每条边都取整到整数设备像素**（2026-11-01 用户反馈「秒数和雷数字体不太清楚」）。
   * 原因：段宽是 2~3 个参考像素，乘上缩放系数（unit）之后在**分数密度**的屏幕上
   * （折叠屏 2.75 / 3.5 倍密度）常常是小数，段的边落在半个像素上 →
   * 画布会做抗锯齿 → 数码管看起来发虚、发糊。
   *
   * 取整的是**边**不是宽：相邻两段共用一条边，两边各自取整会得到同一个值，
   * 所以接缝仍然是严丝合缝的（不会多出绿缝，也不会叠出白块）。
   */
  static rect(ctx: CanvasRenderingContext2D, devX0: number, devY0: number,
    refX: number, refY: number, refW: number, refH: number, sDev: number, pxScale: number): void {
    const x0: number = Math.round(devX0 + refX * sDev);
    const y0: number = Math.round(devY0 + refY * sDev);
    const x1: number = Math.round(devX0 + (refX + refW) * sDev);
    const y1: number = Math.round(devY0 + (refY + refH) * sDev);
    ctx.fillRect(x0 * pxScale, y0 * pxScale, (x1 - x0) * pxScale, (y1 - y0) * pxScale);
  }
}
