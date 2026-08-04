import { fileShare } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'RecentFilePermission';

/** 最近文件需读写：打开阅读 + 批注回写。 */
const RECENT_FILE_OPERATION_MODE: number =
  fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;

const FOLDER_AUTHORIZATION_CAPABILITY: string =
  'SystemCapability.FileManagement.AppFileService.FolderAuthorization';

function isFolderAuthorizationSupported(): boolean {
  return canIUse(FOLDER_AUTHORIZATION_CAPABILITY);
}

function buildPolicy(uri: string): fileShare.PolicyInfo {
  const policy: fileShare.PolicyInfo = {
    uri: uri,
    operationMode: RECENT_FILE_OPERATION_MODE
  };
  return policy;
}

function buildPolicies(uri: string): Array<fileShare.PolicyInfo> {
  const policies: Array<fileShare.PolicyInfo> = [buildPolicy(uri)];
  return policies;
}

function logPolicyErrors(action: string, err: BusinessError<Array<fileShare.PolicyErrorResult>>): void {
  hilog.error(0x0000, TAG, action + ' failed: code=' + err.code.toString() + ', message=' + err.message);
  const details: Array<fileShare.PolicyErrorResult> | undefined = err.data;
  if (err.code === 13900001 && details !== undefined) {
    for (let i = 0; i < details.length; i++) {
      const item: fileShare.PolicyErrorResult = details[i];
      hilog.error(
        0x0000,
        TAG,
        action + ' policy error: code=' + item.code.toString() +
          ', uri=' + item.uri + ', reason=' + item.message
      );
    }
  }
}

/**
 * 在仍持有临时授权时，将 URI 持久化，便于重启后通过 activate 直接打开。
 * @returns 是否持久化成功；设备不支持或失败时返回 false（调用方仍可继续用临时授权）。
 */
export async function persistRecentFileUri(uri: string): Promise<boolean> {
  if (uri.length === 0) {
    return false;
  }
  if (!isFolderAuthorizationSupported()) {
    hilog.warn(0x0000, TAG, 'FolderAuthorization not supported; skip persist');
    return false;
  }
  try {
    await fileShare.persistPermission(buildPolicies(uri));
    hilog.info(0x0000, TAG, 'persistPermission ok');
    return true;
  } catch (error) {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      error as BusinessError<Array<fileShare.PolicyErrorResult>>;
    logPolicyErrors('persistPermission', err);
    return false;
  }
}

/**
 * 激活已持久化的 URI 授权；打开最近文件前按需调用。
 */
export async function activateRecentFileUri(uri: string): Promise<boolean> {
  if (uri.length === 0) {
    return false;
  }
  if (!isFolderAuthorizationSupported()) {
    return false;
  }
  try {
    await fileShare.activatePermission(buildPolicies(uri));
    hilog.info(0x0000, TAG, 'activatePermission ok');
    return true;
  } catch (error) {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      error as BusinessError<Array<fileShare.PolicyErrorResult>>;
    logPolicyErrors('activatePermission', err);
    return false;
  }
}

/**
 * 取消持久化授权（从最近列表移除时调用）。
 */
export async function revokeRecentFileUri(uri: string): Promise<boolean> {
  if (uri.length === 0) {
    return false;
  }
  if (!isFolderAuthorizationSupported()) {
    return false;
  }
  try {
    await fileShare.revokePermission(buildPolicies(uri));
    hilog.info(0x0000, TAG, 'revokePermission ok');
    return true;
  } catch (error) {
    const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
      error as BusinessError<Array<fileShare.PolicyErrorResult>>;
    logPolicyErrors('revokePermission', err);
    return false;
  }
}
