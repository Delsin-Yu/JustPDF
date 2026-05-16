// 无实时模糊：圆角面板使用纯色底，避免 backdrop 模糊在圆角处发灰/漏边。
export const SharedPanelBackgroundColor: string = 'rgba(23, 27, 36, 0.90)';
export const SharedPanelControlHighlightColor: string = 'rgba(255, 255, 255, 0.2)';
/** 书签/文档未保存提示圆点 */
export const UnsavedChangesIndicatorColor: string = 'rgba(255, 132, 0, 0.95)';

/** 与节拍器「设置速度」弹窗、浮层面板一致的模态卡片样式 */
export const ModalCardBackgroundColor: string = 'rgba(12, 15, 21, 0.96)';
export const ModalCardBorderColor: string = 'rgba(255, 255, 255, 0.08)';
export const ModalCardShadow: ShadowOptions = { radius: 18, color: 'rgba(0, 0, 0, 0.28)', offsetY: 6 };
export const ModalDimOverlayColor: string = 'rgba(0, 0, 0, 0.38)';
/** 与 PDFView 页面根背景一致 */
export const ViewerPageBackdropColor: ResourceColor = $r('sys.color.white');
export const ViewerPageLoadingIndicatorColor: string = '#666666';
export const ViewerPageLoadingTextColor: string = '#888888';
export const ModalTitleTextColor: ResourceColor = Color.White;
export const ModalBodyTextColor: string = 'rgba(255, 255, 255, 0.55)';
export const ModalMutedTextColor: string = '#888888';
export const ModalErrorTextColor: string = '#FF7A7A';
export const ModalInputBackgroundColor: string = 'rgba(255, 255, 255, 0.08)';
export const ModalInputPlaceholderColor: string = 'rgba(255, 255, 255, 0.38)';
export const ModalInputCaretColor: string = '#4DA6FF';
export const ModalButtonSecondaryColor: string = 'rgba(255, 255, 255, 0.12)';
export const ModalButtonPrimaryColor: string = 'rgba(77, 166, 255, 0.88)';
