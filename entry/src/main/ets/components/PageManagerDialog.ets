import { Vec2, vpToPx } from './Numbers';
import { PageGroup, PageInfo, PageInfoDataSource, ReadonlyPageInfo } from './PageInfo';
import { ContainerPadding, ContainerSpacing, ContainerWideCfg, ContainerWidePadding, ContainerWideSpacing, FullRect, TopLeft, TopRight, toVisibility } from './UIComponents';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';

const arrowColor = '#ffb1b1b1';
const hoverColor = '#ffffffff';

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
  @State midX: number = 0;
  @State isDraggingSource: boolean = false;

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
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('50%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Left,
            colors: [
              [Color.Transparent, 0],
              [hoverColor, 1]
            ],
            repeating: false
          })
          .alignRules(TopLeft)
          .visibility(toVisibility(this.leftHoverVisible))

          Column() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(35)
              .fontWeight(FontWeight.Bolder)
              .fontColor([arrowColor])
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('50%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [
              [Color.Transparent, 0],
              [hoverColor, 1]
            ],
            repeating: false
          })
          .alignRules(TopRight)
          .visibility(toVisibility(this.rightHoverVisible))
        }
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
      }
      .clip(true)
      .borderRadius(10)
    }
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
            })
          }
          .backgroundColor('#1486e8ff')
          .borderColor('#3486e8ff')
          .borderWidth(2)
          .borderRadius(10)
          .margin(ContainerPadding)
          .padding(ContainerWidePadding)
        })
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