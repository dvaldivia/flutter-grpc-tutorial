import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

import 'chat_message.dart';
import 'chat_outcome_message.dart';
import 'chat_income_message.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  ChatScreen() : super(key: new ObjectKey("Main window"));

  @override
  State createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  static var _uuid = Uuid();

  ChatService _service;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final StreamController _streamController = StreamController<ChatMessage>();

  final TextEditingController _textController = TextEditingController();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _service = ChatService(
        onSentSuccess: onSentSuccess,
        onSentError: onSentError,
        onReceivedSuccess: onReceivedSuccess,
        onReceivedError: onReceivedError);
    _service.startListening();
  }

  @override
  void dispose() {
    _service.shutdown();
    for (ChatMessage message in _messages)
      message.animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Friendlychat")),
      body: Column(
        children: <Widget>[
          Flexible(
            child: StreamBuilder<ChatMessage>(
              stream: _streamController.stream,
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.hasError) {
                  return Text("Error: ${snapshot.error}");
                }
                switch (snapshot.connectionState) {
                  case ConnectionState.none:
                  case ConnectionState.waiting:
                    break;
                  case ConnectionState.active:
                  case ConnectionState.done:
                    debugPrint("builder: ${snapshot.data.text}");
                    _updateMessages(snapshot.data);
                }
                return ListView.builder(
                    padding: EdgeInsets.all(8.0),
                    reverse: true,
                    itemBuilder: (_, int index) => _messages[index],
                    itemCount: _messages.length);
              },
            ),
          ),
          Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).accentColor),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: <Widget>[
            Flexible(
              child: TextField(
                maxLines: null,
                textInputAction: TextInputAction.send,
                controller: _textController,
                onChanged: (String text) {
                  setState(() {
                    _isComposing = text.length > 0;
                  });
                },
                onSubmitted: _isComposing ? _handleSubmitted : null,
                decoration:
                    InputDecoration.collapsed(hintText: "Send a message"),
              ),
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _isComposing
                      ? () => _handleSubmitted(_textController.text)
                      : null),
            ),
          ],
        ),
      ),
    );
  }

  void onSentSuccess(String uuid, String text) {
    debugPrint("message \"$text\" sent to the server");
    var i = _messages.indexWhere((msg) => msg.uuid == uuid);
    if (i != -1) {
      var message = _messages[i];
      if (message is ChatOutcomeMessage) {
        message.controller.setStatus(OutcomeMessageStatus.SENT);
      } else {
        debugPrint(
            "FAILED update status for message \"$uuid\": it is not ChatOutcomeMessage");
      }
    } else {
      debugPrint("FAILED to find message \"$uuid\" to update status");
    }
  }

  void onSentError(String uuid, String text, String error) {
    debugPrint("FAILED to send message \"$text\" to the server: $error");
  }

  void onReceivedSuccess(String text) {
    debugPrint("received message from the server: $text");
    ChatMessage message = ChatIncomeMessage(
      uuid: _uuid.v4(),
      text: text,
      animationController: AnimationController(
        duration: Duration(milliseconds: 700),
        vsync: this,
      ),
    );
    _streamController.add(message);
  }

  void onReceivedError(String error) {
    debugPrint("FAILED to receive messages from the server: $error");
  }

  void _handleSubmitted(String text) {
    _textController.clear();
    setState(() {
      _isComposing = false;
    });

    var uuid = _uuid.v4();
    ChatMessage message = ChatOutcomeMessage(
      uuid: uuid,
      text: text,
      controller: ChatOutcomeMessageController(),
      animationController: AnimationController(
        duration: Duration(milliseconds: 700),
        vsync: this,
      ),
    );

    _streamController.add(message);

    // async send message to the server
    _service.send(uuid, text);
  }

  void _updateMessages(ChatMessage message) {
    var i = _messages.indexWhere((msg) => msg.uuid == message.uuid);
    if (i == -1) {
      // add new message to the chat
      _messages.insert(0, message);
      message.animationController.forward();
    }
  }
}
