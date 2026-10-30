/**
 * Index.ets —— 扫雷主页面
 *
 * M1：全屏棋盘。菜单栏、难度选择、胜负对话框留到后续里程碑。
 */

import { MinefieldCanvas } from '../components/MinefieldCanvas';

@Entry
@Component
struct Index {
  build() {
    Column() {
      MinefieldCanvas()
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#c6cede')
  }
}
