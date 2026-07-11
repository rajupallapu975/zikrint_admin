import 'package:admin_zikrint/models/order_model.dart';
import 'package:admin_zikrint/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/history_service.dart';
import '../../models/app_user.dart';

class HistoryTab extends StatefulWidget {
  final AppUser user;
  const HistoryTab({super.key, required this.user});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> with AutomaticKeepAliveClientMixin<HistoryTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Order History",
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer<HistoryService>(
        builder: (context, service, _) {
          final orders = service.history;

          if (orders.isEmpty) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: DailyIncomeChart(history: const []),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded,
                            size: 64,
                            color: AppColors.textTertiary.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text("No orders yet",
                            style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text("Completed orders will appear here",
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Total shopkeeper earnings (after commission deducted)
          final totalEarned = orders.fold(0.0, (sum, o) => sum + o.printingCost);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              DailyIncomeChart(history: orders),
              const SizedBox(height: 16),
              // Summary row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${orders.length} ORDERS",
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        letterSpacing: 1.5),
                  ),
                  Row(
                    children: [
                      Text(
                        "NET ₹${totalEarned.toStringAsFixed(0)}",
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: Colors.green),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _confirmClear(context, service),
                        child: const Icon(Icons.delete_sweep_rounded,
                            size: 18, color: AppColors.error),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...orders.map((order) => _buildCompactCard(order)),
            ],
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context, HistoryService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear History?",
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text("This will permanently delete all order history."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              service.clearHistory(widget.user.uid);
            },
            child: const Text("Clear",
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCard(OrderModel order) {
    // Show shopkeeper's net payout (printingCost = amount after commission deducted)
    final double netAmount = order.printingCost > 0 ? order.printingCost : order.amount;
    final double grossAmount = order.amount;
    final double commission = order.platformCommission;
    final String service = order.serviceName ?? 'Documents';
    final String customer = order.customerName.contains('@')
        ? order.customerName.split('@').first
        : order.customerName;

    // Time formatting
    final t = order.timestamp;
    final timeStr =
        "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} "
        "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          // Green dot indicator
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Order code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              order.orderCode,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryBlue),
            ),
          ),
          const SizedBox(width: 10),
          // Customer + service
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "$service • ${order.bwPages + order.colorPages} pg • $timeStr",
                  style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Net payout — shown directly
          Text(
            "₹${netAmount.toStringAsFixed(0)}",
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.green),
          ),
        ],
      ),
    );
  }
}

class DailyIncomeChart extends StatelessWidget {
  final List<OrderModel> history;

  const DailyIncomeChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final Map<String, double> dailyData = {};
    final List<DateTime> last7Days = [];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      last7Days.add(date);
      final key = "${date.year}-${date.month}-${date.day}";
      dailyData[key] = 0.0;
    }

    // Use printingCost (net to shopkeeper, after commission)
    for (var order in history) {
      final collectedAt = order.timestamp;
      final key = "${collectedAt.year}-${collectedAt.month}-${collectedAt.day}";
      if (dailyData.containsKey(key)) {
        final earning = order.printingCost > 0 ? order.printingCost : order.amount;
        dailyData[key] = dailyData[key]! + earning;
      }
    }

    double maxIncome =
        dailyData.values.fold(0.0, (max, val) => val > max ? val : max);
    if (maxIncome == 0) maxIncome = 1.0;
    final total = dailyData.values.reduce((a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("DAILY INCOME",
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryBlue,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text("Last 7 Days",
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "₹${total.toInt()} earned",
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: last7Days.map((date) {
                final key = "${date.year}-${date.month}-${date.day}";
                final income = dailyData[key] ?? 0.0;
                final ratio = income / maxIncome;
                final barH = (ratio * 80).clamp(0.0, 80.0);
                final isToday = date.day == now.day &&
                    date.month == now.month &&
                    date.year == now.year;
                final dayLabel = _getDayName(date.weekday);

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (income > 0)
                        Text(
                          "₹${income.toInt()}",
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: isToday
                                  ? Colors.green
                                  : AppColors.primaryBlue),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        width: 20,
                        height: barH < 4 && income > 0 ? 4 : barH,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isToday
                                ? [Colors.green, Colors.green.withValues(alpha: 0.6)]
                                : [AppColors.primaryBlue, AppColors.primaryBlue.withValues(alpha: 0.5)],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(5),
                            topRight: Radius.circular(5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dayLabel,
                        style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isToday
                                ? Colors.green
                                : AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return "MON";
      case 2: return "TUE";
      case 3: return "WED";
      case 4: return "THU";
      case 5: return "FRI";
      case 6: return "SAT";
      case 7: return "SUN";
      default: return "";
    }
  }
}
