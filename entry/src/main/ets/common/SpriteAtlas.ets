/**
 * SpriteAtlas.ets —— 精灵图集加载与绘制
 *
 * 素材放在 entry/src/main/resources/rawfile/ 下，用 resourceManager 读出来，
 * 解成 PixelMap 后按逻辑坐标切片绘制。
 *
 * 绘制坐标约定：**全部用设备像素（px）**，不用 vp。
 * 原因：素材一格是 36 存储像素，要像素锐利就必须让格子的设备像素数是 36 的整数倍；
 * 用 vp 画会引入小数，缩放插值就把边缘弄糊了。
 * 所以 unit（每个逻辑单位的设备像素数）取 2×缩放档位，整数倍。
 */

import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { SPRITE_SCALE } from './Theme';

/** 图集：棋盘 + 游戏 + 动画 + 底板 */
export class SpriteAtlas {
  /** blueSheet / greenSheet：砖块渐变、旗、问号、高亮、红叉、阴影、数字、计数器面板 */
  boardSheet: image.PixelMap | null = null;
  /** minesweeperSheet / flowerGardenSheet：地雷、面板雷图标 */
  gameSheet: image.PixelMap | null = null;
  /** otherSheet：时钟、踩雷动画、拆雷动画、胜利扫描条 */
  otherSheet: image.PixelMap | null = null;
  /** Frame.png：棋盘区底板（九宫格，1 倍） */
  frameSheet: image.PixelMap | null = null;

  async load(ctx: common.UIAbilityContext): Promise<void> {
    this.boardSheet = await SpriteAtlas.loadPixelMap(ctx, 'blueSheet.png');
    this.gameSheet = await SpriteAtlas.loadPixelMap(ctx, 'minesweeperSheet.png');
    this.otherSheet = await SpriteAtlas.loadPixelMap(ctx, 'otherSheet.png');
    this.frameSheet = await SpriteAtlas.loadPixelMap(ctx, 'Frame.png');
  }

  private static async loadPixelMap(ctx: common.UIAbilityContext, name: string): Promise<image.PixelMap | null> {
    try {
      const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(name);
      const source = image.createImageSource(bytes.buffer);
      if (source === null) {
        return null;
      }
      const pixelMap = await source.createPixelMap();
      source.release();
      return pixelMap;
    } catch (err) {
      console.error(`[SpriteAtlas] 加载 ${name} 失败: ${err}`);
      return null;
    }
  }

  /**
   * 从图集裁一块画出来。
   * @param srcRect 逻辑坐标 [x, y, w, h]，取源像素时自动乘 SPRITE_SCALE
   * @param dx,dy,dw,dh 目标矩形（设备像素）
   */
  draw(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcRect: number[], dx: number, dy: number, dw: number, dh: number): void {
    if (sheet === null) {
      return;
    }
    const sx = srcRect[0] * SPRITE_SCALE;
    const sy = srcRect[1] * SPRITE_SCALE;
    const sw = srcRect[2] * SPRITE_SCALE;
    const sh = srcRect[3] * SPRITE_SCALE;
    ctx.drawImage(sheet, sx, sy, sw, sh, dx, dy, dw, dh);
  }

  /**
   * 按逻辑尺寸画：目标边长 = 逻辑尺寸 × unit。
   * unit = 2×n 时正好等于源像素的 n 倍，最近邻放大不会糊。
   */
  drawLogical(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcRect: number[], dx: number, dy: number, unit: number): void {
    this.draw(ctx, sheet, srcRect, dx, dy, srcRect[2] * unit, srcRect[3] * unit);
  }
}
