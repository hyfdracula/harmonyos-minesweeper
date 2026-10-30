/**
 * MinefieldCanvas.ets —— 棋盘画布组件
 *
 * 负责三件事：
 *   1) 把画布上下文和尺寸交给 GameController（换算成设备像素）
 *   2) 加载精灵图集
 *   3) 把触摸事件换算成设备像素后转给控制器
 *
 * 手势用 onTouch 自己判定，不依赖 ArkUI 手势构造器：
 *   按下 → 记录位置并起 400ms 定时器（长按插旗）
 *   移动 → 超过阈值取消长按
 *   抬起 → 没触发过长按且没怎么移动 = 单击开格
 */

import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GameController } from '../common/GameController';

/** ArkUI 的长度可能是数字、百分比字符串或资源，这里统一取数字 */
function lengthToNumber(v: Length): number {
  if (typeof v === 'number') {
    return v;
  }
  if (typeof v === 'string') {
    return parseFloat(v);
  }
  return 0;
}

@Component
export struct MinefieldCanvas {
  controller: GameController = new GameController();

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  /** 实际用来绘图的上下文（API 26 的 onReady 给的是 DrawingRenderingContext，要桥接） */
  private drawCtx: CanvasRenderingContext2D | null = null;
  private areaW: number = 0;
  private areaH: number = 0;
  private density: number = 2.625;
  private ctxReady: boolean = false;

  /** 按下位置（设备像素） */
  private downX: number = 0;
  private downY: number = 0;
  private moved: boolean = false;
  private longPressFired: boolean = false;
  private longPressTimer: number = -1;

  aboutToAppear(): void {
    this.density = display.getDefaultDisplaySync().densityPixels;
    const abilityCtx = getContext(this) as common.UIAbilityContext;
    this.controller.atlas.load(abilityCtx).then(() => {
      this.controller.startNewGame(9, 9, 10);
    });
  }

  aboutToDisappear(): void {
    this.clearLongPress();
    this.controller.dispose();
  }

  private tryAttach(): void {
    if (!this.ctxReady || this.drawCtx === null || this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    this.controller.attach(this.drawCtx, this.areaW, this.areaH, this.density);
  }

  private clearLongPress(): void {
    if (this.longPressTimer !== -1) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady((drawingCtx: DrawingRenderingContext) => {
        // API 26 起 onReady 给的是新的 DrawingRenderingContext，
        // 用 getContext2DFromDrawingContext 桥接回经典的 2D 绘图上下文。
        // 桥接出来的对象与该 Canvas 组件绑定，绘制会落到同一个画布上。
        this.drawCtx = CanvasRenderingContext2D.getContext2DFromDrawingContext(drawingCtx);
        if (this.areaW <= 0 || this.areaH <= 0) {
          // 兜底：onAreaChange 还没回调时，用画布自己的尺寸（默认单位 vp）
          this.areaW = drawingCtx.size.width;
          this.areaH = drawingCtx.size.height;
        }
        this.ctxReady = true;
        this.tryAttach();
      })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 组件尺寸单位是 vp，换算成设备像素由 GameController 处理
        this.areaW = lengthToNumber(newArea.width);
        this.areaH = lengthToNumber(newArea.height);
        this.tryAttach();
      })
      .onTouch((event: TouchEvent) => {
        if (event.changedTouches.length === 0) {
          return;
        }
        const t = event.changedTouches[0];
        const px = t.x * this.density;
        const py = t.y * this.density;
        if (event.type === TouchType.Down) {
          this.downX = px;
          this.downY = py;
          this.moved = false;
          this.longPressFired = false;
          this.clearLongPress();
          this.longPressTimer = setTimeout(() => {
            this.longPressFired = true;
            this.longPressTimer = -1;
            this.controller.longPress(px, py);
          }, 400);
        } else if (event.type === TouchType.Move) {
          const limit = 12 * this.density;
          if (Math.abs(px - this.downX) > limit || Math.abs(py - this.downY) > limit) {
            this.moved = true;
            this.clearLongPress();
          }
        } else if (event.type === TouchType.Up) {
          this.clearLongPress();
          if (!this.longPressFired && !this.moved) {
            this.controller.tap(px, py);
          }
          this.longPressFired = false;
        } else {
          this.clearLongPress();
          this.longPressFired = false;
        }
      })
  }
}
