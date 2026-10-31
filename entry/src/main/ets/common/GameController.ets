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
import { WinMenuPainter, MenuSpec, MENU_BAR_H } from './WinMenu';
import { CustomField, CustomSpec, DLG_W, DLG_H } from './CustomField';
import { NumKeypad } from './NumKeypad';
import { Anim } from './Anim';
import { Ripple, RippleStep } from './Ripple';
import { StatsWindowPainter, StatsData, StatsLevel } from './StatsWindow';
import { DealIn } from './DealIn';
import {
  TILE, MAX_SCALE_INDEX, FRAME_GAP_L, FRAME_GAP_T, FRAME_GAP_R, FRAME_GAP_B,
  gradientFrame, normalTileRect, pressedTileRect, RECT_FLAG, RECT_QUESTION, RECT_HILITE, RECT_MISFLAG,
  RECT_SHADOW_U, RECT_SHADOW_L, RECT_COUNTER, digitRect, RECT_MINE, RECT_PANEL_MINE, RECT_CLOCK,
  COLOR_OUTSIDE, COLOR_FLOOR, COLOR_SUNKEN,
  STRIP_BAND, STRIP_CLOCK_SIZE, STRIP_PANEL_W, STRIP_PANEL_H, STRIP_GAP, stripMargin
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

  /** 同难度重开 */
  restart(): void {
    const cfg = GameController.configOf(this.difficulty);
    // 重开按当前难度走，自定义局的「不进统计」标记要清掉，
    // 否则之后按难度开的局也会被当成自定义局而不记成绩。
    this.customGame = false;
    this.startNewGame(cfg.rows, cfg.cols, cfg.mines);
  }

  /**
   * 开新局。
   *
   * @param silent true = 不播开局音（应用刚启动时用：原版启动是静音的，
   *               只有玩家主动「新建/换难度/再玩一局」才有那一声）。
   */
  startNewGame(rows: number, cols: number, mines: number, silent: boolean = false): void {
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

  /** 设备像素 → Canvas 坐标（vp） */
  private v(px: number): number {
    return px * this.pxScale;
  }

  /** 按当前画布尺寸重算缩放档位与各矩形 */
  layout(): void {
    const e = this.engine;
    if (e.rowCount <= 0 || e.colCount <= 0 || this.canvasW <= 0) {
      return;
    }
    // 1) 算出「整盘刚好放下」的档位
    let fit = 1;
    for (let n = 1; n <= MAX_SCALE_INDEX; n++) {
      const u = 2 * n;
      const fw = e.colCount * TILE * u + (FRAME_GAP_L + FRAME_GAP_R) * u;
      const fh = e.rowCount * TILE * u + (FRAME_GAP_T + FRAME_GAP_B) * u;
      if (fw <= this.canvasW && fh <= this.canvasH) {
        fit = n;
      } else {
        break;
      }
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
      ' unit=' + this.unit + ' 格边=' + this.tile + 'px 棋盘原点=(' + this.boardX + ',' + this.boardY + ')');
  }

  /** 根据当前档位与平移量重算各矩形（设备像素） */
  private applyGeometry(): void {
    const e = this.engine;
    const u = 2 * this.scaleIndex;
    this.unit = u;
    this.tile = TILE * u;
    const boardW = e.colCount * this.tile;
    const boardH = e.rowCount * this.tile;
    this.frameW = boardW + (FRAME_GAP_L + FRAME_GAP_R) * u;
    this.frameH = boardH + (FRAME_GAP_T + FRAME_GAP_B) * u;
    this.frameX = Math.round((this.canvasW - this.frameW) / 2) + this.panX;
    this.frameY = Math.round((this.canvasH - this.frameH) / 2) + this.panY;
    this.boardX = this.frameX + FRAME_GAP_L * u;
    this.boardY = this.frameY + FRAME_GAP_T * u;
  }

  /**
   * 平移量夹紧：棋盘不能被拖出画布；整盘放得下时不允许平移。
   *
   * 坑（Codex 复审 P1）：frame 比画布大时 baseX 为负，**不能**直接把平移量归零——
   * 那样高级局放大后就永远够不到边上的格子。正确做法是夹到 [-|baseX|, |baseX|]：
   * 板子比视口大时允许拖动，且两边都能拖到。
   */
  private clampPan(): void {
    const baseX = (this.canvasW - this.frameW) / 2;
    const baseY = (this.canvasH - this.frameH) / 2;
    const limX = Math.abs(baseX);
    const limY = Math.abs(baseY);
    this.panX = Math.max(-limX, Math.min(limX, this.panX));
    this.panY = Math.max(-limY, Math.min(limY, this.panY));
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

          if (cell.exploded) {
            // 踩中的那颗雷
            this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_MINE, x, y, u);
            // 爆炸动画（只在踩中的那一格上播）
            if (Anim.tripActive && idx === Anim.tripCell) {
              // 原版帧是 57x57 的整块（含溢出格子的部分），按原版偏移 (-18,-18) 画，
              // 不能居中缩放，否则爆炸会缩水。
              const rect = Anim.explodeRect(Anim.tripFrame);
              this.atlas.draw(ctx, this.atlas.otherSheet, rect,
                x + Anim.EXPLODE_OFFSET[0] * u, y + Anim.EXPLODE_OFFSET[1] * u,
                rect[2] * u, rect[3] * u);
            }
          } else if (cell.mine) {
            // 判负时引擎把未插旗的雷全部翻开，这里补上雷
            this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_MINE, x, y, u);
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
      this.atlas.drawLogical(ctx, this.atlas.otherSheet, Anim.disarmRect(f), x, y, u);
    }
    // 2) 扫描条
    const barY = this.scanBarY();
    if (barY < 0) {
      return;
    }
    const boardW = this.engine.colCount * this.tile;
    const barH = Math.round(62 * u);
    this.atlas.draw(ctx, this.atlas.otherSheet, Anim.SCAN_BAR,
      this.boardX, barY, boardW, barH);
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
    const boardBottom = this.boardY + e.rowCount * this.tile;
    const boardRight = this.boardX + e.colCount * this.tile;
    const margin = stripMargin(e.colCount) * u;

    // 左端：时钟 + 计时面板
    const clockX = this.boardX + margin;
    const clockY = boardBottom + Math.round((STRIP_BAND - STRIP_CLOCK_SIZE) / 2) * u;
    const timeX = clockX + (STRIP_CLOCK_SIZE + STRIP_GAP) * u;
    const timeY = boardBottom + Math.round((STRIP_BAND - STRIP_PANEL_H) / 2) * u;

    // 右端：雷数面板 + 雷图标
    const iconX = boardRight - margin - STRIP_CLOCK_SIZE * u;
    const iconY = boardBottom + Math.round((STRIP_BAND - STRIP_CLOCK_SIZE) / 2) * u;
    const mineX = iconX - (STRIP_GAP + STRIP_PANEL_W) * u;
    const mineY = boardBottom + Math.round((STRIP_BAND - STRIP_PANEL_H) / 2) * u;

    this.atlas.drawLogical(ctx, this.atlas.otherSheet, RECT_CLOCK, clockX, clockY, u);
    this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_COUNTER, timeX, timeY, u);
    this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_COUNTER, mineX, mineY, u);
    this.atlas.drawLogical(ctx, this.atlas.gameSheet, RECT_PANEL_MINE, iconX, iconY, u);

    // 字号单位：Canvas 的 font 里 "px" 是**设备像素**（与画布坐标的 vp 不是一回事，
    // 真机实测：写成 vp 换算值会让数字小 2.75 倍）。原版字高约 9 单位 → 字号约 12 单位。
    ctx.font = `bold ${12 * u}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#ffffff';
    ctx.fillText(`${this.seconds}`, this.v(timeX + STRIP_PANEL_W * u / 2), this.v(timeY + STRIP_PANEL_H * u / 2));
    ctx.fillText(`${e.minesRemaining()}`, this.v(mineX + STRIP_PANEL_W * u / 2), this.v(mineY + STRIP_PANEL_H * u / 2));
  }

  // ------------------------------------------------------------------ 交互

  /** 设备像素坐标 → 格子索引，-1 表示不在棋盘上 */
  hitTest(px: number, py: number): number {
    const e = this.engine;
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
        SoundPlayer.play(Sound.BOMB_START);
        this.playBombTail();
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
    } else if (!e.cellAt(r, c).revealed && e.cellAt(r, c).mark !== Mark.Flag) {
      SoundPlayer.play(Sound.INVALID_MOVE);
    }
    if (wasReady && e.gameState === GameState.Playing) {
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
    e.toggleMark(r, c);
    SoundPlayer.play(Sound.FLAG);
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
    SoundPlayer.play(won ? Sound.GAME_WIN : Sound.GAME_LOSE);
    if (!won) {
      // 判负：先播完爆炸动画，再弹对话框（原版就是先炸后弹）
      const cell = this.explodedCellIndex();
      if (cell >= 0) {
        Anim.startTrip(cell);
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
    const barH = Anim.SCAN_BAR[3] * this.unit;
    const boardBottom = this.boardY + e.rowCount * this.tile;
    const boardH = Math.max(1, e.rowCount * this.tile);
    for (let r = 0; r < e.rowCount; r++) {
      for (let c = 0; c < e.colCount; c++) {
        if (!e.cellAt(r, c).mine) {
          continue;
        }
        // 扫描条的上沿从 boardBottom - barH 起步往上走，
        // 扫到这一行（行顶 y = boardY + r*tile）时已走过的比例。
        const mineY = this.boardY + r * this.tile;
        const crossed = (boardBottom - barH - mineY) / boardH;
        cells.push(r * e.colCount + c);
        times.push(Math.max(0, Math.min(1, crossed)) * Anim.SWEEP_MS);
      }
    }
    Anim.startWin(cells, times);
    this.pendingGameOver = true;
    this.startAnimTimer();
  }

  /**
   * 扫描条当前的位置（设备像素，返回条的上沿）；不在扫就返回 -1。
   *
   * 行程：p=0 时条的**下沿**贴棋盘下沿，p=1 时条的**下沿**离开棋盘上沿
   *  —— 即条的上沿从 boardBottom - barH 走到 boardTop - barH，正好扫完全盘。
   */
  private scanBarY(): number {
    if (!Anim.winActive) {
      return -1;
    }
    const e = this.engine;
    const boardBottom = this.boardY + e.rowCount * this.tile;
    const boardH = e.rowCount * this.tile;
    const barH = Anim.SCAN_BAR[3] * this.unit;
    const p = Math.min(1, Anim.winElapsed / Anim.SWEEP_MS);
    return boardBottom - barH - p * boardH;
  }

  /** 找出踩中的那颗雷的格索引（没有就 -1） */
  private explodedCellIndex(): number {
    const e = this.engine;
    for (let r = 0; r < e.rowCount; r++) {
      for (let c = 0; c < e.colCount; c++) {
        if (e.cellAt(r, c).exploded) {
          return r * e.colCount + c;
        }
      }
    }
    return -1;
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
   */
  private playBombTail(): void {
    this.bombTimer1 = setTimeout(() => {
      this.bombTimer1 = -1;
      SoundPlayer.play(Sound.BOMB_RUN);
      this.bombTimer2 = setTimeout(() => {
        this.bombTimer2 = -1;
        SoundPlayer.play(Sound.BOMB_END);
      }, 3949);
    }, 575);
  }

  /** 爆炸音延时的两个定时器（换局时必须撤掉，否则上一局的爆炸声会串到新局） */
  private bombTimer1: number = -1;
  private bombTimer2: number = -1;

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
    const bestText = GameStats.bestTextOf(cfg.name);
    const bestSec = GameStats.bestSecondsOf(cfg.name);
    const isNewBest = !this.customGame && won && (bestSec < 0 || this.seconds <= bestSec);
    if (won) {
      this.dialog = WinDialogPainter.winSpec(this.seconds, GameStats.played, GameStats.won,
        GameStats.percent, bestText, GameStats.bestDateOf(cfg.name), isNewBest);
    } else {
      this.dialog = WinDialogPainter.loseSpec(this.seconds, GameStats.played, GameStats.won, GameStats.percent);
    }
  }

  /** 对话框当前的绘制参数（缩放与位置） */
  private dialogLayout(): void {
    const d = this.dialog;
    if (d === null) {
      return;
    }
    // 参考像素 → 设备像素：按画布宽度取一个整数感舒服的倍数
    const s = Math.max(1, Math.min(2, this.canvasW / 1400));
    this.dialogScale = s;
    this.dialogOx = Math.round((this.canvasW - d.width * s) / 2);
    this.dialogOy = Math.round((this.canvasH - d.height * s) / 2);
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

  /** 打开一个「菜单触发的」对话框（最佳成绩 / 关于） */
  openInfoDialog(kind: string): void {
    if (kind === 'best') {
      // 原版的「最佳成绩」是独立的**扫雷统计信息窗口**（information.jpg 的版式）
      this.openStatsWindow();
      return;
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
  private statsScale: number = 1;
  private statsOx: number = 0;
  private statsOy: number = 0;

  /** 打开统计信息窗口 */
  openStatsWindow(): void {
    this.statsOpen = true;
    this.dialog = null;
    this.menuOpenId = '';
    this.draw();
  }

  /** 统计窗口当前的绘制参数 */
  private statsLayout(): void {
    // 参考像素 → 设备像素：按画布宽度取一个整数感舒服的倍数
    const s = Math.max(1, Math.min(2, this.canvasW / 1500));
    this.statsScale = s;
    this.statsOx = Math.round((this.canvasW - StatsWindowPainter.width() * s) / 2);
    this.statsOy = Math.round((this.canvasH - StatsWindowPainter.height() * s) / 2);
  }

  /** 统计窗口要显示的数据 */
  private statsData(): StatsData {
    const levels: StatsLevel[] = [];
    for (const level of ['初级', '中级', '高级']) {
      levels.push({ level: level, best: GameStats.bestSecondsOf(level), date: GameStats.bestDateOf(level) });
    }
    // 中栏「最佳时间」显示三个难度里最快的那条（最贴近 information.jpg）
    let best = -1;
    let bestDate = '';
    for (const level of ['初级', '中级', '高级']) {
      const s = GameStats.bestSecondsOf(level);
      if (s >= 0 && (best < 0 || s < best)) {
        best = s;
        bestDate = GameStats.bestDateOf(level);
      }
    }
    return {
      bestSeconds: best,
      bestDate: bestDate,
      played: GameStats.played,
      won: GameStats.won,
      currentStreak: GameStats.currentStreak,
      maxStreak: GameStats.maxStreak,
      maxLoseStreak: GameStats.maxLoseStreak,
      perLevel: levels
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
   */
  statsButtonAt(px: number, py: number): string | null {
    if (!this.statsOpen) {
      return null;
    }
    this.statsLayout();
    if (StatsWindowPainter.hitReset(this.statsScale, this.statsOx, this.statsOy, px, py)) {
      return 'reset';
    }
    if (StatsWindowPainter.hitClose(this.statsScale, this.statsOx, this.statsOy, px, py)) {
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

  /** 打开「自定义」对话框（按当前难度的行列数预填） */
  openCustomDialog(): void {
    const cfg = GameController.configOf(this.difficulty);
    this.customSpec = CustomField.specOf(cfg.rows, cfg.cols, cfg.mines);
    this.dialog = null;
    this.menuOpenId = '';
    this.draw();
  }

  /** 自定义对话框 + 数字键盘的摆放位置（设备像素） */
  private customLayout(): void {
    const s = this.dialogScale;
    const dlgW = DLG_W * s;
    const keyW = NumKeypad.width() * s;
    const totalW = dlgW + 12 * s + keyW;
    const totalH = Math.max(DLG_H * s, NumKeypad.height() * s);
    this.customOx = Math.round((this.canvasW - totalW) / 2);
    this.customOy = Math.round((this.canvasH - totalH) / 2);
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
    return WinDialogPainter.hitButton(d, this.dialogScale, this.dialogOx, this.dialogOy, px, py);
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
            { id: 'beginner', label: '初级', checked: this.difficulty === Difficulty.Beginner },
            { id: 'intermediate', label: '中级', checked: this.difficulty === Difficulty.Intermediate },
            { id: 'expert', label: '高级', checked: this.difficulty === Difficulty.Expert },
            { id: 'custom', label: '自定义' },
            { id: 'marks', label: '标记(?)', checked: this.questionMarks },
            { id: 'sep2', label: '', separator: true },
            { id: 'sound', label: '声音', checked: SoundPlayer.isEnabled },
            { id: 'sep3', label: '', separator: true },
            { id: 'best', label: '最佳成绩' },
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
