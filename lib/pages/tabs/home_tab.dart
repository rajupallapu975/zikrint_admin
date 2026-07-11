import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../zikrinter_services_page.dart';
// import 'package:firebase_messaging/firebase_messaging.dart'; // Unused
// import 'package:flutter/foundation.dart'; // Unnecessary

import '../image_viewer_page.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/api_service.dart';
import '../../utils/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import '../order_details_page.dart';
import '../../services/printer_service.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class HomeTab extends StatefulWidget {
  final AppUser user;
  final VoidCallback? onServicesTabRequested;
  const HomeTab({super.key, required this.user, this.onServicesTabRequested});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  final Set<String> _completedBatches = {};
  final Set<String> _expandedBatches = {};
  bool _isSubmitting = false; // 🛡️ Guard against double-tap on "PRINT DONE"

  Map<String, String> _serviceImages = {};

  Future<void> _loadServiceImages() async {
    try {
      final snapshot = await FirebaseFirestore.instanceFor(app: Firebase.app('zikrinter'))
          .collection('zikrinter')
          .get();
      final map = <String, String>{};
      for (final doc in snapshot.docs) {
        final name = (doc.data()['name'] as String? ?? '').toLowerCase().trim();
        final img = doc.data()['imageUrl'] as String? ?? '';
        if (img.isNotEmpty) {
          map[name] = img;
        }
      }
      if (mounted) {
        setState(() {
          _serviceImages = map;
        });
      }
    } catch (e) {
      debugPrint("Error loading service images: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _loadServiceImages();
  }


  @override
  Widget build(BuildContext context) {
    final shopRef = _firestore.collection('shops').doc(widget.user.uid);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Active Orders",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900, 
            fontSize: isDesktop ? 32 : 24,
            letterSpacing: -1
          )
        ),
        actions: [
          _buildQuickWallet(shopRef),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double horizontalPadding = constraints.maxWidth > 800 ? constraints.maxWidth * 0.1 : 16;
          
          return Column(
            children: [
              _buildServicesBanner(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: shopRef.collection('orders').snapshots(),
                  builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text("Sync Error: ${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ));
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      
                      final allDocs = snapshot.data?.docs.map((doc) => OrderModel.fromFirestore(doc)).toList() ?? [];

                      // 🛠️ ROBUST IN-MEMORY FILTERING
                      var orders = allDocs.where((o) {
                        final String orderStatus = (o.orderStatus ?? '').toLowerCase().trim();
                        final String paymentStatus = (o.paymentStatus ?? '').toLowerCase().trim();
                        
                        // 1. Must be Paid
                        final bool isPaid = paymentStatus == 'done' || paymentStatus == 'paid';
                        
                        // 2. Must not be completed or failed
                        final bool isActive = 
                          orderStatus != 'printing completed' && 
                          orderStatus != 'order completed' &&
                          orderStatus != 'hidden_failed' &&
                          orderStatus != 'refunded' &&
                          orderStatus != 'failed_processing';

                        return isPaid && isActive;
                      }).toList();

                      // 🛠️ SORT IN-MEMORY: First In, First Out (Ascending)
                      orders.sort((a, b) {
                        final aT = a.timestamp;
                        final bT = b.timestamp;
                        if (aT == null && bT == null) return 0;
                        if (aT == null) return 1;
                        if (bT == null) return -1;
                        return aT.compareTo(bT);
                      });

                      
                      Map<String, List<OrderModel>> grouped = {};
                      for (var o in orders) {
                        grouped.putIfAbsent(o.orderCode, () => []).add(o);
                      }
                      var sortedKeys = grouped.keys.toList();
                      if (_searchQuery.isNotEmpty) {
                        sortedKeys = sortedKeys.where((k) => k.contains(_searchQuery)).toList();
                      }

                      if (orders.isEmpty && _searchQuery.isEmpty) return _buildEmptyState();

                      return Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: AppColors.softShadow,
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (value) => setState(() => _searchQuery = value),
                                    decoration: const InputDecoration(
                                      hintText: "Search by OrderID (e.g. 6042)...",
                                      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                      border: InputBorder.none,
                                      icon: Icon(Icons.search_rounded, color: AppColors.primaryBlue, size: 20),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Text(
                                      _searchQuery.isEmpty ? "${sortedKeys.length} ACTIVE BATCHES" : "MATCHING BATCHES (${sortedKeys.length})",
                                      style: GoogleFonts.manrope(
                                        fontSize: 10, 
                                        fontWeight: FontWeight.w900, 
                                        color: AppColors.textTertiary,
                                        letterSpacing: 1
                                      )
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, gridConstraints) {
                                final isDesktopGrid = gridConstraints.maxWidth > 800;
                                final columns = gridConstraints.maxWidth > 1200 ? 3 : (isDesktopGrid ? 2 : 1);
                                
                                if (!isDesktopGrid) {
                                  return ListView.builder(
                                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                    itemCount: sortedKeys.length,
                                    itemBuilder: (context, index) {
                                      final mainId = sortedKeys[index];
                                      return _buildMainOrderGroup(mainId, grouped[mainId]!);
                                    },
                                  );
                                }

                                return SingleChildScrollView(
                                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: sortedKeys.map((mainId) {
                                      final items = grouped[mainId]!;
                                      final itemWidth = (gridConstraints.maxWidth - (horizontalPadding * 2) - (16 * (columns - 1))) / columns;
                                      return SizedBox(
                                        width: itemWidth - 1, 
                                        child: _buildMainOrderGroup(mainId, items),
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                   },
                 ),
               ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.print_disabled_rounded, size: 80, color: AppColors.border),
          const SizedBox(height: 16),
          Text("No active orders found", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildQuickWallet(DocumentReference shopRef) {
    return StreamBuilder<DocumentSnapshot>(
      stream: shopRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final balance = (data['walletBalance'] ?? 0.0).toDouble();
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              "₹${balance.toInt()}",
              style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainOrderGroup(String mainId, List<OrderModel> items) {
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final rawName = items.first.customerName;
    final String customerName = rawName.contains('@') ? rawName.split('@').first : rawName;
    final totalAmount = items.fold(0.0, (val, o) => val + o.amount);
    final int totalFiles = items.fold(0, (sum, o) => sum + (o.fileUrls.isNotEmpty ? o.fileUrls.length : 1));
    final bool isCompleted = _completedBatches.contains(mainId);
    final bool isExpanded = _expandedBatches.contains(mainId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isExpanded 
            ? AppColors.primaryBlue.withValues(alpha: 0.08) 
            : (isCompleted ? Colors.green.withValues(alpha: 0.05) : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isExpanded 
              ? AppColors.primaryBlue 
              : (isCompleted ? Colors.green.withValues(alpha: 0.3) : AppColors.border), 
            width: isExpanded ? 2.0 : 1.2
          ),
          boxShadow: isExpanded ? [BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))] : AppColors.softShadow,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey(mainId),
            onExpansionChanged: (val) {
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    if (val) _expandedBatches.add(mainId);
                    else _expandedBatches.remove(mainId);
                  });
                }
              });
            },
            initiallyExpanded: isExpanded,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Builder(
              builder: (context) {
                final String lookupKey = (items[0].serviceName ?? '').toLowerCase().trim();
                final String? imageUrl = _serviceImages[lookupKey];
                
                return Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isExpanded 
                      ? AppColors.primaryBlue.withValues(alpha: 0.1) 
                      : (isCompleted ? Colors.green.withValues(alpha: 0.1) : AppColors.primaryBlue.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isExpanded 
                        ? AppColors.primaryBlue.withValues(alpha: 0.2) 
                        : (isCompleted ? Colors.green.withValues(alpha: 0.2) : AppColors.border),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) => Icon(
                              Icons.print_rounded,
                              color: isExpanded ? AppColors.primaryBlue : AppColors.textSecondary,
                            ),
                          )
                        : Icon(
                            Icons.print_rounded,
                            color: isExpanded ? AppColors.primaryBlue : AppColors.textSecondary,
                          ),
                  ),
                );
              }
            ),
            title: Row(
              children: [
                // Pickup code badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isExpanded 
                      ? AppColors.primaryBlue 
                      : (isCompleted ? Colors.green : AppColors.primaryBlue.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    mainId, 
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900, 
                      fontSize: 14, 
                      color: (isExpanded || isCompleted) ? Colors.white : AppColors.primaryBlue
                    )
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        customerName.toUpperCase(), 
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900, 
                          fontSize: 15, 
                          color: isExpanded ? AppColors.primaryBlue : AppColors.textPrimary, 
                          letterSpacing: 0.5
                        )
                      ),
                      if (items[0].serviceName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          items[0].serviceName!.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryBlue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (items[0].customId != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isExpanded || isCompleted) ? Colors.white.withValues(alpha: 0.2) : AppColors.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      items[0].customId!.toUpperCase().replaceAll('_', ' '),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: (isExpanded || isCompleted) ? Colors.white : AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Row(
              children: [
                Text("$totalFiles File${totalFiles > 1 ? 's' : ''}", style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.bold, color: isExpanded ? AppColors.primaryBlue.withValues(alpha: 0.7) : AppColors.textSecondary)),
                const SizedBox(width: 8),
                Text("• ₹${totalAmount.toInt()}", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: isExpanded ? AppColors.primaryBlue : AppColors.primaryBlue)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    if (isCompleted) {
                      setState(() {
                        _completedBatches.remove(mainId);
                      });
                    } else {
                      _showMarkDoneDialog(mainId, items);
                    }
                  },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green : (isExpanded ? AppColors.primaryBlue.withValues(alpha: 0.1) : AppColors.background),
                      shape: BoxShape.circle,
                      border: Border.all(color: isCompleted ? Colors.green : (isExpanded ? AppColors.primaryBlue : AppColors.border), width: 2),
                    ),
                    child: Icon(
                      Icons.done_all_rounded, 
                      size: 24, 
                      color: isCompleted ? Colors.white : (isExpanded ? AppColors.primaryBlue : AppColors.textTertiary)
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: isExpanded ? AppColors.primaryBlue : AppColors.textTertiary,
                ),
              ],
            ),
             children: [
              const Divider(height: 1, indent: 20, endIndent: 20),
              Container(
                color: AppColors.background.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (items[0].serviceName != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: AppColors.primaryBlue, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "SERVICE: ${items[0].serviceName!.toUpperCase()}",
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primaryBlue,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    ..._buildFlattenedFileItems(mainId, items, isCompleted),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMarkDoneDialog(String mainId, List<OrderModel> items) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Mark Print Done?", style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        content: Text(
          "Are you sure you want to mark Order #$mainId as completely printed?\n\n"
          "Note: When your print is done and confirmed, it will move into the Completed / Pending history page.",
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              // 🛡️ Prevent double-tap from firing two concurrent API calls
              if (_isSubmitting) return;
              setState(() => _isSubmitting = true);

              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final String firstOrderId = items.isNotEmpty ? items.first.id : "";
              
              debugPrint("🔘 [ADMIN] Double Tick Clicked for Order: $mainId (DocID: $firstOrderId)");

              if (firstOrderId.isEmpty) {
                debugPrint("⚠️ [ADMIN] Error: No Order ID found for batch $mainId");
                setState(() => _isSubmitting = false);
                navigator.pop();
                return;
              }

              // 🚀 SHOW LOADING AS IT CALLS BACKEND
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
              );

              debugPrint("🛰️ [ADMIN] Sending 'Mark Printed' Request to Backend for $firstOrderId...");
              final String? errorMsg = await ApiService.markAsPrinted(firstOrderId, widget.user.uid);
              debugPrint("🔌 [ADMIN] Backend Response: ${errorMsg == null ? 'SUCCESS' : 'FAILURE: $errorMsg'}");
              
              if (mounted) {
                navigator.pop(); // Close loading spinner (top of stack)
                navigator.pop(); // Close confirm dialog
              }

              if (mounted) setState(() => _isSubmitting = false);

              if (errorMsg == null) {
                debugPrint("✨ [ADMIN] UI Updating: Batch $mainId marked as completed locally.");
                if (mounted) setState(() => _completedBatches.add(mainId));
                if (mounted) {
                  // 🛡️ Clear any queued snackbars before showing to prevent stacking
                  scaffoldMessenger.clearSnackBars();
                  scaffoldMessenger.showSnackBar(const SnackBar(
                    content: Text("✅ Print Sync Success! Customer notified."),
                    backgroundColor: Colors.green,
                  ));
                }
              } else {
                debugPrint("❌ [ADMIN] Sync failed for $firstOrderId: $errorMsg");
                if (mounted) {
                  scaffoldMessenger.clearSnackBars();
                  scaffoldMessenger.showSnackBar(SnackBar(
                    content: Text("❌ Sync Failed: $errorMsg"),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: Text("PRINT DONE", style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFlattenedFileItems(String mainId, List<OrderModel> items, bool isCompleted) {
    List<Widget> fileWidgets = [];
    int globalSubIdx = 1;
    final Set<String> processedDocIds = {};

    for (var order in items) {
      if (processedDocIds.contains(order.id)) continue;
      processedDocIds.add(order.id);

      if (order.fileUrls.isEmpty) {
        fileWidgets.add(_buildSubOrderItem(mainId, globalSubIdx++, order, isCompleted, fileIdx: 0));
      } else {
        for (int i = 0; i < order.fileUrls.length; i++) {
          fileWidgets.add(_buildSubOrderItem(mainId, globalSubIdx++, order, isCompleted, fileIdx: i));
        }
      }
    }
    return fileWidgets;
  }

  Widget _buildSubOrderItem(String mainId, int subIdx, OrderModel order, bool isCompleted, {required int fileIdx}) {
    final fileName = order.fileNames.length > fileIdx ? order.fileNames[fileIdx] : order.fileName;
    final fileUrl = order.fileUrls.length > fileIdx ? order.fileUrls[fileIdx] : order.fileUrl;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               if (order.orderStatus == 'printing completed')
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(fileName.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded, size: 16, color: fileName.toLowerCase().endsWith('.pdf') ? AppColors.error : AppColors.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final lowUrl = fileUrl?.toLowerCase() ?? "";
                    final lowName = fileName.toLowerCase();
                    String ext = "pdf";
                    if (lowUrl.contains(".jpg") || lowUrl.contains(".jpeg") || lowUrl.contains("format=jpg") || lowName.contains(".jpg") || lowName.contains(".jpeg")) {
                      ext = "jpg";
                    } else if (lowUrl.contains(".png") || lowUrl.contains("format=png") || lowName.contains(".png")) {
                      ext = "png";
                    }
                    return Text(
                      "${mainId}_$subIdx.$ext", 
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary), 
                      maxLines: 1, overflow: TextOverflow.ellipsis
                    );
                  }
                )
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _requirementBadge(order.getIsColor(fileIdx) ? "COLOR" : "B&W", order.getIsColor(fileIdx) ? Colors.orange : Colors.grey),
              _requirementBadge(order.getIsDuplex(fileIdx) ? "2-SIDED" : "1-SIDED", Colors.blue),
              _requirementBadge("${order.getCopies(fileIdx)} COPIES", Colors.purple),
              _requirementBadge(order.getOrientation(fileIdx).toUpperCase(), Colors.teal),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               if (!isCompleted && order.orderStatus != 'order completed') ...[
                  IconButton(
                    onPressed: () async {
                      final url = (order.viewUrls.length > fileIdx ? order.viewUrls[fileIdx] : order.fileUrls[fileIdx]) ?? "";
                      
                      if (url.isNotEmpty) {
                        try {
                           await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        } catch (e) {
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open preview: $e')));
                           }
                        }
                      }
                    },
                    icon: const Icon(Icons.visibility_rounded, color: AppColors.primaryBlue, size: 20),
                    tooltip: "Preview",
                  ),
                   IconButton(
                    onPressed: () async {
                       final url = (order.fileUrls.length > fileIdx ? order.fileUrls[fileIdx] : order.fileUrl) ?? "";
                       
                       if (url.isNotEmpty) {
                         try {
                           final backendUrl = dotenv.env['BACKEND_URL'] ?? 'https://zikrint.duckdns.org';
                           
                           // 🚀 BULLETPROOF: Force clean extension detection
                           String cleanExt = "pdf";
                           if (url.toLowerCase().contains(".jpg") || url.toLowerCase().contains(".jpeg") || url.toLowerCase().contains("format=jpg")) {
                              cleanExt = "jpg";
                           } else if (url.toLowerCase().contains(".png") || url.toLowerCase().contains("format=png")) {
                              cleanExt = "png";
                           }
                           
                           final downloadName = "${mainId}_$subIdx.$cleanExt";
                           
                           // 🚀 FORCE DOWNLOAD PROXY: Solves CORS and guarantees the final filename explicitly
                           final encodedUrl = Uri.encodeComponent(url);
                           final proxyUrl = "$backendUrl/proxy-download?url=$encodedUrl&filename=$downloadName";
                           
                           await launchUrl(Uri.parse(proxyUrl), mode: LaunchMode.externalApplication);
                         } catch (e) {
                           debugPrint('🔴 Download proxy failed: $e');
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not trigger download: $e')));
                           }
                         }
                       }
                    },
                    icon: const Icon(Icons.download_rounded, color: AppColors.primaryBlue, size: 20),
                    tooltip: "Download PDF/Image",
                  ),
                ],

            ],
          ),
        ],
      ),
    );
  }

  Widget _requirementBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12, 
          fontWeight: FontWeight.w900, 
          color: color, 
          letterSpacing: 0.8
        ),
      ),
    );
  }

  Widget _buildServicesBanner() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.primaryBlue.withOpacity(0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primaryBlue, width: 1),
      ),
      child: InkWell(
        onTap: () {
          if (widget.onServicesTabRequested != null) {
            widget.onServicesTabRequested!();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify & Enable Printing Services',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configure custom pricing for Bulk/Single/Double print services & agree to platform commission.',
                      style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primaryBlue),
            ],
          ),
        ),
      ),
    );
  }
}
