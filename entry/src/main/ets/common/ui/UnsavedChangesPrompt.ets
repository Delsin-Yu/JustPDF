export enum UnsavedChangesChoice {
  Cancel = 0,
  Discard = 1,
  Save = 2
}

let unsavedPromptInFlight: boolean = false;

export function hasUnsavedDocumentChanges(hasUnsavedStrokes: boolean, bookmarksDirty: boolean): boolean {
  return hasUnsavedStrokes || bookmarksDirty;
}

/**
 * 当前文档有未保存批注或书签时，提示用户保存、不保存或取消。
 */
export function promptUnsavedChangesAction(uiContext: UIContext): Promise<UnsavedChangesChoice> {
  if (unsavedPromptInFlight) {
    return Promise.resolve(UnsavedChangesChoice.Cancel);
  }
  unsavedPromptInFlight = true;
  return new Promise<UnsavedChangesChoice>((resolve) => {
    let settled = false;
    const finish = (choice: UnsavedChangesChoice): void => {
      if (settled) {
        return;
      }
      settled = true;
      unsavedPromptInFlight = false;
      resolve(choice);
    };

    uiContext.showAlertDialog({
      title: '未保存的更改',
      message: '当前文档有未保存的批注或书签更改。是否保存后再继续？',
      autoCancel: false,
      buttonDirection: DialogButtonDirection.AUTO,
      buttons: [
        {
          value: '保存',
          action: () => finish(UnsavedChangesChoice.Save)
        },
        {
          value: '不保存',
          action: () => finish(UnsavedChangesChoice.Discard)
        },
        {
          value: '取消',
          action: () => finish(UnsavedChangesChoice.Cancel)
        }
      ],
      cancel: () => finish(UnsavedChangesChoice.Cancel)
    });
  });
}
