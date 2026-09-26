// The conversation on a booking.
//
// What people actually use this for is small and specific: "the gate code is
// 4417", "she has already eaten", "I am ten minutes away". Things too small
// for a phone call and too important to leave unsaid. So the screen is a
// thread and nothing more — no attachments, no typing indicator, no read
// receipts beyond the badge clearing.
//
// A thread exists only where a booking does, and only while it is confirmed,
// running or just finished. That is not a limitation to widen later: an open
// messaging surface between strangers on a care platform is a safeguarding
// problem, and the booking is what makes the conversation legitimate.

import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.booking});
  final Booking booking;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<BookingMessage>? _messages;
  String? _error;
  bool _sending = false;
  Timer? _poll;

  String get _withName => widget.booking.providerName ?? 'your carer';

  @override
  void initState() {
    super.initState();
    _load();
    // No websocket here, so the thread is polled. Ten seconds is often enough
    // for a conversation this size and rare enough not to drain a battery.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(quiet: true));
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final m = await Backend.instance.bookingMessages(widget.booking.id);
      if (!mounted) return;
      final grew = _messages == null || m.length != _messages!.length;
      setState(() {
        _messages = m;
        _error = null;
      });
      if (grew) _toBottom();
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toBottom() {
    // After the frame, or the list has not been laid out and there is no
    // extent to scroll to yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Dur.normal,
        curve: Ease.enter,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final sent = await Backend.instance.sendBookingMessage(widget.booking.id, text);
      if (!mounted) return;
      setState(() {
        _messages = [...?_messages, sent];
        _input.clear();
        _error = null;
      });
      _toBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 30),
                  ),
                  InitialsAvatar(name: _withName, size: 38, radius: 12),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_withName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17.5,
                                fontWeight: FontWeight.w800)),
                        Text(
                          '${widget.booking.serviceType.label} · '
                          '${widget.booking.timeFrom}–${widget.booking.timeTo}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _body()),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && _messages == null) {
      return PagePad(
        top: 20,
        child: InlineError(message: _error!, onRetry: _load),
      );
    }
    if (_messages == null) {
      return const PagePad(top: 20, child: SkeletonList(count: 4, avatar: false));
    }
    if (_messages!.isEmpty) {
      return Center(
        child: PagePad(
          child: EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: t('Nothing said yet'),
            message: t(
                'Anything {name} should know before they arrive — a gate code, '
                'which door, whether the dog barks — put it here.',
                {'name': _withName}),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 12),
      itemCount: _messages!.length,
      itemBuilder: (_, i) => _bubble(_messages![i]),
    );
  }

  Widget _bubble(BookingMessage m) {
    if (m.sender == MessageSender.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: SC.sunkTint,
              borderRadius: BorderRadius.circular(SC.rPill),
            ),
            child: Text(m.body,
                textAlign: TextAlign.center,
                style: ST.small.copyWith(fontSize: 12)),
          ),
        ),
      );
    }

    final mine = m.sender == MessageSender.customer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
              decoration: BoxDecoration(
                color: mine ? SC.blueBright : SC.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: SC.hairline),
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    m.body,
                    style: ST.body.copyWith(
                      height: 1.35,
                      color: mine ? Colors.white : SC.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _clock(m.sentAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: mine ? Colors.white70 : SC.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: SC.surface,
        border: Border(top: BorderSide(color: SC.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SC.gutter, 10, SC.gutter, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null && _messages != null) ...[
                InlineError(message: _error!),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: t('Write a message'),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PressableScale(
                    onTap: _input.text.trim().isEmpty || _sending ? null : _send,
                    child: AnimatedContainer(
                      duration: Dur.quick,
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _input.text.trim().isEmpty ? SC.hairlineCool : SC.blueBright,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                            )
                          : Icon(Icons.send_rounded,
                              color: _input.text.trim().isEmpty
                                  ? SC.inkFaint
                                  : Colors.white,
                              size: 21),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _clock(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
