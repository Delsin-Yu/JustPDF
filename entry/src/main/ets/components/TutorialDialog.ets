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
        Span('Just PDF 面向音乐演奏与练习：读谱、书签与批注、PDF 内链跳转，并支持外接翻谱设备；同屏提供节拍器与调音器。\n\n')

        Span('打开文件\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('从系统打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 在文件管理器、分享面板等场景选用本应用打开 PDF，即可进入阅读界面\n')
        Span('• 若文档已加密，阅读页会提示 ')
        Span('输入 PDF 密码').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('；密码仅用于本次阅读，不会保存到设置中\n\n')

        Span('从应用首页打开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 点击「选择文件」，在系统文件选择器中选择 PDF\n')
        Span('• 首页「最近打开」列出曾打开过的文件；点击可再次打开\n')
        Span('• 若文件已删除或权限过期，列表会标注状态，可重新选择文件\n')
        Span('• 在最近列表中向左滑某条记录，可将其从列表中移除\n\n')

        Span('左下角「更多」菜单\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('点击屏幕左下角圆形 ')
        Span('⋯').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 按钮展开菜单，分为两组：\n\n')

        Span('第一组\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('教程').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开本说明\n')
        Span('• ')
        Span('设置').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开设置弹窗（见下文）\n')
        Span('• ')
        Span('全屏 / 窗口').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 在支持自由窗口的设备上切换沉浸式全屏（仅在该类设备上显示）\n')
        Span('• ')
        Span('分享').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 通过系统分享面板分享当前 PDF\n')
        Span('• ')
        Span('节拍器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' / ')
        Span('调音器').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 显示或隐藏对应悬浮面板（详见「乐谱工具」）\n')
        Span('• ')
        Span('批注').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开批注浮窗；旁侧 ')
        Span('●').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 表示有未保存的笔迹\n')
        Span('• ')
        Span('书签').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 打开书签面板；旁侧 ')
        Span('●').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 表示有未保存的书签更改\n\n')

        Span('第二组\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• ')
        Span('显示:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 单页 / 双页 / 双页连续 / 三页 / 三页连续\n')
        Span('• ')
        Span('翻页:…').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 水平滑动 / 屏侧翻页 / 按钮翻页 / 外设翻页\n')
        Span('• ')
        Span('跳转').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 重置视口、跳转首页、跳转尾页\n')
        Span('• ')
        Span('保存文档').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 将批注与书签写入新 PDF；旁侧 ')
        Span('●').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 表示有未保存更改\n\n')

        Span('设置弹窗与菜单的区别\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('「设置」提供：\n')
        Span('• ')
        Span('进度滑块').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 是否在页面右侧显示快速跳页滑块\n')
        Span('• ')
        Span('PDF 跳转链接显示').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 隐藏 / 进入后淡出 / 始终显示链接热区提示（不影响能否点击）\n')
        Span('• ')
        Span('水平滑动灵敏度').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 0～10 档，仅在选择「翻页:水平滑动」时生效\n\n')
        Span('显示模式、翻页方式等仍在「更多」第二组中调整，并会持久保存。\n')
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

        Span('在菜单「翻页:…」中可选：\n')
        Span('• ')
        Span('水平滑动').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 单指横向滑动可预览邻页，松手或甩动足够时翻页；竖向为主时平移画面。灵敏度见「设置」\n')
        Span('• ')
        Span('屏侧翻页').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 点按屏幕左侧约 30% 上一页、右侧约 30% 下一页；首次切换到此模式时会有边缘渐变提示。若刚完成平移、捏合或滚轮缩放，会忽略误触翻页\n')
        Span('• ')
        Span('按钮翻页').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 使用底部「<」「>」\n')
        Span('• ')
        Span('外设翻页').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' — 隐藏底部按钮以减少误触；键盘与蓝牙翻谱器在任意翻页模式下均可翻页\n\n')
        Span('批注浮窗处于「绘制」或「擦除」时，底部会显示「<」「>」以便翻页；关闭浮窗后行为与菜单所选一致。\n\n')

        Span('缩放与平移\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('双指捏合 / 张开\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 缩放约 0.5×～9×；双指也可平移已放大画面\n')
        Span('• 绘制或擦除时，双指优先用于缩放与平移\n\n')

        Span('单指拖动\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 「水平滑动」以外：单指平移页面\n')
        Span('• 「水平滑动」：横向为主用于翻页预览，竖向为主用于平移\n\n')

        Span('鼠标（平板 / 二合一）\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 滚轮在指针附近缩放\n')
        Span('• 左键拖动：常规浏览下平移；批注工具下随工具变化\n\n')

        Span('快速定位\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)
        Span('• 菜单「跳转」— 重置视口、首页或尾页（多页版式下尾页为最后一组可浏览位置）\n')
        Span('• 若已开启「进度滑块」，可拖动右侧竖条跳到任意页\n')
        Span('• 底部显示当前页 / 总页数\n')
        Span('• 界面控件在操作后会短暂完全显示，随后略微变淡，便于沉浸阅读\n\n')

        Span('PDF 内链与书签的详细说明见「书签与链接」页签。\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabBookmarksAndLinks() {
    Scroll() {
      Text() {
        Span('书签\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('打开方式\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 「更多」菜单第一组中的「书签」\n')
        Span('• 文档中已有书签时，菜单按钮上方可能出现圆形书签快捷按钮\n\n')

        Span('面板操作\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 列表中点击书签项可跳到对应页\n')
        Span('• 可添加当前页书签、删除条目、通过「重命名书签」修改标题\n')
        Span('• 浮窗可拖动位置、双指缩放；屏幕较窄时会与节拍器 / 调音器一起停靠在侧边标签区\n\n')

        Span('保存\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 书签更改需通过「保存文档」写入 PDF，与批注共用同一保存流程\n')
        Span('• 未保存时，「书签」「批注」「保存文档」菜单项旁可能显示 ')
        Span('●').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('；切换或关闭文档前若存在未保存更改，系统会提示是否保存\n\n')

        Span('PDF 内跳转链接\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 乐谱或文档中的页内链接：轻点热区可跳到目标页\n')
        Span('• 指向网址的链接：通过系统打开对应 URI\n')
        Span('• 小幅拖动会取消点击，避免与翻页、平移手势冲突\n')
        Span('• 在「设置」中调整 ')
        Span('PDF 跳转链接显示').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('：隐藏 / 进入后淡出 / 始终显示热区提示\n\n')

        Span('链接跳转历史\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 通过页内链接跳转到新页后，「更多」按钮附近会出现圆形 ')
        Span('‹').fontFamily('monospace').fontColor(kbd)
        Span(' / ')
        Span('›').fontFamily('monospace').fontColor(kbd)
        Span(' 按钮，用于在后退栈与前进栈间导航\n')
        Span('• 使用进度滑块跳页也会记入历史，便于回到跳转前位置\n')
        Span('• 打开新文档时历史会清空\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabAnnotation() {
    Scroll() {
      Text() {
        Span('浏览与批注浮窗\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('默认为常规浏览：双指缩放；单指行为随「翻页:…」设置变化（见「阅读」）。\n\n')
        Span('打开批注浮窗：\n')
        Span('• 「更多」→「批注」\n')
        Span('• 常规浏览下单指按住页面直至触点旁环形进度走满\n')
        Span('• 常规浏览下手写笔轻点纸面；部分设备支持笔双击快捷打开\n\n')
        Span('浮窗内可切换「绘制」或「擦除」，右上角关闭；左侧手柄可拖动位置，双指可缩放浮窗。\n\n')

        Span('绘制\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 单指或鼠标左键在页面上绘制；可选预设色与自定义颜色\n')
        Span('• 打开文档时可能自动扫描并导入 PDF 中已有的折线批注（期间会短暂禁止绘制）\n')
        Span('• 双指仍用于缩放与平移整页\n\n')

        Span('擦除\n').fontSize(18).fontWeight(FontWeight.Medium).fontColor(h3)
        Span('• 沿笔划擦除本会话中的笔迹，擦除过程有高亮提示\n')
        Span('• 不会擦掉已通过「保存文档」写入文件的既有笔迹\n\n')

        Span('撤销与重做\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 浮窗内 ')
        Span('撤销').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' / ')
        Span('重做').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('；有可撤销步骤时按钮显示大致步数\n')
        Span('• 若目标笔划不在当前可见页，会自动翻到该页\n')
        Span('• 绘制或擦除工具下，三指同时按下可快速撤销\n')
        Span('• 开始新的绘制或擦除后，更早被撤销的步骤无法再用重做恢复\n\n')

        Span('保存到 PDF\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 批注浮窗内保存，或「更多」→「保存文档」\n')
        Span('• 在系统界面选择路径与文件名；笔迹以常见 PDF 折线注释形式写入\n')
        Span('• 保存会一并写入未保存的书签更改\n')
        Span('• 保存成功后，本次会话内的撤销历史会清空\n\n')

        Span('提示\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('• 本应用不提供文内搜索或选中复制正文；批注为手绘墨迹\n')
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

        Span('• 「更多」→「节拍器」显示或隐藏\n')
        Span('• 可设置 BPM、拍号；提供节拍声与界面反馈\n')
        Span('• 在速度数字轮上 ')
        Span('长按').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 可精确输入 BPM\n')
        Span('• 面板可拖动、双指缩放；窄屏时可与调音器并排或分标签显示\n\n')

        Span('调音器\n\n').fontSize(22).fontWeight(FontWeight.Bold).fontColor(h2)

        Span('• 「更多」→「调音器」显示或隐藏\n')
        Span('• 首次使用需在系统中开启 ')
        Span('麦克风').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span(' 权限\n')
        Span('• 面板内可切换唱名、A4 频率、移调、乐器预设、自动增益、参考音等\n')
        Span('• 与节拍器相同，支持拖动与缩放\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabShortcuts() {
    Scroll() {
      Text() {
        Span('以下快捷键适用于外接键盘的平板或二合一设备。\n\n')

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
        Span('  保存批注与书签到 PDF\n')
      }.fontSize(bodySize).lineSpacing(lineGap).padding(20)
    }.layoutWeight(1).width('100%')
  }

  @Builder
  tabFaq() {
    Scroll() {
      Text() {
        Span('Q: 为什么「设置」里没有显示模式、翻页方式？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在「更多」第二组的「显示:…」与「翻页:…」。「设置」另有进度滑块、PDF 跳转链接显示与水平滑动灵敏度。\n\n')

        Span('Q: 书签改了但没写进文件？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 书签与批注一样，须执行「保存文档」并选择保存位置。菜单旁的 ● 表示仍有未保存更改。\n\n')

        Span('Q: 为什么我的笔迹没有保存进文件？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 须在批注浮窗或菜单中执行「保存文档」。只画在屏幕上而未保存的笔迹不会写入 PDF。\n\n')

        Span('Q: 点链接后如何回到原来的页？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 使用「更多」按钮附近的圆形后退 / 前进按钮；若无按钮，表示当前没有可回溯的链接跳转历史。\n\n')

        Span('Q: 如何删掉画错的线？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 批注浮窗切到「擦除」，或使用撤销；绘制 / 擦除工具下也可三指同按快速撤销。\n\n')

        Span('Q: 全屏按钮找不到？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 仅在支持自由窗口形态的设备上显示「全屏」或「窗口」。\n\n')

        Span('Q: 保存的批注能在别的应用里看吗？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 可以。以常见 PDF 折线注释与书签形式保存，一般阅读器均可查看。\n\n')

        Span('Q: 蓝牙翻谱器怎么用？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 通常模拟方向键，与「翻页:…」选项无关。若希望隐藏底部「<」「>」，可选「外设翻页」。\n\n')

        Span('Q: 调音器没有反应？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在系统设置中开启麦克风权限，并确认环境音量足够。\n\n')

        Span('Q: 批注或书签面板挡住谱子？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 拖动手柄移到合适位置，或用双指缩小面板。\n\n')

        Span('Q: 支持在设备间接着上次阅读吗？\n').fontWeight(FontWeight.Bold).fontColor(highlight)
        Span('A: 在支持 HarmonyOS 应用接续的设备上，可通过系统接续继续打开同一文档；具体以系统与账号能力为准。\n\n')

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
          this.tabBookmarksAndLinks()
        }.tabBar(this.tabBar('书签与链接', 2))

        TabContent() {
          this.tabAnnotation()
        }.tabBar(this.tabBar('注释', 3))

        TabContent() {
          this.tabMusicTools()
        }.tabBar(this.tabBar('乐谱工具', 4))

        TabContent() {
          this.tabShortcuts()
        }.tabBar(this.tabBar('快捷键', 5))

        TabContent() {
          this.tabFaq()
        }.tabBar(this.tabBar('常见问题', 6))
      }
      .barMode(BarMode.Scrollable)
      .barBackgroundColor(Color.Transparent)
      .divider({ strokeWidth: 0.5, color: '#333333' })
      .onChange(index => this.currentTab = index)
      .layoutWeight(1)
      .width('100%')

    }
    .margin(ContainerWidePadding)

  }
}
