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
import { setExitViewerOnBack } from '../navigation/PendingDocumentOpen';
import { OceanBackground, mixHexColors } from '../components/OceanBackground';

const TAG = 'JustPDFIndex';

type EntryStatus = 'valid' | 'noperm' | 'deleted';

/** 标题冷色调的两端，随背景相位插值 */
const HERO_TINT_BRIGHT = '#EAF4FF';
const HERO_TINT_DEEP = '#9CD0E8';
/** 覆盖在渐变上的浅色文字层级 */
const TEXT_PRIMARY = '#F2F7FF';
const TEXT_SECONDARY = 'rgba(255,255,255,0.60)';
const TEXT_TERTIARY = 'rgba(255,255,255,0.38)';
const CARD_BACKGROUND = 'rgba(255,255,255,0.08)';
const CARD_BORDER = 'rgba(255,255,255,0.10)';
/** 历史区域的深色玻璃面板，覆盖完整右栏 */
const HISTORY_PANEL_BACKGROUND = 'rgba(2,8,16,0.12)';
const HISTORY_PANEL_BORDER = 'rgba(255,255,255,0.12)';

/** 宽/方形窗口且有历史列表时，主视觉左栏占窗口宽度的比例 */
const HERO_COLUMN_WIDTH = '40%';
/** 左栏低于此宽度（vp）时强制上下布局，避免分栏裁切 */
const MIN_HERO_COLUMN_VP = 220;
/** 实时高宽比达到此值时视为窄高（与 HEIGHT_LG 语义对齐，但无断点滞后） */
const TALL_ASPECT_RATIO = 1.2;
/** 布局状态切换动画时长（毫秒） */
const LAYOUT_ANIM_DURATION = 300;
/** 历史列表出现/消失的过渡效果：淡入淡出并轻微上浮 */
const HISTORY_TRANSITION: TransitionEffect = TransitionEffect.OPACITY
  .combine(TransitionEffect.translate({ y: 16 }))
  .animation({ duration: LAYOUT_ANIM_DURATION, curve: Curve.Friction });

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
  @State heightBp: HeightBreakpoint = HeightBreakpoint.HEIGHT_LG;
  /** 窗口内容区宽度（vp），用于标题字号连续缩放，避免断点跳变 */
  @State windowWidthVp: number = 360;
  /** 窗口内容区高度（vp），用于实时高宽比判断 */
  @State windowHeightVp: number = 640;
  /** 与背景渐变同源的标题色调，由 OceanBackground 相位回调驱动 */
  @State heroTint: string = HERO_TINT_BRIGHT;
  /** 页面可见时为 true，隐藏时暂停背景动画 */
  @State backgroundActive: boolean = true;
  private preferences: preferences.Preferences = AppStorage.get('preferences') as preferences.Preferences;
  private mainWindow: window.Window | undefined = undefined;
  private windowSizeCallback: (size: window.Size) => void = (size: window.Size) => {
    // 尺寸与断点立即生效，避免 animateTo 插值中间帧出现裁切
    this.applyWindowSize(size.width, size.height);
  };

  aboutToAppear(): void {
    this.refreshBreakpoints();
    this.mainWindow = AppStorage.get('window') as window.Window | undefined;
    if (this.mainWindow) {
      try {
        const rect = this.mainWindow.getWindowProperties().windowRect;
        this.applyWindowSize(rect.width, rect.height);
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
    // 系统 Want 冷/温启动经 Index 转发时，返回应移到后台回到调用方。
    this.loadAndViewFile(launchUri, true);
  }

  aboutToDisappear(): void {
    if (this.mainWindow) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeCallback);
      } catch (_e) {
      }
    }
  }

  onPageShow(): void {
    this.backgroundActive = true;
    // 深色海洋背景上保持浅色状态栏文字
    if (this.mainWindow) {
      try {
        void this.mainWindow.setWindowSystemBarProperties({ statusBarContentColor: '#E8F2FF' })
          .catch((err: BusinessError) => {
            hilog.warn(0x0000, TAG, `setWindowSystemBarProperties 失败: code=${err.code}`);
          });
      } catch (_e) {
      }
    }
  }

  onPageHide(): void {
    this.backgroundActive = false;
  }

  private refreshBreakpoints(): void {
    try {
      this.widthBp = this.getUIContext().getWindowWidthBreakpoint();
      this.heightBp = this.getUIContext().getWindowHeightBreakpoint();
    } catch (_e) {
    }
  }

  /** 同步窗口宽高（px→vp）并刷新断点 */
  private applyWindowSize(widthPx: number, heightPx: number): void {
    this.windowWidthVp = this.getUIContext().px2vp(widthPx);
    this.windowHeightVp = this.getUIContext().px2vp(heightPx);
    this.refreshBreakpoints();
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

  async loadAndViewFile(uri: string, exitOnBack: boolean = false) {
    setExitViewerOnBack(exitOnBack);
    let uiContext = this.getUIContext();
    let dir = uiContext.getHostContext()!.tempDir;
    let sourceFile: fs.File;
    try {
      sourceFile = await fs.open(uri, fs.OpenMode.READ_ONLY);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error opening file: ${error}`);
      await showAlertDialog('文件打开失败', `无法打开选定的PDF文件，请检查文件是否存在或已损坏。\n错误信息: ${error}`, uiContext);
      this.setLoadingAnimated(false);
      return;
    }
    let fileName = sourceFile.name;
    this.loadingFileName = fileName;
    this.setLoadingAnimated(true);
    let file = dir + "/" + fileName;
    let tempFile = dir + "/saveTemp_" + fileName;
    try {
      await fs.copyFile(sourceFile.fd, file);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error copying file: ${error}`);
      await showAlertDialog('文件复制失败', `无法将PDF文件复制到临时目录。请检查存储空间是否充足。\n错误信息: ${error}`, uiContext);
      this.setLoadingAnimated(false);
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
      this.setLoadingAnimated(false);
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

  /**
   * 窄高窗口：高度断点 lg，或实时高宽比已达阈值（消除断点滞后）。
   */
  private isTall(): boolean {
    if (this.heightBp === HeightBreakpoint.HEIGHT_LG) {
      return true;
    }
    if (this.windowWidthVp <= 0) {
      return false;
    }
    return this.windowHeightVp / this.windowWidthVp >= TALL_ASPECT_RATIO;
  }

  /** 宽窗口：排版参数，且作为左右分栏的宽度门槛 */
  private isWide(): boolean {
    return this.widthBp === WidthBreakpoint.WIDTH_MD
      || this.widthBp === WidthBreakpoint.WIDTH_LG
      || this.widthBp === WidthBreakpoint.WIDTH_XL;
  }

  /** 矮窗口（横屏手机、短自由窗口）：压缩标题字号 */
  private isShort(): boolean {
    return this.heightBp === HeightBreakpoint.HEIGHT_SM;
  }

  /**
   * 有历史且非窄高时左右分栏；无历史统一用上下布局的空态（30/70）。
   * 类方形/矮窗也必须足够宽且左栏可达最小宽度，避免拥挤分栏裁切。
   */
  private useSideBySide(): boolean {
    if (this.recentFiles.length === 0 || this.isTall() || !this.isWide()) {
      return false;
    }
    return this.windowWidthVp * 0.4 >= MIN_HERO_COLUMN_VP;
  }

  private onBackgroundPhase(phase: number): void {
    this.heroTint = mixHexColors(HERO_TINT_BRIGHT, HERO_TINT_DEEP, phase);
  }

  /** 用布局动画切换加载态，使主视觉在空态与历史态布局间平滑迁移 */
  private setLoadingAnimated(value: boolean): void {
    this.getUIContext().animateTo({ duration: LAYOUT_ANIM_DURATION, curve: Curve.Friction }, () => {
      this.isLoading = value;
    });
  }

  /** 主视觉可用宽度（vp）：分栏时为左栏，上下/空态时为整窗 */
  private heroAvailableWidthVp(): number {
    const padding = this.heroHorizontalPadding() * 2;
    if (this.useSideBySide()) {
      return this.windowWidthVp * 0.4 - padding;
    }
    return this.windowWidthVp - padding;
  }

  /**
   * 标题主字号：随窗口宽度连续缩放，不依赖宽度断点，
   * 保证 “Just PDF” 在极端窄栏下仍完整可见且横向缩放时无突变。
   */
  private titleFontSize(): number {
    // 经验系数：字号 * 4.5 ≈ “Just PDF”+letterSpacing 所需宽度
    const fitted = Math.floor((this.heroAvailableWidthVp() - 8) / 4.5);
    const maxSize = this.isShort() ? 56 : 84;
    const minSize = 36;
    if (fitted < minSize) {
      return minSize;
    }
    if (fitted > maxSize) {
      return maxSize;
    }
    return fitted;
  }

  /** 历史列表顶部内边距 */
  private historyTopInset(): number {
    return this.isWide() ? 24 : 12;
  }

  /** 历史面板与窗口边缘之间保留少量海洋背景 */
  private historyPanelOuterInset(): number {
    return this.isWide() ? 24 : 12;
  }

  /** 主视觉块左右内边距，为外发光留出空间避免贴边裁切 */
  private heroHorizontalPadding(): number {
    return this.useSideBySide() ? 20 : 12;
  }

  /** 主按钮宽度随标题可用宽度平滑缩放 */
  private pickButtonWidth(): number {
    const target = Math.floor(this.heroAvailableWidthVp() * 0.72);
    if (target < 140) {
      return 140;
    }
    if (target > 240) {
      return 240;
    }
    return target;
  }

  /** 眉题使用标题色调的暗化版本（AARRGGBB） */
  private eyebrowTint(): string {
    return '#8C' + this.heroTint.substring(1);
  }

  /** 标题外发光（低透明度同源色调） */
  private glowTint(): string {
    return '#4D' + this.heroTint.substring(1);
  }

  /** 玻璃字本体色：半透明冷白，直接透出下方海洋渐变 */
  private glassTitleColor(): string {
    return '#B8' + this.heroTint.substring(1);
  }

  /** 玻璃描边高光色 */
  private glassEdgeTint(): string {
    return '#48FFFFFF';
  }

  /** 按钮使用比标题更克制的外发光，避免形成实心光团 */
  private buttonGlowTint(): string {
    return '#24' + this.heroTint.substring(1);
  }

  /** 玻璃按钮的透明底色 */
  private glassButtonFill(): string {
    return '#0FFFFFFF';
  }

  /** 斜向高光模拟玻璃表面的反射层 */
  private glassButtonShader(): LinearGradientOptions {
    const options: LinearGradientOptions = {
      angle: 125,
      colors: [
        ['#30FFFFFF', 0],
        ['#16FFFFFF', 0.38],
        ['#12' + this.heroTint.substring(1), 1]
      ]
    };
    return options;
  }

  /** 小字号按钮文字需要更高的不透明度，同时保留标题的冷色玻璃渐变 */
  private glassButtonTextShader(): LinearGradientOptions {
    const options: LinearGradientOptions = {
      angle: 112,
      colors: [
        ['#F2FFFFFF', 0],
        ['#D9' + this.heroTint.substring(1), 0.5],
        ['#B8B4D8FF', 1]
      ]
    };
    return options;
  }

  /** 玻璃标题渐变着色（半透明停靠点） */
  private glassTitleShader(): LinearGradientOptions {
    const options: LinearGradientOptions = {
      angle: 112,
      colors: [
        ['#F4FFFFFF', 0],
        ['#E0FFFFFF', 0.45],
        ['#C8' + this.heroTint.substring(1), 0.75],
        ['#9CC8E5F5', 1]
      ]
    };
    return options;
  }

  private horizontalInset(): number {
    return this.isWide() ? 48 : 24;
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
      this.getUIContext().animateTo({ duration: LAYOUT_ANIM_DURATION, curve: Curve.Friction }, () => {
        this.removeEntry(index);
      });
    })
  }

  /** 主视觉：大号玻璃标题 + 加载态 / 玻璃按钮，两种布局分支共用 */
  @Builder
  buildHeroBlock() {
    Column() {
      // 玻璃标题：半透明着色器 + 柔光，笔画直接透出海洋渐变。
      Text('Just PDF')
        .fontSize(this.titleFontSize())
        .fontWeight(FontWeight.Bold)
        .lineHeight(this.titleFontSize() * 1.16)
        .letterSpacing(2)
        .maxLines(1)
        .width('100%')
        .textAlign(TextAlign.Center)
        .shaderStyle(this.glassTitleShader())
        .opacity(0.82)
        .textShadow({
          radius: 26,
          color: this.glowTint(),
          offsetX: 0,
          offsetY: 0
        })

      if (this.isLoading) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(TEXT_SECONDARY)
          Text('正在加载 ' + this.loadingFileName)
            .fontSize(14)
            .fontColor(TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 48 })
      } else {
        Column() {
          Button() {
            Text('选择文件')
              .fontSize(25)
              .fontWeight(FontWeight.Bold)
              .letterSpacing(2)
              .shaderStyle(this.glassButtonTextShader())
              .opacity(0.98)
              .textShadow({
                radius: 10,
                color: this.buttonGlowTint(),
                offsetX: 0,
                offsetY: 0
              })
          }
            .type(ButtonType.Capsule)
            .backgroundColor(this.glassButtonFill())
            .linearGradient(this.glassButtonShader())
            .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
            .border({ width: 1, color: this.glassEdgeTint() })
            .width(this.pickButtonWidth())
            .height(56)
            .shadow({
              radius: 26,
              color: this.buttonGlowTint(),
              offsetX: 0,
              offsetY: 0
            })
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
                await showAlertDialog('文件选择失败', `无法选择文件：${businessErr.message}`,
                  uiContext);
                this.setLoadingAnimated(false);
              }
            })
        }
        .margin({ top: 30 })
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: this.heroHorizontalPadding(), right: this.heroHorizontalPadding() })
    .alignItems(HorizontalAlign.Center)
  }

  /** 历史列表玻璃面板：填满外层容器，两种布局分支共用 */
  @Builder
  buildHistoryPanel() {
    Column() {
      Column({ space: 12 }) {
        Text('最近打开')
          .fontSize(13)
          .letterSpacing(4)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.eyebrowTint())
          .width('100%')
          .padding({ left: 4 })

        List({ space: 6 }) {
          ForEach(this.recentFiles, (entry: RecentFileEntry, index?: number) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.doc'))
                  .fontSize(20)
                  .fontColor([this.getEntryStatus(index ?? 0) === 'deleted'
                    ? TEXT_TERTIARY
                    : TEXT_SECONDARY])

                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(entry.fileName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.getEntryStatus(index ?? 0) === 'deleted'
                        ? TEXT_TERTIARY
                        : TEXT_PRIMARY)
                      .decoration(this.getEntryStatus(index ?? 0) === 'deleted'
                        ? { type: TextDecorationType.LineThrough }
                        : { type: TextDecorationType.None })
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(formatDate(entry.openedAt))
                      .fontSize(12)
                      .fontColor(TEXT_TERTIARY)
                  }
                  .alignItems(VerticalAlign.Center)
                  .width('100%')

                  if (this.getEntryStatus(index ?? 0) === 'deleted') {
                    Text('已删除')
                      .fontSize(11)
                      .fontColor(TEXT_TERTIARY)
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
            .borderRadius(14)
            .clip(true)
            .backgroundColor(CARD_BACKGROUND)
            .border({ width: 1, color: CARD_BORDER })
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
                  this.getUIContext().animateTo({
                    duration: LAYOUT_ANIM_DURATION,
                    curve: Curve.Friction
                  }, () => {
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
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 28,
      right: 28,
      top: this.historyTopInset(),
      bottom: 20
    })
    .backgroundColor(HISTORY_PANEL_BACKGROUND)
    .border({ width: 1, color: HISTORY_PANEL_BORDER })
    .borderRadius(28)
    .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 全屏海洋渐变背景，铺满整个窗口（含状态栏之下）
      OceanBackground({
        active: this.backgroundActive,
        onPhaseChange: (phase: number) => {
          this.onBackgroundPhase(phase);
        }
      })

      Column() {
        if (this.useSideBySide()) {
          // 有历史且足够宽的矮/方形窗口：左栏主视觉，右栏历史列表铺满高度
          Row() {
            Column() {
              Blank()
                .layoutWeight(30)
              this.buildHeroBlock()
              Blank()
                .layoutWeight(70)
            }
            .width(HERO_COLUMN_WIDTH)
            .height('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 12, bottom: 12 })

            Column() {
              this.buildHistoryPanel()
            }
            .layoutWeight(1)
            .height('100%')
            .padding({
              right: this.historyPanelOuterInset(),
              top: this.historyPanelOuterInset(),
              bottom: this.historyPanelOuterInset()
            })
            .transition(HISTORY_TRANSITION)
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
        } else {
          // 窄窗或窄高窗：主视觉占顶部 40%，历史列表铺满余下空间
          Column() {
            if (this.recentFiles.length > 0) {
              Column() {
                this.buildHeroBlock()
              }
              .width('100%')
              .height('40%')
              .alignItems(HorizontalAlign.Center)
              .justifyContent(FlexAlign.Center)

              Column() {
                this.buildHistoryPanel()
              }
              .width('100%')
              .layoutWeight(1)
              .height('100%')
              .padding({
                left: this.historyPanelOuterInset(),
                right: this.historyPanelOuterInset(),
                bottom: this.historyPanelOuterInset()
              })
              .transition(HISTORY_TRANSITION)
            } else {
              Blank()
                .layoutWeight(30)
              this.buildHeroBlock()
              Blank()
                .layoutWeight(70)
            }
          }
          .width('100%')
          .height('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .padding({
        top: this.getUIContext().px2vp(this.avoidAreaTopPx),
        bottom: this.getUIContext().px2vp(this.avoidAreaBottomPx)
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
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
