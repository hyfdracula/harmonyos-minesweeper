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
import { BoardStyle, GameStyle } from './Theme';

/** 图集：棋盘 + 游戏 + 动画 + 底板 */
export class SpriteAtlas {
  /** blueSheet / greenSheet：砖块渐变、旗、问号、高亮、红叉、阴影、数字、计数器面板 */
  blueBoardSheet: image.PixelMap | null = null;
  greenBoardSheet: image.PixelMap | null = null;
  /**
   * **当前**棋盘图集（按 boardStyle 选）。
   *
   * 为什么保留这个字段而不是让调用方自己选：GameController 里有十几处
   * `this.atlas.boardSheet`，如果改成方法，这十几处都得动（而 GameController
   * 现在别人在改）。保留字段 + 一个 applyStyle() 切换点，改动面最小。
   */
  boardSheet: image.PixelMap | null = null;
  /** minesweeperSheet / flowerGardenSheet：地雷、面板雷图标 */
  mineGameSheet: image.PixelMap | null = null;
  flowerGameSheet: image.PixelMap | null = null;
  /** **当前**游戏图集（按 gameStyle 选） */
  gameSheet: image.PixelMap | null = null;
  /** otherSheet：时钟、踩雷动画、拆雷动画、胜利扫描条 */
  otherSheet: image.PixelMap | null = null;
  /** Frame.png：棋盘区底板（九宫格，1 倍）。实测这张图上下颠倒、角落还藏着状态条素材，
   *  九宫格不能直接用，本项目不加载它 */
  frameSheet: image.PixelMap | null = null;
  /** helpBoard.png：原版帮助窗口插图（256x192，**1 倍**，不是 2 倍图） */
  helpBoard: image.PixelMap | null = null;
  /** 外观对话框的四张缩略图（**1 倍**原图：thumbMines/thumbFlowers 92×92，thumbBlue/thumbGreen 109×109） */
  thumbMines: image.PixelMap | null = null;
  thumbFlowers: image.PixelMap | null = null;
  thumbBlue: image.PixelMap | null = null;
  thumbGreen: image.PixelMap | null = null;

  /** 当前棋盘样式（蓝 / 绿） */
  boardStyle: BoardStyle = BoardStyle.Blue;
  /** 当前游戏样式（扫雷 / 花园） */
  gameStyle: GameStyle = GameStyle.Mines;

  /**
   * 已加载的 helpBoard 图（**静态**）。
   *
   * 为什么要静态：帮助对话框在 WinDialog.ets 里画这张图，而画对话框的是
   * GameController（那边正在改，不便动），所以用静态字段把 PixelMap 递过去。
   * 全局只有一份图集，静态不会有多份。
   */
  static helpBoardSheet: image.PixelMap | null = null;

  /**
   * 外观对话框的四张缩略图（**静态**）。
   *
   * 理由同 helpBoardSheet：画对话框的是 WinDialog.ets（静态方法，没有图集实例），
   * 所以用静态字段把 PixelMap 递过去。
   */
  static thumbMinesSheet: image.PixelMap | null = null;
  static thumbFlowersSheet: image.PixelMap | null = null;
  static thumbBlueSheet: image.PixelMap | null = null;
  static thumbGreenSheet: image.PixelMap | null = null;

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
    this.blueBoardSheet = await SpriteAtlas.loadPixelMap(ctx, 'blueSheet.png');
    this.greenBoardSheet = await SpriteAtlas.loadPixelMap(ctx, 'greenSheet.png');
    this.mineGameSheet = await SpriteAtlas.loadPixelMap(ctx, 'minesweeperSheet.png');
    this.flowerGameSheet = await SpriteAtlas.loadPixelMap(ctx, 'flowerGardenSheet.png');
    this.otherSheet = await SpriteAtlas.loadPixelMap(ctx, 'otherSheet.png');
    this.helpBoard = await SpriteAtlas.loadPixelMap(ctx, 'helpBoard.png');
    this.thumbMines = await SpriteAtlas.loadPixelMap(ctx, 'thumbMines.png');
    this.thumbFlowers = await SpriteAtlas.loadPixelMap(ctx, 'thumbFlowers.png');
    this.thumbBlue = await SpriteAtlas.loadPixelMap(ctx, 'thumbBlue.png');
    this.thumbGreen = await SpriteAtlas.loadPixelMap(ctx, 'thumbGreen.png');
    SpriteAtlas.helpBoardSheet = this.helpBoard;
    SpriteAtlas.thumbMinesSheet = this.thumbMines;
    SpriteAtlas.thumbFlowersSheet = this.thumbFlowers;
    SpriteAtlas.thumbBlueSheet = this.thumbBlue;
    SpriteAtlas.thumbGreenSheet = this.thumbGreen;
    // 当前生效的图集（默认蓝 + 扫雷）
    this.applyStyle(this.boardStyle, this.gameStyle);
    this.loaded = true;
    console.info('[SpriteAtlas] 图集加载完成 board=' + (this.boardSheet !== null) +
      ' game=' + (this.gameSheet !== null) + ' other=' + (this.otherSheet !== null) +
      ' help=' + (this.helpBoard !== null) +
      ' green=' + (this.greenBoardSheet !== null) +
      ' flower=' + (this.flowerGameSheet !== null) +
      ' thumbs=' + (this.thumbMines !== null && this.thumbFlowers !== null &&
        this.thumbBlue !== null && this.thumbGreen !== null));
  }

  /**
   * 切换棋盘样式 / 游戏样式（外观对话框点「确定」时调用）。
   *
   * 只换引用，不重画：下一帧 draw() 会用新的 boardSheet / gameSheet。
   */
  applyStyle(board: BoardStyle, game: GameStyle): void {
    this.boardStyle = board;
    this.gameStyle = game;
    this.boardSheet = board === BoardStyle.Green ? this.greenBoardSheet : this.blueBoardSheet;
    this.gameSheet = game === GameStyle.Flowers ? this.flowerGameSheet : this.mineGameSheet;
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
    //
    // 坑（2026-10-31，lead 实测发现）：目标矩形要**乘** pxScale 不是除。
    // pxScale = 1/density（vp 每设备像素），所以设备像素 → vp 是「乘 pxScale」。
    // 原来写成 devX / pxScale，等于乘了 density（3.125 倍），
    // 图被画到画布外十倍远的地方去，看上去就是「什么都没画」。
    ctx.drawImage(sheet,
      0, 0, srcW * pxScale, srcH * pxScale,
      devX * pxScale, devY * pxScale,
      srcW * scale * pxScale, srcH * scale * pxScale);
    ctx.imageSmoothingEnabled = smooth;
  }

  /**
   * 把一张 **1:1 的图**画进指定的**设备像素**矩形（源坐标**不乘 SPRITE_SCALE**）。
   *
   * 与 drawWhole 的区别：drawWhole 要求放大倍数是整数（整块平移，最近邻不会错位），
   * 这里允许任意比例 —— 外观对话框里的四张缩略图要放进按参考像素定尺寸的框里，
   * 缩放倍数不是整数（源 92/109 px，框 64/76 参考像素）。
   *
   * @param sheet  源图（null 时什么都不画）
   * @param srcW   源图宽（**源像素**）
   * @param srcH   源图高（源像素）
   * @param devX   目标矩形左上角（**设备像素**）
   * @param devY   同上
   * @param devW   目标矩形宽（设备像素）
   * @param devH   目标矩形高（设备像素）
   * @param pxScale vp / 设备像素（Canvas 与 PixelMap 裁剪矩形都用它换算）
   */
  static drawWholeToRect(ctx: CanvasRenderingContext2D, sheet: image.PixelMap | null,
    srcW: number, srcH: number, devX: number, devY: number, devW: number, devH: number,
    pxScale: number): void {
    if (sheet === null) {
      return;
    }
    // 最近邻：缩放后边缘是硬边，不发虚
    const smooth: boolean = ctx.imageSmoothingEnabled;
    ctx.imageSmoothingEnabled = false;
    // 源矩形用 vp（API 18+ PixelMap 裁剪矩形默认单位是 vp），目标矩形同样是 vp
    ctx.drawImage(sheet,
      0, 0, srcW * pxScale, srcH * pxScale,
      devX * pxScale, devY * pxScale,
      devW * pxScale, devH * pxScale);
    ctx.imageSmoothingEnabled = smooth;
  }
}
