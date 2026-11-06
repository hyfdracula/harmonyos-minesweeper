/**
 * DealIn.ets —— 真 Win7 扫雷「新局发牌」动画（deal-in）的逐格顺序与时间表
 *
 * 只提供**顺序与时间**，不负责绘制。调用方（主线程）用 frameAt() 拿到的布尔数组
 * 逐格判断「这一格还该画成压平的底砖，还是已经弹起来了」。
 *
 * ============================================================================
 * 一、原版现象：整盘先压平，方砖再从四个角一波一波弹起
 * ============================================================================
 *
 * 证据链：
 *
 * 1) [QT] linux-minesweeper-main/src/ui/BoardWidget.h:39-42
 *      // The Win7 deal-in: the fresh board starts pressed flat and the tiles
 *      // pop up in diagonal waves from all four corners. MainWindow calls this
 *      // after each reset/restart.
 *      void playIntro();
 *
 * 2) [Lmy] Minesweeper-master/Minesweeper/Minesweeper.cpp:1476-1478
 *      新局先把整盘画成**压平**的浅色底砖：
 *        for (int m = 0; m < row; m++)
 *            for (int n = 0; n < col; n++)
 *                LightShadow(hdc, m, n, hdcMem, 3, 0);
 *      LightShadow 的第 5/6 个参数是**源贴图坐标** (rowSrc, colSrc)
 *      （Minesweeper.cpp:1564、1579；图块 18x18，Minesweeper.h:56-57），
 *      所以这里是 Minesweeper.bmp 的 (rowSrc=3, colSrc=0) 那块 —— 浅色压平底砖。
 *
 * 3) [Lmy] Minesweeper-master/Minesweeper/Minesweeper.cpp:1495 + 1499-1508
 *      再按 getFirstPaintNo() 给出的序列逐格**弹起**（源贴图换成
 *      (rowSrc=4, colSrc=0) 那块深蓝方砖），每弹一格延时一次：
 *        int *ptemp1 = getFirstPaintNo(row, col);//初始化动画贴图块序列数组
 *        ...
 *        for (int i = 0; i < brickNumber; i++)
 *        {
 *            LightShadow(hdc, ptemp1[i] / col, ptemp1[i] % col, hdcMem, 4, 0);
 *            speed((int)(1100.0 / (row * col)), NULL, 0);//效果延时控制
 *        }
 *      speed() 内部就是 Sleep()（Minesweeper.cpp:1843-1864），所以这是真延时。
 *
 * 4) [QT] linux-minesweeper-main/src/ui/BoardWidget.cpp:24
 *      constexpr int kIntroMs = 700;      // deal-in wave spread; Win7's 1100ms drags
 *      —— 复刻版把发牌压缩到 700 ms，并注明「Win7 的 1100 ms 太拖沓」。
 *      本工程按**原版的 1100 ms** 走。
 *
 * ============================================================================
 * 二、顺序算法：四个角出发的「按长短边比例拉伸过的对角波」
 * ============================================================================
 *
 * 原始顺序来自 [Lmy] Minesweeper-master/Minesweeper/core.h:156-191 的
 * `int* getFirstPaintNo(int row, int col)`，它返回的是一个**格索引的序列数组**
 * （不是距离场）。逐条拆开：
 *
 * 1) 四个波源「种子格」（core.h:159-162）：
 *      int startNo[4] = { 0,
 *          col - 1 - col % 2,
 *          (row - 1 - row % 2) * col,
 *          (row - row % 2) * col - 1 - col % 2 };
 *    取的是**偶数对齐**的角，不是盘面的真实角：行/列数为奇数时种子落在倒数第二
 *    行/列（9x9 是 (0,0) / (0,7) / (7,0) / (7,7)，不是 (0,8)）。
 *    这样四个种子各管一块「坐标奇偶性」不同的区域，四块不重不漏地铺满整盘。
 *    —— 已用 rows/cols 各 1..30 的全部 900 种组合逐个验证：输出恒为 rows*cols 个
 *    互不相同、且都落在盘内的合法格索引（含 1 行 / 1 列的退化盘面）。
 *
 * 2) 长短边比例（core.h:163-165）：
 *      int max = (row >= col) ? row : col;
 *      int min = (row >= col) ? col : row;
 *      int ratio = (int)ceil((float)max / (float)min);
 *    —— 长边上走一步要顶短边 ratio 步，四条波才会在**盘面正中相遇**，
 *    而不是长边那边先跑完。
 *
 * 3) 枚举（core.h:168-188）：i 沿长边（0 .. 2*max-1），j 沿短边（0 .. 2*min-1），
 *    只有 `i / ratio >= j` 的组合才继续（core.h:172，整数除法）。
 *    每一组 (i, j) 再对 4 个波源各算一格（core.h:174-184）：
 *      长边偏移 = ±(i - ratio * j) * 2      （沿长边，只走偶数步）
 *      短边偏移 = ±j * 2                    （沿短边，只走偶数步）
 *    越界的跳过（core.h:176-177 的两个不等式）。
 *
 * 4) 于是某格所属的**波号**就是它被枚举到时的那个 i，而 i 等于
 *      (dMaj + ratio * dMin) / 2
 *    （dMaj = 到该波源沿长边的距离，dMin = 沿短边的距离）。
 *    i = 0 那一拍四个种子格同时弹起；i 越大越靠盘面中心。
 *    → 所以它**不是曼哈顿距离，也不是切比雪夫距离**，
 *      而是一族「按长短边比例拉伸过的对角线」；四个角的波在中线相遇。
 *
 * 5) 与 [QT] 复刻版的差别（BoardWidget.cpp:138-151）：
 *    复刻版用的是同一个公式，但波源直接取**真实四角** {0, rows-1} x {0, cols-1}，
 *    而不是原版的偶数对齐种子。两者只在**行数或列数为奇数**的盘面上有差别：
 *      9x9   波号差 1 拍     16x16 / 16x30 / 24x30 / 10x10 完全一致
 *      9x30  波号差 2 拍
 *    本文件按**原版 core.h** 实现（它才是「复刻 Win7 行为」的那个）。
 *
 * ============================================================================
 * 三、时间表：1100 ms 怎么摊到每一格
 * ============================================================================
 *
 * - **1100 ms 是整段发牌的总预算**，平均摊到每一格：
 *      [Lmy] Minesweeper.cpp:1502  speed((int)(1100.0 / (row * col)), NULL, 0);
 *   注意 speed() 是「画完这一格**之后**才延时」，所以第 k 格（k 从 0 起）
 *   在 k * 每格延时 处弹出。
 *
 * - 本文件对**时间**做了一处取舍（**顺序完全照原版，没动**）：
 *   原版把每格延时**截断成整毫秒**（C 的 (int) 转换），实际跨度是
 *   n * floor(1100 / n) ms：9x9 -> 1053 ms、16x16 -> 1024 ms、
 *   16x30 -> 960 ms、24x30 -> 只剩 720 ms。盘面越大丢得越多，
 *   最大盘（30 列 x 24 行 = 720 格，Theme.ets 的 GRAD_COLS/GRAD_ROWS）
 *   只有原版预算的三分之二。
 *   改为**等比分配并四舍五入到整毫秒**：第 k 格在 round(k * 1100 / n) ms 弹出。
 *   弹出先后与原版逐格一致，但整段动画正好铺满 1100 ms。
 *
 * ============================================================================
 * 三之二、中断：原版「按下滑鼠就断」（2026-11-06 补）
 * ============================================================================
 *
 * 发牌不是「必须看完 1100 ms」的动画 —— **按下滑鼠就断**。
 * 依据 [Lmy] Minesweeper.cpp:1843-1879 的 `speed()`：
 *
 *     //鼠标消息停止动画效果
 *     if ((optionFlag & OF_DRAW) && (!PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)
 *         || (msg.message != WM_LBUTTONDOWN && msg.message != WM_RBUTTONDOWN)))
 *     { ... Sleep(dwMilliseconds); ... }
 *     else
 *     {
 *         msgFlag = true;
 *         PlaySound(NULL, NULL, SND_ASYNC);   // ← 连声音一起停
 *     }
 *
 * 命中 else 之后：`msgFlag = true` 让**后续每一次 speed() 都不再 Sleep**，
 * 于是剩下的格子在同一瞬间全部画完（**不是冻结在半截**）；
 * 同时 `PlaySound(NULL,...)` 把正在播的配乐也停掉。
 * 注意判据是**消息类型**，不看坐标 —— 鼠标在窗口任何位置按下都算；
 * 而且左键**和**右键都算。
 *
 * 参考实现那段发牌循环上方还留着原作者的注释：
 *     //bug	WM_LBUTTONDOWN停止动画, WM_LBUTTONUP消息会初始化mapInfo
 * —— 它把这当成自己的 bug，但那是原版的真实表现。
 *
 * 本项目的做法见 `GameController.interruptDealIn()`：
 * 按下（`TouchType.Down`）→ `dealActive = false`、`dealFlags` 清空
 * （清空的直接效果就是每格都算「已弹起」，即**瞬间画完**）、停掉 firstPaint。
 *
 * 为什么非做不可：原版靠**阻塞循环里的 PeekMessage** 自然做到「按下就断」，
 * 我们是非阻塞的帧定时器，不显式打断的话，发牌动画会与翻开的涟漪**同时跑** ——
 * 用户 2026-11-06 看到的就是「一半格子还在波浪弹起、另一半已经在涟漪淡入」。

 *
 * ============================================================================
 * 四、格索引约定
 * ============================================================================
 *
 * cell = row * cols + col，与 Ripple.ets 的 RippleStep.cell 同一种约定，
 * 也和原版 `LightShadow(hdc, ptemp1[i] / col, ptemp1[i] % col, ...)`
 * （Minesweeper.cpp:1501）的拆法一致。
 *
 * ============================================================================
 * 五、调用方怎么用
 * ============================================================================
 *
 * 1) 每次新局开始时记下起始时刻；每帧算出 elapsedMs。
 * 2) frameAt(elapsedMs, rows, cols) 返回长度 rows*cols 的布尔数组：
 *      false = 这一格**还没弹起**（画浅色压平底砖）
 *      true  = 这一格**已经弹起**（画深蓝方砖）
 * 3) 全部为 true 即发牌结束；也可以直接拿 TOTAL_MS 当总时长。
 */

/** 发牌动画的总时长（毫秒） */
const DEAL_IN_TOTAL_MS: number = 1100;

/**
 * 第 index 格（发牌顺序里的序号，从 0 起）在第几毫秒弹出。
 *
 * 等比分配 + 四舍五入，见文件头「三、时间表」里的取舍说明。
 */
function dealInAtMs(index: number, total: number): number {
  return Math.round((index * DEAL_IN_TOTAL_MS) / total);
}

/**
 * 按原版 getFirstPaintNo() 的规则，枚举出所有格子的**弹出顺序**。
 *
 * 返回值是格索引数组（row * cols + col），下标即发牌顺序。
 * 逐条依据见文件头「二、顺序算法」里标注的 core.h 行号。
 */
function dealInSequence(rows: number, cols: number): number[] {
  const seq: number[] = [];
  const total: number = rows * cols;
  if (rows <= 0 || cols <= 0) {
    return seq;
  }

  // core.h:163-165 —— 长边 / 短边 / 比例
  const maxSide: number = rows >= cols ? rows : cols;
  const minSide: number = rows >= cols ? cols : rows;
  const ratio: number = Math.ceil(maxSide / minSide);

  // core.h:159-162 —— 四个偶数对齐的波源种子格
  const seedCol: number = cols - 1 - (cols % 2);
  const seedRow: number = rows - 1 - (rows % 2);
  const seeds: number[] = [
    0,
    seedCol,
    seedRow * cols,
    seedRow * cols + seedCol
  ];

  // core.h 的 (max == col)：长边在列上则为 true（行数 <= 列数）
  const wide: boolean = maxSide === cols;

  // core.h:168-188 —— 枚举
  for (let i = 0; i < 2 * maxSide; i++) {
    for (let j = 0; j < 2 * minSide; j++) {
      // core.h:172 —— 只有 i / ratio >= j 的组合才继续（整数除法）
      if (Math.floor(i / ratio) < j) {
        continue;
      }
      // 沿长边走的主轴步数（core.h:179-183 里的 (i - ratio * j)）
      const major: number = i - ratio * j;
      for (let k = 0; k < 4; k++) {
        // core.h:176-177 —— 越界检查
        const majorBound: number = wide
          ? (maxSide - 1 - (k % 2))
          : (maxSide - 1 - Math.floor(k / 2));
        const minorBound: number = wide
          ? (minSide - 1 - Math.floor(k / 2))
          : (minSide - 1 - (k % 2));
        if (2 * major > majorBound || 2 * j > minorBound) {
          continue;
        }
        // core.h:179-183 —— 由种子格推出该格的行优先索引
        const base: number = seeds[k];
        let cell: number = 0;
        if (wide) {
          const majorSign: number = (k % 2) === 1 ? -1 : 1;
          const minorSign: number = Math.floor(k / 2) === 1 ? -1 : 1;
          cell = base + majorSign * major * 2 + minorSign * j * 2 * cols;
        } else {
          const majorSign: number = Math.floor(k / 2) === 1 ? -1 : 1;
          const minorSign: number = (k % 2) === 1 ? -1 : 1;
          cell = base + majorSign * major * 2 * cols + minorSign * j * 2;
        }
        if (cell >= 0 && cell < total) {
          seq.push(cell);
        }
      }
    }
  }
  return seq;
}

/** 发牌动画里的一格：它在什么时候弹起来 */
export interface DealInOrder {
  /** 格索引（row * cols + col） */
  cell: number;
  /** 该格弹起的时刻（毫秒，从本次发牌开始算） */
  atMs: number;
}

export class DealIn {
  /**
   * 整段发牌动画的总时长（毫秒）。
   *
   * 依据 [Lmy] Minesweeper-master/Minesweeper/Minesweeper.cpp:1502
   *   speed((int)(1100.0 / (row * col)), NULL, 0);
   * 1100 ms 是原版给整段发牌的**总预算**（每格摊一份）。
   * 复刻版 [QT] BoardWidget.cpp:24 把它压到 700 ms，本工程按原版的 1100 ms 走。
   */
  static readonly TOTAL_MS: number = DEAL_IN_TOTAL_MS;

  /**
   * 算出本次发牌每一格的弹出时刻（按弹出顺序排列）。
   *
   * 顺序依据 [Lmy] core.h:156-191 的 getFirstPaintNo()，
   * 时刻依据 [Lmy] Minesweeper.cpp:1499-1508 的逐格延时（见文件头三节）。
   *
   * @param rows 棋盘行数
   * @param cols 棋盘列数
   * @returns 每格的弹出时刻；rows/cols 非法时返回空数组
   */
  static order(rows: number, cols: number): DealInOrder[] {
    const result: DealInOrder[] = [];
    if (rows <= 0 || cols <= 0) {
      return result;
    }
    const total: number = rows * cols;
    const seq: number[] = dealInSequence(rows, cols);
    for (let k = 0; k < seq.length; k++) {
      const item: DealInOrder = {
        cell: seq[k],
        atMs: dealInAtMs(k, total)
      };
      result.push(item);
    }
    return result;
  }

  /**
   * 某一时刻哪些格已经弹起来了。
   *
   * - false = 还没轮到（画浅色压平底砖）
   * - true  = 已经弹起（画深蓝方砖）
   *
   * @param elapsedMs 从本次发牌开始算起已经过的毫秒数
   * @param rows      棋盘行数
   * @param cols      棋盘列数
   * @returns 长度 rows*cols 的布尔数组，下标 = row * cols + col
   */
  static frameAt(elapsedMs: number, rows: number, cols: number): boolean[] {
    const flags: boolean[] = [];
    if (rows <= 0 || cols <= 0) {
      return flags;
    }
    const total: number = rows * cols;
    for (let i = 0; i < total; i++) {
      flags.push(false);
    }
    const seq: number[] = dealInSequence(rows, cols);
    for (let k = 0; k < seq.length; k++) {
      if (elapsedMs >= dealInAtMs(k, total)) {
        flags[seq[k]] = true;
      }
    }
    return flags;
  }
}
