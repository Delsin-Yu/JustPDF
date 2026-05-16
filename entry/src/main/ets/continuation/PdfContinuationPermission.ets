import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { logContinuationLine, logContinuationWarn } from './PdfContinuation';

export const DISTRIBUTED_DATASYNC_PERMISSION: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';

export async function ensureDistributedDataSyncPermission(
  context: common.UIAbilityContext,
  requestIfNeeded: boolean
): Promise<boolean> {
  const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  const tokenId: number = context.applicationInfo.accessTokenId;
  try {
    const initialStatus: abilityAccessCtrl.GrantStatus =
      await atManager.checkAccessToken(tokenId, DISTRIBUTED_DATASYNC_PERMISSION);
    if (initialStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    if (!requestIfNeeded) {
      logContinuationWarn('未授予 ohos.permission.DISTRIBUTED_DATASYNC');
      return false;
    }
    const requestResult =
      await atManager.requestPermissionsFromUser(context, [DISTRIBUTED_DATASYNC_PERMISSION]);
    const granted = requestResult.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    logContinuationLine(`requestPermissionsFromUser DISTRIBUTED_DATASYNC granted=${granted}`);
    return granted;
  } catch (error) {
    logContinuationWarn(`ensureDistributedDataSyncPermission 异常: ${error}`);
    return false;
  }
}
