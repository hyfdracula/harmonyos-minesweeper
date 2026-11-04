/**
 * SoundPlayer.ets —— 原版 Windows 7 扫雷音效
 *
 * 音效文件来自 win7-assets/audio（微软原版），已复制到
 * entry/src/main/resources/rawfile：共 15 个 wav。
 *
 * 播放方式：用 resourceManager.getRawFd 拿到 rawfile 的 fd，交给 AVPlayer.fdSrc，
 * 免去把文件复制到沙箱目录这一步。fd 由 AVPlayer 持有，应用生命周期内不关闭。
 *
 * ============================================================================
 * 一、事件归属（2026-11-04 按两份复刻的交叉证据改正过）
 * ============================================================================
 *
 *   发牌动画（新建一局 / 换难度） → firstPaint
 *       依据：Win32 复刻 `Minesweeper.rc:344`（IDR_WAVE1 = firstPaint.wav）
 *             + `utf8/Minesweeper.cpp:1495-1508`（在发牌的逐格绘制循环**之前**播）
 *   首点开格                     → tileSingle / tileMultiple / zeroDevelop
 *       依据：首点**没有**专属音效。判据是翻开几格（Qt 复刻 `MainWindow.cpp:41-48`）
 *             或被点格的相邻雷数（Lmy 的 `zeroDevelop()`，`:1774-1797`），
 *             两者都**不看是不是首点**。
 *
 * ============================================================================
 * 二、为什么有「预热」和「对齐播放」（用户报「音画不同步」）
 * ============================================================================
 *
 * 症状：发牌动画开始了，那声配乐才迟迟响起来 —— 声音明显**滞后于画面**。
 *
 * 原因：`play()` 是一条**全异步链**：
 *   ensurePlayer()  →  getRawFd + createAVPlayer + 等 'initialized'   ← 首次几百毫秒
 *   → await stop() → await prepare() → await seek(0) → await play()  ← 每次几十毫秒
 * 而画面动画全部按 `Date.now()` 的**绝对时间轴**走
 * （发牌 1100ms、涟漪、爆炸**本工程是 1000ms** —— 23 帧 × 43.478ms，
 *  不是参考实现的 575ms，那是它的动画长度）。
 * 声音的起点是「调用 play 的那一刻」，画面的起点是「动画开始的那一刻」——
 * 两套时钟各走各的，**必然错位**。
 *
 * 两个处置：
 * 1) **预热（warmup）**：应用启动后就把播放器建好、prepare 好，
 *    这样第一次真正要播的时候不需要现建。
 *    （有**数量预算**：平台建议 AVPlayer 实例数 ≤ 16，见 warmup() 的注释。）
 * 2) **对齐播放（playAt）**：调用方给出「这一声应该在什么时刻响」
 *    （与画面用同一套 `Date.now()` 时间轴），播放器准备好后按**剩余时间**补偿，
 *    于是声音与画面落在同一个绝对时刻上。
 */

import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';

/** 音效名（原版文件名，不带 .wav） */
export class Sound {
  /**
   * 新局发牌的那一声。
   *
   * 目前**全仓无调用点** —— 两份复刻对「发牌那一刻响哪一条」互相矛盾
   * （Qt 复刻说 gameStart，Win32 复刻说 firstPaint，而后者有资源 ID 直接对应原版，
   * 所以本项目选了 firstPaint）。
   * 要彻底定案得在**真 Win7** 上试听一次：在那之前不擅自补播（免得多出一声）。
   */
  static readonly GAME_START: string = 'gameStart';
  static readonly GAME_WIN: string = 'gameWin';
  /** 判负的爆点声：原版是**每颗雷各炸一声、可叠加**（走池子播） */
  static readonly GAME_LOSE: string = 'gameLose';
  static readonly TILE_SINGLE: string = 'tileSingle';
  static readonly TILE_MULTIPLE: string = 'tileMultiple';
  static readonly INVALID_MOVE: string = 'invalidMove';
  /**
   * **发牌动画的配乐**（原版 `IDR_WAVE1`）。
   *
   * 坑（2026-11-04，用户报「点第一个方块时还是播一次开始音」）：
   * 本项目原先把它挂在「首点开格」上 —— **挂错了**。
   * 首点没有专属音效，判据是翻开几格（Qt 复刻 `MainWindow.cpp:41-48`）。
   */
  static readonly FIRST_PAINT: string = 'firstPaint';
  /** 0 格展开（洪泛）的那声 */
  static readonly ZERO_DEVELOP: string = 'zeroDevelop';
  static readonly FLAG: string = 'dbButtonClickFlag';
  static readonly BOMB_START: string = 'mineBombStart';
  static readonly BOMB_RUN: string = 'mineBombRun';
  static readonly BOMB_END: string = 'mineBombEnd';
  /**
   * 花园模式（Win7 的「Flower Garden」玩法）判负的三段音效。
   *
   * 分档规则来自 linux 复刻：雷数 ≤10 播 Short、≤40 播 Medium、更多播 Long。
   */
  static readonly FLOWER_LOSE_SHORT: string = 'flowerLoseShort';
  static readonly FLOWER_LOSE_MEDIUM: string = 'flowerLoseMedium';
  static readonly FLOWER_LOSE_LONG: string = 'flowerLoseLong';
}

export class SoundPlayer {
  private static ctx: common.UIAbilityContext | null = null;
  private static players: Map<string, media.AVPlayer> = new Map();
  private static enabled: boolean = true;
  /** 正在预热中的音效（避免重复建） */
  private static warming: Set<string> = new Set();
  /** 对齐播放用的定时器句柄（按音效名记） */
  private static alignedTimers: Map<string, number> = new Map();

  /**
   * 所有音效名（预热用）。
   *
   * **顺序 = 优先级**：越靠前越常用、越该预热。
   * `warmup()` 会按这个顺序建，够数（MAX_PLAYERS）就停。
   *
   * 故意**不在**这个表里的：
   * - `Sound.GAME_START`：目前**全仓无调用点**（两份复刻对「发牌那一刻响哪一条」
   *   互相矛盾，等真 Win7 试听定案，见 SOUND-MAP.md），留着懒建就行；
   * - `Sound.GAME_LOSE`：走**池子**（要能叠着响），不占普通名额；
   * - 三条 `FLOWER_LOSE_*`：同一局只用其中一条，没必要三个都预热。
   */
  private static readonly ALL_SOUNDS: string[] = [
    Sound.FIRST_PAINT, Sound.TILE_SINGLE, Sound.TILE_MULTIPLE, Sound.ZERO_DEVELOP,
    Sound.FLAG, Sound.INVALID_MOVE, Sound.BOMB_START, Sound.BOMB_RUN, Sound.BOMB_END,
    Sound.GAME_WIN
  ];

  /** 初始化（拿到 AbilityContext 才能取 rawfile） */
  static init(ctx: common.UIAbilityContext): void {
    SoundPlayer.ctx = ctx;
  }

  /** 现在一共建了多少个播放器（普通 + 池子） */
  private static playerCount(): number {
    let n = SoundPlayer.players.size;
    SoundPlayer.poolPlayers.forEach((pool: media.AVPlayer[]) => {
      n += pool.length;
    });
    return n;
  }

  /**
   * 预热：把所有播放器的 fd、AVPlayer、prepare 全部提前做掉。
   *
   * 为什么需要（2026-11-04，用户报「音画不同步」）：
   * 第一次播某个音效时，要现做 `getRawFd` + `createAVPlayer` + 等 `initialized`，
   * 这几百毫秒全花在**该响的那一刻之后** —— 声音于是比画面晚一大截。
   * 预热之后，真正要播的时候只剩 `stop → prepare → seek → play`，
   * 延迟降到几十毫秒量级。
   *
   * **数量有上限**（Codex 复审 P2，2026-11-05）：
   * 平台建议的 AVPlayer 实例上限是 16 个，有些设备更少。
   * 一开始这里是「15 个全建 + 4 个池子 = 19 个」，超了 ——
   * 资源紧张的设备上后面的音效就建不出来，而且建失败的没法靠懒建补回来。
   * 现在按优先级建，够 MAX_PLAYERS 就停；不常用的懒建。
   *
   * 失败不致命：某个音效预热失败，只是它第一次播会慢一点，
   * 真正的播放路径自己还会再建一次。
   */
  static warmup(): void {
    const ctx = SoundPlayer.ctx;
    if (ctx === null) {
      return;
    }
    for (const name of SoundPlayer.ALL_SOUNDS) {
      if (SoundPlayer.playerCount() + SoundPlayer.creatingCount >= SoundPlayer.WARM_BUDGET) {
        console.info('[Sound] 预热已达预算 ' + SoundPlayer.WARM_BUDGET + ' 个，剩下的懒建');
        break;
      }
      if (SoundPlayer.players.has(name) || SoundPlayer.warming.has(name)) {
        continue;
      }
      SoundPlayer.warming.add(name);
      SoundPlayer.ensurePlayer(ctx, name).then(() => {
        SoundPlayer.warming.delete(name);
      }).catch((err: Error) => {
        SoundPlayer.warming.delete(name);
        console.warn('[Sound] 预热失败 ' + name + '：' + err.message);
      });
    }
    // 池子里的播放器也预热几个（判负的级联要叠着响，不能等到那一刻才建）
    //
    // **必须和懒建走同一套预留**（Codex 复审第 13 轮 P2）：
    // 原来这里直接 `createPlayer()`，在途的实例**既不在 `poolPending`、
    // 也不在 `creatingCount` 里** —— 于是「预热还没建完、这时又要播这一声」，
    // 两边各自通过容量检查，最后池子 6 个（上限 4）、实例 16 个（上限 14）。
    // 现在：先**同步占位**，再建；而且用 warming 的键**去重**，
    // 重进 warmup（组件重建）不会重复建。
    for (const name of SoundPlayer.POOLED) {
      const have = SoundPlayer.poolOf(name).length;
      for (let i = have; i < SoundPlayer.POOL_WARM; i++) {
        const key: string = name + '#' + i;
        if (SoundPlayer.warming.has(key)) {
          continue;
        }
        if (SoundPlayer.playerCount() + SoundPlayer.creatingCount >= SoundPlayer.WARM_BUDGET) {
          break;
        }
        if (SoundPlayer.poolOf(name).length + SoundPlayer.poolPendingOf(name) >=
          SoundPlayer.POOL_SIZE) {
          break;
        }
        // **同步占位**
        SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) + 1);
        SoundPlayer.creatingCount++;
        SoundPlayer.warming.add(key);
        SoundPlayer.createPlayer(ctx, name).then((p: media.AVPlayer) => {
          SoundPlayer.creatingCount--;
          SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) - 1);
          // 三个数组要**同步长齐**（poolPlayers / poolStarted / poolBusy），
          // 否则后面按索引取「占用」会取错人（Codex 复审第 12 轮 P2 的同类问题）。
          SoundPlayer.poolOf(name).push(p);
          SoundPlayer.poolStartedOf(name).push(0);
          SoundPlayer.poolBusyOf(name).push(false);
          SoundPlayer.warming.delete(key);
        }).catch((err: Error) => {
          SoundPlayer.creatingCount--;
          SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) - 1);
          SoundPlayer.warming.delete(key);
          console.warn('[Sound] 池子预热失败 ' + name + '：' + err.message);
        });
      }
    }
  }

  static setEnabled(v: boolean): void {
    SoundPlayer.enabled = v;
  }

  static get isEnabled(): boolean {
    return SoundPlayer.enabled;
  }

  /** 播放一个音效（同步调用，实际播放在后台） */
  static play(name: string): void {
    SoundPlayer.playNow(name, true);
  }

  /**
   * 真正播一声。
   *
   * @param log 是否打「播放」那行日志。
   *   `playAt` 走的是「先排期、后播」，它自己打一行「对齐播放」，
   *   所以这里**不能再打一行** —— 否则同一声响在日志里出现两次，
   *   跑测器数「播了几声」时会数错（2026-11-04 实测踩到过）。
   */
  private static playNow(name: string, log: boolean): void {
    if (!SoundPlayer.enabled) {
      return;
    }
    const ctx = SoundPlayer.ctx;
    if (ctx === null) {
      return;
    }
    // **诊断日志**：跑测器要能验证「这一刻到底播了哪一声」——
    // 音效是听觉的，自动测试抓不到；但日志能。
    // 2026-11-04：用户报「音画不同步」和「首点多播一次开始音」，
    // 这两条都靠这条日志在设备上核实（见 tools/click_cases/sound.json）。
    if (log) {
      console.info('[Sound] 播放 ' + name + ' at=' + Date.now());
    }
    SoundPlayer.playAsync(ctx, name).catch((err: Error) => {
      console.error('[Sound] 播放失败 ' + name + ': ' + err.message);
    });
  }

  /**
   * **对齐播放**：这一声应该在 `atMs`（`Date.now()` 时间轴上的绝对时刻）响。
   *
   * 为什么需要（2026-11-04，用户报「音画不同步」）：
   * 画面动画走的是 `Date.now()` 的绝对时间轴，声音却是在「调用 play 的那一刻」
   * 才开始异步准备 —— 两套时钟各走各的，必然错位。
   * 这里把「该响的时刻」交给声音层：播放器准备好后按**剩余时间**补偿，
   * 于是声音与画面落在同一个绝对时刻。
   *
   * @param atMs 该响的绝对时刻（`Date.now()` 口径）。传 0 或过去的时间 = 立刻响。
   */
  static playAt(name: string, atMs: number): void {
    if (!SoundPlayer.enabled) {
      return;
    }
    const ctx = SoundPlayer.ctx;
    if (ctx === null) {
      return;
    }
    // 同一个音效的上一次对齐播放还没到点，就撤掉重来
    const old = SoundPlayer.alignedTimers.get(name);
    if (old !== undefined) {
      clearTimeout(old);
      SoundPlayer.alignedTimers.delete(name);
    }
    const delay: number = Math.max(0, atMs - Date.now());
    if (delay === 0) {
      // 已经到点了：立刻播，日志打「对齐播放」（与走延时那条路同一行式样，
      // 这样跑测器数「播了几声」时，一声响只对应**一行**日志）
      SoundPlayer.playNow(name, false);
      console.info('[Sound] 对齐播放 ' + name + ' at=' + Date.now());
      return;
    }
    const handle: number = setTimeout(() => {
      SoundPlayer.alignedTimers.delete(name);
      SoundPlayer.playNow(name, false);
      console.info('[Sound] 对齐播放 ' + name + ' at=' + Date.now());
    }, delay);
    SoundPlayer.alignedTimers.set(name, handle);
  }

  /**
   * 池子：同一个音效要**同时响好几声**时用（判负的爆炸级联）。
   *
   * 只有一个播放器时，第二声会把第一声**打断**（`seek(0)` 从头播），
   * 于是级联听起来是「哒 哒 哒」而不是「轰隆隆一片」——
   * 原版是叠在一起的（留 30 个缓冲，见 SOUND-AUDIT.md §2）。
   *
   * 这里用 4 个播放器轮转：一颗雷的爆炸声 1.997 秒，
   * 4 个能叠住约 8 秒的级联，够用了。
   *
   * **并发是这里最难的部分**（Codex 复审第 12 轮，2026-11-05，1×P1 + 3×P2）。
   * 级联里多颗雷会**同时**起爆，于是多个 `playPooledAsync` 几乎同时进来。
   * 踩过的坑（都是它用异步桩复现出来的）：
   *   ① **扩容要同步预留名额** —— 原来「查容量 → await 建 → push」，
   *      在建的那一个**没算进容量**，并发 6 次播放后池子涨到 9（上限 4）、
   *      实例总数涨到 19（上限 14）。现在改成**建之前就占位**（pending）。
   *   ② **播放不能等扩容** —— 原来每次播放都先把池子补满才播，
   *      第一次爆炸要等两次冷创建 → 又把延迟放回爆点之后，破坏音画同步。
   *      现在**先用现成的空闲成员**，扩容只��实在没得用时才做。
   *   ③ **选中的成员要立刻标记占用** —— `playOn()` 里 await 期间，
   *      成员还没变成 'playing'，下一个并发调用会挑中**同一个**，
   *      三次并发全挑了 0 号 → 状态操作打架、爆点合并。
   *      现在选中的瞬间就 `busy[i] = true`（同步），播完再放开。
   *   ④ **停止要能作废在途请求** —— 用户在扩容途中点了「跳过」，
   *      `stopPooled()` 停不到还在 `await createPlayer()` 的那个请求，
   *      它回来以后照样播 → 结算框上面又炸了一声。
   *      现在用**取消代次**（generation）：`stopPooled` 把代次 +1，
   *      在途请求回来一看代次变了就作废。
   */
  private static poolPlayers: Map<string, media.AVPlayer[]> = new Map();
  /** 池子里每个播放器**这一轮是从什么时候开始播的**（用来挑空闲的） */
  private static poolStarted: Map<string, number[]> = new Map();
  /** 每个池成员**是否已被占用**（正在起播 / 在播） */
  private static poolBusy: Map<string, boolean[]> = new Map();
  /** 正在建的池成员数（**建之前就占位**，用来防并发超容量） */
  private static poolPending: Map<string, number> = new Map();
  /** 取消代次：`stopPooled` 时 +1，在途请求回来一看代次变了就作废 */
  private static poolGeneration: Map<string, number> = new Map();
  /** 全局「正在建」的播放器数（普通 + 池），建之前占位 */
  private static creatingCount: number = 0;

  /** 需要池子的音效（同一个要能叠着响的） */
  private static readonly POOLED: string[] = [Sound.GAME_LOSE];
  /** 池子最多几个播放器 */
  private static readonly POOL_SIZE: number = 4;
  /** 预热时池子先建几个（其余懒建，省资源） */
  private static readonly POOL_WARM: number = 2;

  /**
   * 平台对 AVPlayer 实例数有建议上限（**16 个**，有些设备还更少）。
   *
   * 坑（Codex 复审 P2，2026-11-05）：
   * 一开始 `warmup()` 把 15 个音效全建了，外加 4 个池子播放器 = **19 个**，
   * 超了上限。资源紧张的设备上，后面的音效就建不出来/准备不了，
   * 而且**建失败的没法靠懒建补回来**（成功的那些还占着位置不放）。
   *
   * 现在分两个预算：
   * - `WARM_BUDGET`：**预热**最多建几个（普通 + 池子）。
   *   超了就停，剩下的懒建 —— 懒建走同一套 promise（见 ensurePlayer），
   *   不会重复建。
   * - `HARD_MAX`：实例总数的**硬上限**。普通播放器懒建时也要看它，
   *   到顶了先**回收一个闲置的**普通播放器（见 reclaimIdle）。
   */
  private static readonly WARM_BUDGET: number = 12;
  /** 实例总数上限（平台建议 16，留 2 个余量） */
  private static readonly HARD_MAX: number = 14;

  /** 用池子播一声（同名的其它声**不会**被这一声打断） */
  static playPooled(name: string): void {
    if (!SoundPlayer.enabled) {
      return;
    }
    const ctx = SoundPlayer.ctx;
    if (ctx === null) {
      return;
    }
    console.info('[Sound] 播放 ' + name + ' at=' + Date.now());
    SoundPlayer.playPooledAsync(ctx, name).catch((err: Error) => {
      console.error('[Sound] 池子播放失败 ' + name + ': ' + err.message);
    });
  }

  /**
   * 停掉池子里正在响的**全部**声音（跳动画/换局时用）。
   *
   * 同时把**取消代次** +1 —— 还在 `await createPlayer()` 的在途请求
   * 回来后一看代次变了，就把自己作废（否则结算框上面又炸一声）。
   *
   * **不要在这里清 `busy`**（Codex 复审第 15 轮 P2，2026-11-05）：
   * `busy[i]` 表示「这个成员正在做状态切换」（stop/prepare/seek/play）。
   * 原来这里把它清成 false，于是**下一轮**级联可能挑中同一个成员，
   * 而上一轮那个请求的 `prepare()` 还没完 —— 两个状态机叠在同一个
   * AVPlayer 上，播放失败。
   * 现在：占用由**持有它的那个请求**在退出时（`finally`）释放，
   * 这里只负责「让它别再播」和「让在途请求作废」。
   */
  static stopPooled(name: string): void {
    SoundPlayer.poolGeneration.set(name, (SoundPlayer.poolGeneration.get(name) || 0) + 1);
    const pool = SoundPlayer.poolPlayers.get(name);
    if (pool === undefined) {
      return;
    }
    for (const p of pool) {
      p.stop().catch(() => {
      });
    }
  }

  /** 池成员数组（没有就建一个空的） */
  private static poolOf(name: string): media.AVPlayer[] {
    let pool = SoundPlayer.poolPlayers.get(name);
    if (pool === undefined) {
      pool = [];
      SoundPlayer.poolPlayers.set(name, pool);
    }
    return pool;
  }

  /** 池成员的「开始时刻」数组 */
  private static poolStartedOf(name: string): number[] {
    let v = SoundPlayer.poolStarted.get(name);
    if (v === undefined) {
      v = [];
      SoundPlayer.poolStarted.set(name, v);
    }
    return v;
  }

  /** 池成员的「占用」数组 */
  private static poolBusyOf(name: string): boolean[] {
    let v = SoundPlayer.poolBusy.get(name);
    if (v === undefined) {
      v = [];
      SoundPlayer.poolBusy.set(name, v);
    }
    return v;
  }

  /** 正在建的池成员数 */
  private static poolPendingOf(name: string): number {
    return SoundPlayer.poolPending.get(name) || 0;
  }

  private static async playPooledAsync(ctx: common.UIAbilityContext,
    name: string): Promise<void> {
    const gen: number = SoundPlayer.poolGeneration.get(name) || 0;
    const pool: media.AVPlayer[] = SoundPlayer.poolOf(name);
    const started: number[] = SoundPlayer.poolStartedOf(name);
    const busy: boolean[] = SoundPlayer.poolBusyOf(name);
    const cancelCheck: () => boolean = SoundPlayer.poolCancelCheck(name, gen);
    // 抢不到就等一会儿的**上限**（毫秒）
    const deadline: number = Date.now() + 600;

    while (true) {
      // ===== 这一段**不能有 await**（要原子地挑成员 / 标记占用）=====
      // 1) 挑一个**空闲**的成员：没被占用，且不在播
      let pick = -1;
      for (let i = 0; i < pool.length; i++) {
        if (!busy[i] && pool[i].state !== 'playing') {
          pick = i;
          break;
        }
      }
      if (pick >= 0) {
        // **立刻**标记占用 —— 否则并发的下一个调用会挑中同一个
        busy[pick] = true;
        started[pick] = Date.now();
        // ===== 到这里才有 await =====
        try {
          await SoundPlayer.playOn(pool[pick], cancelCheck);
        } finally {
          busy[pick] = false;
        }
        return;
      }

      // 2) 没有空闲的 → **先试扩容**（别抢别人正在响的）
      //    （Codex 复审第 13 轮 P2：原来直接抢「开始最早」的那个，
      //      于是池子永远停在预热的那 2 个，后面的爆炸只能把前面的声音切断，
      //      而不是叠起来。）
      const idx: number = await SoundPlayer.growPool(ctx, name, gen);
      if (idx >= 0) {
        try {
          await SoundPlayer.playOn(pool[idx], cancelCheck);
        } finally {
          busy[idx] = false;
        }
        return;
      }

      // 3) 扩不了 —— 先看这一声**是不是已经作废**了
      //    （Codex 复审第 14 轮 P2：`growPool` 因为代次变了返回 -1，
      //      而调用方原来会直接掉进「抢占」那条路，
      //      把**下一轮**级联正在响的声音 seek(0) 了。）
      if ((SoundPlayer.poolGeneration.get(name) || 0) !== gen) {
        return;
      }

      // 4) 抢一个**已经在播**的（seek(0) 重来，剩下最短的尾巴）
      //    **正在做状态切换的不能抢** —— 两个 playOn() 叠在同一个播放器上，
      //    状态机会打架（Codex 复审第 14 轮 P2：实测 6 个请求、4 个成员
      //    时，有两个成员上出现了并发的状态切换，播放失败）。
      let steal = -1;
      for (let i = 0; i < pool.length; i++) {
        // 只抢**已经在播、而且没有状态切换在进行**的成员
        if (!busy[i] && pool[i].state === 'playing') {
          if (steal < 0 || started[i] < started[steal]) {
            steal = i;
          }
        }
      }
      if (steal >= 0) {
        busy[steal] = true;
        started[steal] = Date.now();
        try {
          await SoundPlayer.playOn(pool[steal], cancelCheck);
        } finally {
          busy[steal] = false;
        }
        return;
      }

      // 5) 全都在做状态切换 → 等一会儿再看（等的是「谁先闲下来」）
      if (Date.now() > deadline) {
        console.warn('[Sound] 池子全忙且都在切换状态，放弃这一声: ' + name);
        return;
      }
      await SoundPlayer.sleep(15);
    }
  }

  /**
   * 池子扩容：建一个新成员。
   *
   * **建之前同步占位**（`poolPending` + 全局 `creatingCount`）——
   * 否则并发的多个调用会各自通过容量检查，然后一起超容量
   * （Codex 复审第 12 轮 P1：实测池子从 4 涨到 9、实例从 14 涨到 19）。
   *
   * @return 新成员的下标；建不出来（到上限 / 被取消 / 建失败）返回 -1
   */
  private static async growPool(ctx: common.UIAbilityContext,
    name: string, gen: number): Promise<number> {
    const pool: media.AVPlayer[] = SoundPlayer.poolOf(name);
    if (pool.length + SoundPlayer.poolPendingOf(name) >= SoundPlayer.POOL_SIZE ||
      SoundPlayer.playerCount() + SoundPlayer.creatingCount >= SoundPlayer.HARD_MAX) {
      return -1;
    }
    SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) + 1);
    SoundPlayer.creatingCount++;
    let p: media.AVPlayer;
    try {
      p = await SoundPlayer.createPlayer(ctx, name);
    } catch (err) {
      SoundPlayer.creatingCount--;
      SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) - 1);
      console.warn('[Sound] 池子扩容失败 ' + name);
      return -1;
    }
    SoundPlayer.creatingCount--;
    SoundPlayer.poolPending.set(name, SoundPlayer.poolPendingOf(name) - 1);
    // 建的过程中用户可能点了「跳过」（stopPooled 把代次 +1 了）→ 这次请求作废
    if ((SoundPlayer.poolGeneration.get(name) || 0) !== gen) {
      p.release().catch(() => {
      });
      return -1;
    }
    const idx: number = pool.length;
    pool.push(p);
    SoundPlayer.poolStartedOf(name).push(Date.now());
    SoundPlayer.poolBusyOf(name).push(true);
    return idx;
  }

  /** 池播放的取消判据：代次变了 = 这条请求作废（用户跳过了动画 / 换了局） */
  private static poolCancelCheck(name: string, gen: number): () => boolean {
    return () => (SoundPlayer.poolGeneration.get(name) || 0) !== gen;
  }

  /**
   * 在指定播放器上播一遍（不管之前在不在播）。
   *
   * @param cancelCheck 可选的取消判据。**在真正 play() 之前**查一次 ——
   *   因为 `stop()` / `prepare()` / `seek()` 都是异步的，这中间用户可能
   *   点了「跳过动画」（Codex 复审第 13 轮 P2：原来只在「新建成员」之后
   *   查取消代次，**已存在**的成员那条路不查，于是 pending 的 playOn()
   *   回来照样 play()，结算框上面又炸了一声）。
   */
  private static async playOn(player: media.AVPlayer,
    cancelCheck?: () => boolean): Promise<void> {
    // **动播放器之前先查取消**（Codex 复审第 14 轮 P2）：
    // 原来只在 `play()` 之前查，而 'playing' 那条快速路径是直接
    // `seek(0)` —— 一个**已经作废**的请求会把**下一轮**级联正在响的
    // 声音倒回开头。
    if (SoundPlayer.isCancelled(cancelCheck)) {
      return;
    }
    const state: string = player.state;
    if (state === 'playing') {
      if (SoundPlayer.isCancelled(cancelCheck)) {
        return;
      }
      try {
        await player.seek(0);
      } catch (err) {
      }
      return;
    }
    if (state === 'paused' || state === 'completed') {
      try {
        await player.seek(0);
      } catch (err) {
      }
      if (SoundPlayer.isCancelled(cancelCheck)) {
        return;
      }
      await player.play();
      return;
    }
    try {
      await player.stop();
    } catch (err) {
    }
    try {
      await player.prepare();
    } catch (err) {
    }
    try {
      await player.seek(0);
    } catch (err) {
    }
    if (SoundPlayer.isCancelled(cancelCheck)) {
      return;
    }
    await player.play();
  }

  /** 等一小会儿（毫秒） */
  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 取消判据（没有判据就当没取消） */
  private static isCancelled(cancelCheck?: () => boolean): boolean {
    if (cancelCheck === undefined) {
      return false;
    }
    try {
      return cancelCheck();
    } catch (err) {
      return false;
    }
  }

  /**
   * 拿到（必要时创建）某个音效的播放器。
   *
   * 坑（2026-10-31 真机）：`p.fdSrc = ...` 是**异步状态机**——赋值只是发起一次
   * idle → initialized 的切换，立刻 `await p.prepare()` 会抢在状态切换之前，
   * 抛 `The current state is idle. Prepare operation only supports stopped/initialized`，
   * 结果**所有音效都不响**。官方示例是在 `stateChange` 回调里收到 `initialized`
   * 之后再 `prepare()`，这里照做：注册监听 → 赋 fdSrc → 等 initialized → prepare。
   */
  /**
   * 拿到（必要时创建）某个音效的播放器。
   *
   * **在建的 promise 要共享**（Codex 复审 P2，2026-11-05）：
   * 原来这里只看 `players`（已建好的），不看 `warming`（在建中的）——
   * 于是「预热还没建完、这时又要播这一声」，两条路**各建一个**播放器，
   * 后建好的把先建好的顶掉 `players` 里的条目，
   * 结果是：① 首次播放的准备延迟**没省掉**；② 多出来的那个播放器**没人管**，
   * `dispose()` 也 release 不掉（泄漏）。
   *
   * 现在把**在建的 promise 本身**存起来，谁要都 await 同一个。
   */
  private static creating: Map<string, Promise<media.AVPlayer>> = new Map();

  private static async ensurePlayer(ctx: common.UIAbilityContext,
    name: string): Promise<media.AVPlayer> {
    const existing = SoundPlayer.players.get(name);
    if (existing !== undefined) {
      return existing;
    }
    const inflight = SoundPlayer.creating.get(name);
    if (inflight !== undefined) {
      return inflight;
    }
    // **总数上限真的要执行**（Codex 复审第 12 轮 P2，2026-11-05）：
    // 原来到顶了只打一句警告，然后**照样建** —— 等于没有上限。
    // 现在：到顶了先**回收一个闲置的普通播放器**腾名额；
    // 回收不到（都在响）才退而求其次。
    if (SoundPlayer.playerCount() + SoundPlayer.creatingCount >= SoundPlayer.HARD_MAX) {
      if (!SoundPlayer.reclaimIdle()) {
        console.warn('[Sound] 实例数已达上限 ' + SoundPlayer.HARD_MAX +
          '，' + name + ' 这一声可能播不出来');
      }
    }
    // **建之前就占位**（防并发超容量）
    SoundPlayer.creatingCount++;
    const p: Promise<media.AVPlayer> = SoundPlayer.createPlayer(ctx, name).then((pl: media.AVPlayer) => {
      SoundPlayer.creatingCount--;
      SoundPlayer.players.set(name, pl);
      SoundPlayer.creating.delete(name);
      return pl;
    }).catch((err: Error) => {
      // 建失败要把在建的条目清掉，下一次才能重试
      SoundPlayer.creatingCount--;
      SoundPlayer.creating.delete(name);
      throw err;
    });
    SoundPlayer.creating.set(name, p);
    return p;
  }

  /**
   * 回收一个**闲置的**普通播放器，腾出一个实例名额。
   *
   * 池子成员**不回收**（判负的级联正要用着它们）；
   * 正在响的也不回收（收了就断声）。
   *
   * 回收掉的那个音效，下次要播时再懒建一个 —— 慢一点，但比
   * 「实例数超上限、后面的音效根本建不出来」划算。
   */
  private static reclaimIdle(): boolean {
    // ArkTS 不支持解构声明（arkts-no-destruct-decls），所以分开取。
    for (const name of SoundPlayer.players.keys()) {
      if (SoundPlayer.POOLED.indexOf(name) >= 0) {
        continue;
      }
      const p = SoundPlayer.players.get(name);
      if (p === undefined || p.state === 'playing') {
        continue;
      }
      p.release().catch(() => {
      });
      SoundPlayer.players.delete(name);
      return true;
    }
    return false;
  }

  /**
   * 建一个新播放器（不登记到 players 里）。
   *
   * 池子用（`poolPlayers`）：同一个音效要**同时响好几声**时用得上 ——
   * 判负的爆炸级联里，每颗雷都要炸一声，而那些声音是**叠在一起**的。
   * 只有一个播放器时，第二声会把第一声**打断**（`seek(0)` 从头播）。
   *
   * 原版留了 30 个缓冲（见 SOUND-AUDIT.md §2），
   * 我们用 4 个 —— 够用：一颗雷的爆炸声 1.997 秒，
   * 4 个轮转能叠住约 8 秒的级联。
   */
  private static async createPlayer(ctx: common.UIAbilityContext,
    name: string): Promise<media.AVPlayer> {
    const fdObj = await ctx.resourceManager.getRawFd(name + '.wav');
    const p = await media.createAVPlayer();
    const inited: Promise<void> = new Promise<void>((resolve: () => void,
      reject: (e: Error) => void) => {
      let done: boolean = false;
      const timer: number = setTimeout(() => {
        if (!done) {
          done = true;
          reject(new Error('等待 initialized 超时'));
        }
      }, 3000);
      p.on('stateChange', (state: string) => {
        if (done) {
          return;
        }
        if (state === 'initialized' || state === 'prepared' || state === 'playing') {
          done = true;
          clearTimeout(timer);
          resolve();
        } else if (state === 'error') {
          done = true;
          clearTimeout(timer);
          reject(new Error('AVPlayer 进入 error 状态'));
        }
      });
    });
    p.fdSrc = { fd: fdObj.fd, offset: fdObj.offset, length: fdObj.length };
    await inited;
    await p.prepare();
    return p;
  }

  private static async playAsync(ctx: common.UIAbilityContext, name: string): Promise<void> {
    const player = await SoundPlayer.ensurePlayer(ctx, name);
    await SoundPlayer.playOn(player);
  }

  /** 读播放器的当前状态（读不出来就当 unknown，走慢路径） */

  /**
   * 停掉某个正在播的音效（把播放器停住，不释放）。
   *
   * 为什么需要（2026-11-01，音效审计）：原版 `PlaySound(SND_ASYNC)` 的语义是
   * 「同名音效重触发会打断前一次」；而我们爆炸时是「爆炸中音循环 + 结束时播结束音」，
   * 如果结束音响起时爆炸中音还在放，两个声音会叠在一起 —— 原版是先停循环再放结束音。
   */
  static stop(name: string): void {
    // 待播的对齐播放也要撤：否则「已经排到 300ms 后响」的那一声
    // 会在 stop 之后照样响起来。
    const timer = SoundPlayer.alignedTimers.get(name);
    if (timer !== undefined) {
      clearTimeout(timer);
      SoundPlayer.alignedTimers.delete(name);
    }
    const p = SoundPlayer.players.get(name);
    if (p === undefined) {
      return;
    }
    p.stop().catch(() => {
    });
  }

  /** 释放所有播放器 */
  static dispose(): void {
    SoundPlayer.alignedTimers.forEach((h: number) => {
      clearTimeout(h);
    });
    SoundPlayer.alignedTimers.clear();
    SoundPlayer.players.forEach((p: media.AVPlayer) => {
      p.release().catch(() => {
      });
    });
    SoundPlayer.players.clear();
    SoundPlayer.poolPlayers.forEach((pool: media.AVPlayer[]) => {
      pool.forEach((p: media.AVPlayer) => {
        p.release().catch(() => {
        });
      });
    });
    SoundPlayer.poolPlayers.clear();
    SoundPlayer.poolStarted.clear();
    SoundPlayer.poolBusy.clear();
    SoundPlayer.poolPending.clear();
    SoundPlayer.poolGeneration.clear();
    SoundPlayer.creatingCount = 0;
    SoundPlayer.creating.clear();
    SoundPlayer.warming.clear();
  }
}
