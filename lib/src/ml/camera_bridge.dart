export 'camera_bridge_stub.dart'
    if (dart.library.js_interop) 'camera_bridge_web.dart'
    if (dart.library.ffi) 'camera_bridge_native.dart';
