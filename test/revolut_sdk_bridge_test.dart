import 'package:flutter_test/flutter_test.dart';
import 'package:revolut_sdk_bridge/android/enums/revolut_enums.dart';
import 'package:revolut_sdk_bridge/android/models/revolut_pay_models.dart';

void main() {
  group('ButtonParamsData', () {
    test('toMap exposes documented defaults', () {
      final map = const ButtonParamsData().toMap();

      expect(map['radius'], 'MEDIUM');
      expect(map['size'], 'LARGE');
      expect(map['boxText'], 'NONE');
      expect(map['boxTextCurrency'], isNull);
      expect(map['variantModes'], isNull);
    });

    test('fromMap round-trips all fields', () {
      const params = ButtonParamsData(
        radius: ButtonRadius.large,
        size: ButtonSize.small,
        boxText: BoxText.getCashbackValue,
        boxTextCurrency: 'EUR',
        variantModes: VariantModesData(
          darkTheme: ButtonVariant.light,
          lightTheme: ButtonVariant.dark,
        ),
      );

      final restored = ButtonParamsData.fromMap(params.toMap());

      expect(restored.radius, ButtonRadius.large);
      expect(restored.size, ButtonSize.small);
      expect(restored.boxText, BoxText.getCashbackValue);
      expect(restored.boxTextCurrency, 'EUR');
      expect(restored.variantModes?.darkTheme, ButtonVariant.light);
      expect(restored.variantModes?.lightTheme, ButtonVariant.dark);
    });

    test('fromMap falls back to defaults on unknown values', () {
      final restored = ButtonParamsData.fromMap({
        'radius': 'BOGUS',
        'size': null,
        'boxText': 'NOPE',
      });

      expect(restored.radius, ButtonRadius.medium);
      expect(restored.size, ButtonSize.large);
      expect(restored.boxText, BoxText.none);
    });
  });

  group('OrderResultData', () {
    test('fromMap parses optional fields', () {
      final result = OrderResultData.fromMap({
        'success': false,
        'error': 'boom',
        'cause': 'network',
      });

      expect(result.success, isFalse);
      expect(result.orderId, isNull);
      expect(result.error, 'boom');
      expect(result.cause, 'network');
    });
  });

  group('SdkInitData', () {
    test('fromMap resolves environment by wire value', () {
      final sandbox = SdkInitData.fromMap({
        'environment': 'SANDBOX',
        'returnUri': 'app://pay',
        'merchantPublicKey': 'pk_test',
      });
      final main = SdkInitData.fromMap({
        'environment': 'MAIN',
        'returnUri': 'app://pay',
        'merchantPublicKey': 'pk_live',
      });
      final unknown = SdkInitData.fromMap({
        'environment': 'whatever',
        'returnUri': 'app://pay',
        'merchantPublicKey': 'pk',
      });

      expect(sandbox.environment, RevolutEnvironment.sandbox);
      expect(main.environment, RevolutEnvironment.main);
      expect(unknown.environment, RevolutEnvironment.sandbox);
    });
  });
}
