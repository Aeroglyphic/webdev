// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/service.dart';
// ignore: implementation_imports
import 'package:dwds/src/chrome_proxy_service.dart' show ChromeProxyService;
import 'package:pedantic/pedantic.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

// A client of the vm service that registers some custom extensions like
// hotRestart.
class WebdevVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object>> _responseController;

  WebdevVmClient(
      this.client, this._requestController, this._responseController);

  Future<void> close() async {
    await _requestController.close();
    await _responseController.close();
    client.dispose();
  }

  static Future<WebdevVmClient> create(DebugService debugService) async {
    // Set up hot restart as an extension.
    var requestController = StreamController<Map<String, Object>>();
    var responseController = StreamController<Map<String, Object>>();
    VmServerConnection(requestController.stream, responseController.sink,
        debugService.serviceExtensionRegistry, debugService.chromeProxyService);
    var client = VmService(
        responseController.stream.map(jsonEncode),
        (request) => requestController.sink
            .add(jsonDecode(request) as Map<String, dynamic>));
    var chromeProxyService =
        debugService.chromeProxyService as ChromeProxyService;
    client.registerServiceCallback('hotRestart', (request) async {
      chromeProxyService.destroyIsolate();
      var response = await chromeProxyService.tabConnection.runtime.sendCommand(
          'Runtime.evaluate',
          params: {'expression': r'$dartHotRestart();', 'awaitPromise': true});
      var exceptionDetails = response.result['exceptionDetails'];
      if (exceptionDetails != null) {
        return {
          'error': {
            'code': -32603,
            'message': exceptionDetails['exception']['description'],
            'data': exceptionDetails,
          }
        };
      } else {
        unawaited(chromeProxyService.createIsolate());
        return {'result': Success().toJson()};
      }
    });
    await client.registerService('hotRestart', 'WebDev');

    return WebdevVmClient(client, requestController, responseController);
  }
}
