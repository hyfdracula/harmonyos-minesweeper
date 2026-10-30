/**
 * Index.ets —— 扫雷主页面
 *
 * M2：全屏棋盘 + 左上角菜单（难度切换 / 新游戏）+ 终局结算面板。
 *
 * 原版 Windows 的菜单栏和对话框在手机上没有对应物，这里用两个轻量浮层代替，
 * 全部放在棋盘区之外，不干扰棋盘本身的像素级还原。
 */

import { MinefieldCanvas } from '../components/MinefieldCanvas';
import { GameController, Difficulty } from '../common/GameController';
import { GameSession } from '../common/GameSession';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  /** 页面持有控制器，子组件只负责绘制与交互 */
  private controller: GameController = GameSession.controller;

  @State private menuOpen: boolean = false;
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
        this.setMenu(true);
      } else if (action === 'exit') {
        this.controller.closeDialog();
        this.gameOver = false;
        this.exitApp();
      }
    };
  }

  /** 退出应用（对应原版对话框的「退出(X)」） */
  private exitApp(): void {
    try {
      const ability = getContext(this) as common.UIAbilityContext;
      ability.terminateSelf();
    } catch (err) {
      console.error('[Index] 退出应用失败: ' + (err as Error).message);
    }
  }

  private startGame(d: Difficulty): void {
    console.info('[Menu] startGame 难度=' + d);
    try {
      this.setMenu(false);
      this.gameOver = false;
      this.controller.setDifficulty(d);
      console.info('[Menu] startGame 完成，当前难度=' + this.controller.difficulty);
    } catch (e) {
      console.error('[Menu] startGame 异常: ' + (e as Error).message);
    }
  }

  private newGame(): void {
    this.setMenu(false);
    this.gameOver = false;
    this.controller.restart();
  }

  /** 菜单开合：同时同步棋盘输入锁，菜单打开时棋盘不吃触摸 */
  private setMenu(open: boolean): void {
    this.menuOpen = open;
    this.controller.inputLocked = open;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 棋盘
      Column() {
        MinefieldCanvas()
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 左上角菜单按钮（放在棋盘外的空白角上）
      Stack({ alignContent: Alignment.TopStart }) {
        Button('≡')
          .width(40)
          .height(40)
          .fontSize(22)
          .fontColor('#2b3550')
          .backgroundColor('#e8ecf4')
          .borderRadius(20)
          .margin({ top: 18, left: 18 })
          .onClick(() => {
            this.setMenu(!this.menuOpen);
          })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      // 菜单面板
      if (this.menuOpen) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 菜单面板（自身保持默认命中模式）
          // 【踩坑】不能在这里铺一层全屏 hitTestBehavior(Block) 遮罩：
          // 遮罩会和面板里的条目抢同一次点击，条目就随机失灵。
          // 改成「菜单打开时锁住棋盘输入」（controller.inputLocked），棋盘不会误被点到。
          Column() {
          Text('扫雷')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2b3550')
            .margin({ bottom: 8 })
          Text('新游戏')
            .fontSize(15)
            .fontColor('#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.newGame();
            })
          Divider().color('#c3cadb')
          Text('初级 9×9')
            .fontSize(15)
            .fontColor(this.controller.difficulty === Difficulty.Beginner ? '#1d5fd0' : '#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              console.info('[Menu] 点击 初级 9x9');
              this.startGame(Difficulty.Beginner);
            })
          Text('中级 16×16')
            .fontSize(15)
            .fontColor(this.controller.difficulty === Difficulty.Intermediate ? '#1d5fd0' : '#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              console.info('[Menu] 点击 中级 16x16');
              this.startGame(Difficulty.Intermediate);
            })
          Text('高级 16×30')
            .fontSize(15)
            .fontColor(this.controller.difficulty === Difficulty.Expert ? '#1d5fd0' : '#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              console.info('[Menu] 点击 高级 16x30');
              this.startGame(Difficulty.Expert);
            })
        }
        .width(150)
        .padding({ top: 14, bottom: 14, left: 6, right: 6 })
        .backgroundColor('#eef1f7')
        .borderRadius(10)
        .margin({ top: 66, left: 18 })
        .shadow({ radius: 8, color: '#40000000', offsetX: 0, offsetY: 2 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 结束对话框不再用 ArkUI 面板：原版 Win7 风格的对话框直接画在画布上
      // （见 common/WinDialog.ets），这里只保留一个空壳避免误触。
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#c6cede')
  }
}

