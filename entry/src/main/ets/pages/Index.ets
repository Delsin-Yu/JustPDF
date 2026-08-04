import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';
import { pickFilePathAsync, pickFilePathWithDefaultAsync } from '../components/GUIO';
import { showAlertDialog } from '../components/UIComponents';
import {
  getRecentFiles,
  rememberRecentFile,
  forgetRecentFile,
  RecentFileEntry
} from '../components/RecentFilesHelper';
import { activateRecentFileUri } from '../components/RecentFilePermission';

const TAG = 'JustPDFIndex';

type EntryStatus = 'valid' | 'noperm' | 'deleted';

@Entry
@Component
struct Index {
  @StorageProp('avoidAreaTopPx') avoidAreaTopPx: number = 0;
  @StorageProp('avoidAreaBottomPx') avoidAreaBottomPx: number = 0;
  @State isLoading: boolean = false;
  @State loadingFileName: string = '';
  @State recentFiles: RecentFileEntry[] = [];
  @State entryStatus: EntryStatus[] = [];
  @State widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  private mainWindow: window.Window | undefined = undefined;
  private windowSizeCallback: (size: window.Size) => void = (_size: window.Size) => {
    try {
      this.widthBp = this.getUIContext().getWindowWidthBreakpoint();
    } catch (_e) {
    }
  };

  aboutToAppear(): void {
    try {
      this.widthBp = this.getUIContext().getWindowWidthBreakpoint();
    } catch (_e) {
    }
    this.mainWindow = AppStorage.get('window') as window.Window | undefined;
    if (this.mainWindow) {
      try {
        this.mainWindow.on('windowSizeChange', this.windowSizeCallback);
      } catch (_e) {
      }
    }

    let context = this.getUIContext();
    let routerParams = context.getRouter().getParams() as Record<string, string>;
    if (routerParams != null && routerParams['routerParams'] != '') {
      AppStorage.setOrCreate('launchUri', routerParams['routerParams']);
    }
    if (this.preferences != null) {
      this.recentFiles = getRecentFiles(this.preferences);
      this.entryStatus = new Array(this.recentFiles.length).fill('valid');
      this.validateRecentFilesAsync();
    }
    let launchUriLink = AppStorage?.link<string>('launchUri');
    if (launchUriLink == null) {
      return;
    }
    let launchUri = launchUriLink.get();
    launchUriLink.set('');
    if (launchUri == null || launchUri == '') {
      return;
    }
    this.loadAndViewFile(launchUri);
  }

  aboutToDisappear(): void {
    if (this.mainWindow) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeCallback);
      } catch (_e) {
      }
    }
  }

  private async validateRecentFilesAsync(): Promise<void> {
    for (let i = 0; i < this.recentFiles.length; i++) {
      const entry = this.recentFiles[i];
      // 重启后需先激活已持久化授权，再探测可读性。
      await activateRecentFileUri(entry.systemPath);
      try {
        let testFile = await fs.open(entry.systemPath, fs.OpenMode.READ_ONLY);
        await fs.close(testFile);
        this.entryStatus[i] = 'valid';
      } catch (error) {
        const bizErr = error as BusinessError;
        if (bizErr.code === 13900002) {
          this.entryStatus[i] = 'deleted';
        } else {
          this.entryStatus[i] = 'noperm';
        }
      }
      this.entryStatus = [...this.entryStatus];
    }
  }

  async loadAndViewFile(uri: string) {
    let uiContext = this.getUIContext();
    let dir = uiContext.getHostContext()!.tempDir;
    let sourceFile: fs.File;
    try {
      sourceFile = await fs.open(uri, fs.OpenMode.READ_ONLY);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error opening file: ${error}`);
      await showAlertDialog('文件打开失败', `无法打开选定的PDF文件，请检查文件是否存在或已损坏。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
      return;
    }
    let fileName = sourceFile.name;
    this.loadingFileName = fileName;
    this.isLoading = true;
    let file = dir + "/" + fileName;
    let tempFile = dir + "/saveTemp_" + fileName;
    try {
      await fs.copyFile(sourceFile.fd, file);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error copying file: ${error}`);
      await showAlertDialog('文件复制失败', `无法将PDF文件复制到临时目录。请检查存储空间是否充足。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
      return;
    } finally {
      try {
        await fs.close(sourceFile);
      } catch (error) {
        hilog.error(0x0000, TAG, `Error closing file: ${error}`);
      }
    }

    let args: Record<string, string> = {
      'systemPath': uri,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    }
    if (this.preferences != null) {
      // 趁临时授权仍有效时持久化，供下次直接打开。
      await rememberRecentFile(this.preferences, {
        fileName: fileName,
        systemPath: uri,
        openedAt: new Date().getTime()
      });
    }
    try {
      uiContext.getRouter().replaceUrl({ url: 'pages/PDFView', params: args });
    } catch (error) {
      hilog.error(0x0000, TAG, `Error navigating to PDFView: ${error}`);
      await showAlertDialog('页面跳转失败', `无法打开PDF预览页面，请重试。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
    }
  }

  async openRecentFile(entry: RecentFileEntry): Promise<void> {
    await activateRecentFileUri(entry.systemPath);
    try {
      let testFile = await fs.open(entry.systemPath, fs.OpenMode.READ_ONLY);
      await fs.close(testFile);
      await this.loadAndViewFile(entry.systemPath);
      return;
    } catch (_error) {
    }
    let newUri = await pickFilePathWithDefaultAsync(['.pdf'], entry.systemPath);
    if (newUri != null) {
      await this.loadAndViewFile(newUri);
    }
  }

  private removeEntry(index: number): void {
    if (index < 0 || index >= this.recentFiles.length) {
      return;
    }
    const entry = this.recentFiles[index];
    if (this.preferences != null) {
      void forgetRecentFile(this.preferences, entry.systemPath);
    }
    this.recentFiles.splice(index, 1);
    this.entryStatus.splice(index, 1);
    this.recentFiles = [...this.recentFiles];
    this.entryStatus = [...this.entryStatus];
  }

  private getEntryStatus(index: number): EntryStatus {
    if (index < 0 || index >= this.entryStatus.length) {
      return 'deleted';
    }
    return this.entryStatus[index];
  }

  private isWide(): boolean {
    return this.widthBp === WidthBreakpoint.WIDTH_MD
      || this.widthBp === WidthBreakpoint.WIDTH_LG
      || this.widthBp === WidthBreakpoint.WIDTH_XL;
  }

  @Builder
  buildBranding() {
    Column({ space: 16 }) {
      Text("Just PDF")
        .fontSize(this.isWide() ? 48 : 40)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))

      if (this.isLoading) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('sys.color.font_secondary'))
        Text(`正在加载 ${this.loadingFileName}`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Button("选择文件")
          .type(ButtonType.Capsule)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .width('60%')
          .constraintSize({ maxWidth: 240 })
          .height(50)
          .onClick(async () => {
            try {
              let uri = await pickFilePathAsync(['.pdf']);
              if (uri) {
                await this.loadAndViewFile(uri);
              }
            } catch (err) {
              let businessErr = err as BusinessError;
              hilog.error(0x0000, TAG, `ERR: ${err.code}, message is ${businessErr.message}`);
              let uiContext = this.getUIContext();
              await showAlertDialog('文件选择失败', `无法选择文件：${businessErr.message}`, uiContext);
              this.isLoading = false;
            }
          })
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildSwipeDeleteIndicator(index: number) {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_on_primary')])
      Text('删除')
        .fontSize(13)
        .fontColor($r('sys.color.font_on_primary'))
    }
    .padding({ left: 20, right: 20 })
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.warning'))
    .onClick(() => {
      this.getUIContext().animateTo({ duration: 200 }, () => {
        this.removeEntry(index);
      });
    })
  }

  @Builder
  buildRecentFilesList() {
    Column({ space: 12 }) {
      Text('最近打开')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ left: 4 })

      List({ space: 6 }) {
          ForEach(this.recentFiles, (entry: RecentFileEntry, index?: number) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.doc'))
                  .fontSize(20)
                  .fontColor([this.getEntryStatus(index ?? 0) === 'deleted'
                    ? $r('sys.color.font_tertiary')
                    : $r('sys.color.font_secondary')])

                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(entry.fileName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.getEntryStatus(index ?? 0) === 'deleted'
                        ? $r('sys.color.font_tertiary')
                        : $r('sys.color.font_primary'))
                      .decoration(this.getEntryStatus(index ?? 0) === 'deleted'
                        ? { type: TextDecorationType.LineThrough }
                        : { type: TextDecorationType.None })
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(formatDate(entry.openedAt))
                      .fontSize(12)
                      .fontColor($r('sys.color.font_tertiary'))
                  }
                  .alignItems(VerticalAlign.Center)
                  .width('100%')

                  if (this.getEntryStatus(index ?? 0) === 'deleted') {
                    Text('已删除')
                      .fontSize(11)
                      .fontColor($r('sys.color.font_tertiary'))
                  } else if (this.getEntryStatus(index ?? 0) === 'noperm') {
                    Text('权限过期')
                      .fontSize(11)
                      .fontColor($r('sys.color.warning'))
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 10, bottom: 10, left: 16, right: 16 })
              .opacity(this.getEntryStatus(index ?? 0) === 'deleted' ? 0.6 : 1.0)
            }
            .width('100%')
            .borderRadius(12)
            .clip(true)
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .shadow(ShadowStyle.OUTER_DEFAULT_XS)
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 8 })),
              TransitionEffect.opacity(0)
            ))
            .swipeAction({
              end: {
                builder: () => {
                  this.buildSwipeDeleteIndicator(index ?? 0);
                },
                actionAreaDistance: 56,
                onAction: () => {
                  this.getUIContext().animateTo({ duration: 200 }, () => {
                    this.removeEntry(index ?? 0);
                  });
                }
              }
            })
            .onClick(async () => {
              const status = this.getEntryStatus(index ?? 0);
              if (status === 'valid') {
                await this.openRecentFile(entry);
              } else if (status === 'noperm') {
                let newUri = await pickFilePathWithDefaultAsync(['.pdf'], entry.systemPath);
                if (newUri != null) {
                  await this.loadAndViewFile(newUri);
                }
              }
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      if (this.recentFiles.length > 0 || this.isLoading) {
        Column() {
          this.buildBranding()
        }
        .width('100%')
        .padding({ top: this.isWide() ? 40 : 48, bottom: 20 })

        Column() {
          this.buildRecentFilesList()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({
          left: this.isWide() ? 48 : 16,
          right: this.isWide() ? 48 : 16,
          bottom: 16
        })
        .constraintSize({ maxWidth: this.isWide() ? 720 : undefined })
      } else {
        Column({ space: 20 }) {
          Text("Just PDF")
            .fontSize(this.isWide() ? 64 : 56)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))

          if (this.isLoading) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color($r('sys.color.font_secondary'))
            Text(`正在加载 ${this.loadingFileName}`)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Button("选择文件")
              .type(ButtonType.Capsule)
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .width('60%')
              .constraintSize({ maxWidth: 280 })
              .height(65)
              .onClick(async () => {
                try {
                  let uri = await pickFilePathAsync(['.pdf']);
                  if (uri) {
                    await this.loadAndViewFile(uri);
                  }
                } catch (err) {
                  let businessErr = err as BusinessError;
                  hilog.error(0x0000, TAG, `ERR: ${err.code}, message is ${businessErr.message}`);
                  let uiContext = this.getUIContext();
                  await showAlertDialog('文件选择失败', `无法选择文件：${businessErr.message}`, uiContext);
                  this.isLoading = false;
                }
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      top: this.getUIContext().px2vp(this.avoidAreaTopPx),
      bottom: this.getUIContext().px2vp(this.avoidAreaBottomPx)
    })
    .backgroundColor($r('sys.color.background_primary'))
  }
}

function formatDate(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();
  const isToday = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday = date.getFullYear() === yesterday.getFullYear()
    && date.getMonth() === yesterday.getMonth()
    && date.getDate() === yesterday.getDate();

  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');

  if (isToday) {
    return `今天 ${hours}:${minutes}`;
  }
  if (isYesterday) {
    return `昨天 ${hours}:${minutes}`;
  }
  return `${year}/${month}/${day} ${hours}:${minutes}`;
}
