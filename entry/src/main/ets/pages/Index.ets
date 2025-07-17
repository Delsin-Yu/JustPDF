import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

const TAG = 'JustPDFIndex';

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';

  aboutToAppear(): void {
    let context = this.getUIContext();
    let routerParams = context.getRouter().getParams() as Record<string, string>;
    let localStorage = context.getSharedLocalStorage();
    if(routerParams != null && routerParams['routerParams'] != '')
    {
      if(localStorage == null) localStorage = new LocalStorage();
      localStorage.setOrCreate('launchUri', routerParams['routerParams']);
    }
    let launchUriLink = localStorage?.link<string>('launchUri');
    if(launchUriLink == null) return;
    let launchUri = launchUriLink.get();
    launchUriLink.set('');
    this.loadAndViewFile(launchUri);
  }

  async loadAndViewFile(uri: string) {
    let dir = getContext().filesDir;
    let file = dir + "/temp.pdf";
    hilog.info(0x0000, TAG, "[rawfile_copy_to_sandbox] Path:" + file);
    let sourceFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    await fs.copyFile(sourceFile.fd, file);
    hilog.info(0x0000, TAG, "copyFile succeed");
    router.pushUrl({ url: 'pages/PDFView', params: { src: file } });
  }

  build() {
    Row() {
      Column({space: '30lpx'}) {
        Text("Just PDF")
          .fontSize('70lpx')
          .fontWeight(FontWeight.Bold)
        Button("Select File")
          .fontSize('30lpx')
          .fontWeight(FontWeight.Bold)
          .width('250lpx')
          .height('50lpx')
          .onClick(async () => {
            try {
              const documentSelectOptions = new picker.DocumentSelectOptions();
              documentSelectOptions.maxSelectNumber = 1;
              documentSelectOptions.fileSuffixFilters = ['.pdf'];
              const documentViewPicker = new picker.DocumentViewPicker();
              let uris = await documentViewPicker.select(documentSelectOptions);
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
