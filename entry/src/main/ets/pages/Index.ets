import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pickFilePathAsync } from '../components/GUIO';
import { showAlertDialog } from '../components/UIComponents';

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
    let sourceFile: fs.File;
    try {
      sourceFile = await fs.open(uri, fs.OpenMode.READ_ONLY);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error opening file: ${error}`);
      await showAlertDialog('文件打开失败', `无法打开选定的PDF文件，请检查文件是否存在或已损坏。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
      return;
    }
    let fileName = sourceFile.name;
    this.loadingFileName = fileName;
    this.isLoading = true;
    let file = dir + "/" + fileName;
    let tempFile = dir + "/saveTemp_" + fileName;
    hilog.info(0x0000, TAG, "[rawfile_copy_to_sandbox] Path:" + file);
    try {
      await fs.copyFile(sourceFile.fd, file);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error copying file: ${error}`);
      await showAlertDialog('文件复制失败', `无法将PDF文件复制到临时目录。请检查存储空间是否充足。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
      return;
    } finally {
      try {
        await fs.close(sourceFile);
      } catch (error) {
        hilog.error(0x0000, TAG, `Error closing file: ${error}`);
      }
    }
    hilog.info(0x0000, TAG, "copyFile succeed");

    let args: Record<string, string> = {
      'systemPath': uri,
      'sandboxPath': file,
      'saveTempPath': tempFile,
      'fileName': fileName
    }
    try {
      uiContext.getRouter().replaceUrl({ url: 'pages/PDFView', params: args });
    } catch (error) {
      hilog.error(0x0000, TAG, `Error navigating to PDFView: ${error}`);
      await showAlertDialog('页面跳转失败', `无法打开PDF预览页面，请重试。\n错误信息: ${error}`, uiContext);
      this.isLoading = false;
    }
  }


  build() {
    Row() {
      Column({ space: '50px' }) {
        Text("Just PDF")
          .fontSize('180px')
          .fontWeight(FontWeight.Bold)
        if (this.isLoading) {
          LoadingProgress()
            .width(60)
            .height(60)
          Text(`正在加载 ${this.loadingFileName}`)
            .fontSize(24)
            .fontColor(Color.Gray)
        } else {
          Button("选择文件")
            .type(ButtonType.Capsule)
            .fontSize('100px')
            .fontWeight(FontWeight.Bold)
            .width('650px')
            .height('200px')
            .onClick(async () => {
              try {
                let uri = await pickFilePathAsync(['.pdf']);
                if (uri) {
                  await this.loadAndViewFile(uri);
                }
              } catch (err) {
                let businessErr = err as BusinessError;
                hilog.error(0x0000, TAG, `ERR: ${err.code}, message is ${businessErr.message}`);
                let uiContext = this.getUIContext();
                await showAlertDialog('文件选择失败', `无法选择文件：${businessErr.message}`, uiContext);
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
