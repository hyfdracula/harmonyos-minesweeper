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

  /**
   * 爆炸动画的**取证用慢放倍率**。
   *
   * 为什么需要它：设备端一次截图要 497ms、一次点击要 485ms，
   * 而原版的爆炸只有 1 秒（23 帧）—— 快门比动画窗口还慢，
   * 一次连拍最多压住 1 帧，23 帧根本抓不齐。
   * 慢放 8 倍后爆炸持续 8 秒，快门就能连着抓好几帧，用来**证明帧号是递增的**。
   *
   * **发布包必须是 1**（原版的 1 秒 / 23 帧）。
   * 取证用的那次慢放（= 8）只存在于本机取证期间，证据见
   * docs\ANIM-FRAMES.md；提交时这个常量是 1。
   */
  static readonly EXPLODE_SLOWMO: number = 1;

  static tripActive: boolean = false;
  static tripFrame: number = 0;
  static tripCell: number = -1;
  /**
   * 爆炸动画已经播了多久（ms）。
   *
   * 以前是**按帧计数**推进的（每 tick 帧号 +1），而 tick 的间隔是 30ms，
   * 于是 23 帧只用了 23×30 = 690ms —— 比原版的 1 秒短了三分之一。
   * 原版 animationMineSweeper_MineTrip.xml 是 1 秒 / 23 帧，
   * 所以这里改成**按时间**推进，EXPLODE_FRAME_MS 才是真正被用上的那个常量。
   */
  static tripElapsed: number = 0;

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
    Anim.tripElapsed = 0;
    Anim.tripCell = cellIndex;
  }

  static stopTrip(): void {
    Anim.tripActive = false;
    Anim.tripFrame = 0;
    Anim.tripElapsed = 0;
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
      // 爆炸按**时间**推进（原来按帧计数，实际只跑了 690ms）
      const frameMs = Anim.EXPLODE_FRAME_MS * Anim.EXPLODE_SLOWMO;
      Anim.tripElapsed += dtMs;
      const total = frameMs * Anim.EXPLODE_FRAMES;
      if (Anim.tripElapsed >= total) {
        Anim.tripActive = false;
        Anim.tripFrame = 0;
        Anim.tripElapsed = 0;
        Anim.tripCell = -1;
      } else {
        Anim.tripFrame = Math.min(Anim.EXPLODE_FRAMES - 1,
                                  Math.floor(Anim.tripElapsed / frameMs));
        more = true;
      }
    }
    if (Anim.winActive) {
      Anim.winElapsed += dtMs;
      if (Anim.winElapsed < Anim.winEndMs()) {
        more = true;
      } else {
        Anim.stopWin();
      }
    }
    return more;
  }

  /**
   * 胜利动画什么时候结束（ms）。
   *
   * 原版：扫描条扫完（3 秒）之后，最后一束拆雷光束放完就结束
   * （linux-minesweeper：m_winEnd = max(3000, lastBeamStart + 2000)）。
   *
   * 我们以前写死 3000 + 52.63×38 = 5000ms，可是光束是在扫描条**扫到那一行**
   * 才开始放的 —— 雷在最后几行时，最后一束光束要到 3000ms 之后才开始，
   * 5000ms 就会**把光束砍掉一半**。所以结束时刻必须按最后一束光束算。
   */
  static winEndMs(): number {
    let end = Anim.SWEEP_MS;
    for (let i = 0; i < Anim.beams.length; i++) {
      const e = Anim.beams[i].startMs + Anim.DISARM_FRAME_MS * Anim.DISARM_FRAMES;
      if (e > end) {
        end = e;
      }
    }
    return end;
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

  // ------------------------------------------------------------ 扫描条几何

  /**
   * 胜利扫描条要画的矩形 —— **已经按棋盘矩形裁剪过**。
   *
   * 返回 [srcX, srcY, srcW, srcH, dy, dw, dh]，前四项是 otherSheet 上的源矩形，
   * 后三项是画到画布上的目标矩形（dx 由调用方给，就是棋盘左沿）。
   * 没在扫的时候返回 null。
   *
   * 为什么要裁：
   *   原版（linux-minesweeper，BoardWidget::drawScanBar / Theme.h）是
   *   `p.setClipRect(m_grid)` —— 扫描条被**裁在棋盘矩形内**，
   *   扫到最上面时整条消失，看不到「条停在棋盘顶上」。
   *   我们以前是把整条直接画出来，于是 p=1 时条停在棋盘上沿外面，不消失。
   *
   * 高度按原版保持长宽比：
   *   barH = grid.width() * src.height() / src.width()
   *   （直接用 62*unit 会被拉变形：9×9 的盘面 275:62 的比例对不上）
   *
   * 行程不变：p=0 时条的下沿贴棋盘下沿，p=1 时条整个离开棋盘上沿。
   */
  static scanBarRect(boardTop: number, boardBottom: number, boardW: number): number[] | null {
    if (!Anim.winActive) {
      return null;
    }
    const srcW = Anim.SCAN_BAR[2];
    const srcH = Anim.SCAN_BAR[3];
    const barH = Math.max(1, Math.round(boardW * srcH / srcW));
    const boardH = boardBottom - boardTop;
    const p = Math.min(1, Anim.winElapsed / Anim.SWEEP_MS);
    const barY = boardBottom - barH - p * boardH;   // 自下而上
    // 裁到棋盘矩形内
    const top = Math.max(barY, boardTop);
    const bottom = Math.min(barY + barH, boardBottom);
    if (bottom <= top) {
      return null;                                   // 整条在棋盘外（扫完了）
    }
    const visible = bottom - top;
    // 可见段对应到源精灵上的哪一段
    const scale = srcH / barH;
    const sy = Anim.SCAN_BAR[1] + Math.round((top - barY) * scale);
    const sh = Math.max(1, Math.min(srcH, Math.round(visible * scale)));
    return [Anim.SCAN_BAR[0], sy, srcW, sh, top, boardW, visible];
  }
}
