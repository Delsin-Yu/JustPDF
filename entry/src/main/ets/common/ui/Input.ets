import { KeyCode } from "@kit.InputKit";

export class InputAction {
  keyCodes: KeyCode[];
  ctrl: boolean;
  shift: boolean;
  action: () => void;

  constructor(keyCodes: KeyCode[], ctrl: boolean, shift: boolean, action: () => void) {
    this.keyCodes = keyCodes;
    this.ctrl = ctrl;
    this.shift = shift;
    this.action = action;
  }
}