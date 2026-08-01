import 'package:flutter_test/flutter_test.dart';
import 'package:raddflix/core/player/voice_commands_service.dart';

void main() {
  group('VIBE-5D direct phrase mappings', () {
    test('maps each required phrase to its vibe command', () {
      expect(
        VoiceCommandsService.parse('slowed'),
        VoiceCommand.vibeSlowed,
      );
      expect(
        VoiceCommandsService.parse('nightcore'),
        VoiceCommand.vibeNightcore,
      );
      expect(
        VoiceCommandsService.parse('lofi'),
        VoiceCommand.vibeLofi,
      );
      expect(
        VoiceCommandsService.parse('reverb'),
        VoiceCommand.vibeSlowedReverb,
      );
      expect(
        VoiceCommandsService.parse('no vibe'),
        VoiceCommand.vibeNone,
      );
    });

    test('normalizes case and surrounding whitespace', () {
      expect(
        VoiceCommandsService.parse('  NIGHTCORE  '),
        VoiceCommand.vibeNightcore,
      );
      expect(
        VoiceCommandsService.parse('  No Vibe '),
        VoiceCommand.vibeNone,
      );
    });
  });
}