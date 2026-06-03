import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_page.dart';
import '../../cart/view/cart_page.dart';
import '../../profile/view/profile_page.dart';
import '../../subscription/subscription_page.dart';
import '../../wallet/view/wallet_page.dart';
import '../controller/main_controller.dart';
import '../../../data/services/db_service.dart';
import '../../../data/services/socket_service.dart';
import '../../../data/services/order_service.dart';
import '../../auth/provider/auth_provider.dart';
import '../../profile/widgets/order_review_dialog.dart';
import '../../../data/models/food_models.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/services/notification_api_service.dart';
import '../../../data/services/fcm_service.dart';
import '../widgets/cart_summary_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> with WidgetsBindingObserver {
  final MainController _controller = MainController();
  DateTime? _lastPressedAt;
  StreamSubscription? _fcmSubscription;

  final List<Widget> _pages = [
    const HomePage(),
    const SubscriptionPage(),
    const CartPage(), // Central FAB
    const WalletPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    // Initial cart sync from API
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cart = CartProviderScope.of(context);

      await cart.loadCartFromApi();
      if (!mounted) return;

      // Proactively load addresses to see if we need the permission sheet
      await cart.loadAddresses();
      if (!mounted) return;

      // Sync wallet so cron job deductions accurately show on app launch
      await cart.syncWallet();

      _initSocketListeners();
    });
  }

  void _initSocketListeners() {
    final authState = ref.read(authProvider);
    if (authState is! AuthAuthenticated) return;

    final socket = ref.read(socketServiceProvider);
    final userId = authState.user.id;

    // Join the user's personal room to receive order updates
    socket.joinUserRoom(userId);

    // Join notifications room to receive communication hub broadcasts
    socket.joinNotificationsRoom(userId);
    socket.onNotification((data) {
      if (!mounted) return;
      try {
        final map = Map<String, dynamic>.from(data as Map);
        ref.read(notificationsProvider.notifier).addNotification(
              NotificationModel(
                id: map['_id']?.toString() ??
                    'sock-${DateTime.now().millisecondsSinceEpoch}',
                title: map['title']?.toString() ?? 'Shrimpbite',
                body: map['message']?.toString() ?? '',
                type: map['type']?.toString() ?? 'System',
                isRead: false,
                createdAt: map['createdAt'] != null
                    ? DateTime.tryParse(map['createdAt'].toString()) ??
                        DateTime.now()
                    : DateTime.now(),
              ),
            );
      } catch (e) {
        debugPrint('⚠️ Failed to parse socket notification: $e');
      }
    });

    // Listen for general order status changes
    socket.onOrderUpdate((data) {
      if (!mounted) return;
      debugPrint('🔔 Order update in MainPage: $data');
      // "Delivered" state is now strictly handled by 'orderDelivered' below
    });
    // Dedicated orderDelivered event to trigger the review dialog immediately
    socket.onOrderDelivered((data) {
      if (!mounted) return;
      debugPrint('📦 Dedicated Order Delivered Event: $data');

      _handleOrderDelivered(data);

      final orderId = data['orderId']?.toString() ?? 'Order';
      ref.read(notificationsProvider.notifier).addNotification(
            NotificationModel(
              id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
              title: 'Order Delivered! 🎉',
              body: 'Package #$orderId has been delivered successfully. Enjoy!',
              type: 'order',
              isRead: false,
              createdAt: DateTime.now(),
            ),
          );
    });

    // Listen for live Wallet balance updates coming from cron job / backend
    socket.onWalletUpdate((data) {
      if (!mounted) return;
      debugPrint('💰 Real-time Wallet Update received: $data');
      // Trigger syncWallet so all UI instances refresh immediately
      final cart = CartProviderScope.of(context);
      cart.syncWallet();
    });

    // ── FCM Fallback Listener ────────────────────────────────────────────────
    // If Socket fails (common on free tier), FCM will still trigger the popup
    _fcmSubscription?.cancel();
    _fcmSubscription = FCMService.onMessageReceived.stream.listen((message) {
      if (!mounted) return;

      final data = message.data;
      final notification = message.notification;
      debugPrint('📩 FCM Incoming Data: $data');

      // 1. ALWAYS add to the local notification list so it's not "static"
      if (notification != null) {
        ref.read(notificationsProvider.notifier).addNotification(
              NotificationModel(
                id: message.messageId ??
                    'fcm-${DateTime.now().millisecondsSinceEpoch}',
                title: notification.title ?? 'Shrimpbite Update',
                body: notification.body ?? '',
                type: data['type']?.toString() ?? 'promotion',
                isRead: false,
                createdAt: DateTime.now(),
              ),
            );
      }

      // 2. Handle specific delivery triggers for the review dialog
      final String? type = data['type']?.toString().toLowerCase();
      final String? status = data['status']?.toString().toLowerCase();
      final String? orderId = data['orderId']?.toString() ??
          data['order_id']?.toString() ??
          data['_id']?.toString();

      if (type == 'order_delivered' ||
          status == 'delivered' ||
          (notification?.title?.toLowerCase().contains('delivered') ?? false)) {
        debugPrint('🔔 FCM Fallback: Triggering review dialog for $orderId');
        _handleOrderDelivered({'orderId': orderId});
      }
    });
  }

  Future<void> _handleOrderDelivered(dynamic data) async {
    // If we have orderId, fetch full details for the dialog
    String? orderId = data['orderId']?.toString();
    Map<String, dynamic>? rawOrder;

    try {
      final orderService = ref.read(orderServiceProvider);

      // 1. Try to fetch order by provided ID (if it looks like a Mongo ID)
      if (orderId != null && orderId != 'null' && orderId.length > 20) {
        rawOrder = await orderService.getOrderById(orderId);
      }

      // 2. If ID-fetch failed or orderId was human-readable/null, search history
      if (rawOrder == null || rawOrder.isEmpty) {
        debugPrint(
            '🔍 Order not found by ID or ID is human-readable, searching history...');
        final history = await orderService.getMyOrders();
        if (history.isNotEmpty) {
          // Find the most recent "Delivered" order
          final latestDelivered = history.firstWhere(
            (o) => (o['status'] ?? '').toString().toLowerCase() == 'delivered',
            orElse: () => null,
          );
          if (latestDelivered != null) {
            rawOrder = Map<String, dynamic>.from(latestDelivered);
            debugPrint('✅ Found delivered order in history');
          }
        }
      }

      if (rawOrder == null || rawOrder.isEmpty) {
        debugPrint('❌ Could not find order data for review dialog');
        return;
      }

      if (mounted) {
        final order = UserOrder.fromJson(rawOrder);

        // Show the review dialog automatically
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => OrderReviewDialog(order: order),
        );
      }
    } catch (e) {
      debugPrint('Error handling order delivered event: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FCMService.sendTokenToBackend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    ref.read(socketServiceProvider).offOrderUpdate();
    ref.read(socketServiceProvider).offOrderDelivered();
    ref.read(socketServiceProvider).offWalletUpdate();
    ref.read(socketServiceProvider).offNotification();
    _fcmSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartProviderScope.of(context);
    final bool showSummary =
        cart.itemCount > 0 && _controller.currentIndex != 2;

    return MainControllerScope(
      controller: _controller,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;

          if (_controller.currentIndex != 0) {
            _controller.changePage(0);
            return;
          }

          final now = DateTime.now();
          if (_lastPressedAt == null ||
              now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
            _lastPressedAt = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Press back again to exit the app.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                backgroundColor: Color(0xFF114F3B),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
            );
            return;
          }
          SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          extendBody: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _controller.currentIndex,
                  children: _pages,
                ),
              ),
              if (showSummary)
                Positioned(
                  bottom: 20, // Just above the custom bottom bar
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CartSummaryBar(cart: cart),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _buildCustomBottomBar(),
        ),
      ),
    );
  }

  Widget _buildCustomBottomBar() {
    return SafeArea(
      bottom: true,
      child: Container(
        height: 90,
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Background Bar
            Container(
              height: 75,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_filled, 'Home'),
                  _buildNavItem(1, Icons.local_shipping_outlined, 'Daily'),
                  const SizedBox(width: 60), // Space for FAB
                  _buildNavItem(3, Icons.wallet_rounded, 'Wallet'),
                  _buildNavItem(4, Icons.person_rounded, 'Profile'),
                ],
              ),
            ),
            // Central FAB (Cart) - Green circle as per project identity
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: () => _controller.changePage(2),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF68B92E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF68B92E).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _controller.currentIndex == index;
    return GestureDetector(
      onTap: () => _controller.changePage(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected ? const Color(0xFF68B92E) : Colors.grey.shade400,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color:
                  isSelected ? const Color(0xFF68B92E) : Colors.grey.shade400,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          // Active indicator dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF68B92E) : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
