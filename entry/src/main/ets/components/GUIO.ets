
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'GUIO';

/** authMode 依赖的文件夹选择系统能力（2in1 等设备） */
const FOLDER_SELECTION_CAPABILITY: string =
  'SystemCapability.FileManagement.UserFileService.FolderSelection';

/**
 * 打开文件选择器，让用户选择一个文件
 * @param fileSuffixFilters 文件后缀过滤器
 * @returns 选中文件的URI，如果用户取消则返回 undefined
 */
export async function pickFilePathAsync(fileSuffixFilters: string[]): Promise<string | undefined> {
  const documentViewPicker = new picker.DocumentViewPicker();
  const documentSelectOptions = new picker.DocumentSelectOptions();
  documentSelectOptions.maxSelectNumber = 1;
  documentSelectOptions.fileSuffixFilters = fileSuffixFilters;
  let uris = await documentViewPicker.select(documentSelectOptions);
  if (uris.length > 0) {
    return uris[0];
  }
  return undefined;
}

/**
 * 打开文件选择器，并尝试定位到指定的文件路径。
 * 对 2in1 设备会尝试使用授权模式，用户只需确认授权即可；
 * 对其他设备则预导航到文件所在目录，用户只需找到文件并点击打开。
 * @param fileSuffixFilters 文件后缀过滤器
 * @param defaultUri 需要重新打开的文件的URI（之前通过Picker获取的）
 * @returns 选中文件的URI，如果用户取消则返回 undefined
 */
export async function pickFilePathWithDefaultAsync(
  fileSuffixFilters: string[],
  defaultUri: string
): Promise<string | undefined> {
  const documentViewPicker = new picker.DocumentViewPicker();
  const documentSelectOptions = new picker.DocumentSelectOptions();
  documentSelectOptions.maxSelectNumber = 1;
  documentSelectOptions.fileSuffixFilters = fileSuffixFilters;
  documentSelectOptions.defaultFilePathUri = defaultUri;
  // 优先尝试授权模式（2in1 设备），用户只需确认即可重新获得权限
  if (canIUse(FOLDER_SELECTION_CAPABILITY)) {
    documentSelectOptions.authMode = true;
  }
  try {
    let uris = await documentViewPicker.select(documentSelectOptions);
    if (uris.length > 0) {
      return uris[0];
    }
  } catch (error) {
    let businessErr = error as BusinessError;
    hilog.warn(0x0000, TAG, `授权模式拉起Picker失败(code=${businessErr.code}), 回退到普通模式`);
    // 授权模式可能在某些设备上不支持（非2in1），回退到普通模式带默认路径
    const fallbackOptions = new picker.DocumentSelectOptions();
    fallbackOptions.maxSelectNumber = 1;
    fallbackOptions.fileSuffixFilters = fileSuffixFilters;
    fallbackOptions.defaultFilePathUri = defaultUri;
    try {
      let uris = await documentViewPicker.select(fallbackOptions);
      if (uris.length > 0) {
        return uris[0];
      }
    } catch (fallbackError) {
      hilog.error(0x0000, TAG, `回退模式也失败: ${fallbackError}`);
      // 用户取消或失败，返回 undefined
    }
  }
  return undefined;
}