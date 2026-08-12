import { ContainerPadding, toVisibility } from '../../common/ui/UIComponents';
import {
  SharedPanelBackgroundColor,
  SharedPanelControlHighlightColor,
  UnsavedChangesIndicatorColor
} from '../viewer/PDFPanelVisualConstants';
import { PDFBookmarkListItem } from './PDFBookmarkController';

const BookmarkWindowMargin: number = 16;
const BookmarkWindowWidth: number = 300;
export const BookmarkTotalWidth: number = BookmarkWindowWidth + BookmarkWindowMargin * 2;
export const FloatingBookmarkDefaultScale: number = 1;
const FloatingBookmarkMinScale: number = 0.7;
const FloatingBookmarkMaxScale: number = 1.3;
const FloatingBookmarkDragDistanceVp: number = 1;
const BookmarkHeaderGap: number = 10;
const BookmarkHeaderCloseButtonWidth: number = 44;
const BookmarkHeaderDragMaxWidth: Length = `calc(100% - ${BookmarkHeaderCloseButtonWidth + BookmarkHeaderGap}vp)`;
const BtnSize: number = 40;
const Gap: number = 8;
const Pad: number = 12;
const ListAreaHeight: number = 260;
const BookmarkTitleDialogWidth: number = 280;

export const BookmarkPanelContentWidth: number = BookmarkWindowWidth;
export const BookmarkPanelContentHeight: number = ListAreaHeight + BtnSize + Gap + Pad * 2 + 50;

interface FloatingBookmarkOffset {
  x: number;
  y: number;
}

function clampFloatingBookmarkScale(scale: number): number {
  return Math.max(FloatingBookmarkMinScale, Math.min(FloatingBookmarkMaxScale, scale));
}

export function getFloatingBookmarkTotalWidth(scale: number): number {
  return BookmarkTotalWidth * clampFloatingBookmarkScale(scale);
}

@CustomDialog
export struct BookmarkTitleDialogBuilder {
  private controller: CustomDialogController;
  initialTitle: string = '';
  onCancel: () => void = () => {};
  onConfirm: (title: string) => void = () => {};
  @State private titleInput: string = '';

  aboutToAppear(): void {
    this.titleInput = this.initialTitle;
  }

  private submitTitle(): void {
    const trimmed = this.titleInput.trim();
    if (trimmed.length === 0) {
      return;
    }
    this.controller.close();
    this.onConfirm(trimmed);
  }

  build() {
    Column({ space: 14 }) {
      Text('重命名书签')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({ text: this.titleInput, placeholder: '书签标题' })
        .defaultFocus(true)
        .fontSize(17)
        .fontColor(Color.White)
        .placeholderColor('rgba(255, 255, 255, 0.38)')
        .backgroundColor('rgba(255, 255, 255, 0.08)')
        .borderRadius(14)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .caretColor('#4DA6FF')
        .width('100%')
        .onChange((value: string) => {
          this.titleInput = value;
        })
        .onSubmit(() => this.submitTitle())

      Row({ space: 8 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(38)
          .fontColor(Color.White)
          .backgroundColor('rgba(255, 255, 255, 0.12)')
          .onClick(() => {
            this.controller.close();
            this.onCancel();
          })

        Button('确定')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor('rgba(77, 166, 255, 0.88)')
          .onClick(() => this.submitTitle())
      }
      .width('100%')
    }
    .width(BookmarkTitleDialogWidth)
    .padding(16)
    .backgroundColor('rgba(12, 15, 21, 0.96)')
    .borderRadius(18)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.08)' })
    .shadow({ radius: 18, color: 'rgba(0, 0, 0, 0.28)', offsetY: 6 })
  }
}

@ComponentV2
export struct PDFBookmarkPanelContent {
  @Param entries: PDFBookmarkListItem[] = [];
  @Param selectedId: string = '';
  @Param hasUnsavedBookmarks: boolean = false;
  @Param readOnly: boolean = false;
  @Param useDocked: boolean = false;
  @Param dockedTopOffsetVp: number = 0;
  @Param hostScale: number = FloatingBookmarkDefaultScale;
  @Param hostOffset: FloatingBookmarkOffset = { x: 0, y: 0 };
  @Param showDragHandle: boolean = true;
  @Param onSelect: (id: string) => void = () => {};
  @Param onNavigate: (pageIndex: number) => void = () => {};
  @Param onAddAtCurrentPage: () => void = () => {};
  @Param onDeleteSelected: () => void = () => {};
  @Param onRenameSelected: () => void = () => {};
  @Param onSave: () => void = () => {};
  @Param onClose: () => void = () => {};
  @Param onTouchStateChanged: (active: boolean) => void = () => {};
  @Param onWindowAreaHeightChanged: (heightVp: number) => void = () => {};
  @Param onHostDragStart: () => void = () => {};
  @Param onHostDragUpdate: (event: GestureEvent) => void = () => {};
  @Param onHostDragEnd: () => void = () => {};
  @Param onHostPinchStart: () => void = () => {};
  @Param onHostPinchUpdate: (event: GestureEvent) => void = () => {};
  @Param onHostPinchEnd: () => void = () => {};

  build() {
    Column({ space: Gap }) {
      Row({ space: BookmarkHeaderGap }) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 3 }) {
              ForEach([0, 1, 2, 3], (index: number) => {
                Text('')
                  .width(4)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('rgba(255, 255, 255, 0.26)')
              }, (index: number) => `bookmark-drag-grip-top-${index}`)
            }
            Row({ space: 3 }) {
              ForEach([0, 1, 2, 3], (index: number) => {
                Text('')
                  .width(4)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor('rgba(255, 255, 255, 0.16)')
              }, (index: number) => `bookmark-drag-grip-bottom-${index}`)
            }
          }
          .visibility(toVisibility(this.showDragHandle && !this.useDocked))

          Text('书签')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .height('auto')
        .layoutWeight(1)
        .constraintSize({ maxWidth: BookmarkHeaderDragMaxWidth })
        .padding(ContainerPadding)
        .alignItems(VerticalAlign.Center)
        .borderRadius(10)
        .backgroundColor('rgba(255, 255, 255, 0.05)')
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.06)' })
        .gesture(
          PanGesture({ fingers: 1, distance: FloatingBookmarkDragDistanceVp })
            .onActionStart(() => {
              if (!this.useDocked) {
                this.onHostDragStart();
              }
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.useDocked) {
                this.onHostDragUpdate(event);
              }
            })
            .onActionEnd(() => {
              if (!this.useDocked) {
                this.onHostDragEnd();
              }
            })
            .onActionCancel(() => {
              if (!this.useDocked) {
                this.onHostDragEnd();
              }
            })
        )

        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White])
        }
        .width(BookmarkHeaderCloseButtonWidth)
        .height(BookmarkHeaderCloseButtonWidth)
        .borderRadius(10)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onClose())
      }
      .width('100%')

      if (this.entries.length === 0) {
        Text('暂无书签，可添加当前页书签')
          .fontSize(14)
          .fontColor('rgba(255, 255, 255, 0.45)')
          .width('100%')
          .height(ListAreaHeight)
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.entries, (item: PDFBookmarkListItem) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(`${item.pageIndex + 1}`)
                  .fontSize(13)
                  .fontColor('rgba(255, 255, 255, 0.5)')
                  .width(28)
                  .textAlign(TextAlign.End)
                Text(item.title)
                  .fontSize(15)
                  .fontColor(Color.White)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({
                left: 8 + item.depth * 14,
                right: 8,
                top: 10,
                bottom: 10
              })
              .backgroundColor(this.selectedId === item.id ? SharedPanelControlHighlightColor : Color.Transparent)
              .borderRadius(8)
            }
            .onClick(() => {
              this.onSelect(item.id);
              this.onNavigate(item.pageIndex);
            })
          }, (item: PDFBookmarkListItem) => item.id)
        }
        .width('100%')
        .height(ListAreaHeight)
        .scrollBar(BarState.Auto)
      }

      Row({ space: Gap }) {
        Button({ type: ButtonType.Normal }) {
          Text('添加')
            .fontSize(14)
            .fontColor(Color.White)
        }
        .layoutWeight(1)
        .height(BtnSize)
        .borderRadius(10)
        .backgroundColor('rgba(77, 166, 255, 0.35)')
        .enabled(!this.readOnly)
        .opacity(this.readOnly ? 0.4 : 1)
        .onClick(() => this.onAddAtCurrentPage())

        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(18).fontColor([Color.White])
        }
        .width(BtnSize).height(BtnSize).borderRadius(10)
        .backgroundColor(Color.Transparent)
        .enabled(!this.readOnly && this.selectedId.length > 0)
        .opacity(!this.readOnly && this.selectedId.length > 0 ? 1.0 : 0.35)
        .onClick(() => this.onRenameSelected())

        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([Color.White])
        }
        .width(BtnSize).height(BtnSize).borderRadius(10)
        .backgroundColor(Color.Transparent)
        .enabled(!this.readOnly && this.selectedId.length > 0)
        .opacity(!this.readOnly && this.selectedId.length > 0 ? 1.0 : 0.35)
        .onClick(() => this.onDeleteSelected())

        Stack({ alignContent: Alignment.TopEnd }) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.save')).fontSize(18).fontColor([Color.White])
          }
          .width(BtnSize).height(BtnSize).borderRadius(10)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.onSave())

          if (this.hasUnsavedBookmarks) {
            Text('')
              .width(10)
              .height(10)
              .borderRadius(5)
              .backgroundColor(UnsavedChangesIndicatorColor)
          }
        }
        .width(BtnSize)
        .height(BtnSize)
      }
      .width('100%')
    }
    .width(this.useDocked ? '100%' : BookmarkWindowWidth)
    .padding(Pad)
    .backgroundColor(SharedPanelBackgroundColor)
    .borderRadius({
      topLeft: this.useDocked ? 0 : 16,
      topRight: this.useDocked ? 0 : 16,
      bottomLeft: 16,
      bottomRight: 16
    })
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.07)' })
    .shadow({ radius: 12, color: 'rgba(0, 0, 0, 0.24)', offsetY: 4 })
    .margin(this.useDocked ? 0 : BookmarkWindowMargin)
    .align(Alignment.TopStart)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onTouchStateChanged(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onTouchStateChanged(false);
      }
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.onWindowAreaHeightChanged(newValue.height as number);
    })
    .scale(this.useDocked ? { x: 1, y: 1 } : { x: this.hostScale, y: this.hostScale, centerX: 0, centerY: 0 })
    .offset(this.useDocked ? { x: 0, y: this.dockedTopOffsetVp } : this.hostOffset)
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart(() => {
          if (!this.useDocked) {
            this.onHostPinchStart();
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (!this.useDocked) {
            this.onHostPinchUpdate(event);
          }
        })
        .onActionEnd(() => {
          if (!this.useDocked) {
            this.onHostPinchEnd();
          }
        })
        .onActionCancel(() => {
          if (!this.useDocked) {
            this.onHostPinchEnd();
          }
        })
    )
  }
}
