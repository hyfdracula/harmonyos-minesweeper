/**
 * Anim.ets —— 原版 Windows 7 扫雷的动画
 *
 * 帧表**不是猜的**，来自原版资源的权威索引：
 *   linux-minesweeper/src/ui/Theme.h（该实现把 Win7 扫雷自己的 UI XML 拆成了精灵表，
 *   并注明每张图是 2 倍分辨率存储，逻辑坐标要 ×2 才是存储像素）。
 *
 * 三组动画都在 otherSheet.png 里：
 *
 * 1) **踩雷爆炸**（原版 animationMineSweeper_MineTrip.xml，23 帧 / 1 秒）
 *    帧矩形 = {728 + 59*(f%3), 59*(f/3), 57, 57}
 *    —— 3 列 × 8 行排布，帧与帧之间有 **2px 空隙**（步距 = 57+2 = 59；
 *    按「裸帧宽」切会让爆炸每帧抖 2px）。
 *    绘制偏移 = (-18,-18)（原版 MineExplodeX/YOffset，帧会溢出格子）。
 *
 * 2) **胜利拆雷光束**（原版 animationMinesweeper_MineDisarm.xml，38 帧 / 2 秒）
 *    帧矩形 = {52*(f%7), 152*(f/7), 50, 150}（蓝色主题 x0=0，绿色主题 x0=364）
 *    —— 7 列 × 6 行，同样有 2px 空隙。
 *    光束自带一份该格的方砖副本（在 50×150 里的 (17,69) 处），会盖住格子上下的内容。
 *    绘制偏移 = (-18,-69)。
 *
 * 3) **胜利扫描条**（随拆雷一起，自下而上扫过棋盘，3 秒）
 *    矩形 = {0, 912, 275, 62}，横向拉伸到棋盘宽度。
 *
 * 本文件的矩形都是**逻辑坐标**（存储像素要 ×SPRITE_SCALE）。
 */

/** 一束正在播放的拆雷光束 */
export interface Beam {
  /** 格索引 */
  cell: number;
  /** 光束开始的时刻（ms，从胜利动画开始算） */
  startMs: number;
}

export class Anim {
  // ------------------------------------------------------------ 踩雷爆炸

  /** 爆炸帧数（原版 MineTrip.xml） */
  static readonly EXPLODE_FRAMES: number = 23;
  /** 每帧时长：23 帧 / 1 秒 */
  static readonly EXPLODE_FRAME_MS: number = 1000 / 23;
  /** 爆炸帧在 otherSheet 上的起始 x（逻辑坐标） */
  static readonly EXPLODE_X0: number = 728;
  /** 帧步距 = 帧宽 57 + 2px 空隙 */
  static readonly EXPLODE_PITCH: number = 59;
  /** 爆炸帧的绘制偏移（相对格子左上角，逻辑坐标） */
  static readonly EXPLODE_OFFSET: number[] = [-18, -18];

  static tripActive: boolean = false;
  static tripFrame: number = 0;
  static tripCell: number = -1;

  /** 爆炸帧的源矩形（逻辑坐标） */
  static explodeRect(frame: number): number[] {
    const f = Math.max(0, Math.min(Anim.EXPLODE_FRAMES - 1, frame));
    return [
      Anim.EXPLODE_X0 + Anim.EXPLODE_PITCH * (f % 3),
      Anim.EXPLODE_PITCH * Math.floor(f / 3),
      57, 57
    ];
  }

  static startTrip(cellIndex: number): void {
    Anim.tripActive = true;
    Anim.tripFrame = 0;
    Anim.tripCell = cellIndex;
  }

  static stopTrip(): void {
    Anim.tripActive = false;
    Anim.tripFrame = 0;
    Anim.tripCell = -1;
  }

  // ------------------------------------------------------ 胜利拆雷 + 扫描条

  /** 拆雷光束帧数（原版 MineDisarm.xml） */
  static readonly DISARM_FRAMES: number = 38;
  /** 每帧时长：38 帧 / 2 秒 */
  static readonly DISARM_FRAME_MS: number = 2000 / 38;
  /** 扫描条扫一遍的时长（原版动画 XML 写的是 3 秒） */
  static readonly SWEEP_MS: number = 3000;
  /** 扫描条的源矩形（逻辑坐标，在 otherSheet 上） */
  static readonly SCAN_BAR: number[] = [0, 912, 275, 62];
  /** 拆雷光束的绘制偏移（相对格子左上角，逻辑坐标） */
  static readonly DISARM_OFFSET: number[] = [-18, -69];

  static winActive: boolean = false;
  static winElapsed: number = 0;
  static beams: Beam[] = [];

  /**
   * 开始胜利动画。
   *
   * @param mineCells 每颗雷的格索引
   * @param startTimes 每颗雷的拆解起始时刻（ms），由调用方按扫描条扫到该行的时间算好
   */
  static startWin(mineCells: number[], startTimes: number[]): void {
    Anim.winActive = true;
    Anim.winElapsed = 0;
    Anim.beams = [];
    for (let i = 0; i < mineCells.length; i++) {
      Anim.beams.push({ cell: mineCells[i], startMs: startTimes[i] });
    }
  }

  static stopWin(): void {
    Anim.winActive = false;
    Anim.winElapsed = 0;
    Anim.beams = [];
  }

  /** 拆雷光束的源矩形（逻辑坐标，蓝色主题） */
  static disarmRect(frame: number): number[] {
    const f = Math.max(0, Math.min(Anim.DISARM_FRAMES - 1, frame));
    return [52 * (f % 7), 152 * Math.floor(f / 7), 50, 150];
  }

  /**
   * 推进动画。
   *
   * @param dtMs 距上次推进的毫秒
   * @return true = 还需要继续重绘
   */
  static tick(dtMs: number): boolean {
    let more = false;
    if (Anim.tripActive) {
      Anim.tripFrame++;
      if (Anim.tripFrame >= Anim.EXPLODE_FRAMES) {
        Anim.tripActive = false;
        Anim.tripCell = -1;
      } else {
        more = true;
      }
    }
    if (Anim.winActive) {
      Anim.winElapsed += dtMs;
      if (Anim.winElapsed < Anim.SWEEP_MS + Anim.DISARM_FRAME_MS * Anim.DISARM_FRAMES) {
        more = true;
      } else {
        Anim.stopWin();
      }
    }
    return more;
  }

  /**
   * 某一束光束当前该显示第几帧；-1 表示还没开始或已经放完。
   *
   * @param index 光束序号
   */
  static beamFrame(index: number): number {
    if (!Anim.winActive || index < 0 || index >= Anim.beams.length) {
      return -1;
    }
    const dt = Anim.winElapsed - Anim.beams[index].startMs;
    if (dt < 0) {
      return -1;
    }
    const f = Math.floor(dt / Anim.DISARM_FRAME_MS);
    if (f >= Anim.DISARM_FRAMES) {
      return -1;
    }
    return f;
  }

  /** 全部动画都结束了 */
  static isIdle(): boolean {
    return !Anim.tripActive && !Anim.winActive;
  }
}
