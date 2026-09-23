import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/system_audio_service.dart';

void main() {
  final card = <String, dynamic>{
    'name': 'card0',
    'index': 0,
    'active_profile': 'analog',
    'profiles': {
      'hdmi': {'description': 'HDMI stereo', 'sinks': 1, 'available': true},
    },
    'ports': [
      {
        'name': 'hdmi-output-0',
        'description': 'Monitor',
        'availability': 'available',
        'direction': 'output',
        'profiles': ['hdmi'],
      },
    ],
  };
  test('HDMI profile is discoverable without an active sink', () {
    final choices = SystemAudioService.hdmiOptions([card]);
    expect(choices.single['profile'], 'hdmi');
    expect(choices.single['available'], true);
  });
  test('boolean unavailable profile is not selectable', () {
    final unavailable = {...card, 'profiles': {'hdmi': {'sinks': 1, 'available': false}}};
    expect(SystemAudioService.hdmiOptions([unavailable]).single['available'], false);
  });
  test('disconnected HDMI is visible but unavailable', () {
    final disconnected = {
      ...card,
      'ports': [
        {
          'name': 'hdmi-output-0',
          'availability': 'not available',
          'profiles': ['hdmi'],
        },
      ],
    };
    expect(
      SystemAudioService.hdmiOptions([disconnected]).single['available'],
      false,
    );
  });
  for (final fail in [false, true]) {
    test(
      'HDMI selection ${fail ? "restores profile on failure" : "confirms server and moves streams"}',
      () async {
        var profile = 'analog', defaultSink = 'speaker';
        final calls = <List<String>>[];
        final service = SystemAudioService(
          run: (args) async {
            calls.add(args);
            Object out = '';
            if (args.first == '--format=json') {
              out = switch (args.last) {
                'cards' => [
                  {...card, 'active_profile': profile},
                ],
                'sinks' => [
                  {
                    'name': profile == 'hdmi' ? 'hdmi-sink' : 'speaker',
                    'card': 0,
                    'ports': profile == 'hdmi'
                        ? [
                            {'name': 'hdmi-output-0'},
                          ]
                        : [],
                  },
                ],
                'sources' => [
                  {'name': 'microphone'},
                  {'name': 'speaker.monitor'},
                ],
                'sink-inputs' => [
                  {'index': 42},
                ],
                _ => [],
              };
              out = jsonEncode(out);
            } else if (args.first == 'get-default-sink') {
              out = defaultSink;
            } else if (args.first == 'get-default-source') {
              out = 'microphone';
            } else if (args.first == 'set-card-profile') {
              profile = args.last;
            } else if (args.first == 'set-sink-port' && fail) {
              return ProcessResult(0, 1, '', 'port gone');
            } else if (args.first == 'set-default-sink') {
              defaultSink = args.last;
            }
            return ProcessResult(0, 0, out, '');
          },
        );
        final result = await service.select({
          'kind': 'sink',
          'card': 'card0',
          'profile': 'hdmi',
          'port': 'hdmi-output-0',
        });
        expect(result['ok'], !fail);
        expect(profile, fail ? 'analog' : 'hdmi');
        if (!fail) {
          expect(result['defaultSink'], 'hdmi-sink');
          expect((result['sources'] as List).length, 1);
          expect(
            calls,
            contains(equals(['move-sink-input', '42', 'hdmi-sink'])),
          );
        }
        await service.close();
      },
    );
  }
  test(
    'server error is reported, not represented as an empty successful list',
    () async {
      final service = SystemAudioService(
        run: (_) async => ProcessResult(0, 1, '', 'offline'),
      );
      expect((await service.status())['ok'], false);
      await service.close();
    },
  );
}
