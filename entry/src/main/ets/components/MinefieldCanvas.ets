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
 *   300ms 内连点同一格 = 和弦（双击已翻开的数字格）
 */

import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GameController } from '../common/GameController';
import { GameSession } from '../common/GameSession';

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

/** 双击判定的最大间隔（毫秒） */
const DOUBLE_TAP_MS: number = 300;

@Component
export struct MinefieldCanvas {
  /** 全局控制器（状态在页面生命周期之上，折叠/旋转不丢局） */
  private controller: GameController = GameSession.controller;

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

  /** 上一次点击：用于双击和弦 */
  private lastTapIndex: number = -1;
  private lastTapTime: number = 0;

  aboutToAppear(): void {
    this.density = display.getDefaultDisplaySync().densityPixels;
    const abilityCtx = getContext(this) as common.UIAbilityContext;
    this.controller.atlas.load(abilityCtx).then(() => {
      if (this.controller.engine.rowCount <= 0) {
        // 第一次进来：按当前难度开新局
        const cfg = GameController.configOf(this.controller.difficulty);
        this.controller.startNewGame(cfg.rows, cfg.cols, cfg.mines);
      } else {
        // 页面重建（折叠/旋转）：接着原局继续
        this.controller.resume();
      }
    }).catch((err: Error) => {
      console.error('[MinefieldCanvas] 图集加载失败: ' + err.message);
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
      .onReady((readyCtx: DrawingRenderingContext) => {
        // 坑：API 26 的类型声明说 onReady 的参数是 DrawingRenderingContext，
        // 但运行时给的其实是「构造 Canvas 时传进去的那个上下文对象」。
        // 本工程构造时传的是 CanvasRenderingContext2D，所以再调
        // getContext2DFromDrawingContext 会抛
        // "param is not a DrawingRenderingContext object" → 未捕获异常 → 应用被杀。
        // 所以这里直接用构造时的那个上下文。
        this.drawCtx = this.context;
        if (this.areaW <= 0 || this.areaH <= 0) {
          // 兜底：onAreaChange 还没回调时，用画布自己的尺寸（默认单位 vp）
          this.areaW = this.context.width;
          this.areaH = this.context.height;
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
            this.handleTap(px, py);
          }
          this.longPressFired = false;
        } else {
          this.clearLongPress();
          this.longPressFired = false;
        }
      })
  }

  /**
   * 单击 = 开格；300ms 内再点同一格 = 和弦。
   * 第一下点在已翻开的数字格上时引擎不做任何事，所以双击不会被第一下吃掉。
   */
  private handleTap(px: number, py: number): void {
    const idx = this.controller.hitTest(px, py);
    const now = Date.now();
    if (idx >= 0 && idx === this.lastTapIndex && now - this.lastTapTime < DOUBLE_TAP_MS) {
      this.lastTapIndex = -1;
      this.controller.chord(px, py);
      return;
    }
    this.lastTapIndex = idx;
    this.lastTapTime = now;
    this.controller.tap(px, py);
  }
}

