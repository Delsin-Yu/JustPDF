import { LengthMetrics } from "@kit.ArkUI";

const level2Color = '#4DA6FF';
const level3Color = '#66FF99';
const level4Color = '#99FFCC';
const level5Color = '#FFA500';
const level6Color = '#FFD700';

@ComponentV2
export struct Tutorial{

  build() {
    Text() {
      Span('Just PDF 是为音乐演奏从业者设计的 PDF 阅读器，提供简洁、流畅的阅读及标注体验，以及对常见翻谱器的支持。\n\n')

      Span('打开 PDF 文件\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('从应用内打开\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('1. 启动 Just PDF 应用\n')
      Span('2. 点击"选择文件"按钮\n')
      Span('3. 从文件选择器中选择您要查看的 PDF 文件\n\n')

      Span('从文件管理器打开\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 在文件管理器中找到 PDF 文件\n')
      Span('• 点击文件并选择使用 Just PDF 打开\n\n')

      Span('界面控制\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('显示/隐藏控件\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"收起"按钮可隐藏大部分控制按钮\n')
      Span('• 点击"展开"按钮可重新显示控制按钮\n')
      Span('• 隐藏控件可获得更大的阅读区域\n\n')

      Span('全屏模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"全屏"按钮进入全屏模式（仅限平板的智慧多窗模式和二合一设备）\n')
      Span('• 点击"窗口"按钮退出全屏模式\n')
      Span('• 全屏模式下获得最大的阅读空间\n\n')

      Span('页面显示模式\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('Just PDF 提供五种页面显示模式，您可以通过点击"显示"按钮选择：\n\n')

      Span('单页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 仅显示一页\n\n')

      Span('双页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 同时显示两页（类似打开的书本）\n')
      Span('• 页面按对分组（第 1-2 页，第 3-4 页，等等）\n\n')

      Span('双页连续模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 在显示当前页的同时，同时显示下一页\n')
      Span('• 连续浏览，不按对分组（第 1-2 页，第 2-3 页，等等）\n\n')

      Span('三页模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 同时显示三页\n')
      Span('• 页面按组分组（第 1-3 页，第 4-6 页，等等）\n\n')

      Span('三页连续模式\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 在显示当前页的同时，同时显示下两页\n')
      Span('• 连续浏览，不按组分组（第 1-3 页，第 2-4 页，等等）\n\n')

      Span('页面导航\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('翻页模式\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)

      Span('Just PDF 提供三种翻页方式，通过"模式"按钮选择：\n\n')

      Span('屏侧翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 点击屏幕左侧 30% 区域：上一页\n')
      Span('• 点击屏幕右侧 30% 区域：下一页\n')
      Span('• 屏幕边缘会显示渐变提示\n\n')

      Span('按钮翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 使用屏幕右下角的 < 和 > 按钮翻页\n\n')

      Span('外设翻页\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 仅使用键盘方向键，蓝牙或外接或设备翻页\n')
      Span('• 隐藏屏幕翻页控件，获得更清爽的阅读体验\n\n')

      Span('快速导航\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)

      Span('• ')
      Span('首页按钮').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('：立即跳转到第一页\n')
      Span('• ')
      Span('尾页按钮').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('：立即跳转到最后一页\n')
      Span('• ')
      Span('页面滑块').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('：拖动右侧的垂直滑块快速跳转到任意页面\n\n')

      Span('缩放和平移\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('双指缩放\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 使用两根手指在屏幕上捏合或展开来缩放页面\n\n')

      Span('拖动平移\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 在"拖动"模式下，使用单指拖动来移动页面\n\n')

      Span('视口重置\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"视口"按钮可将页面重置为适应屏幕的大小和位置\n\n')

      Span('注释功能\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('Just PDF 提供基础、仅添加的PDF的注释工具，让您可以迅速的在 PDF 上做标记。\n\n')

      Span('注释模式\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)

      Span('通过右侧的模式按钮切换：\n\n')

      Span('拖动模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 默认模式，用于浏览和导航\n')
      Span('• 可以使用单指或双指拖动移动页面\n')
      Span('• 可以使用双指缩放\n\n')

      Span('绘制模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 在 PDF 页面上绘制橙色标记\n')
      Span('• 使用单指在屏幕上滑动即可绘制\n')
      Span('• 使用双指来缩放以及拖动页面\n\n')

      Span('擦除模式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(level4Color)
      Span('• 擦除之前绘制的标记\n')
      Span('• 触摸或滑过笔画即可擦除\n')
      Span('• 擦除范围会高亮显示\n')
      Span('• 仅能够擦除此次添加的注释（橙色），不会影响到已经保存的注释\n\n')

      Span('注释提示\n\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)

      Span('• 在绘制或擦除模式下，双指缩放会自动暂停注释操作\n')
      Span('• 使用三指同时触摸屏幕可快速撤销上一次操作\n')
      Span('• 切换页面时，注释会自动保存到对应页面\n')
      Span('• 未保存的注释会在"保存"按钮上显示提醒标记（!）\n\n')

      Span('撤销和重做\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('撤销操作\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"撤回"按钮撤销上一次绘制或擦除操作\n')
      Span('• 按钮上的数字显示可撤销的操作数量\n')
      Span('• 支持跨页面撤销\n')
      Span('• 快捷键：')
      Span('Ctrl + Z').fontFamily("monospace").fontColor(level6Color)
      Span('\n')
      Span('• 手势：三指同时触摸屏幕\n\n')

      Span('重做操作\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"重做"按钮恢复已撤销的操作\n')
      Span('• 按钮上的数字显示可重做的操作数量\n')
      Span('• 快捷键：')
      Span('Ctrl + Shift + Z').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('Ctrl + Y').fontFamily("monospace").fontColor(level6Color)
      Span('\n\n')

      Span('注意事项\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 执行新的绘制或擦除操作会清空重做历史\n')
      Span('• 撤销/重做会自动导航到相关页面\n\n')

      Span('保存和分享\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('保存注释\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('1. 点击"保存"按钮\n')
      Span('2. 选择保存位置和文件名\n')
      Span('3. 应用会将所有注释嵌入到 PDF 文件中\n')
      Span('4. 保存成功后，注释历史会被清空\n\n')

      Span('注意：\n').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('• 保存按钮上的感叹号（!）表示有未保存的注释\n')
      Span('• 保存的注释会作为 PDF 标准注释，可在其他 PDF 阅读器中查看\n')
      Span('• 快捷键：')
      Span('Ctrl + S').fontFamily("monospace").fontColor(level6Color)
      Span('\n\n')

      Span('分享文件\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• 点击"分享"按钮打开系统分享面板\n')
      Span('• 支持通过各种方式分享当前 PDF 文件\n')
      Span('• 支持 HarmonyOS 特有的碰一碰分享和手势分享功能\n\n')

      Span('键盘快捷键\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('Just PDF 支持以下键盘快捷键（适用于平板和二合一设备）：\n\n')

      Span('导航\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• ')
      Span('↑').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('←').fontFamily("monospace").fontColor(level6Color)
      Span('：上一页\n')
      Span('• ')
      Span('↓').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('→').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('空格').fontFamily("monospace").fontColor(level6Color)
      Span('：下一页\n')
      Span('• ')
      Span('Ctrl + ↑').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('Ctrl + ←').fontFamily("monospace").fontColor(level6Color)
      Span('：跳转到首页\n')
      Span('• ')
      Span('Ctrl + ↓').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('Ctrl + →').fontFamily("monospace").fontColor(level6Color)
      Span('：跳转到尾页\n\n')

      Span('编辑\n').fontSize(20).fontWeight(FontWeight.Medium).fontColor(level3Color)
      Span('• ')
      Span('Ctrl + Z').fontFamily("monospace").fontColor(level6Color)
      Span('：撤销\n')
      Span('• ')
      Span('Ctrl + Shift + Z').fontFamily("monospace").fontColor(level6Color)
      Span(' 或 ')
      Span('Ctrl + Y').fontFamily("monospace").fontColor(level6Color)
      Span('：重做\n')
      Span('• ')
      Span('Ctrl + S').fontFamily("monospace").fontColor(level6Color)
      Span('：保存\n\n')

      Span('常见问题\n\n').fontSize(24).fontWeight(FontWeight.Bold).fontColor(level2Color)

      Span('Q: 为什么我的注释没有保存？\n').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('A: 请确保点击"保存"按钮并选择保存位置。注释只有在保存后才会永久嵌入 PDF 文件。\n\n')

      Span('Q: 如何删除错误的标注？\n').fontWeight(FontWeight.Bold).fontColor(level5Color)
      Span('A: 切换到"擦除"模式，然后触摸要删除的笔画。或者使用"撤回"按钮撤销最近的操作。\n\n')

      Span('感谢使用 Just PDF！如有任何问题或建议，欢迎反馈。').fontStyle(FontStyle.Italic).fontColor('#CCCCCC')
    }.fontSize(10+6)
    .lineSpacing(LengthMetrics.vp(5))
    .width('100%')
    .padding(20)
  }
}