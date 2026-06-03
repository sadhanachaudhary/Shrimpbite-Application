import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:licius_application/app/data/models/subscription_model.dart';
import 'package:licius_application/app/data/services/subscription_service.dart';
import 'package:licius_application/app/data/services/order_service.dart';
import 'package:licius_application/app/data/services/db_service.dart';
import 'package:licius_application/app/core/utils/date_utils.dart';
import 'package:licius_application/app/modules/orders/view/order_tracking_page.dart';
import 'package:licius_application/app/routes/app_routes.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:licius_application/app/core/constants/app_colors.dart';

import 'package:licius_application/app/core/utils/auth_guard.dart';
import 'package:licius_application/app/modules/auth/provider/auth_provider.dart' as auth;

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  DateTime _selectedDate = DateTime.now();
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now().subtract(const Duration(days: 3));
  }

  void _showSnackBar(String message, {Color backgroundColor = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Returns true if the subscription delivers on the given date
  bool _deliversOn(UserSubscription sub, DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart =
        DateTime(sub.startDate.year, sub.startDate.month, sub.startDate.day);
    if (normalizedDate.isBefore(normalizedStart)) return false;

    if (sub.endDate != null) {
      final normalizedEnd =
          DateTime(sub.endDate!.year, sub.endDate!.month, sub.endDate!.day);
      if (normalizedDate.isAfter(normalizedEnd)) return false;
    }

    final isOnVacation = sub.vacationDates
        .any((vd) => AppDateUtils.isSameDay(vd, normalizedDate));
    if (isOnVacation) return false;

    switch (sub.frequency) {
      case 'Daily':
        return true;
      case 'Alternate Days':
        final diff = normalizedDate.difference(normalizedStart).inDays;
        return diff % 2 == 0;
      case 'Weekly':
        const dayNames = [
          'Sunday',
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday'
        ];
        final dayName = dayNames[date.weekday % 7];
        return sub.customDays.contains(dayName);
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-fetch data when the user logs in after a session expiry
    ref.listen(auth.isAuthenticatedProvider, (prev, next) {
      if (next == true && prev == false) {
        ref.invalidate(mySubscriptionsProvider);
        ref.invalidate(myOrdersProvider);
      }
    });

    final subscriptionsAsync = ref.watch(mySubscriptionsProvider);
    final ordersAsync = ref.watch(myOrdersProvider);
    final cart = CartProviderScope.of(context);
    final balance = cart.walletBalance;
    final isAuthenticated = ref.watch(auth.isAuthenticatedProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: !isAuthenticated 
          ? _buildGuestView()
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(mySubscriptionsProvider);
                ref.invalidate(myOrdersProvider);
                CartProviderScope.read(context).syncWallet();
              },
              color: const Color(0xFF68B92E),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  subscriptionsAsync.when(
                    data: (subs) => Column(
                      children: [
                        _buildHeader(balance, subs),
                        _buildHorizontalCalendar(subs),
                      ],
                    ),
                    loading: () => Column(
                      children: [
                        _buildHeader(balance, []),
                        _buildHorizontalCalendar([]),
                      ],
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: subscriptionsAsync.when(
                      data: (subs) => ordersAsync.when(
                        data: (orders) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _buildVacationButton(subs),
                                  const SizedBox(width: 10),
                                  _buildPauseTomorrowButton(subs),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildStatusCard(subs, orders),
                              const SizedBox(height: 20),
                              _buildYourPlans(subs),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                        loading: () => const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF68B92E))),
                        error: (e, _) => const Center(
                            child: Text('Could not load orders.',
                                style: TextStyle(color: Colors.grey))),
                      ),
                      loading: () => const Center(
                          child:
                              CircularProgressIndicator(color: Color(0xFF68B92E))),
                      error: (e, _) => _buildErrorView(e),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildErrorView(Object e) {
    final is401 = e.toString().contains('401');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(is401 ? Icons.lock_outline : Icons.wifi_off_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              is401 ? 'Session Expired' : 'Could not load data',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            Text(
              is401
                  ? 'Please log in again to continue.'
                  : 'Check your connection and pull down to retry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            if (is401) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => AuthGuard.run(context, ref, () {}),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF68B92E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Log In',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF68B92E).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today_outlined, size: 64, color: Color(0xFF68B92E)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Daily Freshness',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Login to set up subscriptions, manage your daily deliveries, and pause anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => AuthGuard.run(context, ref, () {}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF68B92E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Login / Signup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double balance, List<UserSubscription> subs) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Daily Deliveries',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A))),
                    Text(DateFormat('MMMM yyyy').format(_selectedDate),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF68B92E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF68B92E).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet,
                        color: Color(0xFF68B92E), size: 16),
                    const SizedBox(width: 6),
                    Text('₹${balance.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildHorizontalCalendar(List<UserSubscription> subs) {
    return Container(
      height: 90,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        itemBuilder: (context, index) {
          final date = _startDate.add(Duration(days: index));
          final isToday = DateUtils.isSameDay(date, DateTime.now());
          final isSelected = DateUtils.isSameDay(date, _selectedDate);

          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: Container(
              width: 55,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFF68B92E) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isToday && !isSelected
                    ? Border.all(color: const Color(0xFF68B92E), width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date).toUpperCase(),
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(date.day.toString(),
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Builder(builder: (context) {
                    final nowStr = AppDateUtils.formatDate(DateTime.now());
                    final dateStr = AppDateUtils.formatDate(date);
                    final isPastDate =
                        date.isBefore(DateTime.now()) && nowStr != dateStr;

                    if (isPastDate) return const SizedBox(height: 12);

                    final deliversToday = subs.any((s) =>
                        s.status.toLowerCase() == 'active' &&
                        _deliversOn(s, date));
                    final isSkipped = subs.any((s) => s.vacationDates
                        .any((vd) => AppDateUtils.isSameDay(vd, date)));
                    final globallyPaused = subs.isNotEmpty &&
                        subs.every((s) => s.status.toLowerCase() == 'paused');

                    if (isSkipped || globallyPaused) {
                      return const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text('🏖️', style: TextStyle(fontSize: 10)));
                    }
                    if (deliversToday) {
                      return Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                            color: Color(0xFF68B92E), shape: BoxShape.circle),
                      );
                    }
                    return const SizedBox(height: 12);
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(List<UserSubscription> subs, List<dynamic> orders) {
    final deliveringSubs = subs
        .where((s) => s.status == 'Active' && _deliversOn(s, _selectedDate))
        .toList();
    final skippedSubs = subs
        .where((s) =>
            s.status.toLowerCase() == 'paused' ||
            s.vacationDates
                .any((vd) => AppDateUtils.isSameDay(vd, _selectedDate)))
        .toList();
    final ordersForDate = orders.where((o) {
      if (o is! Map) return false;
      final createdAtStr = o['createdAt']?.toString();
      if (createdAtStr == null) return false;
      try {
        final orderDate = DateTime.parse(createdAtStr);
        return orderDate.day == _selectedDate.day &&
            orderDate.month == _selectedDate.month &&
            orderDate.year == _selectedDate.year;
      } catch (_) {
        return false;
      }
    }).toList();

    final hasDelivery = deliveringSubs.isNotEmpty || ordersForDate.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEBFFD7).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: const Color(0xFF68B92E).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: hasDelivery ? const Color(0xFF68B92E) : Colors.grey,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(hasDelivery ? 'SCHEDULED' : 'NO DELIVERY',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              if (hasDelivery)
                Text('${deliveringSubs.length + ordersForDate.length} item(s)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          if (deliveringSubs.isEmpty &&
              ordersForDate.isEmpty &&
              skippedSubs.isNotEmpty)
            Column(
              children: [
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Text('🏖️', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 8),
                      Text('ON VACATION',
                          style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.w900,
                              fontSize: 10))
                    ])),
                ...skippedSubs
                    .map((sub) => _buildDeliveryItem(sub, isPaused: true)),
              ],
            ),
          if (!hasDelivery && skippedSubs.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No deliveries scheduled for this day.',
                        style: TextStyle(color: Colors.grey))))
          else ...[
            ...ordersForDate.map((order) => _buildRealOrderItem(order)),
            ...deliveringSubs
                .where((sub) => !ordersForDate.any((o) => (o['items'] as List)
                    .any((item) =>
                        item['product']?['_id'] == sub.productId ||
                        item['product'] == sub.productId)))
                .map((sub) => _buildDeliveryItem(sub)),
          ],
        ],
      ),
    );
  }

  Widget _buildRealOrderItem(Map<String, dynamic> order) {
    final item = (order['items'] as List).first;
    final product = item['product'];
    final name =
        product is Map ? product['name']?.toString() ?? 'Item' : 'Item';
    final image =
        (product is Map && (product['images'] as List?)?.isNotEmpty == true)
            ? (product['images'] as List).first.toString()
            : '';
    final qty = item['quantity']?.toString() ?? '1';
    final status = order['status']?.toString() ?? 'Pending';
    final isDelivered = status.toLowerCase() == 'delivered';
    final weightLabel =
        (item['weightLabel'] ?? item['weight_label'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image.isNotEmpty
                  ? Image.network(image,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder)
                  : _imagePlaceholder),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('$name${weightLabel.isNotEmpty ? " ($weightLabel)" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Qty $qty • Real-time Status: $status',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12))
              ])),
          GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => OrderTrackingPage(order: order))),
              child: const Text('Track',
                  style: TextStyle(
                      color: Color(0xFF68B92E),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: TextDecoration.underline))),
          const SizedBox(width: 12),
          Icon(isDelivered ? Icons.check_circle : Icons.radio_button_checked,
              color: const Color(0xFF68B92E)),
        ],
      ),
    );
  }

  Widget _buildDeliveryItem(UserSubscription sub, {bool isPaused = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: sub.productImage.isNotEmpty
                  ? Image.network(sub.productImage,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder)
                  : _imagePlaceholder),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    '${sub.productName}${sub.weightLabel != null && sub.weightLabel!.isNotEmpty ? " (${sub.weightLabel})" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Qty ${sub.quantity} • ${sub.frequency}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12))
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300)),
              child: Text(isPaused ? 'VACATION' : 'PENDING',
                  style: TextStyle(
                      color: isPaused ? Colors.amber : Colors.grey,
                      fontSize: 9,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget get _imagePlaceholder => Container(
      width: 50,
      height: 50,
      color: const Color(0xFFE8F5E9),
      child: const Icon(Icons.set_meal, color: Color(0xFF68B92E), size: 24));

  Widget _buildVacationButton(List<UserSubscription> subs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final hasMultiDayVacation = subs.any((s) => s.vacationDates.any(
        (d) => !d.isBefore(today) && !AppDateUtils.isSameDay(d, tomorrow)));

    return GestureDetector(
      onTap: () => hasMultiDayVacation
          ? _handleStopVacation(subs)
          : _handleVacationSelection(subs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: hasMultiDayVacation
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasMultiDayVacation
                    ? Colors.orange.withValues(alpha: 0.4)
                    : const Color(0xFF68B92E).withValues(alpha: 0.4))),
        child: Row(children: [
          Text(hasMultiDayVacation ? '🏝️ ' : '🏖️ ',
              style: const TextStyle(fontSize: 12)),
          Text(hasMultiDayVacation ? 'Stop Vacation' : 'Set Vacation',
              style: TextStyle(
                  color: hasMultiDayVacation
                      ? const Color(0xFFE65100)
                      : const Color(0xFF114F3B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold))
        ]),
      ),
    );
  }

  Future<void> _handleStopVacation(List<UserSubscription> subs) async {
    final firstAllowed = AppDateUtils.getFirstAllowedDate();
    final allVacationDates = <DateTime>{};
    for (var s in subs) {
      for (var d in s.vacationDates) {
        // Normalize to midnight to ensure comparison works with backend ISO strings
        allVacationDates.add(DateTime(d.year, d.month, d.day));
      }
    }

    final resumableDates =
        allVacationDates.where((d) => !d.isBefore(firstAllowed)).toList();
    resumableDates.sort((a, b) => a.compareTo(b));

    if (resumableDates.isEmpty) {
      _showSnackBar(
          'No future vacation dates to stop. Tomorrow is already locked (Past 8 PM).',
          backgroundColor: Colors.orange);
      return;
    }

    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Resume Deliveries?'),
                content: Text(
                    'This will resume orders from ${AppDateUtils.formatDate(resumableDates.first)} onwards.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep Vacation')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Resume Now',
                          style: TextStyle(fontWeight: FontWeight.bold)))
                ]));

    if (confirm == true && mounted) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()));
      try {
        final dateStrings =
            resumableDates.map((d) => AppDateUtils.formatDate(d)).toList();
        final success = await ref
            .read(subscriptionServiceProvider)
            .updateAllVacationDate(dateStrings, 'remove');

        if (mounted) {
          Navigator.pop(context); // Remove loader
          if (success) {
            _showSnackBar('Vacation stopped! Resuming deliveries.',
                backgroundColor: Colors.green);
            ref.invalidate(mySubscriptionsProvider);
          } else {
            _showSnackBar('Failed to stop vacation. Please try again.',
                backgroundColor: Colors.red);
          }
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showSnackBar('Error: $e', backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _handleVacationSelection(List<UserSubscription> subs) async {
    final firstAllowed = AppDateUtils.getFirstAllowedDate();
    final range = await showDateRangePicker(
        context: context,
        firstDate: firstAllowed,
        lastDate: DateTime.now().add(const Duration(days: 365)));

    if (range != null && mounted) {
      final List<String> dates = [];
      DateTime current = range.start;
      while (!current.isAfter(range.end)) {
        dates.add(AppDateUtils.formatDate(current));
        current = current.add(const Duration(days: 1));
      }

      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Confirm Vacation'),
                  content: Text('Set for ${dates.length} days?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm'))
                  ]));

      if (confirm == true && mounted) {
        showDialog(
            context: context,
            builder: (_) => const Center(child: CircularProgressIndicator()));
        try {
          final success = await ref
              .read(subscriptionServiceProvider)
              .updateAllVacationDate(dates, 'add');
          if (mounted) {
            Navigator.pop(context);
            if (success) {
              _showSnackBar('Vacation scheduled successfully!',
                  backgroundColor: Colors.green);
              ref.invalidate(mySubscriptionsProvider);
            } else {
              _showSnackBar('Failed to set vacation.',
                  backgroundColor: Colors.red);
            }
          }
        } catch (e) {
          if (mounted) Navigator.pop(context);
          _showSnackBar('Error: $e', backgroundColor: Colors.red);
        }
      }
    }
  }

  Widget _buildPauseTomorrowButton(List<UserSubscription> subs) {
    if (subs.isEmpty) return const SizedBox.shrink();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isPast8PM = AppDateUtils.isPastCutOff();
    final isPaused = subs.every((s) =>
        s.status.toLowerCase() == 'paused' ||
        s.vacationDates.any((d) => AppDateUtils.isSameDay(d, tomorrow)));

    if (isPaused) {
      return GestureDetector(
        onTap: () => _resumeTomorrowBulkSkip(subs),
        child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('Resume Tomorrow',
                style: TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 11,
                    fontWeight: FontWeight.bold))),
      );
    }

    return GestureDetector(
      onTap: () =>
          isPast8PM ? _showPast8PMAlert(context) : _pauseTomorrowBulkSkip(subs),
      child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: isPast8PM ? Colors.grey.shade100 : const Color(0xFFEBFFD7),
              borderRadius: BorderRadius.circular(10)),
          child: Text('Pause Tomorrow',
              style: TextStyle(
                  color: isPast8PM ? Colors.grey : Color(0xFF2E7D32),
                  fontSize: 11,
                  fontWeight: FontWeight.bold))),
    );
  }

  void _showPast8PMAlert(BuildContext context) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Past 8 PM'),
                content: const Text('Too late for tomorrow.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'))
                ]));
  }

  Future<void> _pauseTomorrowBulkSkip(List<UserSubscription> subs) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowStr = AppDateUtils.formatDate(tomorrow);
    showDialog(
        context: context,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await ref
          .read(subscriptionServiceProvider)
          .updateAllVacationDate([tomorrowStr], 'add');
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(mySubscriptionsProvider);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _resumeTomorrowBulkSkip(List<UserSubscription> subs) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowStr = AppDateUtils.formatDate(tomorrow);
    showDialog(
        context: context,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await ref
          .read(subscriptionServiceProvider)
          .updateAllVacationDate([tomorrowStr], 'remove');
      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(mySubscriptionsProvider);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _buildYourPlans(List<UserSubscription> subs) {
    final activeOrPaused = subs
        .where((s) =>
            s.status.toLowerCase() == 'active' ||
            s.status.toLowerCase() == 'paused')
        .toList();
    final isVacationOn = activeOrPaused.isNotEmpty &&
        activeOrPaused.every((s) => s.status.toLowerCase() == 'paused');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Your Plans',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          GestureDetector(
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.mySubscriptions),
              child: const Text('View All →',
                  style: TextStyle(
                      color: Color(0xFF68B92E),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)))
        ]),
        const SizedBox(height: 15),
        ...activeOrPaused.map(
            (sub) => _PlanItemWidget(sub: sub, isVacationOn: isVacationOn)),
      ],
    );
  }
}

class _PlanItemWidget extends ConsumerStatefulWidget {
  final UserSubscription sub;
  final bool isVacationOn;
  const _PlanItemWidget({required this.sub, this.isVacationOn = false});
  @override
  ConsumerState<_PlanItemWidget> createState() => _PlanItemWidgetState();
}

class _PlanItemWidgetState extends ConsumerState<_PlanItemWidget> {
  bool? _optimisticIsActive;
  @override
  Widget build(BuildContext context) {
    final status = widget.sub.status;
    final isActive = _optimisticIsActive ?? (status == 'Active');
    final accentColor = isActive ? const Color(0xFF68B92E) : Colors.orange;

    return Slidable(
      key: ValueKey(widget.sub.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (context) async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel Subscription?'),
                  content: const Text('Are you sure you want to completely cancel this subscription?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );

              if (confirm == true) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.accentGreen)),
                );
                
                final success = await ref.read(subscriptionServiceProvider).cancelSubscription(widget.sub.id);
                if (mounted) Navigator.pop(context); // Remove loader

                if (success) {
                  ref.invalidate(mySubscriptionsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Subscription cancelled successfully'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            backgroundColor: const Color(0xFFFE4A49),
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Cancel',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isActive
                    ? const Color(0xFF68B92E).withValues(alpha: 0.15)
                    : Colors.grey.shade200,
                width: 1.5)),
        child: Row(
          children: [
            Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(15)),
                clipBehavior: Clip.antiAlias,
                child: widget.sub.productImage.isNotEmpty
                    ? Image.network(widget.sub.productImage, fit: BoxFit.cover)
                    : const Icon(Icons.set_meal, color: Color(0xFF68B92E))),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.sub.productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(widget.sub.frequency,
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(),
                          style: TextStyle(
                              color: accentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)))
                ])),
            Switch(
              value: isActive,
              activeThumbColor: const Color(0xFF68B92E),
              activeTrackColor: const Color(0xFF68B92E).withValues(alpha: 0.3),
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade200,
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF68B92E).withValues(alpha: 0.5);
                }
                return Colors.grey.shade300;
              }),
              onChanged: (val) async {
                setState(() => _optimisticIsActive = val);
                final ok = await ref
                    .read(subscriptionServiceProvider)
                    .updateStatus(widget.sub.id, val ? 'Active' : 'Paused');
                if (ok) {
                  ref.invalidate(mySubscriptionsProvider);
                } else {
                  setState(() => _optimisticIsActive = null);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
