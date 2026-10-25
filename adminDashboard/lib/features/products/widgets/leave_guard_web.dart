import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSFunction? _handler;

/// Asks the browser to confirm closing / reloading the tab while [enabled]
/// (`beforeunload`), so unsaved product edits aren't lost.
void setBrowserLeaveWarning(bool enabled) {
  final window = globalContext;
  if (enabled && _handler == null) {
    _handler = ((JSObject event) {
      event.callMethod('preventDefault'.toJS);
      event['returnValue'] = ''.toJS;
    }).toJS;
    window.callMethod('addEventListener'.toJS, 'beforeunload'.toJS, _handler);
  } else if (!enabled && _handler != null) {
    window.callMethod('removeEventListener'.toJS, 'beforeunload'.toJS, _handler);
    _handler = null;
  }
}
