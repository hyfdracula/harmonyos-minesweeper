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
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'saolei_stats';

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
      for (const level of GameStats.levels()) {
        const s: number = Number(await GameStats.store.get('best_' + level, -1));
        const d: string = String(await GameStats.store.get('bestDate_' + level, ''));
        if (s >= 0) {
          GameStats.bestSeconds.set(level, s);
        }
        if (d.length > 0) {
          GameStats.bestDate.set(level, d);
        }
      }
    } catch (err) {
      console.error('[GameStats] 读取存档失败: ' + (err as Error).message);
    }
  }

  /** 记录一局结束（level = 难度名） */
  static async record(won: boolean, seconds: number, level: string): Promise<void> {
    GameStats.played += 1;
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
    await GameStats.save();
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
