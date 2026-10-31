/**
 * Theme.ets —— 渲染常量与精灵表坐标
 *
 * 坐标全部是「逻辑坐标」（原版 tile = 18 单位），素材按 2 倍存（36 像素），
 * 取像素时乘 SPRITE_SCALE。唯一事实源：linux-minesweeper/src/ui/Theme.h。
 *
 * 坐标表已于 2026-10-30 逐项裁图核对通过（见 docs/SPEC.md §5.1）。
 */

/** 原版逻辑格子边长 */
export const TILE: number = 18;
/** 最大缩放档位：n=8 时每格 288 设备像素（unit=16，仍是素材的整数倍放大） */
export const MAX_SCALE_INDEX: number = 8;

/** 素材相对逻辑坐标的倍数 */
export const SPRITE_SCALE: number = 2;

/** 最大棋盘（渐变帧按 30 列 × 24 行排布） */
export const GRAD_COLS: number = 30;
export const GRAD_ROWS: number = 24;

/** 砖块渐变每行帧数 */
export const GRAD_PER_ROW: number = 25;

// ---- blueSheet / greenSheet ------------------------------------------------

/** 砖块渐变第 frame 帧（普通态） */
export function normalTileRect(frame: number): number[] {
  const x = TILE * (frame % GRAD_PER_ROW);
  const y = TILE * Math.floor(frame / GRAD_PER_ROW);
  return [x, y, TILE, TILE];
}

/** 砖块渐变第 frame 帧（按下态） */
export function pressedTileRect(frame: number): number[] {
  const r = normalTileRect(frame);
  return [r[0] + 500, r[1], TILE, TILE];
}

/** 旗 */
export const RECT_FLAG: number[] = [400, 560, 18, 18];
/** 问号 */
export const RECT_QUESTION: number[] = [420, 560, 18, 18];
/** 悬停高亮（相加混合） */
export const RECT_HILITE: number[] = [440, 560, 18, 18];
/** 错旗红叉 */
export const RECT_MISFLAG: number[] = [460, 560, 18, 18];
/** 上方阴影条（18×3） */
export const RECT_SHADOW_U: number[] = [480, 560, 18, 3];
/** 左侧阴影条（3×18） */
export const RECT_SHADOW_L: number[] = [1012, 0, 3, 18];
/** 计数器凹槽面板 */
export const RECT_COUNTER: number[] = [0, 580, 40, 21];

/** 数字 1..8（字形槽 12×15，不是原 XML 的 10×13） */
export function digitRect(n: number): number[] {
  return [1000, 15 * (n - 1), 12, 15];
}

// ---- minesweeperSheet / flowerGardenSheet ---------------------------------

/** 格下地雷 */
export const RECT_MINE: number[] = [27, 0, 18, 18];
/** 面板雷图标（银色圆钮装地雷） */
export const RECT_PANEL_MINE: number[] = [0, 0, 25, 25];

// ---- otherSheet ------------------------------------------------------------

/** 时钟图标（银色圆钮装时钟） */
export const RECT_CLOCK: number[] = [905, 425, 25, 25];

/** 踩雷动画帧（雷），23 帧 / 1 秒 */
export const TRIP_FRAMES: number = 23;
export function tripRect(frame: number): number[] {
  return [728 + 59 * (frame % 3), 59 * Math.floor(frame / 3), 57, 57];
}
/** 踩雷动画绘制偏移 */
export const TRIP_OFFSET: number[] = [-18, -18];

/** 拆雷动画帧（胜利），38 帧 / 2 秒 */
export const DISARM_FRAMES: number = 38;
export function disarmRect(frame: number): number[] {
  return [52 * (frame % 7), 152 * Math.floor(frame / 7), 50, 150];
}
/** 拆雷动画绘制偏移 */
export const DISARM_OFFSET: number[] = [-18, -69];

/** 胜利扫描条 */
export const RECT_SCAN_BAR: number[] = [0, 912, 275, 62];

// ---- 棋盘底板 Frame.png ----------------------------------------------------

/** 底板原图尺寸（像素，1 倍） */
export const FRAME_W: number = 600;
export const FRAME_H: number = 351;
/** 九宫格拉伸边距（逻辑单位） */
export const FRAME_GAP_L: number = 30;
export const FRAME_GAP_T: number = 30;
export const FRAME_GAP_R: number = 29;
export const FRAME_GAP_B: number = 32;

// ---- helpBoard.png（原版帮助窗口插图） --------------------------------------

/**
 * 原版帮助窗口插图的源尺寸（**像素，1 倍**）。
 *
 * 坑（最容易踩的一个）：helpBoard.png 是 **1:1** 的图，不像 blueSheet 那样按 2 倍存，
 * 所以取它的源坐标时**不能乘 SPRITE_SCALE**，否则会从图里裁到错的地方
 * （×2 会直接裁到图外，画出空白）。
 *
 * 这张图是微软自己的插图：一局进行中的 Win7 扫雷画面，底部带 [时钟][18] … [-40][雷] 状态条。
 */
export const HELP_BOARD_W: number = 256;
export const HELP_BOARD_H: number = 192;


/**
 * 砖块渐变帧映射：原版不是所有格子同一个蓝色，而是 720 帧（30×24）从左上到右下
 * 由亮到暗的渐变，每格取自己那一帧。小棋盘取「居中窗口」而不是拉伸整个渐变，
 * 否则初级局会显得过亮或过暗。
 */
export function gradientFrame(row: number, col: number, rows: number, cols: number): number {
  const r = Math.min(GRAD_ROWS - 1, row + Math.max(0, Math.floor((GRAD_ROWS - rows) / 2)));
  const c = Math.min(GRAD_COLS - 1, col + Math.max(0, Math.floor((GRAD_COLS - cols) / 2)));
  return r * GRAD_COLS + c;
}

// ---- 配色（实测自原版窗口底图 Frame.png） ---------------------------------

/** 窗口外圈（原来那圈淡蓝玻璃边框，手机版只留底色） */
export const COLOR_OUTSIDE: string = '#c6cede';
/** 棋盘区地板：纯白 */
export const COLOR_FLOOR: string = '#ffffff';
/** 棋盘区四边的凹槽线（实测约 rgb(76,85,111)） */
export const COLOR_SUNKEN: string = '#4c556f';

// ---- 底部状态条 -----------------------------------------------------------

/** 状态条离棋盘下沿的高度（原版是窗口下边框，32 单位高） */
export const STRIP_BAND: number = 32;

/**
 * 最小可点格边（设备像素）。
 *
 * 48 px 是经典的最小点按目标尺寸。窄屏上 30 列的局装得下时只有 36 px（≈10~13 vp），
 * 手指根本点不准；这时宁可让棋盘横向超宽（可单指平移），也不要给一个点不中的棋盘。
 * 用户的要求原话是「外屏不接受降级，我希望可以拖动放大」。
 */
export const MIN_CELL_PX: number = 48;

/** 时钟图标 25×25 */
export const STRIP_CLOCK_SIZE: number = 25;
/** 计数面板 40×21（实测原版 40×22，取素材里的 40×21） */
export const STRIP_PANEL_W: number = 40;
export const STRIP_PANEL_H: number = 21;
/** 图标与面板之间的空隙 */
export const STRIP_GAP: number = 6;

// ---- 外观（Appearance）：棋盘样式 / 游戏样式 ---------------------------------

/**
 * 棋盘样式：蓝色（Silver and Blue）/ 绿色（Green）。
 *
 * 证据：原版 Win7 的「外观」对话框有两组单选图示 —— Select Game Style
 * （Minesweeper / Flower Garden）与 Select Board（Silver and Blue / Green），
 * 见 linux-minesweeper/src/ui/AppearanceDialog.cpp:151-164。
 * 素材：greenSheet.png 与 blueSheet.png 同为 2034×1206，**逐区域同构**
 * （数字/旗/问号/高亮/红叉/阴影逐字节相同），唯一差异是胜利拆雷动画的基址。
 */
export enum BoardStyle {
  Blue = 0,
  Green = 1
}

/**
 * 游戏样式：扫雷（Minesweeper）/ 花园（Flower Garden）。
 *
 * 对应 minesweeperSheet.png（地雷）与 flowerGardenSheet.png（花朵）。
 */
export enum GameStyle {
  Mines = 0,
  Flowers = 1
}

/**
 * 胜利「拆雷」动画的基址（逻辑 x）。
 *
 * otherSheet.png 里并排放着两套拆雷动画：蓝色从逻辑 x=0 起，绿色从 x=364 起
 * （7 帧 × (50+2) = 364）。证据：linux-minesweeper/src/ui/Theme.h:146-151
 * `disarmFrame(BoardStyle s, int frame)` 里的 `x0 = Green ? 364 : 0`。
 */
export const DISARM_BASE_BLUE: number = 0;
export const DISARM_BASE_GREEN: number = 364;

/**
 * 按棋盘样式取拆雷动画的源矩形（逻辑坐标）。
 *
 * 蓝色版就是 Anim.disarmRect 的结果（基址 0），绿色版整体右移 364。
 */
export function disarmRectFor(frame: number, style: BoardStyle): number[] {
  const f = Math.max(0, Math.min(37, frame));
  const x0 = style === BoardStyle.Green ? DISARM_BASE_GREEN : DISARM_BASE_BLUE;
  return [x0 + 52 * (f % 7), 152 * Math.floor(f / 7), 50, 150];
}

/**
 * 花园版的踩雷（开花）动画帧（otherSheet 逻辑坐标）。
 *
 * 花园帧在 otherSheet 的逻辑 x=905 起，每帧 36×36（雷版在 x=728，每帧 57×57）。
 * 证据：linux-minesweeper/src/ui/Theme.h:126-131 `tripFrame(GameStyle g, int frame)`。
 */
export function flowerTripRect(frame: number): number[] {
  const f = Math.max(0, Math.min(22, frame));
  return [905 + 38 * (f % 3), 38 * Math.floor(f / 3), 36, 36];
}

/** 花园版踩雷动画的绘制偏移 */
export const FLOWER_TRIP_OFFSET: number[] = [-9, -9];

/**
 * 状态条两组元素离棋盘左右沿的距离。
 *
 * 从 Win7 复刻截图反推：30 列盘时左右各留 45 单位，组内顺序是
 * [时钟][计时面板] …… [雷数面板][雷图标]（中间大片留空），
 * 计时在左、雷数在右。这与原版窗口的排布一致。
 *
 * 距离随棋盘宽度缩放（公式来自复刻实现，30 列时正好 45 单位），
 * 窄棋盘上会收到 0，保证两组不互相压。
 */
export function stripMargin(cols: number): number {
  return Math.max(0, Math.round((cols - 12.5) * TILE / 7));
}
