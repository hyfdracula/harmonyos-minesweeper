/**
 * SoundPlayer.ets —— 原版 Windows 7 扫雷音效
 *
 * 音效文件来自 win7-assets/audio（微软原版）：
 *   gameStart / gameWin / gameLose / tileSingle / tileMultiple / invalidMove /
 *   firstPaint / zeroDevelop / mineBombStart / mineBombRun / mineBombEnd / dbButtonClickFlag
 *   （已复制到 entry/src/main/resources/rawfile）
 *
 * 播放方式：用 resourceManager.getRawFd 拿到 rawfile 的 fd，交给 AVPlayer.fdSrc，
 * 免去把文件复制到沙箱目录这一步。fd 由 AVPlayer 持有，应用生命周期内不关闭。
 */

import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';

/** 音效名（原版文件名，不带 .wav） */
export class Sound {
  static readonly GAME_START: string = 'gameStart';
  static readonly GAME_WIN: string = 'gameWin';
  static readonly GAME_LOSE: string = 'gameLose';
  static readonly TILE_SINGLE: string = 'tileSingle';
  static readonly TILE_MULTIPLE: string = 'tileMultiple';
  static readonly INVALID_MOVE: string = 'invalidMove';
  /** 第一下的那声（参考实现在「首点开格」时播的就是它，不是 tileSingle） */
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
   * 分档规则来自 linux 复刻：雷数 ≤10 播 Short、≤40 播 Medium、更多播 Long ✓。
   */
  static readonly FLOWER_LOSE_SHORT: string = 'flowerLoseShort';
  static readonly FLOWER_LOSE_MEDIUM: string = 'flowerLoseMedium';
  static readonly FLOWER_LOSE_LONG: string = 'flowerLoseLong';
}

export class SoundPlayer {
  private static ctx: common.UIAbilityContext | null = null;
  private static players: Map<string, media.AVPlayer> = new Map();
  private static enabled: boolean = true;

  /** 初始化（拿到 AbilityContext 才能取 rawfile） */
  static init(ctx: common.UIAbilityContext): void {
    SoundPlayer.ctx = ctx;
  }

  static setEnabled(v: boolean): void {
    SoundPlayer.enabled = v;
  }

  static get isEnabled(): boolean {
    return SoundPlayer.enabled;
  }

  /** 播放一个音效（同步调用，实际播放在后台） */
  static play(name: string): void {
    if (!SoundPlayer.enabled) {
      return;
    }
    const ctx = SoundPlayer.ctx;
    if (ctx === null) {
      return;
    }
    SoundPlayer.playAsync(ctx, name).catch((err: Error) => {
      console.error('[Sound] 播放失败 ' + name + ': ' + err.message);
    });
  }

  /** 依次播放多个音效（爆炸是三段） */
  static playSequence(names: string[], gapMs: number): void {
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      setTimeout(() => {
        SoundPlayer.play(name);
      }, i * gapMs);
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
  private static async ensurePlayer(ctx: common.UIAbilityContext,
    name: string): Promise<media.AVPlayer> {
    const existing = SoundPlayer.players.get(name);
    if (existing !== undefined) {
      return existing;
    }
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
    SoundPlayer.players.set(name, p);
    return p;
  }

  private static async playAsync(ctx: common.UIAbilityContext, name: string): Promise<void> {
    const player = await SoundPlayer.ensurePlayer(ctx, name);
    // 重播：stop() 之后播放器停在 stopped，seek(0) 不会把它变回 prepared，
    // 所以要 stop → prepare → seek(0) → play。
    try {
      await player.stop();
    } catch (err) {
      // 没播过就 stop 会抛错，忽略
    }
    try {
      await player.prepare();
    } catch (err) {
      // 已经在 prepared 时 prepare 可能抛错，忽略
    }
    try {
      await player.seek(0);
    } catch (err) {
      // 某些状态下 seek 会抛错，忽略
    }
    await player.play();
  }

  /** 释放所有播放器 */
  static dispose(): void {
    SoundPlayer.players.forEach((p: media.AVPlayer) => {
      p.release().catch(() => {
      });
    });
    SoundPlayer.players.clear();
  }
}
