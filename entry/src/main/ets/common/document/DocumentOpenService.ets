import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { rememberRecentFile } from '../ui/RecentFilesHelper';
const TAG = 'DocumentOpenService';

/** URI/本地路径复制到沙箱后的阅读页路由参数。 */
export interface DocumentOpenParams {
  systemPath: string;
  sandboxPath: string;
  saveTempPath: string;
  fileName: string;
}

export function documentOpenParamsToRecord(params: DocumentOpenParams): Record<string, string> {
  return {
    'systemPath': params.systemPath,
    'sandboxPath': params.sandboxPath,
    'saveTempPath': params.saveTempPath,
    'fileName': params.fileName
  };
}

/**
 * 将本地可读路径复制到 context.tempDir，并生成 saveTemp_ 写入旁路路径。
 */
export async function prepareFromLocalPath(
  context: Context,
  localPath: string,
  systemPath: string,
  fileNameHint: string
): Promise<DocumentOpenParams> {
  const dir = context.tempDir;
  let sourceFile: fs.File | undefined = undefined;
  try {
    sourceFile = await fs.open(localPath, fs.OpenMode.READ_ONLY);
    const fileName = fileNameHint.length > 0 ? fileNameHint : sourceFile.name;
    const sandboxPath = dir + '/' + fileName;
    const saveTempPath = dir + '/saveTemp_' + fileName;
    await fs.copyFile(sourceFile.fd, sandboxPath);
    await fs.close(sourceFile);
    sourceFile = undefined;
    return {
      systemPath: systemPath,
      sandboxPath: sandboxPath,
      saveTempPath: saveTempPath,
      fileName: fileName
    };
  } catch (error) {
    if (sourceFile !== undefined) {
      try {
        await fs.close(sourceFile);
      } catch (closeError) {
        hilog.error(0, TAG, `关闭文件失败: ${closeError}`);
      }
    }
    throw new Error(`prepareFromLocalPath 失败: ${error}`);
  }
}

/**
 * 将系统 URI（或可解析为 FileUri 的路径）复制到沙箱。
 */
export async function prepareFromUri(
  context: Context,
  uri: string
): Promise<DocumentOpenParams> {
  let localPath = uri;
  try {
    const resolved = new fileUri.FileUri(uri).path;
    if (resolved.length > 0) {
      localPath = resolved;
    }
  } catch (_error) {
  }
  return prepareFromLocalPath(context, localPath, uri, '');
}

/**
 * Index 打开：直接按 uri 打开（不做 FileUri 解析），复制到 tempDir。
 * 与 prepareFromUri 的差异：失败时由调用方弹窗；此处仅负责复制。
 */
export async function prepareFromUriForPicker(
  context: Context,
  uri: string
): Promise<DocumentOpenParams> {
  return prepareFromLocalPath(context, uri, uri, '');
}

export async function rememberOpenedDocument(
  prefs: preferences.Preferences | undefined,
  params: DocumentOpenParams
): Promise<void> {
  if (prefs == null) {
    return;
  }
  await rememberRecentFile(prefs, {
    fileName: params.fileName,
    systemPath: params.systemPath,
    openedAt: new Date().getTime()
  });
}
