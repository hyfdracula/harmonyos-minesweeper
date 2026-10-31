/**
 * Ripple.ets —— 真 Win7 扫雷「洪泛涟漪淡出」的顺序与节奏
 *
 * 只提供**顺序、节奏与不透明度曲线**，不负责绘制。
 * 调用方（主线程）用 ctx.globalAlpha 或逐帧混合把这套节奏画出来。
 *
 * ============================================================================
 * 一、原版到底有没有涟漪？—— 有，而且原始实现是「按层次依次溶开」
 * ============================================================================
 *
 * 证据链（三份参考实现里两份支持、一份是简化复刻）：
 *
 * 1) [QT] linux-minesweeper-main/src/ui/BoardWidget.cpp:26-31
 *      // A flood-open melts outward from the click: the ripple ring advances a
 *      // tick per cell of distance, and each tile it reaches dissolves with a
 *      // quick linear alpha ramp (the shape of animationAlphaQuickFadeOut, at a
 *      // brisker clip than its half second).
 *      constexpr int kRippleStagger = 1;
 *      constexpr int kRippleFadeTicks = 150 / kTickMs;
 *    —— 明确说这就是照原版的 `animationAlphaQuickFadeOut` 做的。
 *    [QT] BoardWidget.h:129-131 也写：
 *      // the flood ripple hides just-opened cells and uncovers them a few per
 *      // tick in breadth-first order
 *
 * 2) [Lmy] Minesweeper-master/Minesweeper/utf8/core.h:406-409
 *      int* getZeroDevelopNo(int startPoint, unsigned short int *&mapInfo, int row, int col)
 *      { return dbQueue(startPoint, 0, mapInfo, row, col); }
 *    —— 返回的是「冲开块的**序列**数组」，不是一次性结果。
 *    同文件 core.h:326-393 `dbQueue()` 的注释是「双队列层次遍历, 实现平面圆形扩散」，
 *    半径每轮 +0.618（core.h:365），并给每一格记一个**层次号** `flagid`
 *    （core.h:261、core.h:309）；core.h:466-468 那个层次号正是用来
 *    「控制爆炸效果延时」的，说明原版是**按层次依次出现**，不是同时出现。
 *
 * 3) [REV] ReversingMinesweeper-master/Minesweeper/game.c:588-616
 *    `ExpandEmptyBlock()` 用工作表逐格调用 `ShowBlockValue()`，**立即显示、
 *    没有任何延时**。这是复刻者的简化，**不能**当作「原版无涟漪」的证据。
 *
 * ============================================================================
 * 二、逐格出现的顺序与节奏（本文件的取值依据）
 * ============================================================================
 *
 * - **分层方式**：按**切比雪夫距离**（8 邻域的「方环」）分层。
 *   [QT] BoardWidget.cpp:283 原文：
 *       const int ring = qMax(qAbs(pt.x() - origin.x()), qAbs(pt.y() - origin.y()));
 *   也就是 max(|dx|, |dy|)，不是曼哈顿距离。
 *   这一层同时就是引擎 BFS 展开的**距离层级**（8 邻域 BFS 的深度 == 切比雪夫环号），
 *   所以「按方环分层」与「按 BFS 距离分层」在数学上是同一件事。
 *
 * - **每圈间隔 30 ms**：
 *   [QT] BoardWidget.cpp:22 `constexpr int kTickMs = 30;`（共用动画时钟，一 tick 一帧）
 *   [QT] BoardWidget.cpp:30 `constexpr int kRippleStagger = 1;`（每圈 1 tick）
 *   一圈 = 30 ms。**不是每格 30 ms，是每「圈」30 ms**；同一圈里的格子同时开始淡出。
 *
 * - **单格淡出 150 ms**：
 *   [QT] BoardWidget.cpp:31 `constexpr int kRippleFadeTicks = 150 / kTickMs;`（= 5 tick）
 *   形状是线性 alpha 斜坡（原版 `animationAlphaQuickFadeOut`）。
 *   淡出期间后面的圈已经在推进，所以相邻圈的淡出会重叠，前沿看起来是一片柔光而不是硬边。
 *
 * - **总时长** = 最大圈号 × 30 ms + 150 ms。
 *   本工程最大盘面 30 列 × 24 行（见 Theme.ets 的 GRAD_COLS=30 / GRAD_ROWS=24），
 *   两格之间最大的切比雪夫距离 = 29，故最坏总时长 = 29×30 + 150 = **1020 ms**。
 *
 * - **小展开不涟漪**：
 *   [QT] BoardWidget.cpp:271
 *       if (order.size() < 6)   // small opens just pop, like the original
 *       return;
 *   展开格数 < 6 时原版是「直接 pop」（一次性出现），不做涟漪。本文件照此处理，
 *   `stepsFrom()` 在这种情况下返回**空数组**，调用方据此按「一次性显示」处理。
 *
 * ============================================================================
 * 三、[Lmy] 的圆形扩散为什么没有直接采用
 * ============================================================================
 *
 * [Lmy] core.h:326-393 的 `dbQueue()` 是**平面圆形扩散**：半径每轮 +0.618，
 * 格子按「离起点的欧氏半径落入哪一圈」分层，层次号再拿去做延时控制。
 * 视觉上比方环柔和，但它的延时单位是「层次」而不是毫秒，无法直接复现，
 * 而且层次边界取决于 0.618 这个魔数。
 * [QT] 是唯一给出**毫秒数**的实现，可复现，且与本工程引擎的 BFS 展开顺序天然兼容
 * （MinesweeperEngine.floodReveal 用队列，出来的顺序就是距离递增的），
 * 故本文件采用 [QT] 的**切比雪夫方环 + 30 ms/圈 + 150 ms 淡出**。
 *
 * ============================================================================
 * 四、调用方怎么画（重要）
 * ============================================================================
 *
 * 对参与涟漪的格子，一帧里的画法：
 *
 *   1) 先画**未揭开的凸起砖**（normalTileRect）；
 *   2) 再叠**已翻开的地板**（pressedTileRect + 阴影 + 数字），
 *      叠的时候用 `ctx.globalAlpha = Ripple.alphaAt(elapsedMs, step.atMs)`。
 *
 * alpha 从 0 涨到 1 的过程，视觉上就是那块凸起砖被「溶」掉、露出下面的地板。
 * 这与 [QT] BoardWidget.cpp:589-605 + 687-693 的画法等价：
 * 那里是反过来画——先画已翻开的地板，再把凸起砖以 `cover = 1 - dt/5` 的不透明度盖在上面，
 * 等价于地板的 alpha 从 0 涨到 1。
 *
 * 涟漪进行中，被涟漪覆盖的格子**不应该**再走「已翻开」的常规绘制路径，
 * 否则会与叠画的地板打架。
 */

/** 涟漪里的一格：它在什么时候开始淡入 */
export interface RippleStep {
  /** 格索引（row * cols + col） */
  cell: number;
  /** 该格开始淡入的时刻（毫秒，从本次展开开始算） */
  atMs: number;
}

export class Ripple {
  // ------------------------------------------------------------ 节奏常量

  /**
   * 每「圈」之间的间隔（毫秒）。
   *
   * 依据 [QT] BoardWidget.cpp:22 `kTickMs = 30` 与 :30 `kRippleStagger = 1`。
   * 注意是**每圈** 30 ms，不是每格 30 ms：同一圈里的格子同时开始淡出。
   */
  static readonly STEP_MS: number = 30;

  /**
   * 单格从「凸起砖」溶成「已翻开地板」的淡出时长（毫秒）。
   *
   * 依据 [QT] BoardWidget.cpp:31 `kRippleFadeTicks = 150 / kTickMs`（= 5 tick = 150 ms）。
   * 形状是线性 alpha 斜坡（原版 animationAlphaQuickFadeOut）。
   */
  static readonly FADE_MS: number = 150;

  /**
   * 展开格数少于这个值就不做涟漪（一次性直接显示）。
   *
   * 依据 [QT] BoardWidget.cpp:271
   *   `if (order.size() < 6)   // small opens just pop, like the original`
   */
  static readonly MIN_CELLS: number = 6;

  /**
   * 最大圈号：30 列 × 24 行的盘面上，两格之间最大的切比雪夫距离。
   *
   * 依据 Theme.ets 的 GRAD_COLS = 30 / GRAD_ROWS = 24（最大棋盘）。
   */
  static readonly MAX_RING: number = 29;

  /**
   * 涟漪的最长总时长（毫秒）= 最大圈号 × 每圈间隔 + 单格淡出。
   *
   * 29 × 30 + 150 = 1020。
   */
  static readonly TOTAL_MS: number = 1020;

  // ------------------------------------------------------------ 顺序与节奏

  /**
   * 算出本次洪泛每一格的淡入时刻。
   *
   * @param startCell 被点的那一格的索引（row * cols + col）
   * @param opened    本次展开的所有格索引（引擎 reveal() 的 outcome.opened）
   * @param rows      棋盘行数
   * @param cols      棋盘列数
   * @returns 每格的淡入时刻；**展开格数不足 MIN_CELLS 时返回空数组**（原版直接 pop）
   */
  static stepsFrom(startCell: number, opened: number[], rows: number, cols: number): RippleStep[] {
    const steps: RippleStep[] = [];
    if (rows <= 0 || cols <= 0) {
      return steps;
    }
    if (startCell < 0 || startCell >= rows * cols) {
      return steps;
    }
    // 原版小展开直接 pop，不做涟漪（[QT] BoardWidget.cpp:271）
    if (opened.length < Ripple.MIN_CELLS) {
      return steps;
    }

    const sr = Math.floor(startCell / cols);
    const sc = startCell - sr * cols;

    // 先算每一格的圈号（切比雪夫距离 = 8 邻域的方环号）
    const rings: number[] = [];
    let maxRing = 0;
    for (let i = 0; i < opened.length; i++) {
      const cell = opened[i];
      if (cell < 0 || cell >= rows * cols) {
        continue;
      }
      const r = Math.floor(cell / cols);
      const c = cell - r * cols;
      const dr = Math.abs(r - sr);
      const dc = Math.abs(c - sc);
      const ring = Math.max(dr, dc);
      rings.push(ring);
      if (ring > maxRing) {
        maxRing = ring;
      }
    }

    // 按圈分桶再摊平：同一圈保持引擎给出的顺序（先进先出），且整体按圈号升序。
    // 用分桶而不是 sort，是为了保证顺序稳定、且不受引擎返回顺序之外的任何影响。
    const buckets: RippleStep[][] = [];
    for (let i = 0; i <= maxRing; i++) {
      buckets.push([]);
    }
    let k = 0;
    for (let i = 0; i < opened.length; i++) {
      const cell = opened[i];
      if (cell < 0 || cell >= rows * cols) {
        continue;
      }
      const ring = rings[k];
      k++;
      const step: RippleStep = { cell: cell, atMs: ring * Ripple.STEP_MS };
      const bucket: RippleStep[] = buckets[ring];
      bucket.push(step);
    }
    for (let i = 0; i <= maxRing; i++) {
      const bucket = buckets[i];
      for (let j = 0; j < bucket.length; j++) {
        steps.push(bucket[j]);
      }
    }
    return steps;
  }

  /**
   * 某一格在 elapsedMs 时刻的不透明度（0..1，淡入）。
   *
   * - 还没轮到（elapsedMs <= atMs）：0，完全没出现
   * - 淡出中：线性从 0 涨到 1，历时 FADE_MS
   * - 淡出完：1，完全显示
   *
   * 线性斜坡的依据 [QT] BoardWidget.cpp:26-31（原版 animationAlphaQuickFadeOut 的形状）。
   *
   * @param elapsedMs 从本次展开开始算起已经过的毫秒数
   * @param atMs      该格的淡入起始时刻（RippleStep.atMs）
   */
  static alphaAt(elapsedMs: number, atMs: number): number {
    if (elapsedMs <= atMs) {
      return 0;
    }
    const dt = elapsedMs - atMs;
    if (dt >= Ripple.FADE_MS) {
      return 1;
    }
    return dt / Ripple.FADE_MS;
  }

  /**
   * 这一串步骤实际要跑多久（毫秒）。
   *
   * = 最后一格的起始时刻 + 单格淡出时长。
   * 用来让调用方知道什么时候可以把涟漪状态清掉。
   *
   * 步骤为空（没做涟漪）时返回 0。
   */
  static totalMsOf(steps: RippleStep[]): number {
    if (steps.length === 0) {
      return 0;
    }
    let last = 0;
    for (let i = 0; i < steps.length; i++) {
      if (steps[i].atMs > last) {
        last = steps[i].atMs;
      }
    }
    return last + Ripple.FADE_MS;
  }
}
