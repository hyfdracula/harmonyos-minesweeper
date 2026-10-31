/**
 * Appearance.ets —— Win7「游戏 → 外观(Change Appearance)」对话框
 *
 * ============================================================================
 * 为什么要有这个文件
 * ============================================================================
 * 原版 Win7 扫雷的「游戏」菜单里有一项「Change Appearance」（F7），弹出一个
 * 带两组单选图示的对话框：
 *   - Select Game Style：Minesweeper（thumbMines.png）/ Flower Garden（thumbFlowers.png）
 *   - Select Board：Silver and Blue（thumbBlue.png）/ Green（thumbGreen.png）
 *   - 外加一个复选框「Randomly choose game style and board」（原版有，Linux 复刻没实现、置灰）
 *
 * 证据链：
 *   - linux-minesweeper/src/ui/AppearanceDialog.h:6 原文
 *     "The Game > Change Appearance dialog, laid out like Windows 7's: a
 *      'Select Game Style' group and a 'Select Board' group, each holding ..."
 *   - linux-minesweeper/src/ui/HelpDialog.cpp:56-68 复刻的 **Win7 帮助原文**：
 *     "To customize the game's appearance / Click the **Game** menu, and then
 *      click **Change Appearance**. / Make your choices, and then click **OK**."
 *     → 原版是**点确定才生效**，不是即时生效；且原版**有确定按钮**。
 *   - linux-minesweeper/src/ui/AppearanceDialog.cpp:151-164 两组的图示与标题
 *   - 原版 exe 里带着这四张缩略图（win7-assets/images/thumb*.png）
 *
 * ============================================================================
 * 本文件的职责边界
 * ============================================================================
 * 这个对话框**画在画布上**（和结束/最佳成绩/关于那几个框同一套体系），
 * 所以它本身就是一个 DlgSpec：分组框、缩略图、复选框都由 WinDialog.ets 画
 * （WinDialogPainter.draw / hitButton 都认识 spec.groups 与 spec.thumbs）。
 *
 * 好处：GameController 那边**不用新增任何绘制/命中代码**，
 * 复用现成的 this.dialog + drawDialog() + dialogButtonAt()，
 * 只需在 dialogButtonAt() 里多处理两类动作 id（见 docs/APPEARANCE-DIALOG.md 的 diff 建议）。
 *
 * ============================================================================
 * 单位约定（与 WinDialog.ets 一致）
 * ============================================================================
 *   * 几何用「参考像素」（参考图 1 倍像素）；绘制时几何乘 sVp，字号乘 sDev。
 *   * 缩略图是 **1:1 的源图**（92×92 / 109×109），源坐标**不乘 SPRITE_SCALE**。
 */

import { SpriteAtlas } from './SpriteAtlas';
import { BoardStyle, GameStyle } from './Theme';
import { DlgSpec, DlgGroup, DlgThumb, DlgCheckBox } from './WinDialog';

/** 对话框参考尺寸（参考像素） */
const DLG_W: number = 420;
const DLG_H: number = 340;

/** 缩略图源图尺寸（**源像素**，1:1 原图） */
const THUMB_MINE_W: number = 92;
const THUMB_MINE_H: number = 92;
const THUMB_BOARD_W: number = 109;
const THUMB_BOARD_H: number = 109;

/** 缩略图在对话框里的显示边长（参考像素） */
const THUMB_MINE_BOX: number = 64;
const THUMB_BOARD_BOX: number = 76;

/**
 * 「颜色」菜单项的显示文字（2026-10-31 由 **lead 按用户本人的 Win7 拍板**）。
 *
 * 用户原话：他的 Windows 7 扫雷点开「游戏(G)」菜单里**确实有「颜色(C)」这一项** ✓
 * （这是关于「原版到底有没有这一项」的唯一权威来源——原版 exe 的菜单资源
 * `ID_MENUITEM_COLOR 529` 也指向同一个名字）。
 *
 * 证据状况（其余两个待定点，见 docs\APPEARANCE-DIALOG.md）：
 *   - 原版 Win7 的英文串是 "Change Appearance"（F7）。证据：Linux 复刻里逐字镜像的
 *     Win7 帮助原文 linux-minesweeper/src/ui/HelpDialog.cpp:56-68
 *     "To customize the game's appearance … Click the Game menu, and then click
 *      **Change Appearance**. Make your choices, and then click **OK**."，
 *     以及 AppearanceDialog.h:6 "The Game > Change Appearance dialog, laid out like Windows 7's"。
 *   - refs 里**找不到中文串**（中文只有 Lmy0217 那个 Win32 复刻自己的菜单）。
 *   - 所以中文名取**用户 Win7 上的真名「颜色(C)」** ✓（英文直译「外观」只是备选）。
 *
 * 要改回「外观(C)」只改这一行。
 */
export const MENU_APPEARANCE_LABEL: string = '颜色(C)';

/** 对话框标题（不带菜单快捷键提示）—— 与菜单项同名 */
export const APPEARANCE_DIALOG_TITLE: string = '颜色';

export class Appearance {
  /**
   * 待定的棋盘样式（蓝 / 绿）。
   *
   * 点缩略图只改这里的**待定值**，点「确定」才真正应用到图集 ——
   * 原版就是这个语义（Win7 帮助原文：Make your choices, and then click OK）。
   */
  static pendingBoard: BoardStyle = BoardStyle.Blue;
  /** 待定的游戏样式（扫雷 / 花园） */
  static pendingGame: GameStyle = GameStyle.Mines;

  /** 对话框参考宽（参考像素） */
  static width(): number {
    return DLG_W;
  }

  /** 对话框参考高（参考像素） */
  static height(): number {
    return DLG_H;
  }

  /**
   * 打开对话框：把当前**生效**的样式带进来当初值。
   *
   * @param board 当前生效的棋盘样式
   * @param game  当前生效的游戏样式
   */
  static begin(board: BoardStyle, game: GameStyle): DlgSpec {
    Appearance.pendingBoard = board;
    Appearance.pendingGame = game;
    return Appearance.spec();
  }

  /**
   * 生成对话框规格（选中态跟着待定值走）。
   *
   * 每次重画前重新生成一份即可 —— 选中态变了，规格也要跟着变。
   */
  static spec(): DlgSpec {
    const groups: DlgGroup[] = [
      // 第 1 组：游戏样式（缩略图 64×64，说明文字墨迹顶 124 —— 让开选中框的下边框 4 参考像素）
      { title: '游戏样式', x: 12, y: 40, w: 396, h: 104 },
      // 第 2 组：棋盘（缩略图 76×76，说明文字墨迹顶 260）
      { title: '棋盘', x: 12, y: 164, w: 396, h: 112 }
    ];
    const thumbs: DlgThumb[] = [
      {
        id: 'thumb:style:mines',
        sheet: SpriteAtlas.thumbMinesSheet,
        srcW: THUMB_MINE_W,
        srcH: THUMB_MINE_H,
        x: 40, y: 52, w: THUMB_MINE_BOX, h: THUMB_MINE_BOX,
        caption: '扫雷', captionY: 120,
        selected: Appearance.pendingGame === GameStyle.Mines
      },
      {
        id: 'thumb:style:flowers',
        sheet: SpriteAtlas.thumbFlowersSheet,
        srcW: THUMB_MINE_W,
        srcH: THUMB_MINE_H,
        x: 226, y: 52, w: THUMB_MINE_BOX, h: THUMB_MINE_BOX,
        caption: '花园', captionY: 120,
        selected: Appearance.pendingGame === GameStyle.Flowers
      },
      {
        id: 'thumb:board:blue',
        sheet: SpriteAtlas.thumbBlueSheet,
        srcW: THUMB_BOARD_W,
        srcH: THUMB_BOARD_H,
        x: 40, y: 176, w: THUMB_BOARD_BOX, h: THUMB_BOARD_BOX,
        caption: '银蓝', captionY: 256,
        selected: Appearance.pendingBoard === BoardStyle.Blue
      },
      {
        id: 'thumb:board:green',
        sheet: SpriteAtlas.thumbGreenSheet,
        srcW: THUMB_BOARD_W,
        srcH: THUMB_BOARD_H,
        x: 226, y: 176, w: THUMB_BOARD_BOX, h: THUMB_BOARD_BOX,
        caption: '绿色', captionY: 256,
        selected: Appearance.pendingBoard === BoardStyle.Green
      }
    ];
    const checkBox: DlgCheckBox = {
      // 原版有这个复选框，但 Linux 复刻没实现、置灰；这里照做（不可点）
      text: '随机选择游戏样式和棋盘',
      x: 18, y: 284, size: 13,
      checked: false,
      disabled: true
    };
    return {
      title: APPEARANCE_DIALOG_TITLE,
      width: DLG_W,
      height: DLG_H,
      chrome: 'aero',
      lines: [],
      groups: groups,
      thumbs: thumbs,
      checkBox: checkBox,
      buttons: [
        { id: 'appearance:ok', label: '确定(O)', x: 210, y: 302, w: 90, h: 26 },
        { id: 'appearance:cancel', label: '取消(C)', x: 310, y: 302, w: 90, h: 26 }
      ]
    };
  }

  /**
   * 点到缩略图：切换**待定**选择。
   *
   * @return true = 确实改了（调用方要重建规格并重画）
   */
  static select(id: string): boolean {
    if (id === 'thumb:style:mines') {
      Appearance.pendingGame = GameStyle.Mines;
      return true;
    }
    if (id === 'thumb:style:flowers') {
      Appearance.pendingGame = GameStyle.Flowers;
      return true;
    }
    if (id === 'thumb:board:blue') {
      Appearance.pendingBoard = BoardStyle.Blue;
      return true;
    }
    if (id === 'thumb:board:green') {
      Appearance.pendingBoard = BoardStyle.Green;
      return true;
    }
    return false;
  }

  /** 动作 id 是不是这个对话框的（GameController 用它来分流） */
  static owns(id: string): boolean {
    return id.startsWith('thumb:') || id.startsWith('appearance:');
  }
}
