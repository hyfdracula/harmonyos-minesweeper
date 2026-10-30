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
