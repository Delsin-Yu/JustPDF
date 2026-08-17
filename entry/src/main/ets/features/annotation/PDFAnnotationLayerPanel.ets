import { AnnotationLayerListItem } from '../../common/page/AnnotationLayer';
import {
  ModalButtonPrimaryColor,
  ModalButtonSecondaryColor,
  ModalCardBackgroundColor,
  ModalInputBackgroundColor,
  ModalInputCaretColor,
  ModalInputPlaceholderColor,
  SharedPanelControlHighlightColor
} from '../viewer/PDFPanelVisualConstants';

const EmbedListHeight: number = 140;
const EmbedAddBtnHeight: number = 32;
const EmbedGap: number = 6;
const LayerRowHeight: number = 36;
const LayerTitleDialogWidth: number = 280;

export const AnnotationLayerEmbedHeight: number = EmbedListHeight + EmbedAddBtnHeight + EmbedGap;

function layerRowKey(item: AnnotationLayerListItem): string {
  const visibleFlag: string = item.visible ? '1' : '0';
  const activeFlag: string = item.isActive ? '1' : '0';
  return item.id + '_' + visibleFlag + '_' + activeFlag + '_' + item.name;
}

@CustomDialog
export struct LayerRenameDialogBuilder {
  private controller: CustomDialogController;
  initialTitle: string = '';
  onCancel: () => void = () => {};
  onConfirm: (title: string) => void = () => {};
  @State private titleInput: string = '';

  aboutToAppear(): void {
    this.titleInput = this.initialTitle;
  }

  private submitTitle(): void {
    const trimmed: string = this.titleInput.trim();
    if (trimmed.length === 0) {
      return;
    }
    this.controller.close();
    this.onConfirm(trimmed);
  }

  build() {
    Column({ space: 14 }) {
      Text('重命名图层')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({ text: this.titleInput, placeholder: '图层名称' })
        .defaultFocus(true)
        .fontSize(17)
        .fontColor(Color.White)
        .placeholderColor(ModalInputPlaceholderColor)
        .backgroundColor(ModalInputBackgroundColor)
        .borderRadius(14)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .caretColor(ModalInputCaretColor)
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
          .backgroundColor(ModalButtonSecondaryColor)
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
          .backgroundColor(ModalButtonPrimaryColor)
          .onClick(() => this.submitTitle())
      }
      .width('100%')
    }
    .width(LayerTitleDialogWidth)
    .padding(16)
    .backgroundColor(ModalCardBackgroundColor)
    .borderRadius(18)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.08)' })
    .shadow({ radius: 18, color: 'rgba(0, 0, 0, 0.28)', offsetY: 6 })
  }
}

@ComponentV2
export struct PDFAnnotationLayerPanel {
  @Param readOnly: boolean = false;
  @Param items: AnnotationLayerListItem[] = [];
  @Param onSelect: (id: string) => void = () => {};
  @Param onToggleVisible: (id: string, visible: boolean) => void = () => {};
  @Param onAdd: () => void = () => {};
  @Param onRename: (id: string, name: string) => void = () => {};
  @Param onDelete: (id: string) => void = () => {};

  private renameDialogController: CustomDialogController | undefined = undefined;

  private openRenameDialog(item: AnnotationLayerListItem): void {
    if (this.readOnly || item.isProtected) {
      return;
    }
    this.renameDialogController = new CustomDialogController({
      builder: LayerRenameDialogBuilder({
        initialTitle: item.name,
        onCancel: () => {},
        onConfirm: (title: string) => {
          this.onRename(item.id, title);
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.38)'
    });
    this.renameDialogController.open();
  }

  private confirmDelete(item: AnnotationLayerListItem): void {
    if (this.readOnly || item.isProtected) {
      return;
    }
    if (item.strokeCount === 0) {
      this.onDelete(item.id);
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除图层',
      message: '将同时删除该图层上的笔迹',
      autoCancel: true,
      buttons: [
        {
          value: '删除',
          action: () => {
            this.onDelete(item.id);
          }
        },
        {
          value: '取消',
          action: () => {}
        }
      ]
    });
  }

  @Builder
  private buildLayerRow(item: AnnotationLayerListItem) {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph(item.visible ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
          .fontSize(16)
          .fontColor([item.visible ? Color.White : 'rgba(255, 255, 255, 0.38)'])
      }
      .width(28)
      .height(28)
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .enabled(!this.readOnly)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        if (this.readOnly) {
          return;
        }
        this.onToggleVisible(item.id, !item.visible);
      })

      Row({ space: 6 }) {
        Text(item.name)
          .fontSize(14)
          .fontColor(item.visible ? Color.White : 'rgba(255, 255, 255, 0.45)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)

        if (item.isActive) {
          Text('当前')
            .fontSize(11)
            .fontColor('rgba(255, 255, 255, 0.78)')
            .flexShrink(0)
        }

        Blank()
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      if (!item.isProtected) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(14).fontColor([Color.White])
        }
        .width(26)
        .height(26)
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .enabled(!this.readOnly)
        .opacity(this.readOnly ? 0.35 : 1)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => this.openRenameDialog(item))

        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([Color.White])
        }
        .width(26)
        .height(26)
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .enabled(!this.readOnly)
        .opacity(this.readOnly ? 0.35 : 1)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => this.confirmDelete(item))
      }
    }
    .width('100%')
    .height(LayerRowHeight)
    .padding({ left: 2, right: 6 })
    .borderRadius(8)
    .backgroundColor(item.isActive ? SharedPanelControlHighlightColor : Color.Transparent)
    .onClick(() => this.onSelect(item.id))
  }

  build() {
    Column({ space: EmbedGap }) {
      if (this.items.length === 0) {
        Text('暂无图层')
          .fontSize(13)
          .fontColor('rgba(255, 255, 255, 0.45)')
          .width('100%')
          .height(EmbedListHeight)
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.items, (item: AnnotationLayerListItem) => {
            ListItem() {
              this.buildLayerRow(item)
            }
          }, (item: AnnotationLayerListItem) => layerRowKey(item))
        }
        .width('100%')
        .height(EmbedListHeight)
        .scrollBar(BarState.Auto)
      }

      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(14).fontColor([Color.White])
          Text('新建图层')
            .fontSize(13)
            .fontColor(Color.White)
        }
      }
      .width('100%')
      .height(EmbedAddBtnHeight)
      .borderRadius(8)
      .backgroundColor('rgba(77, 166, 255, 0.35)')
      .enabled(!this.readOnly)
      .opacity(this.readOnly ? 0.4 : 1)
      .onClick(() => {
        if (this.readOnly) {
          return;
        }
        this.onAdd();
      })
    }
    .width('100%')
  }
}
