/**
 * Index.ets —— 扫雷主页面
 *
 * M5 起：菜单栏、结束对话框、最佳成绩、关于框全部**画在画布上**（common/WinMenu.ets、
 * common/WinDialog.ets），与原版 Windows 一样属于"窗口的一部分"，不是手机浮层。
 * 页面本身只剩下一个铺满的画布。
 *
 * 坑（2026-10-31 真机实测）：
 *   1) `hitTestBehavior(HitTestMode.Block)` 加在容器上，会让它自己的子组件
 *      （Text/Button 的 onClick）收不到点击 —— 容器一律不要设 Block。
 *   2) 全屏遮罩会和面板里的条目抢同一次点击，条目随机失灵 —— 不要用遮罩，
 *      改用 controller.inputLocked 锁住棋盘输入。
 */

import { MinefieldCanvas } from '../components/MinefieldCanvas';
import { GameController, Difficulty } from '../common/GameController';
import { GameSession } from '../common/GameSession';
import { common } from '@kit.AbilityKit';
import { SoundPlayer } from '../common/SoundPlayer';

@Entry
@Component
struct Index {
  private controller: GameController = GameSession.controller;
  /** 结束对话框是否已显示（状态由控制器持有，这里只用于界面刷新） */
  @State private gameOver: boolean = false;
  @State private won: boolean = false;

  aboutToAppear(): void {
    this.controller.onGameOver = (isWin: boolean) => {
      this.won = isWin;
      this.gameOver = true;
    };
    // 结束对话框（画布自绘）的按钮动作
    this.controller.onDialogAction = (action: string) => {
      if (action === 'again') {
        this.newGame();
      } else if (action === 'menu') {
        this.controller.closeDialog();
        this.gameOver = false;
      } else if (action === 'exit') {
        this.controller.closeDialog();
        this.gameOver = false;
        this.exitApp();
      } else if (action === 'close') {
        this.controller.closeDialog();
        this.gameOver = false;
      }
    };
    // 菜单栏动作
    this.controller.onMenuAction = (action: string) => {
      if (action === 'new') {
        this.newGame();
      } else if (action === 'beginner') {
        this.startGame(Difficulty.Beginner);
      } else if (action === 'intermediate') {
        this.startGame(Difficulty.Intermediate);
      } else if (action === 'expert') {
        this.startGame(Difficulty.Expert);
      } else if (action === 'sound') {
        SoundPlayer.setEnabled(!SoundPlayer.isEnabled);
        this.controller.refreshMenu();
      } else if (action === 'marks') {
        this.controller.toggleQuestionMarks();
      } else if (action === 'best' || action === 'about' || action === 'help') {
        this.controller.openInfoDialog(action);
      } else if (action === 'custom') {
        this.controller.openCustomDialog();
      } else if (action === 'exit') {
        this.exitApp();
      }
    };
  }

  private startGame(d: Difficulty): void {
    console.info('[Menu] startGame 难度=' + d);
    try {
      this.gameOver = false;
      this.controller.setDifficulty(d);
      console.info('[Menu] startGame 完成，当前难度=' + this.controller.difficulty);
    } catch (e) {
      console.error('[Menu] startGame 异常: ' + (e as Error).message);
    }
  }

  private newGame(): void {
    this.gameOver = false;
    this.controller.restart();
  }

  /** 退出应用（对应原版菜单的「退出」） */
  private exitApp(): void {
    try {
      const ability = getContext(this) as common.UIAbilityContext;
      ability.terminateSelf();
    } catch (err) {
      console.error('[Index] 退出应用失败: ' + (err as Error).message);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 棋盘（菜单栏与对话框都画在这个画布上）
      Column() {
        MinefieldCanvas()
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#c6cede')
  }
}
