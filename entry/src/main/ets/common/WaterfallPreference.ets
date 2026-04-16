// Module-level holder for the waterfall preference setter. AppStorage cannot
// hold function values, so the EntryAbility registers its setter here and the
// Settings dialog reads it from here.

export class WaterfallPreference {
  static setter: ((enable: boolean) => void) | undefined = undefined;
}
