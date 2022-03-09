import 'dart:convert';

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

/// Receives a [result] that the native client receives it successfully from the JavaScript receiver when it processed a task of a [commandName]'s command.
/// An [error] when the native client receives it from the JavaScript receiver. If a task in JavaScript results in successful, the error will be null.
typedef SendMessageCallback = void Function(
    String commandName, Object? result, String? error);

class KamomeClient {
  /// The name of Kamome API in JavaScript.
  static const apiName = 'kamomeFlutter';

  /// How to handle non-existent command.
  HowToHandleNonExistentCommand howToHandleNonExistentCommand =
      HowToHandleNonExistentCommand.resolved;

  final JavaScriptRunner _jsRunner;
  final Map<String, Command> _commands = {};

  KamomeClient(this._jsRunner);

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
    if (callback != null) {
      String callbackId = _addSendMessageCallback(callback);
      _jsRunner.runJavaScript(
          _JavaScriptMethod.onReceive(commandName, data, callbackId));
    } else {
      _jsRunner
          .runJavaScript(_JavaScriptMethod.onReceive(commandName, data, null));
    }
  }

  /// Sends a message with a [data] as List to the JavaScript receiver with a [commandName].
  void sendWithListData(String commandName, List<dynamic>? data,
      {SendMessageCallback? callback}) {
    if (callback != null) {
      String callbackId = _addSendMessageCallback(callback);
      _jsRunner.runJavaScript(
          _JavaScriptMethod.onReceive(commandName, data, callbackId));
    } else {
      _jsRunner
          .runJavaScript(_JavaScriptMethod.onReceive(commandName, data, null));
    }
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
  ///   name: KamomeClient.channelName,
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

  String _addSendMessageCallback(SendMessageCallback callback) {
    final callbackId = _CallbackId.create();

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

  static String onReceive(String name, Object? data, String? callbackId) {
    if (data != null) {
      final jsonString = json.encode(data);
      if (callbackId != null) {
        return "$_jsObj.onReceive('$name', $jsonString, '$callbackId')";
      } else {
        return "$_jsObj.onReceive('$name', $jsonString, null)";
      }
    } else {
      if (callbackId != null) {
        return "$_jsObj.onReceive('$name', null, '$callbackId')";
      } else {
        return "$_jsObj.onReceive('$name', null, null)";
      }
    }
  }
}

class _CallbackId {
  static int _serial = 0;

  static String create() {
    int id = _serial++;
    return id.toString();
  }
}
