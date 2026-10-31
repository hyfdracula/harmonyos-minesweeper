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
import { GameStats } from '../common/GameStats';
import { BoardStyle, GameStyle } from '../common/Theme';
import { SoundPlayer } from '../common/SoundPlayer';

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

/** 超过这个位移（vp）就认为是在拖动棋盘，而不是点击 */
const MOVE_THRESHOLD_VP: number = 10;

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

  /** 双指捏合状态 */
  private pinchActive: boolean = false;
  private pinchDist: number = 0;
  /** 手势起点的两指间距与当时的缩放档位（用于算累计缩放倍率） */
  private pinchStartDist: number = 0;
  private pinchStartScale: number = 3;
  private pinchMidX: number = 0;
  private pinchMidY: number = 0;

  aboutToAppear(): void {
    this.density = display.getDefaultDisplaySync().densityPixels;
    const abilityCtx = getContext(this) as common.UIAbilityContext;
    // 音效播放器需要 AbilityContext 才能取 rawfile
    SoundPlayer.init(abilityCtx);
    // 读统计（含**外观设置**）和图集，**两个都完成**才开局。
    //
    // 坑（2026-10-31 实测）：之前这两步是并行的（GameStats.load 不 await），
    // 结果「外观设置」的还原跑在存档读到之前 —— 读到的还是默认值 0，
    // 表现为「选了绿色棋盘，重启后又变回蓝色」。
    // 现在串起来：先等存档，再等图集，然后才套用存档里的外观。
    const statsReady: Promise<void> = GameStats.load(abilityCtx).catch(() => {
    });
    const atlasReady: Promise<void> = this.controller.atlas.load(abilityCtx);
    statsReady.then(() => atlasReady).then(() => {
      // 恢复上次的外观设置（原版重启后保留 ✓；存档读失败就还是默认蓝棋盘）
      const bs: BoardStyle = GameStats.boardStyle === 1 ? BoardStyle.Green : BoardStyle.Blue;
      const gs: GameStyle = GameStats.gameStyle === 1 ? GameStyle.Flowers : GameStyle.Mines;
      this.controller.atlas.applyStyle(bs, gs);
      if (this.controller.engine.rowCount <= 0) {
        // 第一次进来：按当前难度开新局
        const cfg = GameController.configOf(this.controller.difficulty);
        this.controller.startNewGame(cfg.rows, cfg.cols, cfg.mines, true);
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
        this.handleTouch(event);
      })
  }

  /**
   * 触摸处理：
   *   单指不动抬起 = 点击开格 / 双击和弦
   *   单指按住 400ms 不动 = 长按插旗
   *   单指按住并移动超过阈值 = 拖动棋盘（平移）
   *   双指 = 捏合缩放（吸附到整数档），同时跟随中点平移
   *
   * 坑：多指手势要用 event.touches（全部触点），changedTouches 只有变化的那些；
   *     双指变单指时必须把这次手势标记为「已移动」，否则抬手会被当成点击。
   */
  private handleTouch(event: TouchEvent): void {
    if (this.controller.inputLocked) {
      // 有对话框 / 统计窗口 / 自定义框开着时：**只让点击通过**，不做平移与捏合。
      // 注意不能在这里直接 return —— 那样连按钮都点不动了
      // （2026-10-31 真机踩到：结束对话框的按钮完全没反应）。
      if (event.type === TouchType.Down) {
        this.moved = false;
        this.longPressFired = false;
      } else if (event.type === TouchType.Up && !this.moved &&
        event.changedTouches.length > 0) {
        const t0 = event.changedTouches[0];
        this.handleTap(t0.x * this.density, t0.y * this.density);
      }
      return;
    }
    const touches = event.touches;
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      if (touches.length >= 2) {
        // 进入/维持双指：取消单击与长按
        this.clearLongPress();
        this.longPressFired = true;
        this.moved = true;
        this.updatePinch(touches);
        return;
      }
      if (this.pinchActive) {
        // 双指抬起一根：结束捏合，并把拖动原点重设到剩下的那根手指上
        // （坑，Codex 复审 P2）：不重设的话，之后那一小段移动会按最初按下点算位移，
        // 棋盘会被整个捏合的位移量甩出去。
        this.pinchActive = false;
        this.moved = true;
        if (touches.length > 0) {
          const t = touches[0];
          this.downX = t.x * this.density;
          this.downY = t.y * this.density;
        }
        return;
      }
      if (event.type === TouchType.Down) {
        const t = event.changedTouches.length > 0 ? event.changedTouches[0] : touches[0];
        const px = t.x * this.density;
        const py = t.y * this.density;
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
      } else {
        const t = event.changedTouches.length > 0 ? event.changedTouches[0] : touches[0];
        const px = t.x * this.density;
        const py = t.y * this.density;
        const limit = MOVE_THRESHOLD_VP * this.density;
        const dx = px - this.downX;
        const dy = py - this.downY;
        if (Math.abs(dx) > limit || Math.abs(dy) > limit) {
          if (!this.moved) {
            this.moved = true;
            this.clearLongPress();
          }
          // 拖动 = 平移棋盘
          console.info('[Touch] 平移 dx=' + Math.round(dx) + ' dy=' + Math.round(dy));
          this.controller.panBy(dx, dy);
          this.downX = px;
          this.downY = py;
        }
      }
    } else {
      // Up / Cancel
      this.clearLongPress();
      if (this.pinchActive) {
        this.pinchActive = false;
        this.moved = true;
        this.longPressFired = false;
        return;
      }
      if (event.type === TouchType.Up) {
        const t = event.changedTouches.length > 0 ? event.changedTouches[0] : null;
        if (!this.longPressFired && !this.moved && t !== null) {
          this.handleTap(t.x * this.density, t.y * this.density);
        }
      }
      this.longPressFired = false;
      this.moved = false;
    }
  }

  /** 双指捏合：按两指间距变化缩放，吸附到整数档；中点同时驱动平移 */
  private updatePinch(touches: TouchObject[]): void {
    const a = touches[0];
    const b = touches[1];
    const ax = a.x * this.density;
    const ay = a.y * this.density;
    const bx = b.x * this.density;
    const by = b.y * this.density;
    const dist = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    const midX = (ax + bx) / 2;
    const midY = (ay + by) / 2;

    if (!this.pinchActive) {
      // 记录手势起点：后续按「起点间距 → 当前间距」算总倍率
      this.pinchActive = true;
      this.pinchDist = dist;
      this.pinchStartDist = dist;
      this.pinchStartScale = this.controller.scaleIndex;
      this.pinchMidX = midX;
      this.pinchMidY = midY;
      return;
    }
    // 坑（Codex 复审 P1）：不能每次 move 只用 dist/prevDist 再取整——
    // 渐进捏合（比如每次放大 5%）每轮都被吸附回原档位，永远放大不了。
    // 必须以手势起点的间距和档位为基准，算累计倍率。
    if (this.pinchStartDist > 1) {
      const target = this.pinchStartScale * (dist / this.pinchStartDist);
      this.controller.zoomTo(target, midX, midY);
    }
    // 中点位移 → 平移
    this.controller.panBy(midX - this.pinchMidX, midY - this.pinchMidY);
    this.pinchDist = dist;
    this.pinchMidX = midX;
    this.pinchMidY = midY;
  }

  /**
   * 单击 = 开格；300ms 内再点同一格 = 和弦。
   * 第一下点在已翻开的数字格上时引擎不做任何事，所以双击不会被第一下吃掉。
   */
  private handleTap(px: number, py: number): void {
    // 统计信息窗口开着时，只吃它的点击
    if (this.controller.statsOpen) {
      const action = this.controller.statsButtonAt(px, py);
      if (action === 'reset') {
        console.info('[Stats] 点击重置');
        GameStats.reset().then(() => {
          this.controller.draw();
        }).catch(() => {
          this.controller.draw();
        });
      } else if (action === 'close') {
        console.info('[Stats] 点击关闭');
        this.controller.closeStats();
      }
      return;
    }
    // 「自定义」对话框开着时，只吃它的点击
    if (this.controller.customSpec !== null) {
      this.controller.customActionAt(px, py);
      return;
    }
    // 结束对话框优先：点它的按钮
    if (this.controller.dialog !== null) {
      const action = this.controller.dialogButtonAt(px, py);
      if (action !== null) {
        console.info('[Dialog] 点击按钮 ' + action);
        const cb = this.controller.onDialogAction;
        if (cb !== null) {
          cb(action);
        }
      }
      return;
    }
    // 菜单栏：菜单开着时优先吃菜单上的点击
    if (this.controller.menuOpenId.length > 0 || this.controller.isOnMenuBar(px, py)) {
      const action = this.controller.menuActionAt(px, py);
      if (action.length > 0) {
        console.info('[Menu] 菜单动作 ' + action);
        const cb = this.controller.onMenuAction;
        if (cb !== null) {
          cb(action);
        }
      }
      return;
    }
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

