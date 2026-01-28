import { add, hslToColor, mul, toSizeVp, Vec2, Vector2 } from './Numbers';
import { PageGroup, PageInfo, PageInfoDataSource, ReadonlyPageInfo } from './PageInfo';
import { ButtonColor, ContainerPadding, ContainerSpacing, ContainerWideCfg, ContainerWidePadding, ContainerWideSpacing, FullRect, StyleButton, TopLeft, TopRight } from './UIComponents';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { LengthMetrics } from '@kit.ArkUI';

const arrowColor = '#ffffffff';
const hoverColor = '#a8000000';

const thumbnailWidth: number = 75;
const previewSize: Vector2 = Vec2(thumbnailWidth, thumbnailWidth * 1.414);
const itemSize = add(previewSize, Vec2(ContainerSpacing + ContainerSpacing, ContainerSpacing + ContainerSpacing));

@Reusable
@Component
struct PageIcon {
  @Require @State pageInfo: PageInfo;
  @Require dataSource: PageInfoDataSource;
  @Require clicked: () => void;

  aboutToAppear(): void {
    this.pageInfo.requestPageThumbnail(previewSize);
  }

  aboutToReuse(params: Record<string, Object | null | undefined>): void {
    this.pageInfo = params.pageInfo as PageInfo;
    this.pageInfo!.requestPageThumbnail(previewSize);
  }

  aboutToRecycle(): void {
    this.pageInfo.evictThumbnail();
  }

  aboutToDisappear(): void {
    this.pageInfo.evictThumbnail();
  }

  @State leftHoverVisible: boolean = false;
  @State rightHoverVisible: boolean = false;
  private midX: number = 0;
  @State isDraggingSource: boolean = false;

  getScale(): ScaleOptions {
    if (!this.leftHoverVisible && !this.rightHoverVisible) {
      return { x: 1, y: 1 };
    }
    return { x: 1.05, y: 1.05 };
  }

  @Builder
  DragPreview() {
    Button({ type: ButtonType.Normal }) {
      Image(this.pageInfo.pageThumbnail)
        .borderRadius(10)
        .draggable(false)
        .margin(0)
        .padding(ContainerPadding)
        .autoResize(true)
        .objectFit(ImageFit.Contain)
    }
    .backgroundColor("#25ffffff")
    .borderRadius(10)
    .size(toSizeVp(mul(itemSize, 0.66666)))
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.pageInfo.pageThumbnail)
          .borderRadius(10)
          .draggable(false)
          .margin(0)
          .padding(ContainerPadding)
          .autoResize(true)
          .size(toSizeVp(itemSize))

        RelativeContainer() {
          Column() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(35)
              .fontWeight(FontWeight.Bolder)
              .fontColor([arrowColor])
          }
          .opacity(this.leftHoverVisible ? 1 : 0)
          .animation({ duration: 250, curve: Curve.EaseOut })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('50%')
          .height('100%')
          .backgroundColor(hoverColor)
          .alignRules(TopLeft)

          Column() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(35)
              .fontWeight(FontWeight.Bolder)
              .fontColor([arrowColor])
          }
          .opacity(this.rightHoverVisible ? 1 : 0)
          .animation({ duration: 250, curve: Curve.EaseOut })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('50%')
          .height('100%')
          .backgroundColor(hoverColor)
          .alignRules(TopRight)
        }
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
      }
      .clip(true)
      .borderRadius(10)
    }
    .scale(this.getScale())
    .opacity(this.isDraggingSource ? 0.5 : 1)
    .animation({ duration: 250, curve: Curve.EaseOut })
    .backgroundColor("#25ffffff")
    .borderRadius(10)
    .onClick(() => this.clicked())
    .onDragStart(event => {
      this.isDraggingSource = true;
      const data = new unifiedDataChannel.UnifiedData(
        new unifiedDataChannel.UnifiedRecord(
          uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
          this.pageInfo.globalPageIndex!
        )
      );
      event.setData(data);
      return this.DragPreview();
    })
    .onDragEnd(() => this.isDraggingSource = false)
    .onDragMove(event => {
      if (this.isDraggingSource) {
        return;
      }
      const globalX = event.getWindowX();
      this.leftHoverVisible = globalX < this.midX;
      this.rightHoverVisible = globalX > this.midX;
    })
    .onDrop(event => {
      this.leftHoverVisible = false;
      this.rightHoverVisible = false;

      const globalX = event.getWindowX();
      let draggedItemIndex = 0;
      try {
        draggedItemIndex = event.getData().getRecords()[0].getValue() as number;
      } catch (error) {
        event.setResult(DragResult.DRAG_FAILED);
        return;
      }

      const currentIndex = this.pageInfo.globalPageIndex!;

      if (draggedItemIndex === currentIndex) {
        event.setResult(DragResult.DRAG_CANCELED);
        return;
      }

      const targetIndex = globalX < this.midX ? currentIndex : currentIndex + 1;

      if (draggedItemIndex === targetIndex) {
        event.setResult(DragResult.DRAG_CANCELED);
        return;
      }

      event.setResult(DragResult.DRAG_SUCCESSFUL);
      this.dataSource.movePage(draggedItemIndex, targetIndex);
    })
    .onDragLeave(event => {
      this.leftHoverVisible = false;
      this.rightHoverVisible = false;
    })
    .onAreaChange((_, area: Area) => this.midX = area.globalPosition.x as number + (area.width as number / 2))
  }
}

@CustomDialog
struct PageRenameDialogBuilder {
  controller: CustomDialogController;
  @Require pageGroupAccessor: () => PageGroup;
  @Require pageGroups: PageInfoDataSource;
  @State newName: string | undefined = undefined;

  build() {
    Column(ContainerWideCfg) {
      TextInput({
        text: this.newName != undefined ? this.newName : this.pageGroupAccessor().groupName
      })
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(50)
        .borderRadius(8)
        .backgroundColor('rgba(255, 255, 255, 0.1)')
        .onChange(newText => {
          this.newName = newText;
        })
      StyleButton({
        text: '重命名',
        style: '100%',
        onClickCallback: () => {
          const pageGroup = this.pageGroupAccessor();
          if (this.newName != undefined && pageGroup.groupName !== this.newName) {
            this.pageGroups.renameGroup(pageGroup, this.newName);
          }
          this.controller.close();
        }
      })
    }
    .padding(ContainerWidePadding)
  }
}

@CustomDialog
export struct PageManagerDialogBuilder {
  @Require pageGroups: PageInfoDataSource;
  @Require onPageSelected: (pageInfo: ReadonlyPageInfo) => void;
  private currentlyRenamingPageGroup: PageGroup | null = null;
  private renameController: CustomDialogController = new CustomDialogController({
    builder: PageRenameDialogBuilder({
      pageGroupAccessor: () => this.currentlyRenamingPageGroup!,
      pageGroups: this.pageGroups,
    }),
    autoCancel: false,
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    keyboardAvoidDistance: LengthMetrics.vp(0)
  });

  @Builder
  GroupHeader(pageGroup: PageGroup, source: PageInfoDataSource) {
    RelativeContainer() {
      Button() {
        Text() {
          SymbolSpan($r('sys.symbol.dot_grid_2x2'))
          Span(pageGroup.groupName)
        }
        .fontWeight(FontWeight.Bold)
        .fontSize(15)
        .fontColor(Color.White)
      }
      .padding(ContainerWidePadding)
      .type(ButtonType.Normal)
      .borderRadius(5)
      .margin({ bottom: ContainerSpacing })
      .alignSelf(ItemAlign.Start)
      .width('100%')
      .align(Alignment.Start)
      .backgroundColor(ButtonColor)
      .bindMenu([
        {
          value: '重命名组',
          action: () => {
            this.currentlyRenamingPageGroup = pageGroup;
            this.renameController.open();
          }
        },
        {
          value: '删除组',
          action: () => {
            source.deleteGroup(pageGroup);
          }
        }
      ])
    }.width('100%').height('auto')
  }

  build() {
    Column() {
      List(ContainerWideCfg) {
        LazyForEach(this.pageGroups, (pageGroup: PageGroup) => {
          ListItemGroup({
            header: this.GroupHeader(pageGroup, this.pageGroups),
            space: ContainerWideSpacing
          }) {
            LazyForEach(pageGroup, (pageInfo: PageInfo) => {
              PageIcon({
                pageInfo: pageInfo,
                dataSource: this.pageGroups,
                clicked: () => {
                  this.onPageSelected(pageInfo);
                }
              }).size(toSizeVp(itemSize))
            }, (pageInfo: PageInfo) => pageInfo.pageGuid)
          }
          .backgroundColor(hslToColor(pageGroup.groupHue, 100, 70, 0.08))
          .borderColor(hslToColor(pageGroup.groupHue, 100, 70, 0.2))
          .borderWidth(2)
          .borderRadius(10)
          .margin(ContainerPadding)
          .padding(ContainerWidePadding)
        }, (pageGroup: PageGroup) => pageGroup.groupGuid)
      }
      .cachedCount(1)
      .lanes({ minLength: itemSize.x, maxLength: itemSize.x }, ContainerSpacing)
      .listDirection(Axis.Vertical)
      .alignListItem(ListItemAlign.Center)
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .alignRules(FullRect)

      Button('添加组')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .backgroundColor(ButtonColor)
        .bindMenu([
          {
            value: '空组',
            action: () => this.pageGroups.push(new PageGroup("空组", []))
          },
          {
            value: '导入文件',
            action: () => {
            }
          }
        ])
    }
    .padding(ContainerWidePadding)
  }
}