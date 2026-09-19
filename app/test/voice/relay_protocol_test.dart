import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/features/voice/data/relay_protocol.dart';

void main() {
  group('parseRelayEvent', () {
    test('parses the ready handshake and accepts the supported format', () {
      final e = parseRelayEvent(
        '{"type":"ready","protocol":1,"model":"google:gemini-2.5-flash-native-audio-latest",'
        '"input_sample_rate":16000,"output_sample_rate":24000,"encoding":"pcm16le","channels":1}',
      );
      expect(e, isA<RelayReady>());
      final ready = e as RelayReady;
      expect(ready.model, 'google:gemini-2.5-flash-native-audio-latest');
      expect(ready.incompatibility, isNull);
    });

    test('flags an unsupported ready format', () {
      final ready =
          parseRelayEvent(
                '{"type":"ready","protocol":2,"model":"x","input_sample_rate":16000,'
                '"output_sample_rate":24000,"encoding":"pcm16le","channels":1}',
              )
              as RelayReady;
      expect(ready.incompatibility, contains('protocol'));

      final stereo =
          parseRelayEvent(
                '{"type":"ready","protocol":1,"model":"x","input_sample_rate":16000,'
                '"output_sample_rate":24000,"encoding":"pcm16le","channels":2}',
              )
              as RelayReady;
      expect(stereo.incompatibility, contains('channels'));
    });

    test('parses transcript with index, speaker, text and delta', () {
      final t =
          parseRelayEvent(
                '{"type":"transcript","index":3,"speaker":"assistant","text":"Hello there","delta":"there"}',
              )
              as RelayTranscript;
      expect(t.index, 3);
      expect(t.speaker, 'assistant');
      expect(t.text, 'Hello there');
      expect(t.delta, 'there');
    });

    test('parses fatal and non-fatal errors', () {
      final fatal =
          parseRelayEvent(
                '{"type":"error","code":"not_configured","message":"Add GOOGLE_API_KEY","fatal":true}',
              )
              as RelayError;
      expect(fatal.fatal, isTrue);
      expect(fatal.code, 'not_configured');
      expect(fatal.message, 'Add GOOGLE_API_KEY');

      final soft =
          parseRelayEvent('{"type":"error","message":"odd frame"}')
              as RelayError;
      expect(soft.fatal, isFalse);
    });

    test('parses tool, clear_output, turn_complete, reconnected and pong', () {
      expect(
        parseRelayEvent(
          '{"type":"tool_call","name":"lookup_time","call_id":"c1"}',
        ),
        isA<RelayToolCall>().having((e) => e.name, 'name', 'lookup_time'),
      );
      expect(
        parseRelayEvent(
          '{"type":"tool_result","name":"lookup_time","call_id":"c1"}',
        ),
        isA<RelayToolResult>(),
      );
      expect(
        parseRelayEvent('{"type":"clear_output","reason":"barge_in"}'),
        isA<RelayClearOutput>().having((e) => e.reason, 'reason', 'barge_in'),
      );
      expect(
        parseRelayEvent('{"type":"turn_complete"}'),
        isA<RelayTurnComplete>(),
      );
      expect(
        parseRelayEvent('{"type":"reconnected","state_restored":true}'),
        isA<RelayReconnected>().having(
          (e) => e.stateRestored,
          'restored',
          true,
        ),
      );
      expect(parseRelayEvent('{"type":"pong"}'), isA<RelayPong>());
    });

    test('unknown types are surfaced, not thrown', () {
      expect(
        parseRelayEvent('{"type":"something_new"}'),
        isA<RelayUnknown>().having((e) => e.type, 'type', 'something_new'),
      );
    });

    test('rejects non-JSON, non-object and typeless frames', () {
      expect(() => parseRelayEvent('not json'), throwsFormatException);
      expect(() => parseRelayEvent('[1,2]'), throwsFormatException);
      expect(() => parseRelayEvent('{"foo":"bar"}'), throwsFormatException);
      expect(
        () => parseRelayEvent('{"type":"transcript","speaker":"user"}'),
        throwsFormatException,
      );
    });
  });

  group('normalizeRelayUrl', () {
    const host = 'musicians-simplified-birthday-students.trycloudflare.com';
    const want = 'wss://$host/gemini/voice';

    test('accepts the https tunnel page URL, bare host and ws://', () {
      expect(normalizeRelayUrl('https://$host/'), want);
      expect(normalizeRelayUrl('https://$host'), want);
      expect(normalizeRelayUrl(host), want);
      expect(normalizeRelayUrl('ws://$host/gemini/voice'), want);
      expect(normalizeRelayUrl('http://$host/gemini/voice'), want);
      expect(normalizeRelayUrl('  $want  '), want);
      expect(normalizeRelayUrl('$want#'), want);
    });

    test('keeps plain ws for local hosts', () {
      expect(
        normalizeRelayUrl('ws://127.0.0.1:8000/gemini/voice'),
        'ws://127.0.0.1:8000/gemini/voice',
      );
      expect(
        normalizeRelayUrl('http://localhost:8000'),
        'ws://localhost:8000/gemini/voice',
      );
      expect(
        normalizeRelayUrl('192.168.1.20:8000'),
        'ws://192.168.1.20:8000/gemini/voice',
      );
    });

    test('keeps a custom path and falls back to the default when empty', () {
      expect(
        normalizeRelayUrl('https://$host/other/path'),
        'wss://$host/other/path',
      );
      expect(normalizeRelayUrl(''), kDefaultRelayUrl);
    });
  });

  group('control messages', () {
    test('encode close, ping and interrupt', () {
      expect(jsonDecode(encodeClose()), {'type': 'close'});
      expect(jsonDecode(encodePing()), {'type': 'ping'});
      expect(jsonDecode(encodeInterrupt(4800)), {
        'type': 'interrupt',
        'played_bytes': 4800,
      });
      expect(() => encodeInterrupt(-1), throwsArgumentError);
    });
  });

  group('TranscriptLog', () {
    RelayTranscript t(int i, String who, String text) =>
        RelayTranscript(index: i, speaker: who, text: text);

    test('replaces the entry at an index instead of appending', () {
      final log = TranscriptLog()
        ..apply(t(0, 'user', 'What ti'))
        ..apply(t(0, 'user', 'What time is it'))
        ..apply(t(0, 'user', 'What time is it in Tokyo?'));
      expect(log.turns.map((e) => e.text), ['What time is it in Tokyo?']);
    });

    test('orders by index and merges adjacent same-speaker fragments', () {
      final log = TranscriptLog()
        ..apply(t(2, 'assistant', ' 9 pm.'))
        ..apply(t(0, 'user', 'Time in Tokyo?'))
        ..apply(t(1, 'assistant', 'It is'))
        ..apply(t(3, 'user', 'Thanks'));
      final turns = log.turns;
      expect(turns.map((e) => e.speaker), ['user', 'assistant', 'user']);
      expect(turns[1].text, 'It is 9 pm.');
      expect(turns[0].isUser, isTrue);
      expect(turns[1].isUser, isFalse);
    });

    test('clear empties the log', () {
      final log = TranscriptLog()..apply(t(0, 'user', 'hi'));
      expect(log.isEmpty, isFalse);
      log.clear();
      expect(log.isEmpty, isTrue);
      expect(log.turns, isEmpty);
    });
  });
}
