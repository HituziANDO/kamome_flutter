import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kamome_flutter/kamome_flutter.dart';
import 'package:webview_flutter_plus/webview_flutter_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case InAppWebViewPage.routeName:
            return MaterialPageRoute(
                builder: (context) => const InAppWebViewPage());
          case WebViewFlutterPlusPage.routeName:
            return MaterialPageRoute(
                builder: (context) => const WebViewFlutterPlusPage());
          default:
            return null;
        }
      },
      home: const InAppWebViewPage(),
    );
  }
}

class WebViewFlutterPlusPage extends StatefulWidget {
  static const routeName = 'webview_flutter_plus';

  const WebViewFlutterPlusPage({Key? key}) : super(key: key);

  @override
  WebViewFlutterPlusPageState createState() => WebViewFlutterPlusPageState();
}

class WebViewFlutterPlusPageState extends State<WebViewFlutterPlusPage> {
  late KamomeClient _client;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('webview_flutter_plus'),
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewPlus(
              javascriptMode: JavascriptMode.unrestricted,
              javascriptChannels: {
                JavascriptChannel(
                  name: KamomeClient.apiName,
                  onMessageReceived: (JavascriptMessage result) {
                    _client.onMessageReceived(result.message);
                  },
                )
              },
              onWebViewCreated: (WebViewPlusController controller) {
                _client = KamomeClient(
                    _JavaScriptRunner(controller.webViewController));
                _addCommands(_client);

                _client.howToHandleNonExistentCommand =
                    HowToHandleNonExistentCommand.rejected;

                controller.loadUrl('assets/index.html');
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Sends a data to the JS code.
          _client.send('greeting', data: {
            'greeting': 'Hello! by WebViewFlutter [\'"+-._~\\@#\$%^&*=,/?;:|{}]'
          }, callback: (commandName, result, error) {
            // Received a result from the JS code.
            print(result);
          });
        },
        tooltip: 'Send Data to JS',
        child: const Icon(Icons.send),
      ),
    );
  }
}

class _JavaScriptRunner implements JavaScriptRunner {
  final WebViewController _controller;

  _JavaScriptRunner(this._controller);

  @override
  void runJavaScript(String js) async {
    await _controller.runJavascript(js);
  }
}

class InAppWebViewPage extends StatefulWidget {
  static const routeName = 'flutter_inappwebview';

  const InAppWebViewPage({Key? key}) : super(key: key);

  @override
  InAppWebViewPageState createState() => InAppWebViewPageState();
}

class InAppWebViewPageState extends State<InAppWebViewPage> {
  late KamomeClient _client;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_inappwebview'),
        actions: [
          IconButton(
              onPressed: () {
                Navigator.of(context)
                    .pushNamed(WebViewFlutterPlusPage.routeName);
              },
              icon: const Icon(Icons.arrow_forward_ios)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InAppWebView(
              initialFile: 'assets/index.html',
              onWebViewCreated: (InAppWebViewController controller) {
                _client =
                    KamomeClient(_InAppWebViewJavaScriptRunner(controller));
                _addCommands(_client);

                _client.howToHandleNonExistentCommand =
                    HowToHandleNonExistentCommand.rejected;

                controller.addJavaScriptHandler(
                    handlerName: KamomeClient.apiName,
                    callback: (args) {
                      _client.onMessageReceived(args[0]);
                    });
              },
              onConsoleMessage: (InAppWebViewController controller,
                  ConsoleMessage consoleMessage) {
                print(consoleMessage);
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Sends a data to the JS code.
          _client.send('greeting', data: {
            'greeting': 'Hello! by InAppWebView [\'"+-._~\\@#\$%^&*=,/?;:|{}]'
          }, callback: (commandName, result, error) {
            // Received a result from the JS code.
            print(result);
          });
        },
        tooltip: 'Send Data to JS',
        child: const Icon(Icons.send),
      ),
    );
  }
}

class _InAppWebViewJavaScriptRunner implements JavaScriptRunner {
  final InAppWebViewController _controller;

  _InAppWebViewJavaScriptRunner(this._controller);

  @override
  void runJavaScript(String js) async {
    await _controller.evaluateJavascript(source: js);
  }
}

void _addCommands(KamomeClient client) {
  client
    ..add(Command('echo', (commandName, data, completion) {
      // Received `echo` command.
      // Then sends resolved result to the JavaScript callback function.
      completion.resolve(data: {
        'message': data!['message'],
      });
    }))
    ..add(Command('echoError', (_, __, completion) {
      // Sends rejected result if failed.
      completion.reject(
          errorMessage: 'Echo Error! [\'"+-._~\\@#\$%^&*=,/?;:|{}]');
    }))
    ..add(Command('tooLong', (_, __, completion) {
      // Too long process...
      Timer(const Duration(seconds: 30), () => completion.resolve());
    }));
}
