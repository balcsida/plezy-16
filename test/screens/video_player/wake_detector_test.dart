import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/wake_detector.dart';

void main() {
  late DateTime wall;
  late Duration mono;
  late List<Duration> wakes;
  late WakeDetector detector;

  setUp(() {
    wall = DateTime.utc(2026, 9, 28, 19, 44);
    mono = Duration.zero;
    wakes = [];
    detector = WakeDetector(onWake: wakes.add, wallClock: () => wall, monotonic: () => mono);
  });

  /// Time passing with the process running: both clocks advance.
  void run(FakeAsync async, Duration time) {
    wall = wall.add(time);
    mono += time;
    async.elapse(time);
  }

  test('running time is never a wake', () {
    fakeAsync((async) {
      detector.start();
      run(async, const Duration(minutes: 30));
      expect(wakes, isEmpty);
      detector.stop();
    });
  });

  test('a standby that froze the process is noticed on the next tick', () {
    fakeAsync((async) {
      detector.start();
      run(async, const Duration(minutes: 1));
      // Measured on the TV: 308 s of standby the monotonic clock never saw.
      wall = wall.add(const Duration(seconds: 308));
      run(async, wakeCheckPeriod);
      expect(wakes, [const Duration(seconds: 308)]);
      run(async, const Duration(minutes: 5));
      expect(wakes, hasLength(1), reason: 'one standby is one wake');
      detector.stop();
    });
  });

  test('a clock correction below the threshold is not a wake', () {
    fakeAsync((async) {
      detector.start();
      wall = wall.add(wakeGapThreshold - const Duration(milliseconds: 1));
      run(async, wakeCheckPeriod);
      expect(wakes, isEmpty);
      detector.stop();
    });
  });

  test('a wall clock set backwards is not a wake', () {
    fakeAsync((async) {
      detector.start();
      wall = wall.subtract(const Duration(hours: 1));
      run(async, wakeCheckPeriod);
      expect(wakes, isEmpty);
      detector.stop();
    });
  });

  test('starting again forgets a gap that a resume already answered', () {
    fakeAsync((async) {
      detector.start();
      wall = wall.add(const Duration(minutes: 5));
      detector.start();
      run(async, const Duration(minutes: 1));
      expect(wakes, isEmpty);
      detector.stop();
    });
  });

  test('stop ends the watch', () {
    fakeAsync((async) {
      detector.start();
      detector.stop();
      wall = wall.add(const Duration(minutes: 5));
      run(async, const Duration(minutes: 1));
      expect(wakes, isEmpty);
    });
  });
}
