import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/playback_reconnect.dart';

void main() {
  test('attempts follow the schedule and the budget ends', () {
    fakeAsync((async) {
      var attempts = 0;
      final reconnect = PlaybackReconnect(onAttempt: () => attempts++);
      for (final delay in playbackReconnectDelays) {
        final before = attempts;
        expect(reconnect.schedule(), isTrue);
        async.elapse(delay - const Duration(milliseconds: 1));
        expect(attempts, before);
        async.elapse(const Duration(milliseconds: 1));
        expect(attempts, before + 1);
      }
      expect(reconnect.hasBudget, isFalse);
      expect(reconnect.schedule(), isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(attempts, playbackReconnectDelays.length);
    });
  });

  test('the schedule outlasts a hung open and a slow network return', () {
    final total = playbackReconnectDelays.fold(Duration.zero, (sum, delay) => sum + delay);
    expect(total, greaterThanOrEqualTo(const Duration(seconds: 45)));
  });

  test('reset refills the budget and cancels the pending attempt', () {
    fakeAsync((async) {
      var attempts = 0;
      final reconnect = PlaybackReconnect(onAttempt: () => attempts++, delays: const [Duration(seconds: 2)]);
      expect(reconnect.schedule(), isTrue);
      reconnect.reset();
      async.elapse(const Duration(minutes: 1));
      expect(attempts, 0);
      expect(reconnect.hasBudget, isTrue);
    });
  });

  test('cancel keeps a superseded attempt from firing without refunding it', () {
    fakeAsync((async) {
      var attempts = 0;
      final reconnect = PlaybackReconnect(onAttempt: () => attempts++, delays: const [Duration(seconds: 2)]);
      expect(reconnect.schedule(), isTrue);
      reconnect.cancel();
      async.elapse(const Duration(minutes: 1));
      expect(attempts, 0);
      expect(reconnect.hasBudget, isFalse);
    });
  });

  test('scheduling again replaces the pending attempt', () {
    fakeAsync((async) {
      var attempts = 0;
      final reconnect = PlaybackReconnect(
        onAttempt: () => attempts++,
        delays: const [Duration(seconds: 2), Duration(seconds: 3)],
      );
      expect(reconnect.schedule(), isTrue);
      expect(reconnect.schedule(), isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(attempts, 1);
    });
  });
}
