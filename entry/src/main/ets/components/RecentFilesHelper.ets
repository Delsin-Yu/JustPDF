import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RecentFilesHelper';

const RECENT_FILES_KEY = 'recentFiles';
const MAX_RECENT_FILES = 10;

export interface RecentFileEntry {
  fileName: string;
  systemPath: string;
  openedAt: number;
}

/**
 * 获取最近打开的文件列表
 */
export function getRecentFiles(prefs: preferences.Preferences): RecentFileEntry[] {
  try {
    const json = prefs.getSync(RECENT_FILES_KEY, '[]') as string;
    return JSON.parse(json) as RecentFileEntry[];
  } catch (error) {
    hilog.error(0x0000, TAG, `读取最近文件列表出错: ${error}`);
    return [];
  }
}

/**
 * 添加一个文件到最近打开列表（去重，保留最新的）
 */
export function addRecentFile(prefs: preferences.Preferences, entry: RecentFileEntry): void {
  try {
    let files = getRecentFiles(prefs);
    // 去重：移除相同 systemPath 的旧记录
    files = files.filter(f => f.systemPath !== entry.systemPath);
    // 新记录插入到最前面
    files.unshift(entry);
    // 限制数量
    if (files.length > MAX_RECENT_FILES) {
      files = files.slice(0, MAX_RECENT_FILES);
    }
    prefs.putSync(RECENT_FILES_KEY, JSON.stringify(files));
    prefs.flushSync();
  } catch (error) {
    hilog.error(0x0000, TAG, `保存最近文件出错: ${error}`);
  }
}

/**
 * 从最近文件列表中移除指定文件
 */
export function removeRecentFile(prefs: preferences.Preferences, systemPath: string): void {
  try {
    let files = getRecentFiles(prefs);
    files = files.filter(f => f.systemPath !== systemPath);
    prefs.putSync(RECENT_FILES_KEY, JSON.stringify(files));
    prefs.flushSync();
  } catch (error) {
    hilog.error(0x0000, TAG, `移除最近文件出错: ${error}`);
  }
}

/**
 * 清空最近文件列表
 */
export function clearRecentFiles(prefs: preferences.Preferences): void {
  try {
    prefs.putSync(RECENT_FILES_KEY, '[]');
    prefs.flushSync();
  } catch (error) {
    hilog.error(0x0000, TAG, `清空最近文件出错: ${error}`);
  }
}
