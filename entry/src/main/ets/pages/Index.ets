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
  }

  private startGame(d: Difficulty): void {
    this.menuOpen = false;
    this.gameOver = false;
    this.controller.setDifficulty(d);
  }

  private newGame(): void {
    this.menuOpen = false;
    this.gameOver = false;
    this.controller.restart();
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
            this.menuOpen = !this.menuOpen;
          })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      // 菜单面板
      if (this.menuOpen) {
        Stack({ alignContent: Alignment.TopStart }) {
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
              this.startGame(Difficulty.Beginner);
            })
          Text('中级 16×16')
            .fontSize(15)
            .fontColor(this.controller.difficulty === Difficulty.Intermediate ? '#1d5fd0' : '#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.startGame(Difficulty.Intermediate);
            })
          Text('高级 16×30')
            .fontSize(15)
            .fontColor(this.controller.difficulty === Difficulty.Expert ? '#1d5fd0' : '#2b3550')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.startGame(Difficulty.Expert);
            })
        }
        .width(150)
        .padding({ top: 14, bottom: 14, left: 6, right: 6 })
        .backgroundColor('#eef1f7')
        .borderRadius(10)
        .margin({ top: 66, left: 18 })
        .shadow({ radius: 8, color: '#40000000', offsetX: 0, offsetY: 2 })
        // 面板本身要吃掉触摸，否则点到面板空白处会穿透到棋盘上开格
        .hitTestBehavior(HitTestMode.Block)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 终局结算（居中）
      if (this.gameOver) {
        Stack({ alignContent: Alignment.Center }) {
        Column() {
          Text(this.won ? '扫雷成功' : '踩到雷了')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.won ? '#1a7f37' : '#b3261e')
            .margin({ bottom: 6 })
          Text(this.won ? `用时 ${this.controller.seconds} 秒` : '再来一局吧')
            .fontSize(14)
            .fontColor('#4a5169')
            .margin({ bottom: 14 })
          Button('再来一局')
            .fontSize(15)
            .backgroundColor('#1d5fd0')
            .onClick(() => {
              this.newGame();
            })
          Button('换个难度')
            .fontSize(15)
            .backgroundColor('#8b93a7')
            .margin({ top: 8 })
            .onClick(() => {
              this.menuOpen = true;
              this.gameOver = false;
            })
        }
        .width(220)
        .padding({ top: 22, bottom: 22 })
        .backgroundColor('#f2f4f9')
        .borderRadius(12)
        .shadow({ radius: 16, color: '#50000000', offsetX: 0, offsetY: 4 })
        // 结算面板吃掉触摸，别让点击穿透到棋盘
        .hitTestBehavior(HitTestMode.Block)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#c6cede')
  }
}

