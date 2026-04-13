import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pickFilePathAsync } from '../components/GUIO';

const TAG = 'JustPDFIndex';

@Entry
@Component
struct Index {
  @State isLoading: boolean = false;
  @State loadingFileName: string = '';

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
    let sourceFile = await fs.open(uri, fs.OpenMode.READ_ONLY);
    let fileName = sourceFile.name;
    this.loadingFileName = fileName;
    this.isLoading = true;
    let file = dir + "/" + fileName;
    let tempFile = dir + "/saveTemp_" + fileName;
    hilog.info(0x0000, TAG, "[rawfile_copy_to_sandbox] Path:" + file);
    try {
      await fs.copyFile(sourceFile.fd, file);
    } finally {
      await fs.close(sourceFile);
    }
    hilog.info(0x0000, TAG, "copyFile succeed");

    let args: Record<string, string> = {
      'systemPath': uri,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    }
    uiContext.getRouter().replaceUrl({ url: 'pages/PDFView', params: args });
  }


  build() {
    Row() {
      Column({ space: '30lpx' }) {
        Text("Just PDF")
          .fontSize('70lpx')
          .fontWeight(FontWeight.Bold)
        if (this.isLoading) {
          LoadingProgress()
            .width('60lpx')
            .height('60lpx')
          Text(`正在加载 ${this.loadingFileName}`)
            .fontSize('24lpx')
            .fontColor(Color.Gray)
        } else {
          Button("选择文件")
            .type(ButtonType.Capsule)
            .fontSize('30lpx')
            .fontWeight(FontWeight.Bold)
            .width('200lpx')
            .height('50lpx')
            .onClick(async () => {
              try {
                let uri = await pickFilePathAsync(['.pdf']);
                if (uri) {
                  await this.loadAndViewFile(uri);
                }
              } catch (err) {
                let businessErr = err as BusinessError;
                hilog.info(0x0000, TAG, `ERR: ${err.code}, message is ${businessErr.message}`);
                this.isLoading = false;
              }
            })
        }
      }
      .width('100%')
    }
    .height('100%')
  }
}
