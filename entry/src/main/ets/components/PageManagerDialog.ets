import { PageInfo } from './PageInfo';
import { ContainerCfg, ContainerWidePadding } from './UIComponents';

@CustomDialog
export struct PageManagerDialogBuilder {
  private controller: CustomDialogController;

  build() {
    Row() {
      List(ContainerCfg) {
        // LazyForEach(this.pages, (page: PageInfo) => {
        // })
      }
    }.padding(ContainerWidePadding)
  }
}