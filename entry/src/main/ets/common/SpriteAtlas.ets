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
  /** Frame.png：棋盘区底板（九宫格，1 倍）。实测这张图上下颠倒、角落还藏着状态条素材，
   *  九宫格不能直接用，本项目不加载它 */
  frameSheet: image.PixelMap | null = null;
  /** helpBoard.png：原版帮助窗口插图（256x192，**1 倍**，不是 2 倍图） */
  helpBoard: image.PixelMap | null = null;

  /**
   * 已加载的 helpBoard 图（**静态**）。
   *
   * 为什么要静态：帮助对话框在 WinDialog.ets 里画这张图，而画对话框的是
   * GameController（那边正在改，不便动），所以用静态字段把 PixelMap 递过去。
   * 全局只有一份图集，静态不会有多份。
   */
  static helpBoardSheet: image.PixelMap | null = null;

  /** 是否已经加载过（页面重建时不必重复读资源） */
  loaded: boolean = false;

  /**
   * 设备像素 → 画布坐标的换算系数（= 1 / densityPixels）。
   *
   * Canvas 的绘制坐标系单位是 **vp**，而本工程内部一律按**设备像素**算
   * （格边必须落在整数设备像素上才有像素级效果），所以送进 Canvas 前要换算。
   */
  pxScale: number = 1;

  async load(ctx: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.boardSheet = await SpriteAtlas.loadPixelMap(ctx, 'blueSheet.png');
    this.gameSheet = await SpriteAtlas.loadPixelMap(ctx, 'minesweeperSheet.png');
    this.otherSheet = await SpriteAtlas.loadPixelMap(ctx, 'otherSheet.png');
    this.helpBoard = await SpriteAtlas.loadPixelMap(ctx, 'helpBoard.png');
    SpriteAtlas.helpBoardSheet = this.helpBoard;
    this.loaded = true;
    console.info('[SpriteAtlas] 图集加载完成 board=' + (this.boardSheet !== null) +
      ' game=' + (this.gameSheet !== null) + ' other=' + (this.otherSheet !== null) +
      ' help=' + (this.helpBoard !== null));
  }

  private static async loadPixelMap(ctx: common.UIAbilityContext, name: string): Promise<image.PixelMap | null> {
    try {
      const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(name);
      console.info('[SpriteAtlas] ' + name + ' 读到 ' + bytes.length + ' 字节');
      const source = image.createImageSource(bytes.buffer);
      if (source === null) {
        console.error('[SpriteAtlas] ' + name + ' createImageSource 返回空');
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
   *
   * 单位陷阱（实测）：Canvas 坐标单位是 **vp**；而且 **PixelMap 源的裁剪矩形
   * (sx,sy,sw,sh) 在 API 18 起默认单位也是 vp**（更早才是 px）。
   * 所以源矩形和目标矩形都要乘 pxScale 换算，否则会从图集里裁到错的区域。
   *
   * @param srcRect 逻辑坐标 [x, y, w, h]，取源像素时自动乘 SPRITE_SCALE
   * @param dx,dy,dw,dh 目标矩形（**设备像素**，内部会换算成 vp）
   */
  draw(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcRect: number[], dx: number, dy: number, dw: number, dh: number): void {
    if (sheet === null) {
      return;
    }
    const s = this.pxScale;
    const sx = srcRect[0] * SPRITE_SCALE * s;
    const sy = srcRect[1] * SPRITE_SCALE * s;
    const sw = srcRect[2] * SPRITE_SCALE * s;
    const sh = srcRect[3] * SPRITE_SCALE * s;
    ctx.drawImage(sheet, sx, sy, sw, sh, dx * s, dy * s, dw * s, dh * s);
  }

  /**
   * 按逻辑尺寸画：目标边长 = 逻辑尺寸 × unit。
   * unit = 2×n 时正好等于源像素的 n 倍，最近邻放大不会糊。
   */
  drawLogical(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcRect: number[], dx: number, dy: number, unit: number): void {
    this.draw(ctx, sheet, srcRect, dx, dy, srcRect[2] * unit, srcRect[3] * unit);
  }

  /**
   * 把一整张 **1:1 的图**画到画布上（源坐标**不乘 SPRITE_SCALE**）。
   *
   * 给 helpBoard.png（256x192 原图）用。上面那个 draw() 会把源矩形乘 SPRITE_SCALE(=2)，
   * 用在 1:1 图上会从图里裁到错的地方（×2 直接裁到图外 → 画出一片空白）。
   *
   * 放大倍数必须是**整数**：这样每个源像素正好占 scale 个设备像素，
   * 配合 imageSmoothingEnabled=false 就是最近邻放大，边缘不会糊。
   *
   * @param sheet  源图（null 时什么都不画）
   * @param srcW   源图宽（**源像素**）
   * @param srcH   源图高（**源像素**）
   * @param devX   目标左上角（**设备像素**）
   * @param devY   同上
   * @param scale  放大倍数（整数）
   * @param pxScale vp / 设备像素（Canvas 与 PixelMap 裁剪矩形都用它换算）
   */
  static drawWhole(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcW: number, srcH: number, devX: number, devY: number, scale: number, pxScale: number): void {
    if (sheet === null) {
      return;
    }
    // 最近邻：放大后每个源像素都是硬边，不发虚
    const smooth: boolean = ctx.imageSmoothingEnabled;
    ctx.imageSmoothingEnabled = false;
    // 源矩形用 vp（API 18+ PixelMap 裁剪矩形默认单位是 vp）
    ctx.drawImage(sheet,
      0, 0, srcW * pxScale, srcH * pxScale,
      devX / pxScale, devY / pxScale,
      srcW * scale / pxScale, srcH * scale / pxScale);
    ctx.imageSmoothingEnabled = smooth;
  }
}
