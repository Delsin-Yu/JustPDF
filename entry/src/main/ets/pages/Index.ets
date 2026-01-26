import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'JustPDFIndex';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    let context = this.getUIContext();
    let routerParams = context.getRouter().getParams() as Record<string, string>;
    if (routerParams != null && routerParams['routerParams'] != '') {
      AppStorage.setOrCreate('launchUri', routerParams['routerParams']);
    }
    let launchUriLink = AppStorage?.link<string>('launchUri');
    if (launchUriLink == null) {
      return;
    }
    let launchUri = launchUriLink.get();
    launchUriLink.set('');
    this.loadAndViewFile(launchUri);
  }

  async loadAndViewFile(uri: string) {
    let uiContext = this.getUIContext();
    let dir = uiContext.getHostContext()!.tempDir;
    let sourceFile = fs.openSync(uri, fs.OpenMode.READ_WRITE);
    let fileName = sourceFile.name;
    let file = dir + "/" + fileName;
    let tempFile = dir + "/saveTemp_" + fileName;
    hilog.info(0x0000, TAG, "[rawfile_copy_to_sandbox] Path:" + file);
    await fs.copyFile(sourceFile.fd, file);
    hilog.info(0x0000, TAG, "copyFile succeed");

    let args: Record<string, string> = {
      'systemPath': uri,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    }
    uiContext.getRouter().replaceUrl({ url: 'pages/PDFView', params: args });
  }

  private documentViewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();

  build() {
    Row() {
      Column({ space: '30lpx' }) {
        Text("Just PDF")
          .fontSize('70lpx')
          .fontWeight(FontWeight.Bold)
        Button("选择文件")
          .type(ButtonType.Capsule)
          .fontSize('30lpx')
          .fontWeight(FontWeight.Bold)
          .width('200lpx')
          .height('50lpx')
          .onClick(async () => {
            try {
              const documentSelectOptions = new picker.DocumentSelectOptions();
              documentSelectOptions.maxSelectNumber = 1;
              documentSelectOptions.fileSuffixFilters = ['.pdf'];
              let uris = await this.documentViewPicker.select(documentSelectOptions);
              let uri = uris[0];
              await this.loadAndViewFile(uri);
            } catch (err) {
              let businessErr = err as BusinessError;
              hilog.info(0x0000, TAG, `ERR: ${err.code}, message is ${businessErr.message}`);
            }
          })
      }
      .width('100%')
    }
    .height('100%')
  }
}
