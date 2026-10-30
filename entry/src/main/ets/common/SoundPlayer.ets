/**
 * SoundPlayer.ets —— 原版 Windows 7 扫雷音效
 *
 * 音效文件来自 win7-assets/audio（微软原版）：
 *   gameStart / gameWin / gameLose / tileSingle / tileMultiple / invalidMove /
 *   zeroDevelop / mineBombStart / mineBombRun / mineBombEnd / dbButtonClickFlag
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
  static readonly FLAG: string = 'dbButtonClickFlag';
  static readonly BOMB_START: string = 'mineBombStart';
  static readonly BOMB_RUN: string = 'mineBombRun';
  static readonly BOMB_END: string = 'mineBombEnd';
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

  private static async playAsync(ctx: common.UIAbilityContext, name: string): Promise<void> {
    let player = SoundPlayer.players.get(name);
    if (player === undefined) {
      const fdObj = await ctx.resourceManager.getRawFd(name + '.wav');
      const p = await media.createAVPlayer();
      p.fdSrc = { fd: fdObj.fd, offset: fdObj.offset, length: fdObj.length };
      await p.prepare();
      SoundPlayer.players.set(name, p);
      player = p;
    }
    // 坑（Codex 复审 P1）：stop() 之后播放器停在 stopped 状态，
    // seek(0) 不会把它变回 prepared，直接 play() 会失败（音效只能响一次）。
    // 所以要 stop → prepare → seek(0) → play。
    try {
      await player.stop();
    } catch (err) {
      // 没播过就 stop 会抛错，忽略
    }
    try {
      await player.prepare();
    } catch (err) {
      // 忽略
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
