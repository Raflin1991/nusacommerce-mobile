import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/constants/app_colors.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/barcode_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/utils/currency_formatter.dart';
import 'package:nusacommerce_mobile/core/widgets/nusa_widgets.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/auth/presentation/login_screen.dart';
import 'package:nusacommerce_mobile/features/auth/presentation/splash_welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OXORA Mobile POS Core Unit & Visual Rebranding Tests', () {
    test('IdrCurrencyFormatter formats Rupiah accurately', () {
      expect(IdrCurrencyFormatter.format(1250000), 'Rp 1.250.000');
      expect(IdrCurrencyFormatter.format(17000), 'Rp 17.000');
      expect(IdrCurrencyFormatter.parse('Rp 20.000'), 20000.0);
    });

    test('BarcodeService parses Prefix 20 Digital Scale Weight Barcode', () {
      // 20 + PLU (10007) + Weight 01500g (1.5kg) + Checksum (9)
      final parsed = BarcodeService.parse('2010007015009');
      expect(parsed.isWeightScaleBarcode, isTrue);
      expect(parsed.scalePlu, '10007');
      expect(parsed.weightKg, 1.5);
    });

    testWidgets('NusaBrandLogo renders transparent official OXORA emblem without dark box', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NusaBrandLogo(size: 64),
            ),
          ),
        ),
      );
      await tester.pump();
      final logoWidget = tester.widget<NusaBrandLogo>(find.byType(NusaBrandLogo));
      expect(logoWidget.backgroundColor, Colors.transparent);
      expect(logoWidget.borderColor, Colors.transparent);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('SplashWelcomeScreen matches OXORA Light Theme visual guide & zero overflow at 360x640', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      final authCubit = AuthCubit(
        apiClient: apiClient,
        offlineDb: OfflineDatabase(prefs),
      );
      addTearDown(authCubit.close);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SplashWelcomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Versi 2.0 • Powered by Autonomous AI'), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.length, 2);
      expect(
        images.any((img) =>
            img.image is AssetImage &&
            (img.image as AssetImage).assetName ==
                'assets/images/oxora_splash_wordmark_light.png'),
        isTrue,
      );
      expect(find.textContaining('NusaCommerce'), findsNothing);
      expect(find.textContaining('OXO.ID'), findsNothing);
    });

    testWidgets('LoginScreen uses clean Light Theme OXORA wordmark (without tagline), oxora.id chip, and zero overflow at 360x640', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'nusa_mobile_base_url': 'http://nusacommerce.test/api/v1',
      });
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      final offlineDb = OfflineDatabase(prefs);
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      addTearDown(authCubit.close);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: LoginScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final loginImg = tester.widget<Image>(find.byType(Image));
      expect((loginImg.image as AssetImage).assetName,
          'assets/images/oxora_wordmark_light.png');
      expect(find.text('oxora.id'), findsOneWidget);
      expect(find.text('Akun Cloud Toko'), findsOneWidget);
      expect(find.text('Toko Mandiri (Offline)'), findsOneWidget);
      expect(find.textContaining('THE AI-POWERED'), findsNothing);
      expect(find.textContaining('OXO.ID'), findsNothing);
      expect(find.textContaining('oxo.id'), findsNothing);
      expect(find.textContaining('nusacommerce'), findsNothing);
      expect(find.textContaining('nusco.id'), findsNothing);

      // Ensure brand header never uses dark executiveNavyGradient
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasDarkNavyBanner = containers.any((c) {
        final dec = c.decoration;
        return dec is BoxDecoration && dec.gradient == AppColors.executiveNavyGradient;
      });
      expect(hasDarkNavyBanner, isFalse);
    });
  });
}
