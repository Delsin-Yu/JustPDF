import { Vec2, vpToPx } from './Numbers';
import { PageGroup, PageInfo, PageInfoDataSource, ReadonlyPageInfo } from './PageInfo';
import { ContainerPadding, ContainerSpacing, ContainerWideCfg, ContainerWidePadding, ContainerWideSpacing, FullRect, TopLeft, TopRight, toVisibility } from './UIComponents';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';

const arrowColor = '#ffffffff';
const hoverColor = '#a8000000';

@Reusable
struct PageIcon {
  @Require pageInfo: PageInfo;
  @Require dataSource: PageInfoDataSource;
  @Require clicked: () => void;

  aboutToAppear(): void {
    this.pageInfo.requestPageThumbnail(vpToPx(Vec2(400, 400), this.getUIContext()));
  }

  aboutToReuse(params: Record<string, Object | null | undefined>): void {
    this.pageInfo.requestPageThumbnail(vpToPx(Vec2(400, 400), this.getUIContext()));
  }

  aboutToRecycle(): void {
    this.pageInfo.evictThumbnail();
  }

  aboutToDisappear(): void {
    this.pageInfo.evictThumbnail();
  }

  @State leftHoverVisible: boolean = false;
  @State rightHoverVisible: boolean = false;
  private area: Area | undefined = undefined;
  private midX: number = 0;
  @State isDraggingSource: boolean = false;

  getScale(): ScaleOptions {
    if (!this.leftHoverVisible && !this.rightHoverVisible) {
      return { x: 1, y: 1 };
    }
    return { x: 1.05, y: 1.05 };
  }

  @Builder
  DragPreview(area: Area) {
    Button({ type: ButtonType.Normal }) {
      Image(this.pageInfo.pageThumbnail)
        .borderRadius(10)
        .draggable(false)
        .margin(0)
        .padding(ContainerPadding)
    }
    .backgroundColor("#25ffffff")
    .borderRadius(10)
    .size({width: area.width as number * 0.6666, height: area.height as number * 0.6666})
  }


  build() {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.pageInfo.pageThumbnail)
          .borderRadius(10)
          .draggable(false)
          .margin(0)
          .padding(ContainerPadding)

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
      return this.DragPreview(this.area!);
    })
    .onDragEnd(() => this.isDraggingSource = false)
    .onDragMove(event => {
      if (this.isDraggingSource) return;
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
    .onAreaChange((_, area: Area) => {
      this.area = area;
      this.midX = area.globalPosition.x as number + (area.width as number / 2);
    })
  }
}


@CustomDialog
export struct PageManagerDialogBuilder {
  private controller: CustomDialogController;
  @State @Require pageGroups: PageInfoDataSource;
  @Require onPageSelected: (pageInfo: ReadonlyPageInfo) => void;

  @Builder
  GroupHeader(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .padding(ContainerPadding)
      .textAlign(TextAlign.Start)
      .width('100%')
      .margin({ bottom: ContainerSpacing })
  }

  build() {
    RelativeContainer() {
      List(ContainerWideCfg) {
        LazyForEach(this.pageGroups, (pageGroup: PageGroup) => {
          ListItemGroup({
            header: this.GroupHeader(pageGroup.groupName),
            space: ContainerWideSpacing
          }) {
            LazyForEach(pageGroup, (pageInfo: PageInfo) => {
              PageIcon({
                pageInfo: pageInfo,
                dataSource: this.pageGroups,
                clicked: () => {
                  this.onPageSelected(pageInfo);
                }
              })
            }, (pageInfo: PageInfo) => pageInfo.pageId)
          }
          .backgroundColor('#1486e8ff')
          .borderColor('#3486e8ff')
          .borderWidth(2)
          .borderRadius(10)
          .margin(ContainerPadding)
          .padding(ContainerWidePadding)
        }, (pageGroup: PageGroup) => pageGroup.groupId)
      }
      .lanes({ minLength: 100, maxLength: 100 }, ContainerWideSpacing)
      .listDirection(Axis.Vertical)
      .alignListItem(ListItemAlign.Center)
      .width('100%')
      .height('100%')
      .padding(ContainerWidePadding)
      .alignRules(FullRect)

    }
    .padding(ContainerWidePadding)
  }
}