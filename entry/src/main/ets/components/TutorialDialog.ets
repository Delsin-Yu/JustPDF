import { LengthMetrics } from '@kit.ArkUI';
import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';

const h2 = '#4DA6FF';
const h3 = '#66FF99';
const highlight = '#FFA500';
const kbd = '#FFD700';
const bodySize = 16;
const lineGap = LengthMetrics.vp(5);

@CustomDialog
export struct TutorialDialogBuilder {
  private controller: CustomDialogController;
  @State currentTab: number = 0;

  @Builder
  tabBar(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.currentTab == index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab == index ? h2 : '#888888')
        .padding({ left: 10, right: 10, top: 10, bottom: 8 })
      Divider()
        .width(this.currentTab == index ? '60%' : '0%')
        .strokeWidth(2)
        .color(h2)
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  tabBasics() {
    Scroll() {
      Text() {
        Span('Just PDF 面向音乐演奏与练习场景：流畅读谱、笔迹标注、外接翻谱器，并内置节拍器与调音器辅助排练。\n\n')

        Span('打开文件\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('从系统打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在文件管理器中点击 PDF，可选用本应用打开\n')
        Span('• 进入阅读界面后即可开始浏览\n\n')

        Span('从应用内打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在首页点击「选择文件」\n')
        Span('• 在系统文件选择器中选择 PDF\n\n')

        Span('左下角「更多」菜单\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('点击屏幕左下角圆形按钮展开菜单，分为两组：\n\n')

        Span('第一组\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('教程').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开本说明\n')
        Span('• ')
        Span('设置').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开设置弹窗（见下文）\n')
        Span('• ')
        Span('全屏 / 窗口').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 在支持自由窗口的设备上切换沉浸式全屏（与菜单当前状态有关）\n')
        Span('• ')
        Span('分享').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 通过系统分享面板分享当前 PDF\n')
        Span('• ')
        Span('节拍器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示或隐藏节拍器面板\n')
        Span('• ')
        Span('调音器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示或隐藏调音器面板\n\n')

        Span('第二组\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('显示:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 单页 / 双页 / 双页连续 / 三页 / 三页连续\n')
        Span('• ')
        Span('翻页:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 屏侧翻页 / 按钮翻页 / 外设翻页\n')
        Span('• ')
        Span('跳转').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 重置视口、跳转首页、跳转尾页\n')
        Span('• 当前交互模式项（显示为 ')
        Span('拖动').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('、')
        Span('绘制').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 或 ')
        Span('擦除').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('）— 展开后可在三种模式间切换\n\n')

        Span('设置弹窗与菜单的区别\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('「设置」中目前仅提供「进度滑块」开关。显示模式、翻页方式、标注模式等均在上述「更多」菜单的第二组中调整，并会持久保存。\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabReadingNavigation() {
    Scroll() {
      Text() {
        Span('版式与翻页\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('在菜单「显示:…」中选择：\n')
        Span('• 单页 — 每次一屏一页\n')
        Span('• 双页 — 按对显示（1-2，3-4，…）\n')
        Span('• 双页连续 — 当前页与下一页连续（1-2，2-3，…）\n')
        Span('• 三页 — 按三张一组（1-3，4-6，…）\n')
        Span('• 三页连续 — 当前起连续三张（1-3，2-4，…）\n\n')

        Span('在菜单「翻页:…」中选择：\n')
        Span('• 屏侧翻页 — 点击屏幕左侧约 30% 上一页，右侧约 30% 下一页\n')
        Span('• 按钮翻页 — 使用右下角「<」「>」翻页\n')
        Span('• 外设翻页 — 隐藏屏上翻页按钮，主要用键盘或蓝牙翻谱器等外设翻页\n\n')

        Span('缩放与平移\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('双指捏合 / 张开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 缩放页面，范围约 0.5×～9×\n')
        Span('• 双指也可平移已放大的画面\n')
        Span('• 在绘制或擦除模式下，双指用于缩放与平移，优先于单指绘画或擦除\n\n')

        Span('单指拖动\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在「拖动」模式下，单指滑动平移页面\n\n')

        Span('鼠标（平板 / 二合一外接鼠标时）\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 滚轮可在指针位置附近缩放\n')
        Span('• 左键拖动的行为随当前标注模式变化（拖动模式下平移页面）\n\n')

        Span('快速定位\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('• 菜单「跳转」— 重置视口（恢复适合屏幕的缩放与位置）、跳转首页或尾页\n')
        Span('• 若已在「设置」中开启「进度滑块」，可拖动右侧竖条跳到任意页\n')
        Span('• 底部显示当前页 / 总页数\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabAnnotation() {
    Scroll() {
      Text() {
        Span('交互模式\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('在「更多」菜单第二组中，点击当前模式名（拖动 / 绘制 / 擦除）展开子菜单切换：\n\n')

        Span('拖动\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 默认浏览模式：单指平移，双指缩放\n\n')

        Span('绘制\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在页面上绘制橙色笔迹\n')
        Span('• 单指滑动绘制；双指仍可用于缩放与平移\n\n')

        Span('擦除\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 沿笔划擦除本次会话中的橙色标注\n')
        Span('• 擦除区域会高亮提示\n')
        Span('• 不会擦除已通过「保存」写入 PDF 的历史注释\n\n')

        Span('撤销与重做\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('有未保存的标注操作时，右下角会出现撤销、重做与保存。\n\n')

        Span('• ')
        Span('撤销').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 撤销上一步；按钮可提示剩余可撤销步数\n')
        Span('• ')
        Span('重做').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 恢复被撤销的操作；一旦开始新的绘制或擦除，已撤销的步骤将无法用重做恢复\n')
        Span('• 若撤销或重做的笔划不在当前可见页，阅读器会自动翻到该页\n')
        Span('• 在绘制或擦除模式下，三指同时触屏可快速撤销\n\n')

        Span('保存到 PDF\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('1. 点击保存\n')
        Span('2. 在系统界面中选择路径与文件名\n')
        Span('3. 笔迹以常见 PDF 阅读器可识别的笔迹形式写入文件\n')
        Span('4. 保存成功后本次会话的撤销历史会清空\n\n')

        Span('提示\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('• 其他 PDF 阅读器可正常查看已保存的注释\n')
        Span('• 按钮半透明表示当前不可用\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabMusicTools() {
    Scroll() {
      Text() {
        Span('节拍器与调音器为悬浮面板，与乐谱同屏使用；拖动、缩放面板时手势不会穿透到 PDF 区域。\n\n')

        Span('节拍器\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 在「更多」菜单中点击「节拍器」显示或隐藏面板\n')
        Span('• 可设置速度（BPM）、拍号分子与分母；提供节拍声与界面上的节拍反馈\n')
        Span('• 在速度数字轮上 ')
        Span('长按').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 可打开数字输入框，在允许范围内精确输入 BPM\n')
        Span('• 面板支持拖动位置与双指缩放；较窄屏幕下可能与调音器并排停靠或通过标签切换，避免遮挡乐谱时可拖动到合适角落\n\n')

        Span('调音器\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 在「更多」菜单中点击「调音器」显示或隐藏面板\n')
        Span('• 首次使用需同意 ')
        Span('麦克风').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 权限，用于采集乐器声音并显示音高与频谱\n')
        Span('• 实时显示音名、可选唱名 / 升降号、A4 频率与移调等选项（以面板内实际控件为准）\n')
        Span('• 支持乐器音区预设、自动增益与参考音等辅助练习的功能\n')
        Span('• 与节拍器相同，支持拖动与缩放；窄屏下注意与节拍器面板的布局关系\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabShortcuts() {
    Scroll() {
      Text() {
        Span('以下快捷键适用于外接键盘的平板或二合一设备。触控与标注的更多说明见「阅读」「注释」页签。\n\n')

        Span('翻页与位置\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• ')
        Span('↑ / ←').fontFamily('monospace').fontColor(kbd)
        Span('  上一页\n')
        Span('• ')
        Span('↓ / → / 空格').fontFamily('monospace').fontColor(kbd)
        Span('  下一页\n')
        Span('• ')
        Span('Ctrl + ↑ / ←').fontFamily('monospace').fontColor(kbd)
        Span('  跳转首页\n')
        Span('• ')
        Span('Ctrl + ↓ / →').fontFamily('monospace').fontColor(kbd)
        Span('  跳转尾页\n\n')

        Span('标注\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• ')
        Span('Ctrl + Z').fontFamily('monospace').fontColor(kbd)
        Span('  撤销\n')
        Span('• ')
        Span('Ctrl + Shift + Z').fontFamily('monospace').fontColor(kbd)
        Span(' / ')
        Span('Ctrl + Y').fontFamily('monospace').fontColor(kbd)
        Span('  重做\n')
        Span('• ')
        Span('Ctrl + S').fontFamily('monospace').fontColor(kbd)
        Span('  保存注释到 PDF\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabFaq() {
    Scroll() {
      Text() {
        Span('Q: 为什么「设置」里没有显示模式、翻页方式？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 这些选项在左下角「更多」菜单的第二组中，分别为「显示:…」与「翻页:…」。「设置」弹窗目前仅包含「进度滑块」开关。\n\n')

        Span('Q: 为什么我的笔迹没有保存进文件？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 必须点击保存并选择输出路径。仅停留在屏幕上而未保存的标注不会写入 PDF。\n\n')

        Span('Q: 如何删掉画错的线？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 切换到「擦除」模式沿笔划擦除，或使用撤销（含三指撤销）。\n\n')

        Span('Q: 全屏按钮找不到？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 仅在支持自由窗口形态的设备上，菜单中会显示「全屏」或「窗口」项；手机等形态可能不显示。\n\n')

        Span('Q: 保存的注释能在别的应用里看吗？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 可以。以通用 PDF 笔迹注释保存，常见 PDF 应用均可显示。\n\n')

        Span('Q: 蓝牙翻谱器怎么用？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在菜单中将「翻页:…」设为「外设翻页」，然后使用翻谱器发送的方向键或等价按键翻页（具体以设备说明为准）。\n\n')

        Span('Q: 调音器没有反应？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 请在系统设置中为本应用开启麦克风权限；并确认环境音量足够、麦克风未被遮挡。\n\n')

        Span('感谢使用 Just PDF。').fontStyle(FontStyle.Italic).fontColor('#CCCCCC')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  build() {
    Column(ContainerWideCfg) {

      Text('Just PDF 使用说明')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .height(60)

      Tabs({ index: this.currentTab }) {
        TabContent() {
          this.tabBasics()
        }.tabBar(this.tabBar('基础', 0))

        TabContent() {
          this.tabReadingNavigation()
        }.tabBar(this.tabBar('阅读', 1))

        TabContent() {
          this.tabAnnotation()
        }.tabBar(this.tabBar('注释', 2))

        TabContent() {
          this.tabMusicTools()
        }.tabBar(this.tabBar('乐谱工具', 3))

        TabContent() {
          this.tabShortcuts()
        }.tabBar(this.tabBar('快捷键', 4))

        TabContent() {
          this.tabFaq()
        }.tabBar(this.tabBar('常见问题', 5))
      }
      .barMode(BarMode.Fixed)
      .barBackgroundColor(Color.Transparent)
      .divider({ strokeWidth: 0.5, color: '#333333' })
      .onChange(index => this.currentTab = index)
      .layoutWeight(1)
      .width('100%')

    }
    .margin(ContainerWidePadding)

  }
}
