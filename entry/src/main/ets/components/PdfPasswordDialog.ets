import { ContainerWideCfg, ContainerWidePadding } from './UIComponents';
import {
  ModalButtonPrimaryColor,
  ModalButtonSecondaryColor,
  ModalCardBackgroundColor,
  ModalCardBorderColor,
  ModalCardShadow,
  ModalErrorTextColor,
  ModalInputBackgroundColor,
  ModalInputCaretColor,
  ModalInputPlaceholderColor,
  ModalMutedTextColor,
  ModalTitleTextColor
} from '../pages/pdfview/PDFPanelVisualConstants';

export interface PdfPasswordDialogOptions {
  fileName: string;
  errorHint?: string;
}

@CustomDialog
struct PdfPasswordDialogBuilder {
  private controller: CustomDialogController;
  fileName: string = '';
  errorHint: string = '';
  onCancel: () => void = () => {
  };
  onConfirm: (password: string) => void = () => {
  };
  @State private passwordValue: string = '';

  private submitPassword(): void {
    this.controller.close();
    this.onConfirm(this.passwordValue);
  }

  private cancelDialog(): void {
    this.controller.close();
    this.onCancel();
  }

  build() {
    Column(ContainerWideCfg) {
      Text('输入 PDF 密码')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .height(52)
        .width('100%')
        .fontColor(ModalTitleTextColor)
        .textAlign(TextAlign.Center)

      Text(this.fileName)
        .fontSize(14)
        .fontColor(ModalMutedTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      if (this.errorHint.length > 0) {
        Text(this.errorHint)
          .fontSize(13)
          .fontColor(ModalErrorTextColor)
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      TextInput({ text: this.passwordValue, placeholder: '密码' })
        .type(InputType.Password)
        .enterKeyType(EnterKeyType.Done)
        .defaultFocus(true)
        .showPasswordIcon(true)
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontColor(ModalTitleTextColor)
        .placeholderColor(ModalInputPlaceholderColor)
        .backgroundColor(ModalInputBackgroundColor)
        .caretColor(ModalInputCaretColor)
        .borderRadius(14)
        .padding({ left: 14, right: 14 })
        .onChange((value: string) => {
          this.passwordValue = value;
        })
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent) => {
          this.submitPassword();
        })

      Row({ space: 12 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(ModalTitleTextColor)
          .backgroundColor(ModalButtonSecondaryColor)
          .onClick(() => this.cancelDialog())

        Button('确定')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(ModalTitleTextColor)
          .backgroundColor(ModalButtonPrimaryColor)
          .onClick(() => this.submitPassword())
      }
      .width('100%')
    }
    .width('100%')
    .padding(ContainerWidePadding)
    .backgroundColor(ModalCardBackgroundColor)
    .borderRadius(18)
    .border({ width: 1, color: ModalCardBorderColor })
    .shadow(ModalCardShadow)
  }
}

/**
 * 弹出密码框；取消返回 null，确认返回用户输入（可为空字符串）。
 * 须在页面完成首次布局后调用（勿在 aboutToAppear 同步路径中 open）。
 */
export function showPdfPasswordDialog(
  _uiContext: UIContext,
  options: PdfPasswordDialogOptions
): Promise<string | null> {
  return new Promise<string | null>((resolve) => {
    let controller: CustomDialogController | undefined = undefined;
    controller = new CustomDialogController({
      builder: PdfPasswordDialogBuilder({
        fileName: options.fileName,
        errorHint: options.errorHint ?? '',
        onCancel: () => resolve(null),
        onConfirm: (password: string) => resolve(password)
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      width: '85%',
      customStyle: true,
      maskColor: 'rgba(0, 0, 0, 0.38)'
    });
    setTimeout(() => {
      controller?.open();
    }, 0);
  });
}
