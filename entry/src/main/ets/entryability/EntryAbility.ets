import { AbilityConstant, ConfigurationConstant, UIAbility, Want, errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { GameSession } from '../common/GameSession';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 抓未捕获的 ArkTS 异常：没有这个处理器时，未捕获异常会直接终止应用
    try {
      errorManager.on('globalErrorOccurred', (reason) => {
        hilog.error(DOMAIN, 'testTag', '未捕获异常 name=%{public}s msg=%{public}s stack=%{public}s',
          reason.name, reason.message, reason.stack ?? '');
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '注册错误处理器失败: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 窗口级变化（折叠开合 / 内屏↔外屏切换）监听。
    //
    // 坑（Codex 对抗性复审 P1，2026-11-02）：原来把 onWindowStageChange 写成
    // **UIAbility 的生命周期方法** —— UIAbility 根本没有这个回调，
    // 方法体里的代码永远不执行（实测日志里也确实没有「窗口级变化」这一行）。
    //
    // 找过一圈才找到对的钩子：
    //   - `windowStage.on('windowStageChange')` 不存在（WindowStageEventType 是
    //     显示/隐藏/焦点的枚举，跟折叠无关）；
    //   - `window.on('windowSizeChange')` 就是它 —— 折叠换屏时窗口尺寸必然变，
    //     回调参数是新的 Size（宽高）。
    //
    // 尺寸变化本身由 Canvas 的 onAreaChange → attach → layout() 负责（那条路实测是通的），
    // 这里补的是「窗口变了但画布尺寸还没跟上」的那一瞬，另外留一条日志给审计看。
    try {
      windowStage.getMainWindowSync().on('windowSizeChange', (size: window.Size) => {
        hilog.info(DOMAIN, 'testTag', '窗口尺寸变化 %{public}d x %{public}d', size.width, size.height);
        try {
          GameSession.controller.onWindowStageChanged();
        } catch (err) {
          hilog.error(DOMAIN, 'testTag', '窗口尺寸变化后重排失败: %{public}s', JSON.stringify(err));
        }
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '注册窗口尺寸变化监听失败: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /**
   * 窗口级变化（**折叠开合 / 内屏↔外屏切换**）时的重排入口。
   *
   * 注意：这不是 UIAbility 的生命周期回调（UIAbility 没有 onWindowStageChange，
   * 写成同名方法会永远不执行 —— Codex 对抗性复审 P1，2026-11-02）。
   * 真正的监听在 onWindowStageCreate 里，用 `windowStage.on('windowStageChange')` 注册。
   *
   * 幂等：layout() 里「用户手动缩放过就保留档位」那条规则照旧生效，
   * 所以折叠换屏**不会把用户的缩放档重置回适配档**（用户原话：折叠换屏时不丢视角）。
   */
  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', 'Ability onForeground');
    try {
      // 回到前台：若正在游戏中则恢复计时
      GameSession.controller.resumeFromBackground();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '恢复计时失败: %{public}s', JSON.stringify(err));
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', 'Ability onBackground');
    try {
      // 切后台暂停计时：手机上放口袋时不该继续耗秒数
      GameSession.controller.pauseForBackground();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '暂停计时失败: %{public}s', JSON.stringify(err));
    }
  }
}
