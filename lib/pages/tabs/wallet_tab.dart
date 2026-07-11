import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/app_colors.dart';

class WalletTab extends StatefulWidget {
  final AppUser user;
  const WalletTab({super.key, required this.user});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> with AutomaticKeepAliveClientMixin<WalletTab> {
  @override
  bool get wantKeepAlive => true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _showWithdrawalForm(double currentBalance, Map<String, dynamic> shopData) {
    if (currentBalance < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Min withdrawal is ₹10! 🪙"),
          backgroundColor: Colors.orange));
      return;
    }

    final amountCtrl = TextEditingController(text: currentBalance.floor().toString());
    final upiNameCtrl = TextEditingController(text: shopData['upiName'] ?? '');
    final upiIdCtrl   = TextEditingController(text: shopData['upiId']   ?? '');
    final mobileCtrl  = TextEditingController(text: shopData['upiMobile'] ?? '');
    final shopRef     = _firestore.collection('shops').doc(widget.user.uid);

    String? selectedApp = shopData['upiApp'] ?? 'PhonePe';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool isLoading = false;

          bool isValid() =>
              (double.tryParse(amountCtrl.text) ?? 0) >= 10 &&
              (double.tryParse(amountCtrl.text) ?? 0) <= currentBalance &&
              upiNameCtrl.text.trim().isNotEmpty &&
              upiIdCtrl.text.trim().contains('@') &&
              mobileCtrl.text.trim().length == 10;

          Future<void> submit() async {
            setModal(() => isLoading = true);
            final amount = double.parse(amountCtrl.text);
            try {
              await _firestore.runTransaction((tx) async {
                final snap = await tx.get(shopRef);
                final live = ((snap.data() as Map)['walletBalance'] ?? 0.0).toDouble();
                if (live < amount) throw 'Insufficient balance';

                // Save UPI details for next time (do NOT deduct wallet yet)
                tx.update(shopRef, {
                  'upiName':   upiNameCtrl.text.trim(),
                  'upiId':     upiIdCtrl.text.trim(),
                  'upiMobile': mobileCtrl.text.trim(),
                  'upiApp':    selectedApp,
                });

                // Create withdrawal request — Zikrinter owner must APPROVE to deduct
                final reqRef = _firestore.collection('withdrawal_requests').doc();
                tx.set(reqRef, {
                  'requestId':  reqRef.id,
                  'shopId':     widget.user.uid,
                  'shopName':   shopData['shopName'] ?? 'Shop',
                  'upiApp':     selectedApp,
                  'upiName':    upiNameCtrl.text.trim(),
                  'upiId':      upiIdCtrl.text.trim(),
                  'upiMobile':  mobileCtrl.text.trim(),
                  'amount':     amount,
                  'status':     'pending',
                  'requestedAt': FieldValue.serverTimestamp(),
                });
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("✅ Withdrawal request raised!"),
                    backgroundColor: AppColors.success));
              }
            } catch (e) {
              setModal(() => isLoading = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Error: $e"),
                    backgroundColor: AppColors.error));
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF5F259F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.account_balance_wallet_rounded,
                              color: Color(0xFF5F259F), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Withdraw via UPI",
                                style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary)),
                            Text("Available: ₹${currentBalance.toStringAsFixed(2)}",
                                style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Amount field
                    _buildUpiField(amountCtrl, "Amount (₹)", Icons.payments_rounded,
                        isNumber: true, hint: "Min ₹10"),
                    const SizedBox(height: 16),

                    // UPI App selector
                    Text("UPI App",
                        style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textTertiary,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['PhonePe', 'Google Pay', 'Paytm', 'Other']
                          .map((app) => Expanded(
                                child: GestureDetector(
                                  onTap: () => setModal(() => selectedApp = app),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selectedApp == app
                                          ? const Color(0xFF5F259F)
                                          : AppColors.background,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selectedApp == app
                                            ? const Color(0xFF5F259F)
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      app == 'Google Pay' ? 'GPay' : app,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: selectedApp == app
                                              ? Colors.white
                                              : AppColors.textSecondary),
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    // UPI registered name
                    _buildUpiField(upiNameCtrl, "Name on UPI / Account Holder",
                        Icons.person_rounded,
                        hint: "e.g. Raju Pallapu"),
                    const SizedBox(height: 12),

                    // UPI ID
                    _buildUpiField(upiIdCtrl, "UPI ID",
                        Icons.alternate_email_rounded,
                        hint: "e.g. raju@ybl"),
                    const SizedBox(height: 12),

                    // Mobile number
                    _buildUpiField(mobileCtrl, "Mobile Number",
                        Icons.phone_android_rounded,
                        isNumber: true, hint: "10-digit number"),
                    const SizedBox(height: 24),

                    // Summary chip
                    if ((double.tryParse(amountCtrl.text) ?? 0) >= 10)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.green.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("You will receive",
                                style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700)),
                            Text("₹${amountCtrl.text}",
                                style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.green)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Raise Request button
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: (isLoading || !isValid()) ? null : submit,
                        icon: isLoading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isLoading ? "Submitting..." : "Raise Withdrawal Request",
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5F259F),
                          disabledBackgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUpiField(TextEditingController ctrl, String label, IconData icon,
      {bool isNumber = false, String? hint}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters:
            isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          icon: Icon(icon, color: const Color(0xFF5F259F), size: 20),
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textSecondary),
          hintStyle: GoogleFonts.manrope(
              fontSize: 12, color: AppColors.textTertiary),
          border: InputBorder.none,
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    super.build(context);
    final shopRef = _firestore.collection('shops').doc(widget.user.uid);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Earnings & Payouts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))),
      body: StreamBuilder<DocumentSnapshot>(
        stream: shopRef.snapshots(),
        builder: (context, shopSnapshot) {
          if (!shopSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final shopData = shopSnapshot.data?.data() as Map<String, dynamic>? ?? {};
          final balance = (shopData['walletBalance'] ?? 0.0).toDouble();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBalanceCard(balance, shopData),
                const SizedBox(height: 32),
                Text("Printing Stats", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatCard("B/W Pages", "${shopData['totalBwPages'] ?? 0}", Icons.print_rounded, Colors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard("Color Pages", "${shopData['totalColorPages'] ?? 0}", Icons.color_lens_rounded, Colors.orange)),
                  ],
                ),
                const SizedBox(height: 48),
                Center(
                  child: Text(
                    "Switch to INSIGHTS tab for full history", 
                    style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textTertiary)
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(double balance, Map<String, dynamic> shopData) {
    bool isWide = MediaQuery.of(context).size.width > 900;
    return Container(
      width: double.infinity, padding: EdgeInsets.all(isWide ? 40 : 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1E3A8A), Color(0xFF0056B3)], 
          begin: Alignment.topLeft, 
          end: Alignment.bottomRight
        ), 
        borderRadius: BorderRadius.circular(32), 
        boxShadow: [BoxShadow(color: AppColors.primaryBlue.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 15))]
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
                  const Text("Available Balance", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text("₹${balance.toStringAsFixed(2)}", style: GoogleFonts.inter(color: Colors.white, fontSize: isWide ? 48 : 38, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ],
              ),
              if (isWide) const Icon(Icons.account_balance_wallet_rounded, color: Colors.white30, size: 80),
            ],
          ),
          const SizedBox(height: 40),
          Align(
            alignment: isWide ? Alignment.centerLeft : Alignment.center,
            child: InkWell(
              onTap: () => _showWithdrawalForm(balance, shopData),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 48), 
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20), 
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))]
                ), 
                child: Text("Withdraw Funds", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.w900, fontSize: 15))
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: AppColors.surface, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ), 
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)), 
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5))
              ]
            ),
          ),
        ],
      )
    );
  }
}
