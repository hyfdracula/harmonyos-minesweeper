/**
 * Anim.ets —— 原版 Windows 7 扫雷的动画
 *
 * 目前实现的：**踩雷爆炸动画**（8 帧火球）。
 *
 * 帧表是**从素材实测出来的**，不是猜的：
 *   素材 otherSheet.png（2048×2016），爆炸序列在 x≈1596..1665 这一列，
 *   8 帧沿 y 排列（用 alpha 通道逐行投影得到每一帧的上下边界）。
 *   下表用的是**逻辑坐标**（= 存储像素 / 2，与 SpriteAtlas 的 SPRITE_SCALE 对应），
 *   格式 [x, y, w, h]。
 *
 * 顺带记录：**Win7 插旗没有动画**（旗直接出现），所以本工程也不做；
 * 素材里的花朵是「花园版」变体的开花动画，与本项目无关。
 */
export class Anim {
  /**
   * 爆炸帧表（逻辑坐标，来源 otherSheet.png 实测）。
   * 每一帧的大小不同：先是一团火花，然后火球涨大再消散。
   */
  static readonly EXPLODE_FRAMES: number[][] = [
    [798, 19, 35, 19],
    [798, 70, 35, 35],
    [798, 136, 35, 20],
    [798, 194, 35, 22],
    [798, 253, 35, 23],
    [798, 311, 35, 23],
    [798, 370, 35, 23],
    [798, 433, 35, 17]
  ];

  /** 每帧停留时间（毫秒）：8 帧 ≈ 0.56 秒，和原版「炸一下就没」的手感接近 */
  static readonly FRAME_MS: number = 70;

  /** 爆炸动画是否在播 */
  static tripActive: boolean = false;
  /** 当前帧号 */
  static tripFrame: number = 0;
  /** 爆炸发生在第几格（格索引） */
  static tripCell: number = -1;

  /** 开始播放爆炸动画 */
  static startTrip(cellIndex: number): void {
    Anim.tripActive = true;
    Anim.tripFrame = 0;
    Anim.tripCell = cellIndex;
  }

  /** 停止爆炸动画 */
  static stopTrip(): void {
    Anim.tripActive = false;
    Anim.tripFrame = 0;
    Anim.tripCell = -1;
  }

  /** 推进一帧；返回 true 表示还在播（需要继续重绘） */
  static tick(): boolean {
    if (!Anim.tripActive) {
      return false;
    }
    Anim.tripFrame++;
    if (Anim.tripFrame >= Anim.EXPLODE_FRAMES.length) {
      Anim.tripActive = false;
      Anim.tripCell = -1;
      return false;
    }
    return true;
  }

  /** 当前帧的源矩形；不在播时返回 null */
  static currentRect(): number[] | null {
    if (!Anim.tripActive) {
      return null;
    }
    if (Anim.tripFrame < 0 || Anim.tripFrame >= Anim.EXPLODE_FRAMES.length) {
      return null;
    }
    return Anim.EXPLODE_FRAMES[Anim.tripFrame];
  }

  /** 全部动画都结束了 */
  static isIdle(): boolean {
    return !Anim.tripActive;
  }
}
