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

function sanitizeCopiedFileName(rawName: string): string {
  let name = rawName;
  const queryIndex = name.indexOf('?');
  if (queryIndex >= 0) {
    name = name.substring(0, queryIndex);
  }
  const slashIndex = name.lastIndexOf('/');
  if (slashIndex >= 0 && slashIndex + 1 < name.length) {
    name = name.substring(slashIndex + 1);
  }
  if (name.length === 0 || name === '.' || name === '..') {
    return 'shared.pdf';
  }
  return name;
}

function fileNameHintFromUri(uri: string): string {
  try {
    const parsed = new fileUri.FileUri(uri);
    if (parsed.name.length > 0) {
      return sanitizeCopiedFileName(parsed.name);
    }
  } catch (_error) {
  }
  return sanitizeCopiedFileName(uri);
}

/**
 * 将本地可读路径或已授权 URI 复制到 context.tempDir，并生成 saveTemp_ 写入旁路路径。
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
    const rawName = fileNameHint.length > 0 ? fileNameHint : sourceFile.name;
    const fileName = sanitizeCopiedFileName(rawName);
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
        hilog.error(0, TAG, '关闭文件失败: ' + String(closeError));
      }
    }
    throw new Error('prepareFromLocalPath 失败: ' + String(error));
  }
}

/**
 * 将系统分享 / 跨应用打开传入的 URI 复制到沙箱。
 * 必须先按原始 URI 打开：临时读授权挂在 URI 上，FileUri.path 会落到对方沙箱而无法访问。
 */
export async function prepareFromUri(
  context: Context,
  uri: string
): Promise<DocumentOpenParams> {
  const fileNameHint = fileNameHintFromUri(uri);
  try {
    return await prepareFromLocalPath(context, uri, uri, fileNameHint);
  } catch (uriError) {
    hilog.warn(0, TAG, 'prepareFromUri 按 URI 打开失败，回退 FileUri.path: ' + String(uriError));
    let localPath = '';
    try {
      localPath = new fileUri.FileUri(uri).path;
    } catch (_error) {
    }
    if (localPath.length === 0 || localPath === uri) {
      throw new Error('prepareFromUri 失败: ' + String(uriError));
    }
    return prepareFromLocalPath(context, localPath, uri, fileNameHint);
  }
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
