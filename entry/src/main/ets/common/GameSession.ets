/**
 * GameSession.ets —— 全局会话
 *
 * 游戏状态放在页面生命周期之上：折叠屏展开/收起、屏幕旋转、页面重建时，
 * 局面、计时、难度都不会丢。这是折叠屏适配的前提（M4）。
 *
 * 用模块级单例而不是往子组件传参，避免依赖 ArkUI 非状态变量的初始化规则。
 */

import { GameController } from './GameController';

export class GameSession {
  /** 全局唯一的游戏控制器 */
  static controller: GameController = new GameController();
}
