/**
 * GameController.ets —— 棋盘渲染与交互状态
 *
 * 坐标系：**设备像素**。unit = 每个逻辑单位的设备像素数 = 2 × 缩放档位 n。
 * 取 n 为整数 → 素材一格（36 存储像素）被整数倍放大，最近邻不会糊。
 *
 * 布局（2026-10-30 实测修订，见 docs/SPEC.md §5.4–§5.6）：
 *   棋盘区 = 白色地板 + 左/右/下三边 1px 凹槽线（原版的玻璃窗口边框不上手机）
 *   翻开的格子 = 该格的「按下态」浅灰砖块 + 凸起邻居投下来的黑边
 *   底部状态条 = [时钟][计时面板] …… [雷数面板][雷图标]，两端展开
 *   两组离棋盘左右沿的距离 margin = max(0, (cols - 12.5) × 18 / 7)
 */

import { MinesweeperEngine, Mark, GameState } from './MinesweeperEngine';
import { SpriteAtlas } from './SpriteAtlas';
import { WinDialogPainter, DlgSpec } from './WinDialog';
import { GameStats } from './GameStats';
import { SoundPlayer, Sound } from './SoundPlayer';
import { WinMenuPainter, MenuSpec, MENU_BAR_H, appearanceEntry } from './WinMenu';
import { Appearance } from './Appearance';
import { SevenSeg } from './SevenSeg';
import { CustomField, CustomSpec, DLG_W, DLG_H } from './CustomField';
import { NumKeypad } from './NumKeypad';
import { Anim, Boom } from './Anim';
import { Ripple, RippleStep } from './Ripple';
import { StatsWindowPainter, StatsData, StatsLevel } from './StatsWindow';
import { DealIn } from './DealIn';
import {
  TILE, MAX_SCALE_INDEX, MIN_CELL_PX, FRAME_GAP_L, FRAME_GAP_T, FRAME_GAP_R, FRAME_GAP_B,
  gradientFrame, normalTileRect, pressedTileRect, RECT_FLAG, RECT_QUESTION, RECT_HILITE, RECT_MISFLAG,
  RECT_SHADOW_U, RECT_SHADOW_L, RECT_COUNTER, digitRect, RECT_MINE, RECT_PANEL_MINE, RECT_CLOCK,
  COLOR_OUTSIDE, COLOR_FLOOR, COLOR_SUNKEN,
  STRIP_BAND, STRIP_CLOCK_SIZE, STRIP_PANEL_W, STRIP_PANEL_H, STRIP_GAP, stripMargin,
  disarmRectFor, GameStyle, flowerTripRect, FLOWER_TRIP_OFFSET, BoardStyle
} from './Theme';

/** 难度档位（与原版一致） */
export enum Difficulty {
  Beginner = 0,       // 初级 9×9，10 雷
  Intermediate = 1,   // 中级 16×16，40 雷
  Expert = 2          // 高级 16 行 × 30 列，99 雷
}

/** 一档难度的盘面参数 */
export interface DifficultyConfig {
  rows: number;
  cols: number;
  mines: number;
  name: string;
}

/** 临时标定开关：true 时只画标定图，用来测 Canvas 的坐标单位 */
const CALIBRATE: boolean = false;

export class GameController {
  engine: MinesweeperEngine = new MinesweeperEngine();
  atlas: SpriteAtlas = new SpriteAtlas();
  context: CanvasRenderingContext2D | null = null;

  /** 画布尺寸（设备像素） */
  canvasW: number = 0;
  canvasH: number = 0;

  /** 每个逻辑单位的设备像素数 = 2 × 缩放档位 */
  unit: number = 2;

  /**
   * 设备像素 → Canvas 坐标（vp）的换算系数 = 1 / densityPixels。
   * Canvas 的坐标系单位是 vp，本工程内部按设备像素算，绘制时统一换算。
   */
  private pxScale: number = 1;

  /** 窗口（底板）矩形，设备像素 */
  frameX: number = 0;
  frameY: number = 0;
  frameW: number = 0;
  frameH: number = 0;
  /** 棋盘矩形，设备像素 */
  boardX: number = 0;
  boardY: number = 0;
  tile: number = 36;
  /** 状态条带的顶边，设备像素。竖向溢出时**钉在画布底边**（HUD），否则贴在棋盘下沿 */
  stripTop: number = 0;
  /** 棋盘能用的纵向高度（菜单栏下沿 ~ 状态条上沿），设备像素 */
  boardAreaH: number = 0;
  /** 状态条是否钉在画布底边（HUD 模式）——这时它盖住棋盘下沿，点击不能落到棋盘上 */
  hudActive: boolean = false;

  /** 计时（秒） */
  seconds: number = 0;
  timerHandle: number = -1;

  /** 悬停格（鼠标用，触屏暂用按下态） */
  hoverIndex: number = -1;

  /** 当前难度 */
  difficulty: Difficulty = Difficulty.Beginner;

  // ---------------------------------------------------------------- 缩放 / 平移

  /** 缩放档位 n：每格边长 = TILE * (2n)，n=1 时 36 设备像素，n=8 时 288 */
  scaleIndex: number = 3;
  /** 「整盘刚好放下」所需的档位（随画布尺寸变化） */
  fitScaleIndex: number = 3;
  /** 用户是否手动缩放过：没缩放过就始终用 fit 档 */
  userZoomed: boolean = false;
  /** 棋盘平移量（设备像素） */
  panX: number = 0;
  panY: number = 0;

  /** 菜单打开时为 true：棋盘不吃触摸，避免菜单与棋盘抢点击 */
  /**
   * 有对话框/统计窗口开着时，棋盘不接受拖动与缩放。
   *
   * （原来这是一个没人写的字段，等于没锁；改成派生属性后，
   *   结束对话框、自定义对话框、统计窗口开着时拖动棋盘都不会误触。）
   */
  get inputLocked(): boolean {
    return this.dialog !== null || this.customSpec !== null || this.statsOpen;
  }
  /** 结束对话框（原版 Win7 风格）；null 表示没开 */
  dialog: DlgSpec | null = null;
  private dialogScale: number = 1;
  private dialogOx: number = 0;
  private dialogOy: number = 0;

  /** 当前展开的顶层菜单（'' = 全关） */
  menuOpenId: string = '';
  /** 菜单栏的菜单规格（随当前难度打勾而变） */
  private menuSpec: MenuSpec = { tops: [] };
  /** 「自定义」对话框（null = 没开） */
  customSpec: CustomSpec | null = null;
  private customOx: number = 0;
  private customOy: number = 0;
  /** 是否允许插问号（原版「游戏 → 标记(?)」开关） */
  questionMarks: boolean = true;
  /** 当前这局是不是「自定义」难度（自定义局不进统计） */
  customGame: boolean = false;
  /** 终局回调（页面用它弹结果面板） */
  onGameOver: ((won: boolean) => void) | null = null;
  /** 结束对话框按钮被点：'again' | 'menu' | 'exit' */
  onDialogAction: ((action: string) => void) | null = null;
  private gameOverNotified: boolean = false;

  /** 各难度的盘面参数 */
  static configOf(d: Difficulty): DifficultyConfig {
    if (d === Difficulty.Intermediate) {
      return { rows: 16, cols: 16, mines: 40, name: '中级' };
    }
    if (d === Difficulty.Expert) {
      return { rows: 16, cols: 30, mines: 99, name: '高级' };
    }
    return { rows: 9, cols: 9, mines: 10, name: '初级' };
  }

  /** 换难度并开新局 */
  setDifficulty(d: Difficulty): void {
    this.difficulty = d;
    this.customGame = false;
    const cfg = GameController.configOf(d);
    this.startNewGame(cfg.rows, cfg.cols, cfg.mines);
  }

  /**
   * 同盘面重开。
   *
   * 坑（2026-10-31，custom-agent 审计 P1）：原来这里用 `configOf(this.difficulty)`，
   * 于是**自定义局的「新建(F2)」和「再玩一局(P)」会把 20×20×50 的盘面换成 9×9 初级盘**。
   * 原版语义是「重新开始这个游戏」——用的是当前盘面的参数，不是难度预设。
   * 现在直接取引擎当前的行列与雷数。
   *
   * `customGame` 标记**保留**：重开后的这一局仍然是自定义局，仍然不进统计
   * （Win7 的规则就是自定义局不计入获胜率）。
   */
  restart(): void {
    const rows = this.engine.rowCount;
    const cols = this.engine.colCount;
    const mines = this.engine.mineCount;
    if (rows <= 0 || cols <= 0) {
      const cfg = GameController.configOf(this.difficulty);
      this.customGame = false;
      this.startNewGame(cfg.rows, cfg.cols, cfg.mines);
      return;
    }
    this.startNewGame(rows, cols, mines);
  }

  /**
   * 开新局。
   *
   * @param silent true = 不播开局音（应用刚启动时用：原版启动是静音的，
   *               只有玩家主动「新建/换难度/再玩一局」才有那一声）。
   */
  startNewGame(rows: number, cols: number, mines: number, silent: boolean = false): void {
    console.info('[GameController] 新局 ' + rows + 'x' + cols + ' 雷=' + mines);
    this.engine.reset(rows, cols, mines);
    this.seconds = 0;
    this.stopTimer();
    this.stopAnimTimer();
    // 换局要把上一局的动画状态全清掉：踩雷爆炸与胜利扫描条都要停，
    // 否则扫描条会盖在新棋盘上（Codex 复审 P2）。
    Anim.stopTrip();
    Anim.stopWin();
    this.stopRipple();
    // 还没播完的爆炸音也要撤（Codex 复审 P2：上一局的爆炸声会串到新局）
    this.stopBombTail();
    this.gameOverNotified = false;
    this.dialog = null;
    this.menuOpenId = '';
    this.buildMenu();
    // 新局回到「整盘刚好放下」的视角
    this.userZoomed = false;
    this.panX = 0;
    this.panY = 0;
    this.layout();
    this.draw();
    // 新局的发牌动画（方砖从四角一波波弹起）
    this.startDealIn();
    if (!silent) {
      SoundPlayer.play(Sound.GAME_START);
    }
  }

  /** 画布就绪 / 尺寸变化 */
  attach(ctx: CanvasRenderingContext2D, widthVp: number, heightVp: number, density: number): void {
    this.context = ctx;
    this.canvasW = Math.max(1, Math.round(widthVp * density));
    this.canvasH = Math.max(1, Math.round(heightVp * density));
    this.pxScale = 1 / density;
    this.atlas.pxScale = this.pxScale;
    this.layout();
    this.draw();
  }

  /**
   * 窗口级变化（折叠开合 / 内屏↔外屏切换）后重新布局。
   *
   * 由 EntryAbility.onWindowStageChange 调用。
   * 尺寸变化本身由 Canvas 的 onAreaChange → attach → layout() 负责，
   * 这里补的是「窗口级变化但尺寸还没变」的那一瞬，以及给审计留一条日志依据。
   *
   * 幂等：layout() 里「用户手动缩放过就保留档位」那条规则照旧生效，
   * 所以折叠换屏**不会把用户的缩放档重置回适配档** ✓
   * （用户原话：折叠换屏时不丢视角）。
   */
  onWindowStageChanged(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    this.layout();
    this.draw();
  }

  /**
   * 设备像素 → Canvas 坐标（vp）
   *
   * 坑（2026-10-31，LAYOUT-MATRIX 审计 P2-6）：这里原来直接 `px * pxScale`，
   * 于是**落在分数设备像素上**的矩形与文字会被抗锯齿糊掉（对话框的缩放是小数，
   * 按钮、文字全在半像素上）。像素级复刻要求边缘锐利，所以先取整再换算。
   */
  private v(px: number): number {
    return Math.round(px) * this.pxScale;
  }

  /** 按当前画布尺寸重算缩放档位与各矩形 */
  layout(): void {
    const e = this.engine;
    if (e.rowCount <= 0 || e.colCount <= 0 || this.canvasW <= 0) {
      return;
    }
    // 1) 算出「整盘刚好放下」的档位
    //
    // 坑（2026-10-31，LAYOUT-MATRIX 审计 P1-2/P1-3）：原来算的是「原版窗口底板
    // frame」的尺寸，也就是棋盘 + 四周 59×62 单位的玻璃边框留白。**手机版不画那个边框**
    // （drawBoardArea 只在棋盘矩形内填白地板），这 59/62 单位纯属白占缩放预算，
    // 把高级局在窄屏上压到 n=1（格边 10~13 vp，手指根本点不准）。
    // 现在只按**真正画出来的东西**算预算：
    //   横向 = 棋盘宽
    //   纵向 = 菜单栏 + 棋盘高 + 状态条带（状态条就住在棋盘正下方 32u 的带子里）
    const menuPx: number = this.menuBarPx();
    let fit = 1;
    for (let n = 1; n <= MAX_SCALE_INDEX; n++) {
      const u = 2 * n;
      const bw = e.colCount * TILE * u;
      const bh = e.rowCount * TILE * u + STRIP_BAND * u;
      if (bw <= this.canvasW && menuPx + bh <= this.canvasH) {
        fit = n;
      } else {
        break;
      }
    }
    // 「整块装得下」优先；但整块装得下的那一档**格边 < 48 px 时，宁可溢出也要够大**：
    // 抬到格边 ≥ 48 的那一档，允许棋盘纵向溢出（顶对齐 + 状态条钉画布底边当 HUD）。
    //
    // 为什么：用户原话「外屏不接受降级，我希望可以拖动放大」——**小到点不准比溢出更糟**。
    // 30 列的局在窄屏（外屏 1323 px / Mate 90 Pro 1280 px）上宽度是几何必然，
    // 装得下的那一档只有 n=1（格边 36 px ≈ 10~13 vp），手指根本点不准。
    //
    // 坑（2026-10-31，LEAD-CHANGE-AUDIT 的 L1）：不能无条件抬。
    // 抬档会让棋盘同时纵向溢出，而纵向居中会把棋盘顶部推到菜单栏底下——
    // 那几行既看不见也点不着（菜单栏的点击归菜单）。
    // 现在两件事一起兜住：① 纵向装不下时**顶对齐**菜单栏下沿；② 状态条**钉在画布底边**
    // （HUD），所以溢出时计时与雷数仍然看得见。
    //
    // 坑（2026-10-31，LAYOUT-MATRIX v3.0 §4.2 B）：「抬完纵向装得下才抬」这条旧前提
    // 会把 Pura X Max 典藏版内屏（2584×1824）的 24×30 自定义局卡在 n=1：
    // 格边 36 px = 13.09 vp，点不准；抬到 n=2（格边 72 px = 26 vp）会纵向超出 90 px。
    // 现在**一律抬到格边 ≥ 48 的那一档**，纵向溢出交给顶对齐 + HUD 处理。
    //
    // v4.0 规则（一句话）：「整块装得下」优先；但整块装得下的那一档格边 < 48 设备像素，
    // 就用更大的档位，**允许纵向溢出**（用户原话：小到点不准比溢出更糟）。
    // 数字与推导见 docs\LAYOUT-MATRIX.md §4.3（规格仓），断言见 tools\check_layout.py。
    if (TILE * 2 * fit < MIN_CELL_PX && fit < MAX_SCALE_INDEX) {
      // 最小可点档：格边 ≥ MIN_CELL_PX 的最小 n（48 / 36 = 1.33 → 2）
      const minTouchN: number = Math.ceil(MIN_CELL_PX / (TILE * 2));
      fit = Math.min(MAX_SCALE_INDEX, Math.max(fit + 1, minTouchN));
    }
    this.fitScaleIndex = fit;
    // 2) 用户没手动缩放过就用适配档；缩放过就保留用户的档位（折叠换屏时不丢视角）
    if (!this.userZoomed) {
      this.scaleIndex = fit;
      this.panX = 0;
      this.panY = 0;
    }
    this.applyGeometry();
    this.clampPan();
    this.applyGeometry();
    console.info('[GameController] 布局 画布=' + this.canvasW + 'x' + this.canvasH + 'px 密度换算=' +
      this.pxScale.toFixed(4) + ' 适配档n=' + fit + ' 当前档n=' + this.scaleIndex +
      ' unit=' + this.unit + ' 格边=' + this.tile + 'px 棋盘原点=(' + this.boardX + ',' + this.boardY +
      ') HUD=' + (this.hudActive ? 1 : 0) + ' 状态条上沿=' + this.stripTop + 'px' +
      // 盘面规格也打进日志：跑测器要断言「真的开出了 24×30 这一局」，
      // 而格边/原点是**随设备变**的（两个模拟器的画布尺寸不同），写死就会在别的设备上假失败。
      // 2026-11-01（Codex 复审 P2）加。
      ' 盘面=' + this.engine.rowCount + 'x' + this.engine.colCount +
      ' 雷=' + this.engine.mineCount +
      // 外观（棋盘色/玩法）也打进日志：跑测器要断言「点了缩略图**没有**生效」，
      // 而颜色框会把整块棋盘盖住 —— 靠像素比不出来（框盖住的地方比到的是框里的选中框），
      // 靠日志里的外观最准。2026-11-01 加。
      ' 外观=' + (this.atlas.boardStyle === BoardStyle.Green ? '绿' : '蓝') +
      '/' + (this.atlas.gameStyle === GameStyle.Flowers ? '花园' : '扫雷'));
  }

  /**
   * 根据当前档位与平移量重算各矩形（设备像素）
   *
   * 坑（2026-10-31，LAYOUT-MATRIX 审计 P1-2/P1-3）：原来 frame 是「棋盘 + 不可见的
   * 玻璃边框留白」，整块在画布上居中，于是留白白占地方、菜单栏也没进预算。
   * 现在 frame 就是**画出来的内容**（棋盘 + 状态条带）：
   *   - 横向：棋盘在画布里居中
   *   - 纵向：从菜单栏下沿往下，把「棋盘 + 状态条」这一组在剩余空间里居中
   */
  private applyGeometry(): void {
    const e = this.engine;
    const u = 2 * this.scaleIndex;
    this.unit = u;
    this.tile = TILE * u;
    const boardW = e.colCount * this.tile;
    const boardH = e.rowCount * this.tile;
    this.frameW = boardW;
    this.frameH = boardH + STRIP_BAND * u;
    this.frameX = Math.round((this.canvasW - this.frameW) / 2) + this.panX;
    const menuPx: number = this.menuBarPx();
    const availH: number = Math.max(1, this.canvasH - menuPx);
    const stripH: number = STRIP_BAND * u;
    // 状态条的位置：**竖向装得下就贴在棋盘下沿；装不下就钉在画布底边**（像 HUD）。
    //
    // 坑（2026-10-31，LAYOUT-MATRIX v3.0 §3）：状态条原来画在 boardBottom 之下，
    // 棋盘纵向溢出时整条状态条会掉到屏幕外——计时和雷数都看不见（和横向超宽时
    // 雷数计数器跑出屏幕是同一类问题）。钉到画布底边后，无论棋盘多大都看得见。
    const groupFits: boolean = menuPx + boardH + stripH <= this.canvasH;
    const hudTop: number = this.canvasH - stripH;
    // 棋盘能用的纵向空间：装得下就用「菜单栏下沿 ~ 画布底」；钉 HUD 时只到 HUD 顶
    this.boardAreaH = groupFits ? availH : Math.max(1, hudTop - menuPx);
    // 整组（棋盘 + 状态条）在剩余空间里居中；装不下就顶对齐菜单栏下沿
    //（居中会把顶部推到菜单栏底下，那几行既看不见也点不着）
    const frameYBase: number = groupFits
      ? menuPx + Math.round((availH - boardH - stripH) / 2)
      : menuPx;
    this.frameY = frameYBase + this.panY;
    this.boardX = this.frameX;
    this.boardY = this.frameY;
    this.stripTop = groupFits ? (this.boardY + boardH) : hudTop;
    this.hudActive = !groupFits;
  }

  /** 菜单栏高度（设备像素） */
  private menuBarPx(): number {
    return Math.round(MENU_BAR_H / this.pxScale);
  }

  /**
   * 平移量夹紧：棋盘不能被拖出画布；整盘放得下时不允许平移。
   *
   * 坑（Codex 复审 P1）：frame 比画布大时 baseX 为负，**不能**直接把平移量归零——
   * 那样高级局放大后就永远够不到边上的格子。正确做法是夹到 [-|baseX|, |baseX|]：
   * 板子比视口大时允许拖动，且两边都能拖到。
   */
  private clampPan(): void {
    const e = this.engine;
    // 坑（2026-10-31）：原来 limX/limY 用 |(画布-底板)/2|，**放得下的时候也允许拖**，
    // 于是初级局能把棋盘拖到偏出屏幕。现在改成：放得下就不许拖，放不下才给
    // (内容-可视)/2 的余量，保证两边都能拖到。
    const limX: number = this.frameW > this.canvasW ? (this.frameW - this.canvasW) / 2 : 0;
    // 纵向按**棋盘**与「菜单栏下沿 ~ 状态条上沿」这块可视区比：
    // 状态条钉在画布底边（HUD）时，可视区要减去状态条那条带子，
    // 否则最后一行会被 HUD 压住却还允许往下拖。
    //
    // 纵向是**单向**的：只能往上推（panY ≤ 0），推到棋盘下沿与 HUD 上沿齐平为止。
    // 对称范围（±溢出量/2）会让最后一行永远缺一截——棋盘只比可视区高 90 px 时，
    // 居中那个位置上下各露 45 px，最后一行被 HUD 吃掉 45 px，点不准。
    //
    // 这条就是 Codex 对抗性复审的 **P1**（「向上平移的上限只允许溢出量的一半 →
    // 底部格子平移到头仍被状态条压住，点不到」）：上限改成**整个溢出量**。
    // 处理记录见 docs\LAYOUT-MATRIX.md §4.3.4。
    const boardH: number = e.rowCount * this.tile;
    const overV: number = boardH > this.boardAreaH ? boardH - this.boardAreaH : 0;
    this.panX = Math.max(-limX, Math.min(limX, this.panX));
    this.panY = overV > 0 ? Math.max(-overV, Math.min(0, this.panY)) : 0;
  }

  /** 缩放到指定档位（1..MAX_SCALE_INDEX），以画布坐标 (fx,fy)（设备像素）为锚点 */
  zoomTo(n: number, fx: number, fy: number): void {
    const target = Math.max(1, Math.min(MAX_SCALE_INDEX, Math.round(n)));
    if (target === this.scaleIndex) {
      return;
    }
    const oldTile = this.tile;
    const oldBoardX = this.boardX;
    const oldBoardY = this.boardY;
    this.scaleIndex = target;
    this.userZoomed = true;
    this.applyGeometry();
    // 让锚点处的棋盘内容保持不动：boardX_new = fx - (fx - boardX_old) * (tile_new / tile_old)
    const k = this.tile / oldTile;
    const wantBoardX = fx - (fx - oldBoardX) * k;
    const wantBoardY = fy - (fy - oldBoardY) * k;
    this.panX += wantBoardX - this.boardX;
    this.panY += wantBoardY - this.boardY;
    this.clampPan();
    this.applyGeometry();
    this.draw();
    // 缩放档位打进日志：真机上双指捏合没法用 uitest 注入，只能靠这行确认
    // 「捏合真的生效了、捏到了第几档」。docs\REAL-DEVICE-CHECKLIST.md 的第 11 节就靠它。
    console.info('[Touch] 捏合 档位n=' + this.scaleIndex);
  }

  /** 按设备像素平移棋盘 */
  panBy(dx: number, dy: number): void {
    if (dx === 0 && dy === 0) {
      return;
    }
    this.panX += dx;
    this.panY += dy;
    this.clampPan();
    this.applyGeometry();
    this.draw();
  }

  /** 回到「整盘刚好放下」的视角 */
  resetView(): void {
    this.userZoomed = false;
    this.panX = 0;
    this.panY = 0;
    this.layout();
    this.draw();
  }

  /** 当前档位下，一格边长占画布的比例（捏合缩放用） */
  get tileRatio(): number {
    return this.tile / 36;
  }

  // ------------------------------------------------------------------ 绘制

  draw(): void {
    const ctx = this.context;
    if (ctx === null) {
      return;
    }
    try {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, this.v(this.canvasW), this.v(this.canvasH));
      if (CALIBRATE) {
        this.drawCalibration(ctx);
        return;
      }
      this.drawBoardArea(ctx);
      this.drawBoard(ctx);
      this.drawExplosions(ctx);
      this.drawScanBar(ctx);
      this.drawStatusStrip(ctx);
      this.drawMenu(ctx);
      this.drawCustom(ctx);
      this.drawDialog(ctx);
      this.drawStats(ctx);
    } catch (err) {
      console.error('[GameController] 绘制失败: ' + (err as Error).message);
    }
  }

  /**
   * 临时标定图（CALIBRATE=true 时启用）：
   * 红 = 100 单位、绿 = 275 单位、两者都按 vp 语义写在坐标里；
   * 若画布吃 vp，红块应是 275 设备像素、绿块 756；若吃 px，则红 100、绿 275。
   */
  private drawCalibration(ctx: CanvasRenderingContext2D): void {
    ctx.fillStyle = '#ff0000';
    ctx.fillRect(0, 0, 100, 100);
    ctx.fillStyle = '#00ff00';
    ctx.fillRect(200, 0, 275, 275);
    ctx.fillStyle = '#0000ff';
    ctx.fillRect(600, 0, 100, 100);
    // 同一个时钟图标分别画成 100 单位和 275 单位
    this.atlas.draw(ctx, this.atlas.otherSheet, RECT_CLOCK, 0, 300, 100, 100);
    this.atlas.draw(ctx, this.atlas.otherSheet, RECT_CLOCK, 200, 300, 275, 275);
  }

  /**
   * 棋盘区：白色地板 + 左/右/下三边的凹槽线。
   *
   * 原版这层是窗口底图（Frame.bmp）里的一块白色凹陷区域，手机上不画那圈
   * 玻璃边框，只保留地板和凹槽线——实测色值见 Theme.ets。
   */
  private drawBoardArea(ctx: CanvasRenderingContext2D): void {
    const e = this.engine;
    if (e.rowCount <= 0 || e.colCount <= 0) {
      return;
    }
    ctx.fillStyle = COLOR_OUTSIDE;
    ctx.fillRect(0, 0, this.v(this.canvasW), this.v(this.canvasH));

    const x = this.boardX;
    const y = this.boardY;
    const w = e.colCount * this.tile;
    const h = e.rowCount * this.tile;

    ctx.fillStyle = COLOR_FLOOR;
    ctx.fillRect(this.v(x), this.v(y), this.v(w), this.v(h));

    // 凹槽线：左、右、下三边各 1 像素（原版上边是渐变，没有硬线）
    ctx.fillStyle = COLOR_SUNKEN;
    ctx.fillRect(this.v(x - 1), this.v(y), this.v(1), this.v(h + 1));
    ctx.fillRect(this.v(x + w), this.v(y), this.v(1), this.v(h + 1));
    ctx.fillRect(this.v(x - 1), this.v(y + h), this.v(w + 2), this.v(1));
  }

  /** 棋盘 */
  private drawBoard(ctx: CanvasRenderingContext2D): void {
    const e = this.engine;
    const u = this.unit;
    const tile = this.tile;
    const isFlower = this.atlas.gameStyle === GameStyle.Flowers;
    for (let r = 0; r < e.rowCount; r++) {
      for (let c = 0; c < e.colCount; c++) {
        const cell = e.cellAt(r, c);
        const x = this.boardX + c * tile;
        const y = this.boardY + r * tile;
        const idx = r * e.colCount + c;

        if (cell.revealed) {
          // 地板 = 该格的「按下态」渐变砖块（浅灰），再叠上凸起格子投下来的黑边
          const frame = gradientFrame(r, c, e.rowCount, e.colCount);
          // 洪泛涟漪：展开中的格子还盖着未揭开的凸起砖，地板/数字按 alpha 淡入
          // （原版的 animationAlphaQuickFadeOut，见 Ripple.ets 的依据说明）
          const alpha = this.rippleAlphaOf(idx);
          if (alpha < 1) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, normalTileRect(frame), x, y, u);
            ctx.globalAlpha = alpha;
          }
          this.atlas.drawLogical(ctx, this.atlas.boardSheet, pressedTileRect(frame), x, y, u);

          // 阴影：上方（或首行）和左方（或首列）有凸起格子时，画黑边
          const upRaised = r === 0 || !e.cellAt(r - 1, c).revealed;
          const leftRaised = c === 0 || !e.cellAt(r, c - 1).revealed;
          const shadowT = 3 * u;
          if (upRaised) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_SHADOW_U, x, y, u);
          }
          if (leftRaised) {
            if (upRaised) {
              // 角落不重复加深：从黑边下方开始画
              this.atlas.drawLogical(ctx, this.atlas.boardSheet, [1012, 3, 3, 15], x, y + shadowT, u);
            } else {
              this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_SHADOW_L, x, y, u);
            }
          }

          if (cell.mine) {
            // 踩中的那颗雷，以及判负时引擎翻开的其它未插旗的雷。
            //
            // 原版是**冲击波级联**（参考实现 BoardWidget.cpp:641-645、667-680）：
            //  - 还没轮到的那颗雷仍然**盖在凸起砖下面**，等冲击波扫到它才炸开；
            //  - 矿雷是起爆就画出来；花园玩法的花是「从无到有」长出来的，
            //    所以花开完才出现（参考实现那一行是
            //    `Flowers ? finished : started`）。
            const boomStart = Anim.tripActive ? Anim.boomStartMsOfCell(idx) : -1;
            if (boomStart < 0) {
              this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_MINE, x, y, u);
            } else if (Anim.tripElapsed < boomStart) {
              // 还没轮到：盖着凸起砖（和未揭开的格子一样）
              this.atlas.drawLogical(ctx, this.atlas.boardSheet,
                normalTileRect(gradientFrame(r, c, e.rowCount, e.colCount)), x, y, u);
            } else if (!isFlower || Anim.tripElapsed >= boomStart + Anim.explodeDurationMs()) {
              // 矿雷：起爆就画雷；花园：花开完才画花
              this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_MINE, x, y, u);
            }
          } else if (cell.misflagged) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_FLAG, x, y, u);
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_MISFLAG, x, y, u);
          } else if (cell.adjacent > 0) {
            // 数字框 12×15，在 18×18 的格子里居中（原版实测：数字居于格子中部）
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, digitRect(cell.adjacent),
              x + 3 * u, y + 1.5 * u, u);
          }
          if (alpha < 1) {
            ctx.globalAlpha = 1;
          }
        } else {
          const frame = gradientFrame(r, c, e.rowCount, e.colCount);
          if (this.dealCellUp(idx)) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, normalTileRect(frame), x, y, u);
          } else {
            // 发牌动画中：还没弹起的格画成压平的底砖
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, pressedTileRect(frame), x, y, u);
          }
          if (cell.mark === Mark.Flag) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_FLAG, x, y, u);
          } else if (cell.mark === Mark.Question) {
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_QUESTION, x, y, u);
          }
          if (cell.misflagged) {
            // 插错旗：雷数对不上，旗上打叉（原版判负时这样标）
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_MISFLAG, x, y, u);
          }
          if (idx === this.hoverIndex) {
            // 悬停高亮：原版是**加法混合**（参考实现 Theme.h 注明 "The hilite is additive"），
            // 这张精灵本身 100% 不透明，普通合成会把整格涂成深青色块。
            ctx.globalCompositeOperation = 'lighter';
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_HILITE, x, y, u);
            ctx.globalCompositeOperation = 'source-over';
          }
        }
      }
    }
  }

  /**
   * 画判负的爆炸级联。
   *
   * **必须在整块棋盘画完之后单独画**（原版如此）：
   * 参考实现 BoardWidget.cpp:751-775 的注释写得很清楚 ——
   * 「The loss cascade's explosions, painted over the grid so each fireball
   * can spill across its neighbours' tiles」。
   *
   * 以前我们是在格子循环**里面**画的，于是后画的邻格会把火球溢出到
   * 邻格的那部分盖掉；爆炸帧是 57×57 的整块、按原版偏移 (-18,-18) 画，
   * 确实会溢出格子约一格，必须画在棋盘之上。
   */
  private drawExplosions(ctx: CanvasRenderingContext2D): void {
    if (!Anim.tripActive || Anim.booms.length === 0) {
      return;
    }
    const e = this.engine;
    const u = this.unit;
    const isFlower = this.atlas.gameStyle === GameStyle.Flowers;
    for (let i = 0; i < Anim.booms.length; i++) {
      const frame = Anim.boomFrame(i);
      if (frame < 0) {
        continue;                       // 还没轮到，或者已经放完了
      }
      const idx = Anim.booms[i].cell;
      const r = Math.floor(idx / e.colCount);
      const c = idx % e.colCount;
      const x = this.boardX + c * this.tile;
      const y = this.boardY + r * this.tile;
      // 原版帧是整块（含溢出格子的部分），按原版偏移画，不能居中缩放
      const rect = isFlower ? flowerTripRect(frame) : Anim.explodeRect(frame);
      const off = isFlower ? FLOWER_TRIP_OFFSET : Anim.EXPLODE_OFFSET;
      this.atlas.draw(ctx, this.atlas.otherSheet, rect,
        x + off[0] * u, y + off[1] * u,
        rect[2] * u, rect[3] * u);
    }
  }

  /**
   * 底部状态条：时钟+计时在左，雷数+雷图标在右，中间大片留空。
   * 位置按原版反推：两组分别贴着棋盘的左右沿，留白随棋盘宽度缩放。
   */
  /**
   * 画胜利动画的两样东西：
   *   1) 拆雷光束（逐颗雷，光束自带那份方砖副本，会盖住格子上下）
   *   2) 扫描条（自下而上扫过棋盘）
   */
  private drawScanBar(ctx: CanvasRenderingContext2D): void {
    const u = this.unit;
    // 1) 拆雷光束
    for (let i = 0; i < Anim.beams.length; i++) {
      const f = Anim.beamFrame(i);
      if (f < 0) {
        continue;
      }
      const cell = Anim.beams[i].cell;
      const r = Math.floor(cell / this.engine.colCount);
      const c = cell - r * this.engine.colCount;
      const x = this.boardX + c * this.tile + Anim.DISARM_OFFSET[0] * u;
      const y = this.boardY + r * this.tile + Anim.DISARM_OFFSET[1] * u;
      this.atlas.drawLogical(ctx, this.atlas.otherSheet, disarmRectFor(f, this.atlas.boardStyle), x, y, u);
    }
    // 2) 扫描条
    //
    // 原版是把扫描条**裁在棋盘矩形内**的（linux-minesweeper 的
    // BoardWidget::drawScanBar 里是 `p.setClipRect(m_grid)`），扫到顶整条消失。
    // 我们以前把整条直接画出来，于是条停在棋盘顶上不消失；几何与裁剪都搬到
    // Anim.scanBarRect() 了（Anim.ets 是动画模块的地盘），这里只负责取矩形并画。
    //
    // HUD 模式（棋盘纵向溢出、状态条钉在画布底边）下，棋盘下沿那一截被状态条压住、
    // 根本看不见，所以扫描条只扫**看得见**的那一段（和拆雷光束的计时用同一个下沿）。
    const boardW = this.engine.colCount * this.tile;
    const boardBottom = this.sweepBottom();
    const bar = Anim.scanBarRect(this.boardY, boardBottom, boardW);
    if (bar === null) {
      return;
    }
    this.atlas.draw(ctx, this.atlas.otherSheet, [bar[0], bar[1], bar[2], bar[3]],
      this.boardX, bar[4], bar[5], bar[6]);
  }

  /**
   * 扫描条与拆雷光束用的「棋盘下沿」。
   *
   * HUD 模式下状态条钉在画布底边、压着棋盘最后 32 px，那一截看不见也点不到，
   * 扫描条扫过去也是白扫（而且会被状态条的不透明底色盖掉），所以只扫看得见的那段。
   */
  private sweepBottom(): number {
    const raw: number = this.boardY + this.engine.rowCount * this.tile;
    return this.hudActive ? Math.min(raw, this.stripTop) : raw;
  }

  // ------------------------------------------------------------ 新局发牌动画

  /**
   * 新局发牌动画（原版：整盘先压平，方砖从四个角一波波弹起，总时长 1100ms）。
   *
   * 顺序与时刻的依据见 DealIn.ets 的文件头。
   */
  private dealFlags: boolean[] = [];
  private dealStart: number = 0;
  private dealActive: boolean = false;

  private startDealIn(): void {
    const e = this.engine;
    if (e.rowCount <= 0 || e.colCount <= 0) {
      return;
    }
    this.dealFlags = DealIn.frameAt(0, e.rowCount, e.colCount);
    this.dealStart = Date.now();
    this.dealActive = true;
    this.ensureFrameTimer();
  }

  private stopDealIn(): void {
    this.dealActive = false;
    this.dealFlags = [];
  }

  /** 推进发牌动画，返回 true 表示还在进行 */
  private tickDealIn(): boolean {
    if (!this.dealActive) {
      return false;
    }
    const e = this.engine;
    const elapsed = Date.now() - this.dealStart;
    if (elapsed >= DealIn.TOTAL_MS) {
      console.info('[DealIn] 发牌动画结束 elapsed=' + elapsed);
      this.stopDealIn();
      return false;
    }
    this.dealFlags = DealIn.frameAt(elapsed, e.rowCount, e.colCount);
    return true;
  }

  /** 该格是否已经弹起（发牌动画中） */
  private dealCellUp(idx: number): boolean {
    if (this.dealFlags.length === 0) {
      return true;
    }
    return this.dealFlags[idx] === true;
  }

  // ------------------------------------------------------------ 洪泛涟漪

  /**
   * 洪泛涟漪（原版的 animationAlphaQuickFadeOut）。
   *
   * 原版：展开的格子按**切比雪夫方环**分层，每圈间隔 30ms，单格 150ms 线性淡入；
   * 展开格数少于 6 时不涟漪，直接出现。依据见 Ripple.ets 里的注释。
   */
  private rippleSteps: RippleStep[] = [];
  private rippleStart: number = 0;
  private rippleActive: boolean = false;

  /** 开始一次涟漪（展开格数不足时自动跳过） */
  private startRipple(startCell: number, opened: number[]): void {
    this.stopRipple();
    const steps = Ripple.stepsFrom(startCell, opened, this.engine.rowCount, this.engine.colCount);
    if (steps.length === 0) {
      return;
    }
    this.rippleSteps = steps;
    this.rippleStart = Date.now();
    this.rippleActive = true;
    this.ensureFrameTimer();
  }

  private stopRipple(): void {
    this.rippleActive = false;
    this.rippleSteps = [];
  }

  /** 推进涟漪，返回 true 表示还在进行 */
  private tickRipple(): boolean {
    if (!this.rippleActive) {
      return false;
    }
    if (Date.now() - this.rippleStart >= Ripple.totalMsOf(this.rippleSteps)) {
      this.stopRipple();
      return false;
    }
    return true;
  }

  /** 某格当前的淡入不透明度（1 = 完全显示） */
  private rippleAlphaOf(cellIndex: number): number {
    if (this.rippleSteps.length === 0) {
      return 1;
    }
    const elapsed = Date.now() - this.rippleStart;
    for (const step of this.rippleSteps) {
      if (step.cell === cellIndex) {
        return Ripple.alphaAt(elapsed, step.atMs);
      }
    }
    return 1;
  }

  /**
   * 状态条。
   *
   * 真 Win7 的顺序（依据微软自己的 helpBoard.png，14 倍放大逐像素核对）：
   *
   *     [时钟][计时面板] ····················· [雷数面板][雷图标]
   *
   * 左边那个圆钮**是时钟不是笑脸**（盘面上有指针）；左边 LED 的「18」只能是计时，
   * 右边 LED 的「-40」只能是雷数（雷数允许为负，这个负号是关键证据）。
   * 这与 Lmy0217 复刻的绘制代码完全一致：它的时钟图标取自 Frame.bmp 左上角，
   * 画在棋盘下沿的左端，计时面板紧跟其右；雷数面板与雷图标在右端。
   */
  private drawStatusStrip(ctx: CanvasRenderingContext2D): void {
    const u = this.unit;
    const e = this.engine;
    const boardRight = this.boardX + e.colCount * this.tile;
    const margin = stripMargin(e.colCount) * u;
    // 纵向：状态条带的顶边。竖向装得下时贴在棋盘下沿；棋盘纵向溢出时
    // **钉在画布底边**（HUD），保证计时与雷数永远看得见。
    const stripTop = this.stripTop;

    // ---- HUD 模式：先把带子刷成不透明底色 --------------------------------
    //
    // 坑（Codex 对抗性复审 P2，2026-11-01）：HUD 模式下状态条是**压着**棋盘最后
    // 几行的，而 hitTest() 在 stripTop 及以下一律返回 -1（点不到）。
    // 以前只画图标和面板、不铺底色，于是被压住的那几行格子**照样看得见**，
    // 看着能点其实点不动 —— 明确的误导。
    // 现在先把带子铺成不透明底色（和竖向装得下时带子那块的颜色一样），
    // 被压住的格子就彻底看不见了；它们本来就要靠纵向拖动才露得出来。
    if (this.hudActive) {
      ctx.fillStyle = COLOR_OUTSIDE;
      ctx.fillRect(0, this.v(stripTop), this.v(this.canvasW), this.v(this.canvasH - stripTop));
    }

    // ---- 状态条内容自己的缩放档 su ---------------------------------------
    //
    // 坑（Codex 对抗性复审 P2，2026-11-01）：状态条原来跟着棋盘档位放大，
    // 而一组计数器有 71 个参考单位宽（时钟 25 + 间隙 6 + 面板 40），两组就是 142u；
    // 画布只有 1280 px 时 u 一旦超过 8 就放不下两组了。
    // 实测：n=8、30 列、1280 宽屏时 margin=720px，计时面板从 x=1216 起（大半在屏外），
    // 雷数面板整个跑到屏幕外 —— **两个计数都看不见**。
    // 状态条是「窗口边框」性质的元素，原版里它本来就不随棋盘缩放，
    // 所以这里给内容单独一档 su = min(u, 两组放得下的最大档)。
    // su 必须是**偶数**：图集里的精灵是 2 倍存储像素，偶数档才能整数倍放大（不糊）。
    const groupRef: number = STRIP_CLOCK_SIZE + STRIP_GAP + STRIP_PANEL_W;   // 71
    const maxSu: number = 2 * Math.floor(this.canvasW / (2 * groupRef) / 2);
    const su: number = Math.max(2, Math.min(u, maxSu));

    // 贴边留白：棋盘侧的 margin 也会随 u 放大（30 列时 margin = 45u），
    // 放大到一定程度两组会挤在一起甚至互相压。留白必须按「两组放得下」夹住。
    const groupW: number = groupRef * su;                                  // 一组的宽
    const anchorMargin: number = Math.min(margin,
      Math.max(0, Math.floor((this.canvasW - 2 * groupW) / 2)));

    // 左端：时钟 + 计时面板
    // 锚点用 **max(棋盘左沿 + margin, 留白)**：棋盘比屏幕宽时（30 列的局在窄屏上
    // 棋盘宽 2160px、屏宽 1280px），原来时钟钉在棋盘左沿 = 屏外 440px，
    // 雷数钉在棋盘右沿 = 屏外 440px —— **两个计数都看不见**，而且数字是居中画在面板里的，
    // 露出来的那条面板边也不含数字（实测见 docs\CLICK-MATRIX-90P.md 收官补测）。
    // 现在两端都「贴住屏幕边」，无论棋盘多宽都同时可见。
    const clockX: number = Math.max(0, Math.min(
      Math.max(this.boardX + margin, anchorMargin),
      this.canvasW - groupW - anchorMargin));
    // 内容块顶端：su === u 时**与旧实现逐像素一致**
    // （旧写法是 Math.round((32-25)/2) * u = 4u；改成 round(3.5*u) 会差半格，
    //   计数器的位置就变了，七段数码管的实测读数会跟着偏。）
    // su < u（极端缩放，两组放不下）时，内容块在带子里居中。
    const contentTop: number = (su === u)
      ? stripTop + Math.round((STRIP_BAND - STRIP_CLOCK_SIZE) / 2) * u
      : stripTop + Math.round((STRIP_BAND * u - STRIP_CLOCK_SIZE * su) / 2);
    const clockY: number = contentTop;
    const timeX: number = clockX + (STRIP_CLOCK_SIZE + STRIP_GAP) * su;
    // 面板比时钟矮，要在时钟里垂直居中
    const timeY: number = contentTop + Math.round((STRIP_CLOCK_SIZE - STRIP_PANEL_H) * su / 2);

    // 右端：雷数面板 + 雷图标（同样贴住屏幕右沿）
    let iconX: number = Math.min(boardRight - margin - STRIP_CLOCK_SIZE * su,
      this.canvasW - anchorMargin - STRIP_CLOCK_SIZE * su);
    // 两组不许互相压：右组（面板在左、图标在右）整体要在左组右边
    iconX = Math.max(iconX, clockX + groupW + (STRIP_GAP + STRIP_PANEL_W) * su);
    // 也不许跑出画布
    iconX = Math.min(iconX, this.canvasW - STRIP_CLOCK_SIZE * su);
    const iconY: number = contentTop;
    const mineX: number = iconX - (STRIP_GAP + STRIP_PANEL_W) * su;
    const mineY: number = timeY;

    this.atlas.drawLogical(ctx, this.atlas.otherSheet, RECT_CLOCK, clockX, clockY, su);
    this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_COUNTER, timeX, timeY, su);
    this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_COUNTER, mineX, mineY, su);
    this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_PANEL_MINE, iconX, iconY, su);

    // 两个计数器用**七段数码管**画，不是字体。
    // 权威证据：微软原版 helpBoard.png 的状态条里「18」是七段、「-40」带独立负号段。
    // 几何见 docs\SEVEN-SEG-COUNTER.md（七段渲染器在 SevenSeg.ets）。
    // 单位换算：面板是 40u×21u 设备像素 ⇒ 一个参考像素 = u 设备像素 = u·pxScale vp。
    const segVp: number = su * this.pxScale;
    SevenSeg.draw(ctx, this.seconds, this.v(timeX), this.v(timeY), segVp, su);
    SevenSeg.draw(ctx, e.minesRemaining(), this.v(mineX), this.v(mineY), segVp, su);
  }

  // ------------------------------------------------------------------ 交互

  /** 设备像素坐标 → 格子索引，-1 表示不在棋盘上 */
  hitTest(px: number, py: number): number {
    const e = this.engine;
    // 状态条钉在画布底边（HUD）时，它盖住棋盘的下沿；点到 HUD 上不算点棋盘。
    // 这是 Codex 对抗性复审的 **P2**（「状态条钉底时 hitTest 仍把落在状态条区域的点击
    // 映射到被压住的格子——点一下计数器就可能翻开一个看不见的格子，甚至踩到雷」）。
    // 处理记录见 docs\LAYOUT-MATRIX.md §4.3.4。
    if (this.hudActive && py >= this.stripTop) {
      return -1;
    }
    const c = Math.floor((px - this.boardX) / this.tile);
    const r = Math.floor((py - this.boardY) / this.tile);
    if (r < 0 || r >= e.rowCount || c < 0 || c >= e.colCount) {
      return -1;
    }
    return r * e.colCount + c;
  }

  /** 点一格：开格 */
  tap(px: number, py: number): void {
    if (this.dialog !== null) {
      // 结束对话框开着时，棋盘不接受点击
      return;
    }
    const idx = this.hitTest(px, py);
    if (idx < 0) {
      return;
    }
    const e = this.engine;
    const r = Math.floor(idx / e.colCount);
    const c = idx - r * e.colCount;
    const wasReady = e.gameState === GameState.Ready;
    const outcome = e.reveal(r, c);
    if (outcome.changed) {
      if (outcome.lost) {
        // 踩雷：原版是「爆炸开始 → 爆炸中(循环) → 爆炸结束」三段。
        // 参考实现：爆炸动画 25 帧 × 23ms = 575ms，动画结束后循环播爆炸中音，最后播结束音。
        // 本项目动画 8 帧 × 70ms = 560ms，与原版动画时长基本一致。
        //
        // **爆炸起始音不在这里播**：判负有两条路（点开踩到的雷 / 和弦把邻雷翻出来），
        // 起始音统一放在 notifyGameOver() 的判负分支里起，两条路都有，
        // 也只播一次（Codex 复审 P2，2026-11-01）。
        //
        // 花园（花朵）玩法**不播爆炸三段**：原版的 mineTripped() 在花园模式下直接返回
        // （Linux 复刻 Sounds.h:71），只有枯萎的花声。我们这里也要跳过，
        // 否则爆炸三段与花朵声叠成 4 条一起响（音效审计 P1，2026-11-01）。
      } else if (wasReady) {
        // 第一下：原版播 firstPaint（不是 tileSingle）
        SoundPlayer.play(Sound.FIRST_PAINT);
      } else if (e.cellAt(r, c).adjacent === 0) {
        // 0 格展开：原版用 zeroDevelop 这一声
        SoundPlayer.play(Sound.ZERO_DEVELOP);
      } else if (outcome.opened.length > 1) {
        SoundPlayer.play(Sound.TILE_MULTIPLE);
      } else {
        SoundPlayer.play(Sound.TILE_SINGLE);
      }
    } else if (e.gameState === GameState.Playing &&
      !e.cellAt(r, c).revealed && e.cellAt(r, c).mark !== Mark.Flag) {
      // 只有**还在玩**的时候才响「非法操作」音。
      // 坑（音效审计 P2，2026-11-01）：结束框点「换个难度(D)」把框关掉后棋局仍是终局，
      // 这时再点棋盘会走进这个分支 → 每点一声 invalidMove；原版终局后棋盘是锁住的。
      SoundPlayer.play(Sound.INVALID_MOVE);
    }
    if (wasReady && e.gameState === GameState.Playing) {
      // 原版：第一下就把计数器**置 1**，然后每秒 +1（SPEC §3.7）——不是先显示 00。
      this.seconds = 1;
      this.startTimer();
    }
    // 洪泛涟漪：展开格数够多才涟漪（原版少于 6 格直接出现）
    if (!outcome.lost && outcome.opened.length >= Ripple.MIN_CELLS) {
      this.startRipple(r * e.colCount + c, outcome.opened);
    }
    this.syncTimerWithState();
    this.notifyGameOver();
    this.draw();
  }

  /**
   * 和弦：点已翻开且带数字的格子，若周围旗数等于数字就翻开其余邻格。
   * 旗插错了会同时引爆并判负（引擎处理）。
   */
  chord(px: number, py: number): void {
    const idx = this.hitTest(px, py);
    if (idx < 0) {
      return;
    }
    const e = this.engine;
    const r = Math.floor(idx / e.colCount);
    const c = idx - r * e.colCount;
    const cell = e.cellAt(r, c);
    if (!cell.revealed || cell.adjacent <= 0) {
      return;
    }
    const before = e.revealedCount;
    e.chord(r, c);
    if (e.revealedCount > before) {
      SoundPlayer.play(Sound.TILE_MULTIPLE);
    } else if (e.gameState === GameState.Playing) {
      // 和弦不成（周围旗数 ≠ 数字）→ 原版播 invalidMove。
      // 参考：Linux 复刻 BoardWidget.cpp:840、Lmy 克隆 Minesweeper.cpp:1357-1359。
      // 以前这里什么都不响，等于 invalidMove.wav 在正常玩法里永远不响（音效审计 P1）。
      SoundPlayer.play(Sound.INVALID_MOVE);
    }
    this.syncTimerWithState();
    this.notifyGameOver();
    this.draw();
  }

  /** 长按一格：标记循环 */
  longPress(px: number, py: number): void {
    const idx = this.hitTest(px, py);
    if (idx < 0) {
      return;
    }
    const e = this.engine;
    const r = Math.floor(idx / e.colCount);
    const c = idx - r * e.colCount;
    // 引擎在「已翻开的格 / 终局」时会拒绝插旗并返回 false —— 这时**不该**响插旗音。
    // 以前这里丢了返回值，长按已翻开的格子也会响一声（音效审计 P2，2026-11-01）。
    const marked: boolean = e.toggleMark(r, c);
    if (marked) {
      SoundPlayer.play(Sound.FLAG);
    }
    this.syncTimerWithState();
    this.draw();
  }

  /** 胜负已定就停表，别让计时器在终局后继续跳 */
  private syncTimerWithState(): void {
    const s = this.engine.gameState;
    if (s === GameState.Won || s === GameState.Lost) {
      this.stopTimer();
    }
  }

  /** 终局只通知一次 */
  private notifyGameOver(): void {
    if (this.gameOverNotified) {
      return;
    }
    const s = this.engine.gameState;
    if (s !== GameState.Won && s !== GameState.Lost) {
      return;
    }
    this.gameOverNotified = true;
    const won = s === GameState.Won;
    if (won) {
      SoundPlayer.play(Sound.GAME_WIN);
    } else if (this.atlas.gameStyle === GameStyle.Flowers) {
      // 花园模式判负：换成三段花朵音效（雷数 ≤10 Short / ≤40 Medium / 更多 Long）。
      // 注意是**替换**而不是叠加 —— 两个播放器各自独立起播，叠加会变成两种声音同时响。
      //
      // 坑（Codex 复审 P2，2026-11-01）：分档必须用**本局总雷数**，不能用剩余雷数。
      // 剩余雷数是「总雷数 − 已插旗数」，判负前玩家往往已经插了 30 面旗，
      // 于是 40 雷的局会按 10 雷去播 Short、99 雷的局会按 40 雷去播 Medium —— 全错档。
      const mines: number = this.engine.mineCount;
      const name: string = mines <= 10 ? Sound.FLOWER_LOSE_SHORT
        : (mines <= 40 ? Sound.FLOWER_LOSE_MEDIUM : Sound.FLOWER_LOSE_LONG);
      SoundPlayer.play(name);
    } else {
      SoundPlayer.play(Sound.GAME_LOSE);
    }
    if (!won) {
      // 判负：先播完爆炸动画，再弹对话框（原版就是先炸后弹）。
      // 原版是**冲击波级联**：踩中的那颗先炸，其余没插旗的雷依次炸。
      const booms = this.buildBoomList();
      if (booms.length > 0) {
        Anim.startTrip(booms);
        // 爆炸三段（开始 / 中 / 结束）在这里起 —— **判负只有这一条路**
        // （点开踩到的雷与和弦翻出邻雷，最后都走 notifyGameOver），
        // 所以起始音放在这里，两条路都响、而且只响一次
        // （Codex 复审 P2，2026-11-01：和弦触发的判负原来一声不响）。
        // 花园玩法不播爆炸三段（见 tap 里的说明）。
        if (this.atlas.gameStyle !== GameStyle.Flowers) {
          SoundPlayer.play(Sound.BOMB_START);
          this.playBombTail();
        }
        this.pendingGameOver = true;
        this.startAnimTimer();
        return;
      }
    } else {
      // 胜利：扫描条自下而上扫过棋盘，各行的雷依次被拆解光束烧掉，
      // 扫完之后才弹胜利对话框（原版如此）
      this.startWinSweep();
      return;
    }
    this.buildDialog(won);
    const cb = this.onGameOver;
    if (cb !== null) {
      cb(won);
    }
  }

  /**
   * 某一行雷的**拆雷光束起跳时刻**（毫秒，从扫描开始算起）。
   *
   * - 棋盘完整可见时：按行号均匀分配
   *   `SWEEP_MS * (rows - r) / (rows + 1)`
   *   （依据 linux-minesweeper/src/ui/BoardWidget.cpp:244 的
   *   `const int start = kScanTicks * (rows - r) / (rows + 1);`）
   * - 棋盘被状态条压住一截时（HUD 模式）：扫描条实际只从**看得见的下沿**扫起，
   *   所以按看得见的那一段几何算「条的上沿什么时候到这一行」，
   *   保证光束与扫描条**始终同步**（Codex 复审 P2，2026-11-01）。
   */
  private beamStartMs(r: number): number {
    const e = this.engine;
    const rows: number = e.rowCount;
    const fullBottom: number = this.boardY + rows * this.tile;
    const clipped: boolean = this.hudActive && fullBottom > this.stripTop;
    if (!clipped) {
      return Math.round(Anim.SWEEP_MS * (rows - r) / (rows + 1));
    }
    const visBottom: number = this.sweepBottom();
    const rowTop: number = this.boardY + r * this.tile;
    if (rowTop >= visBottom) {
      // 这一行整个被状态条压住，看不见 —— 光束在画面外，起跳时刻无所谓。
      return 0;
    }
    const span: number = Math.max(1, visBottom - this.boardY);
    return Math.round(Anim.SWEEP_MS * (visBottom - rowTop) / span);
  }

  /**
   * 胜利动画：扫描条扫过 + 逐行拆雷光束。
   *
   * 原版（MineDisarm.xml + 扫描条）：扫描条自下而上扫过棋盘（3 秒），
   * 扫到某一行时，那一行的雷开始播放拆解光束（38 帧 / 2 秒），
   * 全部结束后才弹胜利对话框。
   */
  private startWinSweep(): void {
    const e = this.engine;
    const cells: number[] = [];
    const times: number[] = [];
    for (let r = 0; r < e.rowCount; r++) {
      for (let c = 0; c < e.colCount; c++) {
        if (!e.cellAt(r, c).mine) {
          continue;
        }
        // 每颗雷的拆雷光束在扫描条扫到**它那一行**时起跳，
        // 起跳时刻**按行号均匀分配**：
        //     start = SWEEP_MS * (rows - r) / (rows + 1)
        // 依据：linux-minesweeper/src/ui/BoardWidget.cpp:244
        //   `const int start = kScanTicks * (rows - r) / (rows + 1);`
        //
        // 以前我们算的是「扫描条的上沿扫到该行上沿的时刻」，
        // 用的是扫描条的**真实高度**（棋盘宽 × 62/275，9×9 时约 2.03 格、
        // 30×24 时约 5.41 格）。条那么高，一开始就盖住了最底下几行，
        // 于是**最底几行的光束会在 0 ms 同时开火**（9×9 底两行、30×24 底六行），
        // 看上去不对。改成按行号分配之后，每行的光束依次开火。
        //
        // HUD 模式（棋盘纵向溢出、状态条钉在画布底边）下，扫描条只扫**看得见**的那一段
        // （见 sweepBottom()），所以光束的起跳时刻也得按**看得见的那段**算 ——
        // 否则扫描条早就扫过去了，可见行的光束却还没起跳（Codex 复审 P2，2026-11-01）。
        const startMs: number = this.beamStartMs(r);
        cells.push(r * e.colCount + c);
        times.push(startMs);
      }
    }
    Anim.startWin(cells, times);
    this.pendingGameOver = true;
    this.startAnimTimer();
  }

  /**
   * 判负时的**爆炸级联表**（原版 Win7 的冲击波）。
   *
   * 原版：踩中的那颗先炸（起跳 0），其余**没插旗**的雷按冲击波环到达的时刻
   * 依次炸 —— 离踩中的那颗越远，炸得越晚，中间那段空白就是延迟。
   *
   * 依据：linux-minesweeper/src/ui/BoardWidget.cpp:167-206（startExplosion）
   *   - 踩中的那颗：start = 0
   *   - 其余的：start = max(1, round(dist * kRingStagger)) tick（dist 是欧氏格距）
   *   - 插了旗的雷不炸（`cell.mark == Mark::Flag` 直接跳过）
   *
   * 我们这边「没插旗的雷」正好就是引擎判负时翻开的那些
   * （MinesweeperEngine.lose()：只有 cell.mine && cell.mark !== Mark.Flag 才 revealed）。
   */
  private buildBoomList(): Boom[] {
    const e = this.engine;
    let centreR = -1;
    let centreC = -1;
    for (let r = 0; r < e.rowCount && centreR < 0; r++) {
      for (let c = 0; c < e.colCount && centreR < 0; c++) {
        if (e.cellAt(r, c).exploded) {
          centreR = r;
          centreC = c;
        }
      }
    }
    if (centreR < 0) {
      return [];
    }
    const booms: Boom[] = [];
    for (let r = 0; r < e.rowCount; r++) {
      for (let c = 0; c < e.colCount; c++) {
        const cell = e.cellAt(r, c);
        if (!cell.mine || cell.mark === Mark.Flag) {
          continue;                        // 没插旗的雷才会炸
        }
        const idx = r * e.colCount + c;
        if (cell.exploded) {
          booms.push({ cell: idx, startMs: 0 });
          continue;
        }
        const dr = r - centreR;
        const dc = c - centreC;
        const dist = Math.sqrt(dr * dr + dc * dc);
        booms.push({ cell: idx, startMs: Anim.boomStartMs(dist) });
      }
    }
    // 按起爆时刻排序：先炸的先画，后炸的盖在上面
    booms.sort((a: Boom, b: Boom): number => a.startMs - b.startMs);
    return booms;
  }

  /**
   * 爆炸音的后两段。
   *
   * 原版时序（参考实现的 mineBomb 函数）：
   *   1) 爆炸开始音（一次性）
   *   2) 爆炸动画 25 帧 × 23ms = 575ms
   *   3) 爆炸中音，**循环**播放，同时其它雷逐个烧红
   *   4) 爆炸结束音
   * 各 wav 实测时长：mineBombStart 1.294s / mineBombRun 3.949s / mineBombEnd 1.951s。
   *
   * 两个坑（Codex 复审 P2，2026-11-01）：
   * - **爆炸中音要续播**：wav 只有 3.949 秒，而大棋盘（30×24）的级联能到 6 秒以上；
   *   不续播就会「声音停了、动画还在炸」，中间好几秒静音。
   * - **结束音的时刻从级联开始算**，不是从爆炸中音起算（否则会晚 575ms）。
   */
  private playBombTail(): void {
    // 整条级联要炸多久（从级联开始算起；Anim.startTrip() 刚跑过，值是准的）
    const totalMs: number = Math.max(0, Anim.tripEndMs());
    this.bombTimer1 = setTimeout(() => {
      this.bombTimer1 = -1;
      SoundPlayer.play(Sound.BOMB_RUN);
      // 续播：同名音效重触发会打断前一次（SoundPlayer.play 的语义与原版
      // PlaySound(SND_ASYNC) 一致），所以循环调用就得到「连续的爆炸中音」。
      this.bombTimer3 = setInterval(() => {
        SoundPlayer.play(Sound.BOMB_RUN);
      }, 3700);
      // 结束音在**整条级联炸完**时响，时刻从级联开始算起。
      const delay: number = Math.max(0, totalMs - 575);
      this.bombTimer2 = setTimeout(() => {
        this.bombTimer2 = -1;
        this.stopBombRunLoop();
        SoundPlayer.stop(Sound.BOMB_RUN);
        SoundPlayer.play(Sound.BOMB_END);
      }, delay);
    }, 575);
  }

  /** 爆炸音延时的三个定时器（换局时必须撤掉，否则上一局的爆炸声会串到新局） */
  private bombTimer1: number = -1;
  private bombTimer2: number = -1;
  /** 爆炸中音的续播定时器 */
  private bombTimer3: number = -1;

  /** 停掉「爆炸中音」的续播 */
  private stopBombRunLoop(): void {
    if (this.bombTimer3 !== -1) {
      clearInterval(this.bombTimer3);
      this.bombTimer3 = -1;
    }
  }

  /** 撤掉还没播完的爆炸音 */
  private stopBombTail(): void {
    if (this.bombTimer1 !== -1) {
      clearTimeout(this.bombTimer1);
      this.bombTimer1 = -1;
    }
    if (this.bombTimer2 !== -1) {
      clearTimeout(this.bombTimer2);
      this.bombTimer2 = -1;
    }
    this.stopBombRunLoop();
  }

  private startAnimTimer(): void {
    this.ensureFrameTimer();
  }

  private stopAnimTimer(): void {
    // 动画状态本身由 Anim 管，这里只把「等它放完再弹框」的标记清掉，
    // 时钟由统一帧定时器自己判断还要不要继续跑。
    this.pendingGameOver = false;
  }

  // -------------------------------------------------- 统一帧定时器（30ms）

  /**
   * 画布上所有逐帧动画（发牌 / 涟漪 / 爆炸 / 胜利扫描条）共用一个定时器。
   *
   * 早先用三个独立 setInterval 各画一次，重叠时同一帧会把整块画布画三遍，
   * 折叠屏上会掉帧。现在统一成：有动画才开，没动画就关，每帧只画一次。
   */
  private frameHandle: number = -1;
  /** 上一帧时刻，给 Anim.tick 算 dt */
  private frameLast: number = 0;
  /** 动画放完后要不要弹结束对话框 */
  private pendingGameOver: boolean = false;

  private ensureFrameTimer(): void {
    if (this.frameHandle !== -1) {
      return;
    }
    this.frameLast = Date.now();
    this.frameHandle = setInterval(() => {
      this.tickFrames();
    }, 30);
  }

  private stopFrameTimer(): void {
    if (this.frameHandle !== -1) {
      clearInterval(this.frameHandle);
      this.frameHandle = -1;
    }
  }

  /** 一帧：推进所有动画，最后只重画一次 */
  private tickFrames(): void {
    const now = Date.now();
    const dt = now - this.frameLast;
    this.frameLast = now;

    const dealMore = this.tickDealIn();
    const rippleMore = this.tickRipple();
    const animMore = Anim.tick(dt);
    const anyMore = dealMore || rippleMore || animMore;

    if (!anyMore) {
      this.stopFrameTimer();
      if (this.pendingGameOver) {
        this.pendingGameOver = false;
        // 顺序很重要：**先建对话框再重画**，否则对话框建好了却没画出来
        // （Codex 复审 P1：胜利扫描条结束后对话框一直不出现）。
        const won = this.engine.gameState === GameState.Won;
        this.buildDialog(won);
        this.draw();
        const cb = this.onGameOver;
        if (cb !== null) {
          cb(won);
        }
        return;
      }
    }
    this.draw();
  }

  // ------------------------------------------------------------------ 结束对话框

  /** 生成结束对话框（原版 Win7 风格） */
  private buildDialog(won: boolean): void {
    const cfg = GameController.configOf(this.difficulty);
    GameStats.level = cfg.name;
    // 自定义局**不进统计**：原版 Win7 的自定义局既不记最好成绩，
    // 也不计入「已玩游戏/已胜游戏」（见 linux 复刻 MainWindow.cpp:236-238 的注释）。
    if (!this.customGame) {
      GameStats.record(won, this.seconds, cfg.name).catch(() => {
        // 存档失败不影响对局
      });
    }
    // 自定义局的「最快时间 / 日期」两行**不显示**。
    // 坑（2026-10-31，custom-agent 裁决 P6）：自定义局不进统计，所以它没有纪录；
    // 原来这里照抄了**预设难度**（初级/中级/高级）的纪录，等于给自定义局报了个
    // 毫不相干的成绩。空字符串会让 winSpec 跳过这两行（见 WinDialog.winSpec）。
    const bestText: string = this.customGame ? '' : GameStats.bestTextOf(cfg.name);
    const bestSec = GameStats.bestSecondsOf(cfg.name);
    const isNewBest = !this.customGame && won && (bestSec < 0 || this.seconds <= bestSec);
    if (won) {
      this.dialog = WinDialogPainter.winSpec(this.seconds, GameStats.played, GameStats.won,
        GameStats.percent, bestText, this.customGame ? '' : GameStats.bestDateOf(cfg.name),
        isNewBest);
    } else {
      this.dialog = WinDialogPainter.loseSpec(this.seconds, GameStats.played, GameStats.won, GameStats.percent);
    }
    // 告诉跑测器弹的是**哪一个**框（2026-11-01）。
    // 跑测器的「赢一局」脚本偶尔会踩到雷、弹出的是失败框；它自己分不出来，
    // 就继续按胜利框的坐标点按钮 —— 点空、框不关，用例报成「按钮坏了」，
    // 锅全甩给被测代码。这条日志是应用自己说的，不靠像素猜。
    console.info('[Dialog] 打开 ' + (won ? '胜利' : '失败'));
  }

  /** 对话框当前的绘制参数（缩放与位置） */
  /**
   * 对话框/统计窗口的缩放倍数（参考像素 → 设备像素）。
   *
   * 坑（2026-10-31，LAYOUT-MATRIX 审计 P2-7）：这个值原来只在 dialogLayout() 里算，
   * 而 dialogLayout() 只被 drawDialog() 调用；draw() 的顺序是 drawCustom() 在
   * drawDialog() 之前，打开自定义框时 this.dialog 为 null → dialogLayout() 直接 return
   * → 自定义框拿到的是**陈旧的** dialogScale（首次为初值 1）。
   * 结果自定义框在任何画布上都固定 402 px 宽，比同屏的结束对话框小 2 倍。
   * 现在抽成独立方法，drawCustom()/customLayout() 自己调一次。
   *
   * 坑（2026-10-31，X7 点击矩阵 A1）：原来的公式 `canvasW/1400` 隐含假设画布宽约
   * 1400 px。Mate X7 内屏 2210 px 只得到 1.58 倍，自定义框正文每汉字只有 ~2.7 vp，
   * 数字键盘每键 ~10 vp——手指根本点不准。
   * 改成按**物理密度**算（Win7 的对话框是 96 dpi 下的固定物理尺寸，手机上应当等比放大），
   * 再保证窗口放得下（左右各留 32 px），最后封顶 2 倍避免在超宽屏上过大。
   *
   * 坑（2026-10-31，Codex 复审 P2）：**只按宽度封顶不够**。
   * 短画布（横屏、分屏）上，按宽度算出来的倍数会让对话框**高度超出屏幕**，
   * 底部按钮跑到屏幕外点不到（实测例：900×400 画布 @密度 2.75，
   * 396×340 的胜利框 ×2 = 792×680，按钮全在屏外）。
   * 所以高度也必须参与封顶。
   */
  private computeDialogScale(refWidth: number, refHeight: number): number {
    const density = 1 / this.pxScale;
    const maxByWidth = (this.canvasW - 32) / refWidth;
    const maxByHeight = (this.canvasH - 32) / refHeight;
    // 下限 **0.5** 而不是 1（custom-agent 裁决）：画布窄到放不下时，
    // 宁可整体缩小也要**完整可见** —— 被截断的按钮是点不到的。
    // 真机（含分屏窄条 540px）都到不了这个尺寸，但这是从根上消除裁切的办法。
    return Math.max(0.5, Math.min(2, density, maxByWidth, maxByHeight));
  }

  private dialogLayout(): void {
    const d = this.dialog;
    if (d === null) {
      return;
    }
    // 参考像素 → 设备像素
    const s = this.computeDialogScale(d.width, d.height);
    this.dialogScale = s;
    this.dialogOx = Math.round((this.canvasW - d.width * s) / 2);
    // 比画布还高时**顶对齐**：居中会让上下各露一半，底部按钮就够不着了
    // （LEAD-CHANGE-AUDIT 的 L4）。
    this.dialogOy = d.height * s > this.canvasH
      ? 0
      : Math.round((this.canvasH - d.height * s) / 2);
  }

  /** 画结束对话框 */
  private drawDialog(ctx: CanvasRenderingContext2D): void {
    const d = this.dialog;
    if (d === null) {
      return;
    }
    this.dialogLayout();
    // 几何用 vp，字号用设备像素：两者差一个密度（见 SPEC §5.7）
    WinDialogPainter.draw(ctx, d, this.dialogScale, this.dialogScale * this.pxScale,
      this.v(this.dialogOx), this.v(this.dialogOy));
    // 可选图标（例如「关于」框里的雷）
    // 注意：drawLogical 的入参是**设备像素**（内部自己乘 pxScale 转 vp），
    // 这里不要再乘 pxScale，否则换算两次会画偏（Codex 复审 P2）。
    if (d.icon !== undefined && d.iconPos !== undefined) {
      this.atlas.drawLogical(ctx, this.atlas.gameSheet, d.icon,
        this.dialogOx + d.iconPos[0] * this.dialogScale,
        this.dialogOy + d.iconPos[1] * this.dialogScale,
        this.dialogScale);
    }
  }

  /** 打开一个「菜单触发的」对话框（最佳成绩 / 关于 / 颜色） */
  openInfoDialog(kind: string): void {
    if (kind === 'best') {
      // 原版的「最佳成绩」是独立的**扫雷统计信息窗口**（information.jpg 的版式）
      this.openStatsWindow();
      return;
    } else if (kind === 'appearance') {
      this.dialog = Appearance.begin(this.atlas.boardStyle, this.atlas.gameStyle);
    } else if (kind === 'help') {
      this.dialog = WinDialogPainter.helpSpec();
    } else {
      this.dialog = WinDialogPainter.aboutSpec();
    }
    this.draw();
  }

  // ------------------------------------------------------------ 统计信息窗口

  /** 统计信息窗口是否打开 */
  statsOpen: boolean = false;
  /** 统计窗口左栏难度列表当前选中项（0=初级 1=中级 2=高级） */
  statsSelectedLevel: number = 0;
  private statsScale: number = 1;
  private statsOx: number = 0;
  private statsOy: number = 0;

  /** 打开统计信息窗口 */
  openStatsWindow(): void {
    this.statsOpen = true;
    this.dialog = null;
    this.menuOpenId = '';
    // 左栏默认选中当前难度这一档（原版打开统计窗口时选中的是当前玩的那一档）
    this.statsSelectedLevel = this.difficulty === Difficulty.Intermediate ? 1 :
      (this.difficulty === Difficulty.Expert ? 2 : 0);
    this.draw();
  }

  /** 统计窗口当前的绘制参数 */
  private statsLayout(): void {
    // 参考像素 → 设备像素：与对话框同一套缩放规则（按物理密度算 + 保证放得下）
    const s = this.computeDialogScale(StatsWindowPainter.width(), StatsWindowPainter.height());
    this.statsScale = s;
    this.statsOx = Math.round((this.canvasW - StatsWindowPainter.width() * s) / 2);
    // 比画布还高时顶对齐（底部按钮要够得着）
    this.statsOy = StatsWindowPainter.height() * s > this.canvasH
      ? 0
      : Math.round((this.canvasH - StatsWindowPainter.height() * s) / 2);
  }

  /** 统计窗口要显示的数据 */
  private statsData(): StatsData {
    const levels: StatsLevel[] = [];
    for (const level of ['初级', '中级', '高级']) {
      levels.push({ level: level, best: GameStats.bestSecondsOf(level), date: GameStats.bestDateOf(level) });
    }
    // 中栏「最佳时间」显示**左栏当前选中那一档**的纪录。
    // 原版这个列表是可以点的，选初级就显示初级的最好成绩（information.jpg 里
    // 选中初级、中栏显示 17 秒那一条就是这个样子）。
    const sel: number = Math.max(0, Math.min(2, this.statsSelectedLevel));
    const picked: StatsLevel = levels[sel];
    return {
      bestSeconds: picked.best,
      bestDate: picked.date,
      played: GameStats.played,
      won: GameStats.won,
      currentStreak: GameStats.currentStreak,
      maxStreak: GameStats.maxStreak,
      maxLoseStreak: GameStats.maxLoseStreak,
      perLevel: levels,
      selected: sel
    };
  }

  /** 画统计信息窗口 */
  private drawStats(ctx: CanvasRenderingContext2D): void {
    if (!this.statsOpen) {
      return;
    }
    this.statsLayout();
    StatsWindowPainter.draw(ctx, this.statsData(),
      this.statsScale, this.statsScale * this.pxScale,
      this.v(this.statsOx), this.v(this.statsOy));
  }

  /**
   * 点到统计窗口的按钮：返回 'reset' / 'close' / null。
   *
   * 点窗口**外面**也算关闭（返回 'close'），避免手机上误入后找不到出口。
   */
  statsButtonAt(px: number, py: number): string | null {
    if (!this.statsOpen) {
      return null;
    }
    this.statsLayout();
    // 标题栏右上角的红叉（画了就得能点）
    if (StatsWindowPainter.hitTitleClose(this.statsScale, this.statsOx, this.statsOy, px, py)) {
      return 'close';
    }
    if (StatsWindowPainter.hitReset(this.statsScale, this.statsOx, this.statsOy, px, py)) {
      return 'reset';
    }
    if (StatsWindowPainter.hitClose(this.statsScale, this.statsOx, this.statsOy, px, py)) {
      return 'close';
    }
    // 左栏难度列表：点哪一档就选中哪一档，中栏跟着换
    const li: number = StatsWindowPainter.hitListItem(this.statsScale, this.statsOx, this.statsOy, px, py);
    if (li >= 0 && li <= 2) {
      if (this.statsSelectedLevel !== li) {
        this.statsSelectedLevel = li;
        console.info('[Stats] 选中难度 ' + li);
        this.draw();
      }
      return null;
    }
    const w = StatsWindowPainter.width() * this.statsScale;
    const h = StatsWindowPainter.height() * this.statsScale;
    const outside = px < this.statsOx || px > this.statsOx + w ||
      py < this.statsOy || py > this.statsOy + h;
    if (outside) {
      return 'close';
    }
    return null;
  }

  /** 关闭统计窗口 */
  closeStats(): void {
    this.statsOpen = false;
    this.draw();
  }

  // ------------------------------------------------------------ 自定义难度

  /**
   * 打开「自定义」对话框。
   *
   * 预填**当前盘面**的参数，不是当前难度的预设值。
   * 坑（2026-10-31，custom-agent 裁决 P4）：原来用 `configOf(this.difficulty)`，
   * 于是「高级局 → 自定义」预填的是 30×16 而不是当前正在玩的那一局。
   * 原版是拿当前盘面预填的（用户多半是微调当前局）。
   * 依据：docs\CUSTOM-DIALOG-VERDICT.md
   */
  openCustomDialog(): void {
    this.customSpec = CustomField.specOf(this.engine.rowCount, this.engine.colCount,
      this.engine.mineCount);
    this.dialog = null;
    this.menuOpenId = '';
    this.draw();
  }

  /** 自定义对话框 + 数字键盘的摆放位置（设备像素） */
  private customLayout(): void {
    // 自己算缩放，别用 dialogLayout() 的陈旧值（见 computeDialogScale 的坑）
    this.dialogScale = this.computeDialogScale(DLG_W + 12 + NumKeypad.width(),
      Math.max(DLG_H, NumKeypad.height()));
    const s = this.dialogScale;
    const dlgW = DLG_W * s;
    const keyW = NumKeypad.width() * s;
    const totalW = dlgW + 12 * s + keyW;
    const totalH = Math.max(DLG_H * s, NumKeypad.height() * s);
    this.customOx = Math.round((this.canvasW - totalW) / 2);
    this.customOy = totalH > this.canvasH ? 0 : Math.round((this.canvasH - totalH) / 2);
  }

  /** 画「自定义」对话框与数字键盘 */
  private drawCustom(ctx: CanvasRenderingContext2D): void {
    const spec = this.customSpec;
    if (spec === null) {
      return;
    }
    this.customLayout();
    const sDev = this.dialogScale;
    const sVp = this.dialogScale * this.pxScale;
    const oxVp = this.v(this.customOx);
    const oyVp = this.v(this.customOy);
    CustomField.draw(ctx, spec, sDev, sVp, oxVp, oyVp);
    // 数字键盘放在对话框右边
    const keyX = oxVp + (DLG_W + 12) * sVp;
    NumKeypad.draw(ctx, sDev, sVp, keyX, oyVp);
  }

  /**
   * 「自定义」对话框的命中测试。
   * @param px 设备像素
   * @param py 设备像素
   * @return 'ok' | 'cancel' | 'height' | 'width' | 'mines' | ''（没点到）
   */
  customActionAt(px: number, py: number): string {
    const spec = this.customSpec;
    if (spec === null) {
      return '';
    }
    this.customLayout();
    const sVp = this.dialogScale * this.pxScale;
    const oxVp = this.v(this.customOx);
    const oyVp = this.v(this.customOy);
    const pxVp = this.v(px);
    const pyVp = this.v(py);
    // 先看对话框本身
    const inDlg = pxVp >= oxVp && pxVp <= oxVp + DLG_W * sVp &&
      pyVp >= oyVp && pyVp <= oyVp + DLG_H * sVp;
    if (inDlg) {
      const hit = CustomField.hit(spec, this.dialogScale, sVp, oxVp, oyVp, pxVp, pyVp);
      if (hit === 'ok') {
        const s = CustomField.clampSpec(spec);
        this.customSpec = null;
        // 自定义局：难度名不变，成绩不进统计（原版如此）
        this.customGame = true;
        this.startNewGame(s.height, s.width, s.mines);
        this.draw();
        return '';
      }
      if (hit === 'cancel') {
        this.customSpec = null;
        this.draw();
        return '';
      }
      if (hit.length > 0) {
        CustomField.focusField(spec, hit);
        this.draw();
      }
      return '';
    }
    // 再看数字键盘
    const keyX = oxVp + (DLG_W + 12) * sVp;
    const key = NumKeypad.hit(sVp, keyX, oyVp, pxVp, pyVp);
    if (key.length > 0) {
      if (key === 'del') {
        CustomField.backspace(spec);
      } else {
        CustomField.inputChar(spec, key);
      }
      this.draw();
    }
    return '';
  }

  /**
   * 点到结束对话框的按钮：返回动作标识，没点到返回 null。
   * 对话框打开时棋盘不接受点击。
   */
  dialogButtonAt(px: number, py: number): string | null {
    const d = this.dialog;
    if (d === null) {
      return null;
    }
    this.dialogLayout();
    const hit = WinDialogPainter.hitButton(d, this.dialogScale, this.dialogOx, this.dialogOy, px, py);
    // 「颜色」对话框：缩略图切换 / 确定 / 取消 —— 自己处理，不往上抛
    if (hit !== null && Appearance.owns(hit)) {
      if (hit === 'appearance:ok') {
        this.atlas.applyStyle(Appearance.pendingBoard, Appearance.pendingGame);
        // 外观变了要重新打一次布局日志（跑测器靠日志里的「外观=」断言
        // 「点了缩略图到底生效没有」——颜色框把棋盘整个盖住，像素比不出来）。
        this.layout();
        // 再单独打一条：跑测器断言「点缩略图 + 关框之后**没有**这条」，
        // 就说明外观**没有**被偷偷应用上（取消/红叉都不该打这条）。
        console.info('[Dialog] 应用外观 ' +
          (Appearance.pendingBoard === BoardStyle.Green ? '绿' : '蓝') + '/' +
          (Appearance.pendingGame === GameStyle.Flowers ? '花园' : '扫雷'));
        // 原版重启后保留外观 ✓ → 存进 preferences
        GameStats.saveStyle(
          Appearance.pendingBoard === BoardStyle.Green ? 1 : 0,
          Appearance.pendingGame === GameStyle.Flowers ? 1 : 0).catch(() => {
        });
        this.dialog = null;
      } else if (hit === 'appearance:cancel') {
        this.dialog = null;
      } else if (Appearance.select(hit)) {
        console.info('[Dialog] 点到缩略图 ' + hit);
        this.dialog = Appearance.spec();
      }
      this.draw();
      return null;
    }
    return hit;
  }

  /** 关闭结束对话框（比如重新开局时） */
  closeDialog(): void {
    this.dialog = null;
    // 关掉对话框必须重画，否则画布上还留着上一帧的对话框
    // （Codex 复审 P2）
    this.draw();
  }

  // ------------------------------------------------------------------ 菜单栏

  /** 生成菜单栏规格（当前难度打勾） */
  private buildMenu(): void {
    this.menuSpec = {
      tops: [
        {
          id: 'game',
          label: '游戏(G)',
          entries: [
            { id: 'new', label: '新建', accelerator: 'F2' },
            { id: 'sep1', label: '', separator: true },
            { id: 'beginner', label: '初级', checked: !this.customGame && this.difficulty === Difficulty.Beginner },
            { id: 'intermediate', label: '中级', checked: !this.customGame && this.difficulty === Difficulty.Intermediate },
            { id: 'expert', label: '高级', checked: !this.customGame && this.difficulty === Difficulty.Expert },
            // 自定义局：原版把「自定义」这一项打勾、三档预设全部取消
            // （原版用 Difficulty=3 表示自定义，见 Lmy 克隆 resource.h:32 与
            //  windowing.c:885-887 的 InitializeCheckedMenuItems）。
            { id: 'custom', label: '自定义', checked: this.customGame },
            { id: 'marks', label: '标记(?)', checked: this.questionMarks },
            { id: 'sep2', label: '', separator: true },
            { id: 'sound', label: '声音', checked: SoundPlayer.isEnabled },
            { id: 'sep3', label: '', separator: true },
            { id: 'best', label: '最佳成绩' },
            appearanceEntry(),
            { id: 'sep4', label: '', separator: true },
            { id: 'exit', label: '退出', accelerator: 'X' }
          ]
        },
        {
          id: 'help',
          label: '帮助(H)',
          entries: [
            { id: 'help', label: '帮助(H)', accelerator: 'F1' },
            { id: 'sep1', label: '', separator: true },
            { id: 'about', label: '关于扫雷', accelerator: 'A' }
          ]
        }
      ]
    };
  }

  /** 菜单栏与下拉菜单的绘制 */
  private drawMenu(ctx: CanvasRenderingContext2D): void {
    const fontPx = 14 / this.pxScale;   // 14vp 字号换算成设备像素
    const density = 1 / this.pxScale;
    const wVp = this.v(this.canvasW);
    const hVp = MENU_BAR_H;
    WinMenuPainter.drawBar(ctx, this.menuSpec, fontPx, density, 0, 0, wVp, hVp, this.menuOpenId);
    if (this.menuOpenId.length > 0) {
      const top = this.menuSpec.tops.find((t) => t.id === this.menuOpenId);
      if (top !== undefined) {
        const x = WinMenuPainter.dropX(this.menuSpec, this.menuOpenId, fontPx, density, 0);
        WinMenuPainter.drawDrop(ctx, top.entries, fontPx, x, hVp);
      }
    }
  }

  /** 点是否落在菜单栏上（含下拉面板） */
  isOnMenuBar(px: number, py: number): boolean {
    const pyVp = this.v(py);
    if (pyVp <= MENU_BAR_H) {
      return true;
    }
    if (this.menuOpenId.length === 0) {
      return false;
    }
    const top = this.menuSpec.tops.find((t) => t.id === this.menuOpenId);
    if (top === undefined) {
      return false;
    }
    const fontPx = 14 / this.pxScale;
    const density = 1 / this.pxScale;
    const x = WinMenuPainter.dropX(this.menuSpec, this.menuOpenId, fontPx, density, 0);
    // 下拉面板的高度：逐项累加
    let h = 8;
    for (const e of top.entries) {
      h += e.separator ? 7 : 24;
    }
    const pxVp = this.v(px);
    return pxVp >= x && pxVp <= x + 168 && pyVp >= MENU_BAR_H && pyVp <= MENU_BAR_H + h;
  }

  /** 菜单动作回调（页面处理） */
  onMenuAction: ((action: string) => void) | null = null;

  /** 菜单规格变了（比如声音开关）就重建并重画 */
  refreshMenu(): void {
    this.buildMenu();
    this.draw();
  }

  /** 切换「标记(?)」：关掉问号后，长按只有 旗 → 无 两种状态 */
  toggleQuestionMarks(): void {
    this.questionMarks = !this.questionMarks;
    this.engine.questionMarksAllowed = this.questionMarks;
    this.refreshMenu();
  }

  /**
   * 打开「游戏」下拉菜单。
   *
   * 结束对话框中间那个按钮的文案是「换个难度(D)」——名字说了要换难度，
   * 原来点了只是把框关掉（custom-agent 审计指出「名不副实」）。
   * 现在它真的把难度菜单打开，用户接着点初级/中级/高级即可。
   */
  openGameMenu(): void {
    this.dialog = null;
    this.buildMenu();
    this.menuOpenId = 'game';
    this.draw();
  }

  /**
   * 菜单栏命中测试：返回动作标识。
   * @param px 设备像素 x
   * @param py 设备像素 y
   */
  menuActionAt(px: number, py: number): string {    const fontPx = 14 / this.pxScale;
    const density = 1 / this.pxScale;
    const pxVp = this.v(px);
    const pyVp = this.v(py);
    // 下拉菜单优先（它在菜单栏之上）
    if (this.menuOpenId.length > 0) {
      const top = this.menuSpec.tops.find((t) => t.id === this.menuOpenId);
      if (top !== undefined) {
        const x = WinMenuPainter.dropX(this.menuSpec, this.menuOpenId, fontPx, density, 0);
        const id = WinMenuPainter.entryHit(top.entries, x, MENU_BAR_H, pxVp, pyVp);
        if (id.length > 0) {
          // 坑（2026-10-31，CLICK-MATRIX-90P 异常 1）：选中条目后**没有关掉下拉菜单**。
          // 换难度类动作会走 startNewGame()，里面把 menuOpenId 清了，所以看着正常；
          // 但「标记(?)」「声音」走的是 refreshMenu()，不清 menuOpenId，
          // 结果整块菜单留在画布上不消失（动作其实已经执行了）。
          // 这里统一先关菜单，后面的动作怎么处理都不影响。
          this.menuOpenId = '';
          return id;
        }
        // 点在下拉面板以外 → 关闭菜单
        this.menuOpenId = '';
        this.draw();
        return '';
      }
    }
    // 菜单栏上的顶层项
    const topId = WinMenuPainter.topHit(this.menuSpec, fontPx, density, 0, 0, MENU_BAR_H, pxVp, pyVp);
    if (topId.length > 0) {
      this.menuOpenId = (this.menuOpenId === topId) ? '' : topId;
      this.draw();
      return '';
    }
    return '';
  }

  // ------------------------------------------------------------------ 计时

  private startTimer(): void {
    if (this.timerHandle !== -1) {
      return;
    }
    this.timerHandle = setInterval(() => {
      if (this.seconds < 999) {
        this.seconds++;
      }
      this.draw();
    }, 1000);
  }

  private stopTimer(): void {
    if (this.timerHandle !== -1) {
      clearInterval(this.timerHandle);
      this.timerHandle = -1;
    }
  }

  /**
   * 还有没有动画要跑。
   *
   * 发牌/涟漪/爆炸/胜利扫描条都算——漏掉任何一个，
   * 切后台或换屏重建后就可能停在那儿不动（Codex 复审 P1）。
   */
  private hasActiveFrameWork(): boolean {
    return Anim.winActive || Anim.tripActive || this.dealActive || this.rippleActive;
  }

  /** 组件销毁时调用：停掉计时器，别让它继续往已销毁的画布上画 */
  dispose(): void {
    this.stopTimer();
    this.stopFrameTimer();
    // 注意：**不要**清 pendingGameOver。
    // 折叠/旋转会重建画布（dispose → attach → resume），若这时正在放爆炸或
    // 胜利扫描条，清掉标记会导致动画放完后既不弹结束框、也不记成绩
    // （Codex 复审 P1）。
    this.context = null;
  }

  /** 应用切到后台：暂停计时（手机上放口袋不该继续耗秒数） */
  pauseForBackground(): void {
    if (this.timerHandle !== -1) {
      clearInterval(this.timerHandle);
      this.timerHandle = -1;
    }
    // 逐帧动画也停（手机上放口袋不该继续耗电），回前台会接着放
    this.stopFrameTimer();
  }

  /** 应用回到前台：若正在游戏中则恢复计时 */
  resumeFromBackground(): void {
    if (this.engine.gameState === GameState.Playing) {
      this.startTimer();
    }
    // 任何动画被打断都要接着跑（发牌、涟漪、爆炸、胜利扫描条）
    if (this.hasActiveFrameWork()) {
      this.startAnimTimer();
    }
  }

  /** 页面重建（折叠/旋转）后恢复：接着原局继续，计时器重新走 */
  resume(): void {
    if (this.engine.gameState === GameState.Playing) {
      this.startTimer();
    }
    if (this.hasActiveFrameWork()) {
      this.startAnimTimer();
    }
    if (this.context !== null) {
      this.layout();
      this.draw();
    }
  }
}
