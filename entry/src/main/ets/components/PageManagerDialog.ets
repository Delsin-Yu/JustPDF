import { Vec2, vpToPx } from './Numbers';
import { PageGroup, PageInfo, PageInfoDataSource, ReadonlyPageInfo } from './PageInfo';
import { ContainerPadding, ContainerWideCfg, ContainerWidePadding, ContainerWideSpacing } from './UIComponents';


@Reusable
struct PageIcon {
  @Require pageInfo: PageInfo;
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

  build() {
    Button({ type: ButtonType.Normal }) {
      Image(this.pageInfo.pageThumbnail)
        .draggable(false)
        .borderRadius(10)
        .margin(0)
    }
    .backgroundColor("#25ffffff")
    .borderRadius(10)
    .padding(ContainerPadding)
    .onClick(() => this.clicked())
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
      .height(40)
  }

  build() {
    Row() {
      List(ContainerWideCfg) {
        LazyForEach(this.pageGroups, (pageGroup: PageGroup) => {
          ListItemGroup({
            header: this.GroupHeader(pageGroup.groupName),
            space: ContainerWideSpacing
          }) {
            LazyForEach(pageGroup, (pageInfo: PageInfo) => {
              PageIcon({
                pageInfo: pageInfo,
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
    }.padding(ContainerWidePadding)
  }
}