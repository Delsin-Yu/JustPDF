
import { picker } from '@kit.CoreFileKit';

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