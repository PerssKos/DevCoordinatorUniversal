import 'package:devcoordinator/features/shell/app_shell.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'negative compound statuses take precedence over positive substrings',
    () {
      expect(statusTone('unhealthy'), AppStatusTone.danger);
      expect(statusTone('active with failure'), AppStatusTone.danger);
      expect(statusTone('verified policy violation'), AppStatusTone.danger);
    },
  );

  test('healthy and transitional statuses retain their semantic tones', () {
    expect(statusTone('healthy'), AppStatusTone.success);
    expect(statusTone('pending'), AppStatusTone.warning);
    expect(statusTone('detached'), AppStatusTone.neutral);
  });
}
