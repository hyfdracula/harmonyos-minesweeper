/**
 * GameStats.ets —— 局数统计与各难度最快纪录（持久化到 Preferences）
 *
 * 原版结束对话框里有「已玩游戏 / 已胜游戏 / 百分比 / 最快时间 + 日期」，
 * 这里用 @kit.ArkData 的 preferences 实现。
 *
 * 坑（2026-10-31）：ArkTS 的静态方法里不允许用 this（arkts-no-standalone-this），
 *    所以这里一律写类名 GameStats.xxx。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'saolei_stats';

export class GameStats {
  /** 已玩总局数 */
  static played: number = 0;
  /** 已获胜局数 */
  static won: number = 0;
  /** 最快用时（秒）；-1 表示还没有纪录 */
  static bestSeconds: number = -1;
  /** 最快纪录的日期文本 */
  static bestDate: string = '';

  private static store: preferences.Preferences | null = null;

  /** 读取存档（异步，失败不阻塞游戏） */
  static async load(ctx: common.UIAbilityContext): Promise<void> {
    try {
      GameStats.store = await preferences.getPreferences(ctx, { name: STORE_NAME });
      const p: number = Number(await GameStats.store.get('played', 0));
      const w: number = Number(await GameStats.store.get('won', 0));
      const b: number = Number(await GameStats.store.get('bestSeconds', -1));
      const d: string = String(await GameStats.store.get('bestDate', ''));
      GameStats.played = p;
      GameStats.won = w;
      GameStats.bestSeconds = b;
      GameStats.bestDate = d;
    } catch (err) {
      console.error('[GameStats] 读取存档失败: ' + (err as Error).message);
    }
  }

  /** 记录一局结束 */
  static async record(won: boolean, seconds: number): Promise<void> {
    GameStats.played += 1;
    if (won) {
      GameStats.won += 1;
      if (GameStats.bestSeconds < 0 || seconds <= GameStats.bestSeconds) {
        GameStats.bestSeconds = seconds;
        GameStats.bestDate = GameStats.nowText();
      }
    }
    await GameStats.save();
  }

  /** 胜率（百分比，整数） */
  static get percent(): number {
    if (GameStats.played <= 0) {
      return 0;
    }
    return Math.round((GameStats.won * 100) / GameStats.played);
  }

  /** 最快用时文本；没有纪录时返回空串 */
  static get bestText(): string {
    if (GameStats.bestSeconds < 0) {
      return '';
    }
    return GameStats.bestSeconds + '秒';
  }

  private static async save(): Promise<void> {
    const store = GameStats.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('played', GameStats.played);
      await store.put('won', GameStats.won);
      await store.put('bestSeconds', GameStats.bestSeconds);
      await store.put('bestDate', GameStats.bestDate);
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
