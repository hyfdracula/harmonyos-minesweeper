/**
 * GameStats.ets —— 局数统计与各难度最快纪录（持久化到 Preferences）
 *
 * 原版结束对话框里有「已玩游戏 / 已胜游戏 / 百分比 / 最快时间 + 日期」，
 * 这里用 @kit.ArkData 的 preferences 实现。
 *
 * 坑（2026-10-31）：ArkTS 的静态方法里不允许用 this（arkts-no-standalone-this），
 *    所以这里一律写类名 GameStats.xxx。
 *
 * 坑（Codex 复审 P2）：最快纪录必须**按难度分开存**，
 *    否则初级跑出的成绩会被当成高级的纪录显示。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'saolei_stats';

/**
 * 一个难度档的「四项纪录」。
 *
 * 对应 Win7 原版「最佳成绩」表里的四行（逐条的出处见
 * docs/DIALOG-PIXEL-DIFF-3.md §1）：
 *   最快用时   —— 获胜局里最短的一次用时（秒）
 *   最快百分比 —— 历史上出现过的最高胜率
 *   最慢百分比 —— 历史上出现过的最低胜率
 *   最慢用时   —— 获胜局里最长的一次用时（秒）
 *
 * 百分比的分母 = **该难度已玩的局数**（不是全局局数）：
 * Lmy 克隆 io.h:268-271 就是 `valueCount[2] = (int)(winCount/gameCount*100)`，
 * gameCount/winCount 都取自同一个难度档的分节。
 */
export interface LevelRecord {
  /** 该难度已玩局数（百分比的分母） */
  played: number;
  /** 该难度获胜局数（百分比的分子） */
  won: number;
  /** 最慢用时（秒，只统计获胜局）；-1 = 没有纪录 */
  slowest: number;
  /** 最快百分比（保留一位小数）；-1 = 没有纪录 */
  bestPercent: number;
  /** 最慢百分比（保留一位小数）；-1 = 没有纪录 */
  worstPercent: number;
}

export class GameStats {
  /** 已玩总局数 */
  static played: number = 0;
  /** 已获胜局数 */
  static won: number = 0;
  /** 当前连胜（连续获胜局数） */
  static currentStreak: number = 0;
  /** 最多连胜 */
  static maxStreak: number = 0;
  /** 当前连败（内部用来算最多连败） */
  static currentLoseStreak: number = 0;
  /** 最多连败 */
  static maxLoseStreak: number = 0;

  private static store: preferences.Preferences | null = null;
  /** 各难度的最快用时（秒）；key = 难度名，缺省表示没有纪录 */
  private static bestSeconds: Map<string, number> = new Map();
  /** 各难度最快纪录的日期文本 */
  private static bestDate: Map<string, string> = new Map();
  /** 各难度的其余三项纪录（局数/胜局、最慢用时、最快/最慢百分比） */
  private static levelRecords: Map<string, LevelRecord> = new Map();

  /**
   * 外观设置（**原版重启后是保留的** ✓）。
   * 0 = 蓝棋盘 / 扫雷玩法，1 = 绿棋盘 / 花园玩法。
   * 存在这里而不是 SpriteAtlas 里，是因为它要进 preferences 存档 ✓。
   */
  static boardStyle: number = 0;
  static gameStyle: number = 0;

  /** 读取存档（异步，失败不阻塞游戏） */
  static async load(ctx: common.UIAbilityContext): Promise<void> {
    try {
      GameStats.store = await preferences.getPreferences(ctx, { name: STORE_NAME });
      const p: number = Number(await GameStats.store.get('played', 0));
      const w: number = Number(await GameStats.store.get('won', 0));
      GameStats.played = p;
      GameStats.won = w;
      GameStats.currentStreak = Number(await GameStats.store.get('currentStreak', 0));
      GameStats.maxStreak = Number(await GameStats.store.get('maxStreak', 0));
      GameStats.currentLoseStreak = Number(await GameStats.store.get('currentLoseStreak', 0));
      GameStats.maxLoseStreak = Number(await GameStats.store.get('maxLoseStreak', 0));
      GameStats.boardStyle = Number(await GameStats.store.get('boardStyle', 0));
      GameStats.gameStyle = Number(await GameStats.store.get('gameStyle', 0));
      for (const level of GameStats.levels()) {
        const s: number = Number(await GameStats.store.get('best_' + level, -1));
        const d: string = String(await GameStats.store.get('bestDate_' + level, ''));
        if (s >= 0) {
          GameStats.bestSeconds.set(level, s);
        }
        if (d.length > 0) {
          GameStats.bestDate.set(level, d);
        }
        // 四项纪录（新增键；老存档里没有就是「没有纪录」，不影响老数据）
        const lp: number = Number(await GameStats.store.get('lvPlayed_' + level, 0));
        const lw: number = Number(await GameStats.store.get('lvWon_' + level, 0));
        const ls: number = Number(await GameStats.store.get('lvSlowest_' + level, -1));
        const lb: number = Number(await GameStats.store.get('lvBestPct_' + level, -1));
        const lwst: number = Number(await GameStats.store.get('lvWorstPct_' + level, -1));
        if (lp > 0 || lw > 0 || ls >= 0 || lb >= 0 || lwst >= 0) {
          GameStats.levelRecords.set(level, {
            played: lp, won: lw, slowest: ls, bestPercent: lb, worstPercent: lwst
          });
        }
      }
    } catch (err) {
      console.error('[GameStats] 读取存档失败: ' + (err as BusinessError).message +
        ' / ' + (err as BusinessError).code);
    }
  }

  /**
   * 保存外观设置（棋盘样式 / 游戏样式）。
   *
   * 原版 Win7 的「颜色」对话框选完是**持久**的：下次启动还是绿色棋盘 / 花园玩法 ✓。
   * 之前我们只在内存里切，重启就回默认 ✗。
   *
   * @param board 0 = 蓝棋盘，1 = 绿棋盘
   * @param game  0 = 扫雷玩法，1 = 花园玩法
   */
  static async saveStyle(board: number, game: number): Promise<void> {
    GameStats.boardStyle = board;
    GameStats.gameStyle = game;
    const store = GameStats.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('boardStyle', board);
      await store.put('gameStyle', game);
      await store.flush();
      console.info('[GameStats] 外观已保存 board=' + board + ' game=' + game);
    } catch (err) {
      console.error('[GameStats] 保存外观失败: ' + (err as BusinessError).message +
        ' / ' + (err as BusinessError).code);
    }
  }

  /** 记录一局结束（level = 难度名） */
  static async record(won: boolean, seconds: number, level: string): Promise<void> {    GameStats.played += 1;
    if (won) {
      GameStats.won += 1;
      GameStats.currentStreak += 1;
      GameStats.currentLoseStreak = 0;
      if (GameStats.currentStreak > GameStats.maxStreak) {
        GameStats.maxStreak = GameStats.currentStreak;
      }
      const cur = GameStats.bestSeconds.get(level);
      if (cur === undefined || seconds <= cur) {
        GameStats.bestSeconds.set(level, seconds);
        GameStats.bestDate.set(level, GameStats.nowText());
      }
    } else {
      GameStats.currentStreak = 0;
      GameStats.currentLoseStreak += 1;
      if (GameStats.currentLoseStreak > GameStats.maxLoseStreak) {
        GameStats.maxLoseStreak = GameStats.currentLoseStreak;
      }
    }
    // 各难度的四项纪录（Win7 原版「最佳成绩」表的四行）
    GameStats.updateLevelRecord(level, won, seconds);
    await GameStats.save();
  }

  /**
   * 更新某个难度的四项纪录。
   *
   * - 最快用时：获胜局里最短的一次（与 bestSeconds 同一份数据，不重复存）
   * - 最慢用时：获胜局里最长的一次（输的局没有可比性，不计入）
   * - 最快/最慢百分比：该难度**历史胜率**的最大/最小值，
   *   胜率 = 获胜局数 / 该难度已玩局数（分母是这个难度的局数，不是全局局数）
   */
  private static updateLevelRecord(level: string, won: boolean, seconds: number): void {
    const rec: LevelRecord = GameStats.levelRecord(level);
    rec.played += 1;
    if (won) {
      rec.won += 1;
      if (rec.slowest < 0 || seconds > rec.slowest) {
        rec.slowest = seconds;
      }
    }
    // 胜率保留一位小数（Win7 原版显示到整数，这里多留一位，别把 2/3 抹成 67）
    const rate: number = Math.round((rec.won * 1000) / rec.played) / 10;
    if (rec.bestPercent < 0 || rate > rec.bestPercent) {
      rec.bestPercent = rate;
    }
    if (rec.worstPercent < 0 || rate < rec.worstPercent) {
      rec.worstPercent = rate;
    }
    GameStats.levelRecords.set(level, rec);
  }

  /** 指定难度的四项纪录；没有记录时返回一份全空的纪录 */
  static levelRecord(level: string): LevelRecord {
    const r: LevelRecord | undefined = GameStats.levelRecords.get(level);
    if (r !== undefined) {
      return r;
    }
    return { played: 0, won: 0, slowest: -1, bestPercent: -1, worstPercent: -1 };
  }

  /**
   * 重置全部成绩（原版统计窗口底部的「重置(R)」按钮）。
   *
   * 原版语义：清空局数、连胜连败与各难度的最好成绩。
   */
  static async reset(): Promise<void> {
    GameStats.played = 0;
    GameStats.won = 0;
    GameStats.currentStreak = 0;
    GameStats.maxStreak = 0;
    GameStats.currentLoseStreak = 0;
    GameStats.maxLoseStreak = 0;
    GameStats.bestSeconds.clear();
    GameStats.bestDate.clear();
    GameStats.levelRecords.clear();
    await GameStats.save();
  }

  /** 胜率（百分比，整数） */
  static get percent(): number {
    if (GameStats.played <= 0) {
      return 0;
    }
    return Math.round((GameStats.won * 100) / GameStats.played);
  }

  /** 指定难度的最快用时（秒）；没有纪录时返回 -1 */
  static bestSecondsOf(level: string): number {
    const s = GameStats.bestSeconds.get(level);
    return s === undefined ? -1 : s;
  }

  /** 指定难度的最快用时文本；没有纪录时返回空串 */
  static bestTextOf(level: string): string {
    const s = GameStats.bestSeconds.get(level);
    if (s === undefined) {
      return '';
    }
    return s + '秒';
  }

  /** 指定难度的最快纪录日期 */
  static bestDateOf(level: string): string {
    const d = GameStats.bestDate.get(level);
    return d === undefined ? '' : d;
  }

  /** 当前难度名（用于查询纪录） */
  static level: string = '初级';

  private static levels(): string[] {
    return ['初级', '中级', '高级'];
  }

  private static async save(): Promise<void> {
    const store = GameStats.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('played', GameStats.played);
      await store.put('won', GameStats.won);
      await store.put('currentStreak', GameStats.currentStreak);
      await store.put('maxStreak', GameStats.maxStreak);
      await store.put('currentLoseStreak', GameStats.currentLoseStreak);
      await store.put('maxLoseStreak', GameStats.maxLoseStreak);
      for (const level of GameStats.levels()) {
        const s = GameStats.bestSeconds.get(level);
        if (s !== undefined) {
          await store.put('best_' + level, s);
        } else {
          await store.delete('best_' + level);
        }
        const d = GameStats.bestDate.get(level);
        if (d !== undefined) {
          await store.put('bestDate_' + level, d);
        } else {
          await store.delete('bestDate_' + level);
        }
        // 四项纪录（新增键）
        const rec: LevelRecord = GameStats.levelRecord(level);
        if (rec.played > 0 || rec.won > 0 || rec.slowest >= 0 ||
          rec.bestPercent >= 0 || rec.worstPercent >= 0) {
          await store.put('lvPlayed_' + level, rec.played);
          await store.put('lvWon_' + level, rec.won);
          await store.put('lvSlowest_' + level, rec.slowest);
          await store.put('lvBestPct_' + level, rec.bestPercent);
          await store.put('lvWorstPct_' + level, rec.worstPercent);
        }
      }
      await store.flush();
    } catch (err) {
      console.error('[GameStats] 写存档失败: ' + (err as Error).message);
    }
  }

  private static nowText(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : '' + n);
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
      p(d.getHours()) + ':' + p(d.getMinutes());
  }
}
