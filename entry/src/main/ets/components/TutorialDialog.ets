import { LengthMetrics } from '@kit.ArkUI';
import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';

const h2 = '#4DA6FF';
const h3 = '#66FF99';
const h4 = '#99FFCC';
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
        .fontSize(15)
        .fontWeight(this.currentTab == index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab == index ? h2 : '#888888')
        .padding({ left: 14, right: 14, top: 10, bottom: 8 })
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
        Span('Just PDF 是为音乐演奏从业者设计的 PDF 阅读器，提供简洁、流畅的阅读及标注体验，以及对常见翻谱器的支持。\n\n')

        Span('打开文件\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('从文件管理器打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在文件管理器中找到 PDF 文件，点击即可使用 Just PDF 打开\n')
        Span('• 应用将直接进入阅读界面，无需额外操作\n\n')

        Span('从应用内打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 启动 Just PDF，点击"选择文件"按钮\n')
        Span('• 从文件选择器中选择要查看的 PDF 文件\n\n')

        Span('菜单按钮\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('屏幕左下角的圆形按钮是菜单开关。点击展开后可见以下功能按钮：\n\n')

        Span('操作').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 切换拖动、绘制、擦除模式\n')
        Span('跳转').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 重置视口、跳转首页 / 尾页\n')
        Span('设置').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示模式、翻页模式、进度滑块开关\n')
        Span('节拍器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示/隐藏节拍器悬浮窗口（占位）\n')
        Span('分享').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 通过系统分享面板分享 PDF 文件\n')
        Span('全屏').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 切换全屏 / 窗口模式（仅限平板和二合一设备）\n')
        Span('教程').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开本教程\n\n')

        Span('设置选项\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('显示模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 单页 — 仅显示一页\n')
        Span('• 双页 — 按对显示（1-2, 3-4, …）\n')
        Span('• 双页连续 — 连续显示当前页与下一页（1-2, 2-3, …）\n')
        Span('• 三页 — 按组显示（1-3, 4-6, …）\n')
        Span('• 三页连续 — 连续显示当前页与后两页（1-3, 2-4, …）\n\n')

        Span('翻页模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 屏侧翻页 — 点击屏幕左侧 30% 上一页，右侧 30% 下一页\n')
        Span('• 按钮翻页 — 使用屏幕右下角的 < > 按钮翻页\n')
        Span('• 外设翻页 — 仅通过键盘或蓝牙翻谱器翻页，隐藏屏幕翻页控件\n\n')

        Span('进度滑块\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 开启后在屏幕右侧显示垂直滑块，拖动可快速跳转到任意页面\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabNavigation() {
    Scroll() {
      Text() {
        Span('缩放与平移\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('双指缩放\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 两根手指捏合或展开来缩放页面\n')
        Span('• 缩放范围：0.5x ~ 9x\n')
        Span('• 在绘制或擦除模式下，双指缩放会自动暂停注释操作\n\n')

        Span('单指拖动\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在"拖动"模式下，单指滑动来移动页面\n\n')

        Span('重置视口\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 通过菜单的"跳转"→"重置视口"将页面恢复为适应屏幕大小\n\n')

        Span('快速导航\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 通过菜单的"跳转"按钮，可以跳转首页或尾页\n')
        Span('• 拖动右侧进度滑块（需在设置中开启）快速定位到任意页面\n')
        Span('• 右下角显示当前页码/总页数\n\n')

        Span('页面跳转\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 通过菜单的"跳转"按钮，可快速返回首页或尾页\n')
        Span('• 拖动右侧进度滑块（需在设置中开启）可快速定位页面\n')
        Span('• 右下角页码可帮助确认当前位置\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabAnnotation() {
    Scroll() {
      Text() {
        Span('注释模式\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('通过菜单的"操作"按钮切换以下模式：\n\n')

        Span('拖动模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 默认模式，用于浏览和导航\n')
        Span('• 单指拖动页面，双指缩放\n\n')

        Span('绘制模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在页面上绘制橙色标记\n')
        Span('• 单指滑动即可绘制\n')
        Span('• 双指仍可缩放和拖动页面\n\n')

        Span('擦除模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 触摸或滑过笔画即可擦除\n')
        Span('• 擦除范围会高亮显示\n')
        Span('• 仅擦除本次添加的注释（橙色），不影响已保存的注释\n\n')

        Span('撤销与重做\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('当存在注释操作时，屏幕右下角会出现撤销、重做和保存按钮。\n\n')

        Span('• ')
        Span('撤销').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 撤销上一次操作，按钮显示可撤销次数\n')
        Span('• ')
        Span('重做').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 恢复已撤销的操作\n')
        Span('• 执行新的绘制或擦除会清空重做历史\n')
        Span('• 撤销/重做会自动导航到相关页面\n')
        Span('• 三指同时触摸屏幕可快速撤销（仅在绘制/擦除模式下）\n\n')

        Span('保存注释\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('1. 点击保存按钮\n')
        Span('2. 选择保存位置和文件名\n')
        Span('3. 所有注释将嵌入 PDF 文件\n')
        Span('4. 保存成功后，注释历史将清空\n\n')

        Span('提示：\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('• 注释保存为 PDF 标准格式，可在其他阅读器中查看\n')
        Span('• 按钮变暗（半透明）表示当前无法使用\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabShortcuts() {
    Scroll() {
      Text() {
        Span('键盘快捷键\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('适用于平板和二合一设备的外接键盘。\n\n')

        Span('导航\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
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

        Span('编辑\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('Ctrl + Z').fontFamily('monospace').fontColor(kbd)
        Span('  撤销\n')
        Span('• ')
        Span('Ctrl + Shift + Z / Ctrl + Y').fontFamily('monospace').fontColor(kbd)
        Span('  重做\n')
        Span('• ')
        Span('Ctrl + S').fontFamily('monospace').fontColor(kbd)
        Span('  保存\n\n')

        Span('手势\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• ')
        Span('三指触摸').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 快速撤销（仅在绘制/擦除模式下）\n')
        Span('• ')
        Span('双指捏合').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 缩放页面\n')
        Span('• ')
        Span('单指拖动').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 拖动模式下平移页面，绘制模式下绘制标记\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabFaq() {
    Scroll() {
      Text() {
        Span('Q: 为什么我的注释没有保存？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 请确保点击保存按钮并选择保存位置。注释只有在保存后才会永久嵌入 PDF 文件。\n\n')

        Span('Q: 如何删除错误的标注？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 切换到"擦除"模式，触摸要删除的笔画。或使用撤销按钮撤销最近的操作。\n\n')

        Span('Q: 全屏按钮在哪里？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 全屏按钮仅在平板和二合一设备上显示，在菜单展开后可见。\n\n')

        Span('Q: 保存的注释能在其他应用中看到吗？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 是的，注释保存为 PDF 标准格式（Polyline Annotation），可在任何 PDF 阅读器中查看。\n\n')

        Span('Q: 如何使用蓝牙翻谱器？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在设置中将翻页模式切换为"外设翻页"，然后使用蓝牙翻谱器的方向键翻页。\n\n')

        Span('感谢使用 Just PDF！').fontStyle(FontStyle.Italic).fontColor('#CCCCCC')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  build() {
    Column(ContainerWideCfg) {

      Text('Just PDF 使用教程')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .height(60)

      Tabs({ index: this.currentTab }) {
        TabContent() {
          this.tabBasics()
        }.tabBar(this.tabBar('基础', 0))

        TabContent() {
          this.tabNavigation()
        }.tabBar(this.tabBar('导航', 1))

        TabContent() {
          this.tabAnnotation()
        }.tabBar(this.tabBar('注释', 2))

        TabContent() {
          this.tabShortcuts()
        }.tabBar(this.tabBar('快捷键', 3))

        TabContent() {
          this.tabFaq()
        }.tabBar(this.tabBar('FAQ', 4))
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