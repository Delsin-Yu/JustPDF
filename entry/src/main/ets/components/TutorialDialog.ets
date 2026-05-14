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
        Span('Just PDF 面向音乐演奏与练习：读谱、批注、外接翻谱设备，并内置节拍器与调音器。\n\n')

        Span('打开文件\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('从系统打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在文件管理器等场景下选用本应用打开 PDF，即可进入阅读界面\n\n')

        Span('从应用首页打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 点击「选择文件」，在系统文件选择器中选择 PDF\n')
        Span('• 若曾打开过文件，首页会列出「最近打开」；点击某项可再次打开\n')
        Span('• 在最近列表中向左滑某条记录，可将其从列表中移除\n\n')

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
        Span(' — 在支持自由窗口的设备上切换沉浸式全屏（仅在该类设备上显示此项）\n')
        Span('• ')
        Span('分享').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 通过系统分享面板分享当前 PDF\n')
        Span('• ')
        Span('节拍器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示或隐藏节拍器面板\n')
        Span('• ')
        Span('调音器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示或隐藏调音器面板\n')
        Span('• ')
        Span('批注').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开批注浮窗，进行绘制或擦除（详见「注释」页签）\n\n')

        Span('第二组\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('显示:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 单页 / 双页 / 双页连续 / 三页 / 三页连续\n')
        Span('• ')
        Span('翻页:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 横向滑动 / 屏侧翻页 / 按钮翻页 / 外设翻页\n')
        Span('• ')
        Span('跳转').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 重置视口、跳转首页、跳转尾页\n')
        Span('• ')
        Span('保存文档').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 将当前批注保存为新 PDF（与批注浮窗内的保存相同）\n\n')

        Span('设置弹窗与菜单的区别\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('「设置」中提供「进度滑块」开关，以及「横向滑动灵敏度」档位滑块（0～10，步进 1）：同时调节松手翻页所需滑动距离与甩动翻页的容易程度；仅在选择「翻页:横向滑动」时生效。显示模式、翻页方式等仍在「更多」菜单第二组中调整，并会持久保存。\n')
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

        Span('在菜单「翻页:…」中可选（与菜单列表顺序一致）：\n')
        Span('• 横向滑动 — 默认方式。在常规浏览下，单指以横向为主在页面上滑动，可看到邻页随手指移动；松手时若位移足够（或与滑动速度综合判断后足够）则翻到该侧邻页，否则回到当前页。竖向为主的滑动仍会平移当前画面。可在左下角「更多」—「设置」中用「横向滑动灵敏度」在 0（更钝、需拖更远 / 甩得更用力）到 10（更敏）之间调节；中间档为默认手感。\n')
        Span('• 屏侧翻页 — 点击屏幕左侧约 30% 区域上一页，右侧约 30% 下一页\n')
        Span('• 按钮翻页 — 使用底部「<」「>」翻页\n')
        Span('• 外设翻页 — 在常规浏览下隐藏底部「<」「>」翻页按钮，减少误触；键盘、蓝牙翻谱器等外设在任意翻页模式下均可照常翻页（通常对应方向键或设备说明中的等价按键）\n\n')
        Span('当批注浮窗打开且使用「绘制」或「擦除」时，底部会显示「<」「>」以便翻页；关闭浮窗并回到常规浏览后，翻页行为与菜单中所选模式一致。\n\n')

        Span('缩放与平移\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('双指捏合 / 张开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 缩放页面，范围约 0.5×～9×\n')
        Span('• 双指也可平移已放大的画面\n')
        Span('• 在绘制或擦除模式下，双指用于缩放与平移，优先于单指绘画或擦除\n\n')

        Span('单指拖动\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在常规浏览下，若当前为「横向滑动」以外的翻页方式，单指滑动用于平移页面\n')
        Span('• 在「横向滑动」下，以横向为主的单指滑动用于翻页预览（见上文）；以竖向为主时用于平移\n\n')

        Span('鼠标（平板 / 二合一外接鼠标时）\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 滚轮可在指针位置附近缩放\n')
        Span('• 左键拖动的行为随当前批注工具变化（在常规浏览下为平移页面）\n\n')

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
        Span('浏览与批注浮窗\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('默认为常规浏览：单指平移画面（在「横向滑动」翻页方式下，横向滑动优先用于翻页预览，见「阅读」页签），双指缩放。\n\n')
        Span('打开批注浮窗的方式：\n')
        Span('• 「更多」菜单第一组中的「批注」\n')
        Span('• 在常规浏览下，单指按住乐谱直至触点旁环形进度走满\n')
        Span('• 在常规浏览下，使用手写笔轻点纸面\n\n')
        Span('浮窗内可切换到「绘制」或「擦除」，右上角「×」关闭浮窗；关闭后回到常规浏览。浮窗左侧有条形手柄，可拖动改变位置；双指捏合可缩放浮窗大小。\n\n')

        Span('绘制\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 单指在页面上滑动绘制笔迹；在浮窗中选择颜色（多组预设色与自选颜色）\n')
        Span('• 双指仍可用于缩放与平移整页\n\n')

        Span('擦除\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 沿笔划擦除本会话中的笔迹；擦除过程有高亮提示\n')
        Span('• 不会擦掉已通过「保存文档」写入 PDF 的既有笔迹\n\n')

        Span('撤销与重做\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('撤销、重做位于批注浮窗内；有可撤销步骤时，按钮上会显示大致步数。\n\n')

        Span('• ')
        Span('撤销').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 撤销上一步操作\n')
        Span('• ')
        Span('重做').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 恢复被撤销的操作；一旦开始新的绘制或擦除，更早被撤销的步骤将无法再用重做恢复\n')
        Span('• 若撤销或重做的笔划不在当前可见页，阅读器会自动翻到该页\n')
        Span('• 在绘制或擦除工具下，三指同时按下触屏可快速撤销\n\n')

        Span('保存到 PDF\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 在批注浮窗内点击保存，或使用「更多」第二组中的「保存文档」\n')
        Span('• 在系统界面中选择路径与文件名\n')
        Span('• 笔迹以常见 PDF 阅读器可识别的形式写入文件\n')
        Span('• 保存成功后，本次会话内的撤销历史会清空\n\n')

        Span('提示\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('• 其他 PDF 阅读器可正常查看已保存的批注\n')
        Span('• 按钮置灰或半透明表示当前不可用\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabMusicTools() {
    Scroll() {
      Text() {
        Span('节拍器与调音器为悬浮面板，与乐谱同屏使用；在面板上拖动、缩放时，手势不会作用到 PDF 阅读区域。\n\n')

        Span('节拍器\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 在「更多」菜单中点击「节拍器」显示或隐藏面板\n')
        Span('• 可设置速度（BPM）、拍号分子与分母；提供节拍声与界面上的节拍反馈\n')
        Span('• 在速度数字轮上 ')
        Span('长按').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 可打开数字输入框，在允许范围内精确输入 BPM\n')
        Span('• 面板可拖动位置、双指缩放；屏幕较窄时可与调音器并排或分标签显示，按需拖到不挡谱的位置\n\n')

        Span('调音器\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 在「更多」菜单中点击「调音器」显示或隐藏面板\n')
        Span('• 首次使用需在系统中为本应用开启 ')
        Span('麦克风').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 权限，用于采集乐器声并显示音高与音准偏差\n')
        Span('• 面板内可切换唱名 / 升降号、A4 频率、移调、乐器音区预设、自动增益、参考音等（以面板上的开关与按钮为准）\n')
        Span('• 与节拍器相同，支持拖动与缩放；窄屏时注意与节拍器面板的摆放\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabShortcuts() {
    Scroll() {
      Text() {
        Span('以下快捷键适用于外接键盘的平板或二合一设备。触控与批注的更多说明见「阅读」「注释」页签。\n\n')

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

        Span('批注\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

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
        Span('  保存批注到 PDF\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabFaq() {
    Scroll() {
      Text() {
        Span('Q: 为什么「设置」里没有显示模式、翻页方式？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 这些选项在左下角「更多」菜单的第二组：「显示:…」与「翻页:…」。「设置」弹窗另有「进度滑块」开关与「横向滑动灵敏度」（仅影响横向滑动翻页）。\n\n')

        Span('Q: 为什么我的笔迹没有保存进文件？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 须在批注浮窗内保存，或使用菜单里的「保存文档」，并在系统中选择保存位置。只画在屏幕上而未执行保存的笔迹不会写入 PDF。\n\n')

        Span('Q: 如何删掉画错的线？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 打开批注浮窗，切换到「擦除」沿笔划擦除；或使用撤销；在绘制或擦除工具下也可三指同时按下触屏快速撤销。\n\n')

        Span('Q: 全屏按钮找不到？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 仅在支持自由窗口形态的设备上，菜单中会显示「全屏」或「窗口」；其他形态下可能不显示该项。\n\n')

        Span('Q: 保存的批注能在别的应用里看吗？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 可以。以常见 PDF 笔迹注释形式保存，一般 PDF 应用均可查看。\n\n')

        Span('Q: 蓝牙翻谱器怎么用？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 翻谱器一般模拟键盘方向键（或设备说明中的等价键），与当前「翻页:…」选哪一项无关，均可用于上一页 / 下一页。若希望常规浏览时底部不出现「<」「>」，可在菜单中选「外设翻页」隐藏它们。\n\n')

        Span('Q: 调音器没有反应？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在系统设置中为本应用开启麦克风权限；并确认环境音量足够、麦克风未被遮挡。\n\n')

        Span('Q: 批注浮窗挡住谱子怎么办？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 按住浮窗左侧手柄拖到合适位置，或用双指缩小浮窗。\n\n')

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
