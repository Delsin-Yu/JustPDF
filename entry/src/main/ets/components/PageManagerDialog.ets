import { Vec2, vpToPx } from './Numbers';
import { PageGroup, PageInfo, PageInfoDataSource, ReadonlyPageGroup, ReadonlyPageInfo } from './PageInfo';
import { ContainerCfg, ContainerPadding, ContainerSpacing, ContainerWideCfg, ContainerWidePadding, ContainerWideSpacing } from './UIComponents';


@Reusable
struct PageIcon {
  @Require pageInfo: PageInfo;

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

  build() {
    Column(ContainerCfg) {
      Image(this.pageInfo.pageThumbnail)
        .borderRadius(10)
        .draggable(false)
    }.padding(ContainerPadding)
  }
}


@CustomDialog
export struct PageManagerDialogBuilder {
  private controller: CustomDialogController;
  @State @Require pageGroups: PageInfoDataSource;

  @Builder
  GroupHeader(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .padding(ContainerPadding)
      .textAlign(TextAlign.Start)
      .width('100%')
  }

  build() {
    Row() {
      List(ContainerWideCfg) {
        LazyForEach(this.pageGroups, (pageGroup: PageGroup) => {
          ListItemGroup({ header: this.GroupHeader(pageGroup.groupName) }) {
            LazyForEach(pageGroup, (pageInfo: PageInfo) => {
              PageIcon({pageInfo: pageInfo})
            })
          }
          .padding(ContainerWidePadding)
          .backgroundColor('#1486e8ff')
          .borderColor('#3486e8ff')
          .borderWidth(2)
          .borderRadius(10)
        })
      }
      .lanes({ minLength: 100, maxLength: 100 }, ContainerWideSpacing)
      .listDirection(Axis.Vertical)
      .alignListItem(ListItemAlign.Center)
      .width('100%')
      .height('100%')
      .padding(ContainerWidePadding)
    }.padding(ContainerWidePadding)
  }
}