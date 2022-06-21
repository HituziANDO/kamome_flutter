import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

/// The version code of the Kamome Flutter plugin.
const kamomeVersionCode = 50200;

enum HowToHandleNonExistentCommand {
  /// Anyway resolved passing null.
  resolved,

  /// Always rejected and passing an error message.
  rejected,

  /// Always raises an exception.
  exception
}

abstract class JavaScriptRunner {
  void runJavaScript(String js);
}

typedef ReadEventListener = void Function();

/// Receives a [result] that the native client receives it successfully from the JavaScript receiver when it processed a task of a [commandName]'s command.
/// An [error] when the native client receives it from the JavaScript receiver. If a task in JavaScript results in successful, the error will be null.
typedef SendMessageCallback = void Function(
    String commandName, Object? result, String? error);

class KamomeClient {
  /// The name of Kamome API in JavaScript.
  static const apiName = 'kamomeFlutter';
  static const _commandSYN = '_kamomeSYN';
  static const _commandACK = '_kamomeACK';

  /// How to handle non-existent command.
  HowToHandleNonExistentCommand howToHandleNonExistentCommand =
      HowToHandleNonExistentCommand.resolved;

  /// A ready event listener.
  /// The listener is called when the Kamome JavaScript library goes ready state.
  ReadEventListener? readEventListener;

  final JavaScriptRunner _jsRunner;
  final Map<String, Command> _commands = {};
  final List<_Request> _requests = [];
  final _WaitForReady _waitForReady = _WaitForReady();
  bool _ready = false;

  /// Tells whether the Kamome JavaScript library is ready.
  bool get isReady => _ready;

  KamomeClient(this._jsRunner) {
    // Add preset commands.
    add(Command(_commandSYN, (_, __, completion) {
      _ready = true;
      completion.resolve(data: {"versionCode": kamomeVersionCode});
    }));
    add(Command(_commandACK, (_, __, completion) {
      Future.delayed(const Duration(milliseconds: 1)).then((_) => {
            if (readEventListener != null) {readEventListener!()}
          });
      completion.resolve();
    }));
  }

  /// Adds a [command] called by the JavaScript code.
  void add(Command command) {
    _commands[command.name] = command;
  }

  /// Removes a command of specified [commandName].
  void remove(String commandName) {
    if (hasCommand(commandName)) {
      _commands.remove(commandName);
    }
  }

  /// Tells whether a command of specified [name] is added.
  /// Returns true if the command is added, otherwise false.
  bool hasCommand(String name) {
    return _commands.containsKey(name);
  }

  /// Sends a message to the JavaScript receiver with a [commandName].
  void send(String commandName,
      {Map<String, dynamic>? data, SendMessageCallback? callback}) {
    String? callbackId = _addSendMessageCallback(commandName, callback);
    _requests
        .add(_Request(name: commandName, callbackId: callbackId, data: data));
    _waitForReadyAndSendRequests();
  }

  /// Sends a message with a [data] as List to the JavaScript receiver with a [commandName].
  void sendWithListData(String commandName, List<dynamic>? data,
      {SendMessageCallback? callback}) {
    String? callbackId = _addSendMessageCallback(commandName, callback);
    _requests
        .add(_Request(name: commandName, callbackId: callbackId, data: data));
    _waitForReadyAndSendRequests();
  }

  /// Executes specified [commandName]'s command.
  void execute(String commandName,
      {Map<String, dynamic>? data, required LocalCompletionCallback callback}) {
    _handle(commandName, data, LocalCompletion(callback));
  }

  /// The receiver method that the JavaScript object passes a [message].
  /// For example, if you use webview_flutter plugin, see following code.
  ///
  /// ```
  /// JavascriptChannel(
  ///   name: KamomeClient.apiName,
  ///   onMessageReceived: (JavascriptMessage result) {
  ///     _kamomeClient.onMessageReceived(result.message);
  ///   },
  /// )
  /// ```
  void onMessageReceived(String message) {
    final Map<String, dynamic> object = json.decode(message);
    final requestId = object['id'] as String;
    final name = object['name'] as String;

    Map<String, dynamic>? data;
    if (object.containsKey('data') && object['data'] != null) {
      data = object['data'] as Map<String, dynamic>;
    }

    _handle(name, data, Completion(_jsRunner, requestId));
  }

  void _handle(
      String commandName, Map<String, dynamic>? data, Completable completion) {
    final command = _commands[commandName];

    if (command != null) {
      command.execute(data, completion);
    } else {
      switch (howToHandleNonExistentCommand) {
        case HowToHandleNonExistentCommand.rejected:
          completion.reject(errorMessage: 'CommandNotAdded');
          break;
        case HowToHandleNonExistentCommand.exception:
          throw CommandNotAddedException(commandName);
        default:
          completion.resolve();
      }
    }
  }

  String? _addSendMessageCallback(
      String commandName, SendMessageCallback? callback) {
    if (callback == null) {
      return null;
    }

    final callbackId = '_km_' + commandName + '_' + const Uuid().v4();

    // Add a temporary command receiving a result from the JavaScript handler.
    add(Command(callbackId, (commandName, data, completion) {
      if (data == null) return;

      final success = data['success'] as bool;

      if (success) {
        callback(commandName, data['result'], null);
      } else {
        String errorMessage = 'UnknownError';
        if (data.containsKey('error')) {
          errorMessage = data['error'] as String;
        }
        callback(commandName, null, errorMessage);
      }

      completion.resolve();

      // Remove the temporary command.
      remove(callbackId);
    }));

    return callbackId;
  }

  /// Waits for ready. If ready, sends requests to the JS library.
  void _waitForReadyAndSendRequests() {
    if (!isReady) {
      bool isWaiting = _waitForReady.wait(_waitForReadyAndSendRequests);

      if (!isWaiting) {
        // print("Waiting for ready has timed out.");
      }

      return;
    }

    for (var request in _requests) {
      _jsRunner.runJavaScript(_JavaScriptMethod.onReceive(request));
    }

    // Reset
    _requests.clear();
  }
}

typedef CommandHandler = void Function(
    String commandName, Map<String, dynamic>? data, Completable completion);

class Command {
  final String name;
  final CommandHandler? _handler;

  Command(this.name, this._handler);

  void execute(Map<String, dynamic>? data, Completable completion) {
    if (_handler != null) {
      _handler!(name, data, completion);
    }
  }
}

abstract class Completable {
  bool isCompleted();

  /// Sends resolved result with [data] to a JavaScript callback function.
  void resolve({Object? data});

  /// Sends rejected result with an [errorMessage] to a JavaScript callback function.
  void reject({String? errorMessage});
}

class Completion implements Completable {
  final JavaScriptRunner _jsRunner;
  final String _requestId;
  bool _completed = false;

  Completion(this._jsRunner, this._requestId);

  @override
  bool isCompleted() {
    return _completed;
  }

  @override
  void resolve({Object? data}) {
    if (isCompleted()) return;

    _completed = true;

    _jsRunner.runJavaScript(_JavaScriptMethod.onComplete(data, _requestId));
  }

  @override
  void reject({String? errorMessage}) {
    if (isCompleted()) return;

    _completed = true;

    _jsRunner
        .runJavaScript(_JavaScriptMethod.onError(errorMessage, _requestId));
  }
}

/// Calls when a command is processed using KamomeClient#execute(WithMap) method.
/// An [error] is not null if the process of the command is failed.
typedef LocalCompletionCallback = void Function(Object? result, String? error);

class LocalCompletion implements Completable {
  final LocalCompletionCallback _callback;
  bool _completed = false;

  LocalCompletion(this._callback);

  @override
  bool isCompleted() {
    return _completed;
  }

  @override
  void resolve({Object? data}) {
    if (isCompleted()) return;

    _completed = true;

    _callback(data, null);
  }

  @override
  void reject({String? errorMessage}) {
    if (isCompleted()) return;

    _completed = true;

    if (errorMessage != null && errorMessage.isNotEmpty) {
      _callback(null, errorMessage);
    } else {
      _callback(null, 'Rejected');
    }
  }
}

class CommandNotAddedException implements Exception {
  /// A command's name that is not added to a client.
  final String commandName;

  CommandNotAddedException(this.commandName);
}

class _Request {
  final String name;
  final String? callbackId;
  final Object? data;

  _Request({required this.name, required this.callbackId, required this.data});
}

class _JavaScriptMethod {
  static const _jsObj = "window.KM";

  static String onComplete(Object? data, String requestId) {
    if (data != null) {
      final jsonString = json.encode(data);
      return "$_jsObj.onComplete($jsonString, '$requestId')";
    } else {
      return "$_jsObj.onComplete(null, '$requestId')";
    }
  }

  static String onError(String? error, String requestId) {
    if (error != null) {
      // `Uri.encodeQueryComponent` converts spaces to '+' and
      // the `decodeURIComponent` function on JS decodes '%20' to spaces.
      String errMsg = Uri.encodeQueryComponent(error);
      errMsg = errMsg.replaceAll('+', '%20');
      return "$_jsObj.onError('$errMsg', '$requestId')";
    } else {
      return "$_jsObj.onError(null, '$requestId')";
    }
  }

  static String onReceive(_Request request) {
    if (request.data != null) {
      final jsonString = json.encode(request.data);
      if (request.callbackId != null) {
        return "$_jsObj.onReceive('${request.name}', $jsonString, '${request.callbackId}')";
      } else {
        return "$_jsObj.onReceive('${request.name}', $jsonString, null)";
      }
    } else {
      if (request.callbackId != null) {
        return "$_jsObj.onReceive('${request.name}', null, '${request.callbackId}')";
      } else {
        return "$_jsObj.onReceive('${request.name}', null, null)";
      }
    }
  }
}

class _WaitForReady {
  int _retryCount = 0;

  bool wait(Function() execute) {
    if (_retryCount >= 50) {
      return false;
    }
    _retryCount++;

    Future.delayed(const Duration(milliseconds: 200)).then((_) => execute());

    return true;
  }
}
