import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../network/api_client.dart';

class PaymentService {
  final ApiClient _apiClient;
  late Razorpay _razorpay;

  PaymentService(this._apiClient) {
    _razorpay = Razorpay();
  }

  void init({
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onFailure,
    required Function(ExternalWalletResponse) onExternalWallet,
  }) {
    _razorpay.clear();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, onFailure);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
  }

  Future<void> openCheckout({
    required double amount,
    required String contact,
    required String email,
    String? razorpayOrderId,
    String description = 'Wallet Top-up',
  }) async {
    try {
      String? orderId = razorpayOrderId;

      if (orderId == null) {
        // 1. Create order on backend (Only for Wallet Top-up)
        print("Starting openCheckout for Top-up... amount is $amount");
        final orderResponse = await _apiClient.post(
          '${ApiClient.paymentBaseUrl}/create-order',
          data: {'amount': amount},
          requiresAuth: true,
        );
        orderId = orderResponse['order']['id'];
      } else {
        print("Starting openCheckout for Direct Order... amount is $amount");
      }

      print("Final orderId for Razorpay: $orderId");

      // 2. Open Razorpay Checkout
      var options = {
        'key': dotenv.maybeGet('RAZORPAY_KEY_ID') ?? 'rzp_live_SpvDYvOvJGKsNI',
        'amount': (amount * 100).toInt(),
        'name': 'Shrimpbite',
        'order_id': orderId,
        'description': description,
        'prefill': {'contact': contact, 'email': email},
        'external': {
          'wallets': ['paytm']
        }
      };

      print("Opening Razorpay with options: $options");
      _razorpay.open(options);
      print("Razorpay open() called successfully.");
    } catch (e, stacktrace) {
      print("=====================================");
      print("ERROR IN PAYMENT SERVICE: ${e.toString()}");
      print("STACKTRACE: $stacktrace");
      print("=====================================");
      rethrow;
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(
    ref.watch(apiClientProvider),
  );
});
