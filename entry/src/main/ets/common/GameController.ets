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
  inputLocked: boolean = false;
  /** 结束对话框（原版 Win7 风格）；null 表示没开 */
  dialog: DlgSpec | null = null;
  private dialogScale: number = 1;
  private dialogOx: number = 0;
  private dialogOy: number = 0;
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
    const cfg = GameController.configOf(d);
    this.startNewGame(cfg.rows, cfg.cols, cfg.mines);
  }

  /** 同难度重开 */
  restart(): void {
    const cfg = GameController.configOf(this.difficulty);
    this.startNewGame(cfg.rows, cfg.cols, cfg.mines);
  }

  startNewGame(rows: number, cols: number, mines: number): void {
    this.engine.reset(rows, cols, mines);
    this.seconds = 0;
    this.stopTimer();
    this.gameOverNotified = false;
    this.dialog = null;
    // 新局回到「整盘刚好放下」的视角
    this.userZoomed = false;
    this.panX = 0;
    this.panY = 0;
    this.layout();
    this.draw();
    SoundPlayer.play(Sound.GAME_START);
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

  /** 平移量夹紧：棋盘不能被拖出画布；整盘放得下时不允许平移 */
  private clampPan(): void {
    const halfW = (this.canvasW - this.frameW) / 2;
    const halfH = (this.canvasH - this.frameH) / 2;
    if (halfW <= 0) {
      this.panX = 0;
    } else {
      this.panX = Math.max(-halfW, Math.min(halfW, this.panX));
    }
    if (halfH <= 0) {
      this.panY = 0;
    } else {
      this.panY = Math.max(-halfH, Math.min(halfH, this.panY));
    }
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
      this.drawStatusStrip(ctx);
      this.drawDialog(ctx);
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
        } else {
          const frame = gradientFrame(r, c, e.rowCount, e.colCount);
          this.atlas.drawLogical(ctx, this.atlas.boardSheet, normalTileRect(frame), x, y, u);
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
            this.atlas.drawLogical(ctx, this.atlas.boardSheet, RECT_HILITE, x, y, u);
          }
        }
      }
    }
  }

  /**
   * 底部状态条：时钟+计时在左，雷数+雷图标在右，中间大片留空。
   * 位置按原版反推：两组分别贴着棋盘的左右沿，留白随棋盘宽度缩放。
   */
  private drawStatusStrip(ctx: CanvasRenderingContext2D): void {
    const u = this.unit;
    const e = this.engine;
    const boardBottom = this.boardY + e.rowCount * this.tile;
    const boardRight = this.boardX + e.colCount * this.tile;
    const margin = stripMargin(e.colCount) * u;

    const clockX = this.boardX + margin;
    const clockY = boardBottom + Math.round((STRIP_BAND - STRIP_CLOCK_SIZE) / 2) * u;
    const timeX = clockX + (STRIP_CLOCK_SIZE + STRIP_GAP) * u;
    const timeY = boardBottom + Math.round((STRIP_BAND - STRIP_PANEL_H) / 2) * u;

    const iconX = boardRight - margin - STRIP_CLOCK_SIZE * u;
    const iconY = clockY;
    const mineX = iconX - (STRIP_GAP + STRIP_PANEL_W) * u;
    const mineY = timeY;

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
        // 踩雷：原版是三段爆炸声
        SoundPlayer.playSequence([Sound.BOMB_START, Sound.BOMB_RUN, Sound.BOMB_END], 260);
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
    this.buildDialog(s === GameState.Won);
    SoundPlayer.play(s === GameState.Won ? Sound.GAME_WIN : Sound.GAME_LOSE);
    const cb = this.onGameOver;
    if (cb !== null) {
      cb(s === GameState.Won);
    }
  }

  // ------------------------------------------------------------------ 结束对话框

  /** 生成结束对话框（原版 Win7 风格） */
  private buildDialog(won: boolean): void {
    GameStats.record(won, this.seconds).catch(() => {
      // 存档失败不影响对局
    });
    const isNewBest = won && (GameStats.bestSeconds < 0 || this.seconds <= GameStats.bestSeconds);
    if (won) {
      this.dialog = WinDialogPainter.winSpec(this.seconds, GameStats.played, GameStats.won,
        GameStats.percent, GameStats.bestText, GameStats.bestDate, isNewBest);
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

  /** 组件销毁时调用：停掉计时器，别让它继续往已销毁的画布上画 */
  dispose(): void {
    this.stopTimer();
    this.context = null;
  }

  /** 应用切到后台：暂停计时（手机上放口袋不该继续耗秒数） */
  pauseForBackground(): void {
    if (this.timerHandle !== -1) {
      clearInterval(this.timerHandle);
      this.timerHandle = -1;
    }
  }

  /** 应用回到前台：若正在游戏中则恢复计时 */
  resumeFromBackground(): void {
    if (this.engine.gameState === GameState.Playing) {
      this.startTimer();
    }
  }

  /** 页面重建（折叠/旋转）后恢复：接着原局继续，计时器重新走 */
  resume(): void {
    if (this.engine.gameState === GameState.Playing) {
      this.startTimer();
    }
    if (this.context !== null) {
      this.layout();
      this.draw();
    }
  }
}
