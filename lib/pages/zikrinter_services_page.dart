// lib/pages/zikrinter_services_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_colors.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ZikrinterServicesPage extends StatefulWidget {
  final String shopId;

  const ZikrinterServicesPage({super.key, required this.shopId});

  @override
  State<ZikrinterServicesPage> createState() => _ZikrinterServicesPageState();
}

class _ZikrinterServicesPageState extends State<ZikrinterServicesPage> with AutomaticKeepAliveClientMixin<ZikrinterServicesPage> {
  @override
  bool get wantKeepAlive => true;

  bool _autoOpened = false;

  List<dynamic> _services = [];
  Map<String, dynamic> _shopData = {};
  bool _isLoading = true;
  StreamSubscription? _versionSubscription;

  void _listenToServiceVersion() {
    _fetchServicesAndPricing();
    _versionSubscription = FirebaseFirestore.instanceFor(app: Firebase.app('psfc'))
        .collection('shops')
        .doc('serviceVersion')
        .snapshots()
        .listen((doc) {
      _fetchServicesAndPricing();
    }, onError: (err) {
      debugPrint("Error listening to serviceVersion: $err");
    });
  }

  Future<void> _fetchServicesAndPricing() async {
    try {
      final response = await http.get(Uri.parse('${dotenv.env['BACKEND_URL'] ?? "https://zikrint.duckdns.org"}/api/shop/services?shopId=${widget.shopId}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _services = data['services'] ?? [];
            _shopData = data['shop'] ?? {};
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading services: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _listenToServiceVersion();
  }

  @override
  void dispose() {
    _versionSubscription?.cancel();
    super.dispose();
  }

  bool _isSizePricingMissing(String size, Map<String, dynamic> globalParams, Map<String, dynamic>? shopConfig) {
    final sizeKey = size.toLowerCase();
    if (shopConfig == null || shopConfig['isEnabled'] != true) return false;

    final bwSingleGlobal = globalParams['${sizeKey}_bw_singleSide'] ?? globalParams['bw_singleSide'] ?? {};
    final colorSingleGlobal = globalParams['${sizeKey}_color_singleSide'] ?? globalParams['color_singleSide'] ?? {};
    
    final bool isBwEnabledGlobally = bwSingleGlobal['isEnabled'] == true || globalParams['bw_singleSide']?['isEnabled'] == true;
    final bool isColorEnabledGlobally = colorSingleGlobal['isEnabled'] == true || globalParams['color_singleSide']?['isEnabled'] == true;

    final sizeConfig = shopConfig['paperSizes']?[sizeKey];
    if (sizeConfig != null) {
      final bwPrice = (sizeConfig['bw']?['singleSidePrice'] ?? 0.0) as num;
      final colorPrice = (sizeConfig['color']?['singleSidePrice'] ?? 0.0) as num;
      
      final bool isBwMissing = isBwEnabledGlobally && bwPrice <= 0.0;
      final bool isColorMissing = isColorEnabledGlobally && colorPrice <= 0.0;
      return isBwMissing || isColorMissing;
    }

    final bwPriceFlat = (shopConfig['${sizeKey}_bw_singleSidePrice'] ?? 0.0) as num;
    final colorPriceFlat = (shopConfig['${sizeKey}_color_singleSidePrice'] ?? 0.0) as num;
    
    if (sizeKey == 'a4') {
      final bwPriceA4 = (shopConfig['bw_singleSidePrice'] ?? 0.0) as num;
      final colorPriceA4 = (shopConfig['color_singleSidePrice'] ?? shopConfig['singleSidePrice'] ?? 0.0) as num;
      
      final bool isBwMissing = isBwEnabledGlobally && bwPriceA4 <= 0.0 && bwPriceFlat <= 0.0;
      final bool isColorMissing = isColorEnabledGlobally && colorPriceA4 <= 0.0 && colorPriceFlat <= 0.0;
      return isBwMissing || isColorMissing;
    }

    final bool isBwMissing = isBwEnabledGlobally && bwPriceFlat <= 0.0;
    final bool isColorMissing = isColorEnabledGlobally && colorPriceFlat <= 0.0;
    return isBwMissing || isColorMissing;
  }

  List<String> _getPendingPaperSizes(Map<String, dynamic> globalParams, Map<String, dynamic>? shopConfig) {
    final List<String> paperSizes = List<String>.from(globalParams['paperSizes'] ?? ['A4']);
    final List<String> pending = [];
    for (final size in paperSizes) {
      if (_isSizePricingMissing(size, globalParams, shopConfig)) {
        pending.add(size);
      }
    }
    return pending;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Zikrinter Services', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            tooltip: 'Sign Out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : () {
              final zikrinterServices = _shopData['zikrinterServices'] as Map<String, dynamic>? ?? {};
              final docs = _services;

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text('No active services registered on the platform.', textAlign: TextAlign.center),
                  ),
                );
              }

              String? docXeroxId;
              for (final d in docs) {
                final name = (d as Map<String, dynamic>)['name']?.toString().toLowerCase().trim() ?? '';
                if (name == 'documents (xerox)' || name == 'documents' || name == 'xerox') {
                  docXeroxId = d['id'];
                  break;
                }
              }

              bool requiredConfigured = false;
              if (docXeroxId != null) {
                final config = zikrinterServices[docXeroxId] as Map<String, dynamic>?;
                if (config != null && config['isEnabled'] == true) {
                  final paperSizes = List<String>.from(config['paperSizes']?.keys ?? []);
                  if (paperSizes.isNotEmpty) {
                    requiredConfigured = true;
                  } else {
                    final colorPrice = (config['color_singleSidePrice'] ?? config['singleSidePrice'] ?? 0.0) as num;
                    final bwPrice = (config['bw_singleSidePrice'] ?? 0.0) as num;
                    if (colorPrice > 0.0 || bwPrice > 0.0) {
                      requiredConfigured = true;
                    }
                  }
                }
              }

              if (!requiredConfigured && docXeroxId != null && !_autoOpened) {
                _autoOpened = true;
                final targetDoc = docs.firstWhere((d) => d['id'] == docXeroxId);
                final targetData = targetDoc as Map<String, dynamic>;
                final rawTargetName = targetData['name'] ?? 'Xerox';
                final targetName = (rawTargetName.toString().toLowerCase().trim() == 'xerox' || rawTargetName.toString().toLowerCase().trim() == 'documents')
                    ? 'Documents (Xerox)'
                    : rawTargetName;
                final targetConfig = zikrinterServices[docXeroxId] as Map<String, dynamic>?;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showConfigureBottomSheet(
                    context,
                    docXeroxId!,
                    targetName,
                    targetData,
                    targetConfig,
                  );
                });
              }

              return Column(
                children: [
                  if (!requiredConfigured)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Please configure pricing for 'Documents (Xerox)' service to activate your captain dashboard.",
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final serviceDoc = docs[index] as Map<String, dynamic>;
                        final serviceId = serviceDoc['id'];
                        final serviceData = serviceDoc;
                        final rawName = serviceData['name'] ?? 'Printing Service';
                        final name = (rawName.toString().toLowerCase().trim() == 'xerox' || rawName.toString().toLowerCase().trim() == 'documents')
                            ? 'Documents (Xerox)'
                            : rawName;
                        final images = List<String>.from(serviceData['images'] ?? []);
                        final List<String> paperSizesList = List<String>.from(serviceData['paperSizes'] ?? ['A4']);

                        final shopConfig = zikrinterServices[serviceId] as Map<String, dynamic>?;
                        final isEnabled = shopConfig?['isEnabled'] == true;

                        final isDocumentsXerox = serviceId == 'ZHwQd18Vy08TZkyBFXjB' ||
                            name.toString().toLowerCase().trim() == 'documents (xerox)' ||
                            name.toString().toLowerCase().trim() == 'documents(xerox)';

                        // Identify missing sizes
                        final pendingSizes = isEnabled ? _getPendingPaperSizes(serviceData, shopConfig) : <String>[];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isEnabled ? const Color(0xFF2E7D32).withOpacity(0.4) : Colors.grey.withOpacity(0.1),
                              width: isEnabled ? 2 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        color: isDocumentsXerox ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                        child: isDocumentsXerox
                                            ? Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 28),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Inbuilt',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.blueAccent,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : (images.isNotEmpty
                                                ? Image.network(
                                                    images.first,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.grey),
                                                  )
                                                : const Icon(Icons.image, color: Colors.grey)),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isEnabled
                                                  ? const Color(0xFF2E7D32).withOpacity(0.1)
                                                  : Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isEnabled ? 'Active' : 'Inactive',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: isEnabled ? const Color(0xFF2E7D32) : Colors.grey,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                
                                if (isEnabled) ...[
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your Shop Pricing (${paperSizesList.join(", ").toUpperCase()}):',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textTertiary),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // Show pricing for each size
                                  ...paperSizesList.map((size) {
                                    final sizeKey = size.toLowerCase();
                                    final sizeConfig = shopConfig?['paperSizes']?[sizeKey];
                                    
                                    double? bwPrice;
                                    double? colorPrice;
                                    
                                    if (sizeConfig != null) {
                                      bwPrice = (sizeConfig['bw']?['singleSidePrice'] ?? 0.0) as double;
                                      colorPrice = (sizeConfig['color']?['singleSidePrice'] ?? 0.0) as double;
                                    } else {
                                      // flat fallback
                                      bwPrice = (shopConfig?['${sizeKey}_bw_singleSidePrice'] ?? 0.0) as double;
                                      colorPrice = (shopConfig?['${sizeKey}_color_singleSidePrice'] ?? 0.0) as double;
                                      
                                      if (sizeKey == 'a4') {
                                        bwPrice = (shopConfig?['bw_singleSidePrice'] ?? bwPrice) as double;
                                        colorPrice = (shopConfig?['color_singleSidePrice'] ?? shopConfig?['singleSidePrice'] ?? colorPrice) as double;
                                      }
                                    }
                                    
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('${size.toUpperCase()} (B&W / Color)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                          Text(
                                            (bwPrice > 0 || colorPrice > 0)
                                                ? '₹${bwPrice.toStringAsFixed(1)} / ₹${colorPrice.toStringAsFixed(1)}'
                                                : 'Pricing Pending',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: (bwPrice > 0 || colorPrice > 0) ? AppColors.primaryBlue : Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],

                                // 🟢 Banner for newly added paper sizes requiring setup
                                if (pendingSizes.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded, color: Colors.green, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '🟢 New Paper Sizes Added',
                                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${pendingSizes.length} paper size(s) (${pendingSizes.join(", ").toUpperCase()}) require pricing before customers can place orders.',
                                                style: GoogleFonts.inter(fontSize: 12, color: Colors.green.shade800),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () => _showConfigureBottomSheet(
                                            context, 
                                            serviceId, 
                                            name, 
                                            serviceData, 
                                            shopConfig,
                                            pendingSizes: pendingSizes,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            minimumSize: const Size(80, 36),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                          ),
                                          child: Text('Configure', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () => _showConfigureBottomSheet(context, serviceId, name, serviceData, shopConfig),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isEnabled ? AppColors.primaryBlue : Colors.grey[200],
                                    foregroundColor: isEnabled ? Colors.white : AppColors.textPrimary,
                                    elevation: 0,
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text(isEnabled ? 'Edit Pricing' : 'Configure & Enable'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }(),
    );
  }

  Future<void> _showConfigureBottomSheet(
    BuildContext context,
    String serviceId,
    String serviceName,
    Map<String, dynamic> serviceData,
    Map<String, dynamic>? existingShopConfig, {
    List<String>? pendingSizes,
  }) async {
    print('DEBUG: [Edit Pricing Clicked]');
    print('DEBUG:   Service ID: $serviceId');
    print('DEBUG:   Service Name: $serviceName');
    print('DEBUG:   Existing Config: $existingShopConfig');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ServiceConfigureSheet(
          shopId: widget.shopId,
          serviceId: serviceId,
          serviceName: serviceName,
          serviceData: serviceData,
          existingShopConfig: existingShopConfig,
          shopServicesConfig: _shopData['zikrinterServices'],
          pendingSizes: pendingSizes,
        );
      },
    );
    setState(() => _isLoading = true);
    await _fetchServicesAndPricing();
  }
}

class _ServiceConfigureSheet extends StatefulWidget {
  final String shopId;
  final String serviceId;
  final String serviceName;
  final Map<String, dynamic> serviceData;
  final Map<String, dynamic>? existingShopConfig;
  final Map<String, dynamic>? shopServicesConfig;
  final List<String>? pendingSizes;

  Map<String, dynamic> get globalParams => serviceData['parameters'] as Map<String, dynamic>? ?? {};

  const _ServiceConfigureSheet({
    required this.shopId,
    required this.serviceId,
    required this.serviceName,
    required this.serviceData,
    this.existingShopConfig,
    this.shopServicesConfig,
    this.pendingSizes,
  });

  @override
  State<_ServiceConfigureSheet> createState() => _ServiceConfigureSheetState();
}

class _ServiceConfigureSheetState extends State<_ServiceConfigureSheet> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  final TextEditingController _spiralController = TextEditingController();
  final TextEditingController _thermalController = TextEditingController();
  final TextEditingController _paperController = TextEditingController();

  bool _agreedToTerms = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _agreedToTerms = widget.existingShopConfig?['agreedToTerms'] == true;
    
    final existingBindings = widget.existingShopConfig?['bindings'] as Map<String, dynamic>? ?? {};
    _spiralController.text = (existingBindings['spiral'] ?? '').toString();
    _thermalController.text = (existingBindings['thermal'] ?? '').toString();
    _paperController.text = (existingBindings['paper'] ?? '').toString();
  }

  TextEditingController _getController(String size, String paramKey) {
    final sizeKey = size.toLowerCase();
    if (!_controllers.containsKey(sizeKey)) {
      _controllers[sizeKey] = {};
    }

    if (!_controllers[sizeKey]!.containsKey(paramKey)) {
      final isProjectBinding = widget.serviceId == 'project_binding' || widget.serviceName.toLowerCase().contains('project');
      Map<String, dynamic> sourceConfig = widget.existingShopConfig ?? {};

      if (isProjectBinding) {
        if (sizeKey == 'a4') {
          // Documents (Xerox)
          sourceConfig = widget.shopServicesConfig?['ZHwQd18Vy08TZkyBFXjB'] as Map<String, dynamic>? ?? {};
        } else if (sizeKey.contains('bond')) {
          // Bond Paper Printing
          sourceConfig = widget.shopServicesConfig?['nyAKL7mMnGGkTx2Ow9HA'] as Map<String, dynamic>? ?? {};
        }
      }

      final lookupSizeKey = sizeKey.contains('bond') ? 'a4' : sizeKey;
      final paperSizeConfig = sourceConfig['paperSizes']?[lookupSizeKey] ?? {};
      dynamic value;

      if (paramKey == 'price') {
        value = paperSizeConfig['price'] ?? paperSizeConfig['color']?['singleSidePrice'] ?? paperSizeConfig['bw']?['singleSidePrice'];
        value ??= sourceConfig['${lookupSizeKey}_color_singleSidePrice'] ?? sourceConfig['${lookupSizeKey}_bw_singleSidePrice'];
      } else {
        final colorMode = paramKey.split('_')[0];
        final type = paramKey.split('_')[1];

        // Fetch nested value
        value = paperSizeConfig[colorMode]?[type == 'bulkPrinting' ? 'bulkPrintingPrice' : '${type}Price'];

        // Fallback to legacy flat prefixed key
        value ??= widget.existingShopConfig?['${sizeKey}_${colorMode}_${type}Price'] ?? 
                  widget.existingShopConfig?['${sizeKey}_${colorMode}_${type == 'bulkPrinting' ? 'bulkPrinting' : type}Price'];

        // A4 fallback
        if (value == null && sizeKey == 'a4') {
          if (colorMode == 'color') {
            if (type == 'singleSide') {
              value = widget.existingShopConfig?['color_singleSidePrice'] ??
                      widget.existingShopConfig?['singleSidePrice'];
            } else if (type == 'doubleSide') {
              value = widget.existingShopConfig?['color_doubleSidePrice'] ??
                      widget.existingShopConfig?['doubleSidePrice'];
            } else if (type == 'bulkPrinting') {
              value = widget.existingShopConfig?['color_bulkPrintingPrice'] ??
                      widget.existingShopConfig?['bulkPrintingPrice'];
            }
          } else {
            value = widget.existingShopConfig?['bw_${type}Price'] ??
                    widget.existingShopConfig?['bw_${type == 'bulkPrinting' ? 'bulkPrinting' : type}Price'];
          }
        }
      }

      _controllers[sizeKey]![paramKey] = TextEditingController(
        text: value?.toString() ?? '',
      );
    }

    return _controllers[sizeKey]![paramKey]!;
  }

  @override
  void dispose() {
    for (final sizeMap in _controllers.values) {
      for (final c in sizeMap.values) {
        c.dispose();
      }
    }
    _spiralController.dispose();
    _thermalController.dispose();
    _paperController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    print('DEBUG: [_submit] Save button clicked.');
    if (!_formKey.currentState!.validate()) {
      print('DEBUG: [_submit] Form validation failed.');
      return;
    }
    if (!_agreedToTerms) {
      print('DEBUG: [_submit] Agreed to terms is false. Blocking submit.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must agree to the terms and platform commission.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> pricingData = {};
      final List<String> paperSizes = List<String>.from(widget.serviceData['paperSizes'] ?? ['A4']);
      final List<String> sizesToSave = widget.pendingSizes ?? paperSizes;
      
      final isProjectBinding = widget.serviceId == 'project_binding' || widget.serviceName.toLowerCase().contains('project');
      Map<String, dynamic>? bindingsPricing;

      if (isProjectBinding) {
        // 1. Prepare bindings pricing
        final double spiralPrice = double.tryParse(_spiralController.text) ?? 0.0;
        final double thermalPrice = double.tryParse(_thermalController.text) ?? 0.0;
        final double paperPrice = double.tryParse(_paperController.text) ?? 0.0;
        bindingsPricing = {
          'spiral': spiralPrice,
          'thermal': thermalPrice,
          'paper': paperPrice,
        };

        print('DEBUG: [_submit] Project Binding service detected.');
        print('DEBUG:   Bindings pricing: $bindingsPricing');

        // 2. Save Project Binding (without paperSizes printing pricing)
        final Map<String, dynamic> payload = {
          'shopId': widget.shopId,
          'serviceId': widget.serviceId,
          'isEnabled': true,
          'pricingData': {},
          'bindingsPricing': bindingsPricing,
        };

        print('DEBUG: [_submit] Sending POST payload to backend: ${jsonEncode(payload)}');
        final response = await http.post(
          Uri.parse('${dotenv.env['BACKEND_URL'] ?? "https://zikrint.duckdns.org"}/api/shop/pricing'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        print('DEBUG: [_submit] Response status code: ${response.statusCode}');
        print('DEBUG: [_submit] Response body: ${response.body}');

        if (response.statusCode != 200) {
          throw Exception("Backend failed to save pricing: ${response.body}");
        }
      } else {
        print('DEBUG: [_submit] Normal service detected: ${widget.serviceName}');
        for (final size in sizesToSave) {
          final sizeKey = size.toLowerCase();

          final double colorSinglePrice = double.tryParse(_getController(size, 'color_singleSide').text) ?? 0.0;
          final double colorDoublePrice = double.tryParse(_getController(size, 'color_doubleSide').text) ?? 0.0;
          final double colorBulkPrice = double.tryParse(_getController(size, 'color_bulkPrinting').text) ?? 0.0;

          final double bwSinglePrice = double.tryParse(_getController(size, 'bw_singleSide').text) ?? 0.0;
          final double bwDoublePrice = double.tryParse(_getController(size, 'bw_doubleSide').text) ?? 0.0;
          final double bwBulkPrice = double.tryParse(_getController(size, 'bw_bulkPrinting').text) ?? 0.0;

          pricingData[sizeKey] = {
            'bw': {
              'singleSidePrice': bwSinglePrice,
              'doubleSidePrice': bwDoublePrice,
              'bulkPrintingPrice': bwBulkPrice,
            },
            'color': {
              'singleSidePrice': colorSinglePrice,
              'doubleSidePrice': colorDoublePrice,
              'bulkPrintingPrice': colorBulkPrice,
            }
          };
        }

        print('DEBUG: [_submit] Prepared pricingData: $pricingData');

        final Map<String, dynamic> payload = {
          'shopId': widget.shopId,
          'serviceId': widget.serviceId,
          'isEnabled': true,
          'pricingData': pricingData,
        };


        print('DEBUG: [_submit] Sending POST payload to backend: ${jsonEncode(payload)}');
        final response = await http.post(
          Uri.parse('${dotenv.env['BACKEND_URL'] ?? "https://zikrint.duckdns.org"}/api/shop/pricing'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        print('DEBUG: [_submit] Response status code: ${response.statusCode}');
        print('DEBUG: [_submit] Response body: ${response.body}');

        if (response.statusCode != 200) {
          throw Exception("Backend failed to save pricing: ${response.body}");
        }
      }

      print('DEBUG: [_submit] Success! Service configured successfully.');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service configured successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print('DEBUG: [_submit] ERROR occurred during submit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save configuration: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _disableService() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${dotenv.env['BACKEND_URL'] ?? "https://zikrint.duckdns.org"}/api/shop/pricing'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'shopId': widget.shopId,
          'serviceId': widget.serviceId,
          'isEnabled': false,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Backend failed to disable service: ${response.body}");
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service disabled successfully.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to disable service: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    final List<String> paperSizes = List<String>.from(widget.serviceData['paperSizes'] ?? ['A4']);
    final List<String> sizesToDisplay = widget.pendingSizes ?? paperSizes;
    final isProjectBinding = widget.serviceId == 'project_binding' || widget.serviceName.toLowerCase().contains('project');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.pendingSizes != null ? 'Configure New Paper Sizes' : 'Configure ${widget.serviceName}',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                widget.pendingSizes != null 
                    ? 'Enter pricing for newly added paper sizes to activate them.'
                    : 'Set the prices you want to charge your customers. Platform commissions will be automatically deducted.',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Render sizes
              if (isProjectBinding) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  elevation: 0,
                  color: Colors.blue[50]!.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.blue[100]!),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Printing rates for A4 and Bond Paper (A4) are automatically fetched from your Xerox and Bond Paper Printing configurations.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  elevation: 0,
                  color: Colors.grey[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure Binding Rates',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryBlue),
                        ),
                        const SizedBox(height: 20),
                        _buildPriceInputField(
                          label: 'Spiral Binding Flat Price',
                          commissionValue: (widget.globalParams['spiral_binding']?['commission'] ?? 0.0).toDouble(),
                          commissionType: widget.globalParams['spiral_binding']?['commissionType'] as String?,
                          controller: _spiralController,
                        ),
                        const SizedBox(height: 20),
                        _buildPriceInputField(
                          label: 'Thermal Binding Flat Price',
                          commissionValue: (widget.globalParams['thermal_binding']?['commission'] ?? 0.0).toDouble(),
                          commissionType: widget.globalParams['thermal_binding']?['commissionType'] as String?,
                          controller: _thermalController,
                        ),
                        const SizedBox(height: 20),
                        _buildPriceInputField(
                          label: 'Paper Binding Flat Price',
                          commissionValue: (widget.globalParams['paper_binding']?['commission'] ?? 0.0).toDouble(),
                          commissionType: widget.globalParams['paper_binding']?['commissionType'] as String?,
                          controller: _paperController,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                ...sizesToDisplay.map((size) {
                  final sizeKey = size.toLowerCase();

                  // Color Parameters
                  final colorSingleGlobal = widget.globalParams['${sizeKey}_color_singleSide'] ?? widget.globalParams['color_singleSide'] ?? {};
                  final colorDoubleGlobal = widget.globalParams['${sizeKey}_color_doubleSide'] ?? widget.globalParams['color_doubleSide'] ?? {};
                  final colorBulkGlobal = widget.globalParams['${sizeKey}_color_bulkPrinting'] ?? widget.globalParams['color_bulkPrinting'] ?? {};

                  // Black & White Parameters
                  final bwSingleGlobal = widget.globalParams['${sizeKey}_bw_singleSide'] ?? widget.globalParams['bw_singleSide'] ?? {};
                  final bwDoubleGlobal = widget.globalParams['${sizeKey}_bw_doubleSide'] ?? widget.globalParams['bw_doubleSide'] ?? {};
                  final bwBulkGlobal = widget.globalParams['${sizeKey}_bw_bulkPrinting'] ?? widget.globalParams['bw_bulkPrinting'] ?? {};

                  final colorSingleEnabled = colorSingleGlobal['isEnabled'] == true || widget.globalParams['color_singleSide']?['isEnabled'] == true;
                  final colorDoubleEnabled = colorDoubleGlobal['isEnabled'] == true || widget.globalParams['color_doubleSide']?['isEnabled'] == true;
                  final colorBulkEnabled = colorBulkGlobal['isEnabled'] == true || widget.globalParams['color_bulkPrinting']?['isEnabled'] == true;

                  final bwSingleEnabled = bwSingleGlobal['isEnabled'] == true || widget.globalParams['bw_singleSide']?['isEnabled'] == true;
                  final bwDoubleEnabled = bwDoubleGlobal['isEnabled'] == true || widget.globalParams['bw_doubleSide']?['isEnabled'] == true;
                  final bwBulkEnabled = bwBulkGlobal['isEnabled'] == true || widget.globalParams['bw_bulkPrinting']?['isEnabled'] == true;

                  final isPassportService = widget.serviceId == 'passport_photos' || widget.serviceName.toLowerCase().contains('passport');

                  if (isPassportService) {
                    final packageConfig = widget.globalParams['${sizeKey}_color_singleSide'] ?? {};
                    final commissionVal = (packageConfig['commission'] ?? 0.0).toDouble();
                    final commissionTypeStr = packageConfig['commissionType'] as String? ?? 'percentage';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      elevation: 0,
                      color: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$size Package Pricing',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryBlue),
                            ),
                            const SizedBox(height: 16),
                            _buildPriceInputField(
                              label: 'Cost for $size',
                              commissionValue: commissionVal,
                              commissionType: commissionTypeStr,
                              controller: _getController(size, 'color_singleSide'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 24),
                    elevation: 0,
                    color: Colors.grey[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${size.toUpperCase()} Sheet pricing',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryBlue),
                          ),
                          const SizedBox(height: 16),
                          
                          if (colorSingleEnabled || colorDoubleEnabled || colorBulkEnabled) ...[
                            const Text(
                              'Color Pricing (per page)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                            const SizedBox(height: 12),
                            if (colorSingleEnabled) ...[
                              _buildPriceInputField(
                                label: 'Single Side Price (Color)',
                                commissionValue: (colorSingleGlobal['commission'] ?? widget.globalParams['color_singleSide']?['commission'] ?? 0.0).toDouble(),
                                commissionType: colorSingleGlobal['commissionType'] ?? widget.globalParams['color_singleSide']?['commissionType'] as String?,
                                controller: _getController(size, 'color_singleSide'),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (colorDoubleEnabled) ...[
                              _buildPriceInputField(
                                label: 'Double Side Price (Color)',
                                commissionValue: (colorDoubleGlobal['commission'] ?? widget.globalParams['color_doubleSide']?['commission'] ?? 0.0).toDouble(),
                                commissionType: colorDoubleGlobal['commissionType'] ?? widget.globalParams['color_doubleSide']?['commissionType'] as String?,
                                controller: _getController(size, 'color_doubleSide'),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (colorBulkEnabled) ...[
                              _buildPriceInputField(
                                label: 'Bulk Printing Price (Color)',
                                commissionValue: (colorBulkGlobal['commission'] ?? widget.globalParams['color_bulkPrinting']?['commission'] ?? 0.0).toDouble(),
                                commissionType: colorBulkGlobal['commissionType'] ?? widget.globalParams['color_bulkPrinting']?['commissionType'] as String?,
                                controller: _getController(size, 'color_bulkPrinting'),
                                setPages: (colorBulkGlobal['setPages'] ?? widget.globalParams['color_bulkPrinting']?['setPages']) as int?,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          if (bwSingleEnabled || bwDoubleEnabled || bwBulkEnabled) ...[
                            const Divider(),
                            const SizedBox(height: 12),
                            const Text(
                              'Black & White Pricing (per page)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            if (bwSingleEnabled) ...[
                              _buildPriceInputField(
                                label: 'Single Side Price (B&W)',
                                commissionValue: (bwSingleGlobal['commission'] ?? widget.globalParams['bw_singleSide']?['commission'] ?? 0.0).toDouble(),
                                commissionType: bwSingleGlobal['commissionType'] ?? widget.globalParams['bw_singleSide']?['commissionType'] as String?,
                                controller: _getController(size, 'bw_singleSide'),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (bwDoubleEnabled) ...[
                              _buildPriceInputField(
                                label: 'Double Side Price (B&W)',
                                commissionValue: (bwDoubleGlobal['commission'] ?? widget.globalParams['bw_doubleSide']?['commission'] ?? 0.0).toDouble(),
                                commissionType: bwDoubleGlobal['commissionType'] ?? widget.globalParams['bw_doubleSide']?['commissionType'] as String?,
                                controller: _getController(size, 'bw_doubleSide'),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (bwBulkEnabled) ...[
                              _buildPriceInputField(
                                label: 'Bulk Printing Price (B&W)',
                                commissionValue: (bwBulkGlobal['commission'] ?? widget.globalParams['bw_bulkPrinting']?['commission'] ?? 0.0).toDouble(),
                                commissionType: bwBulkGlobal['commissionType'] ?? widget.globalParams['bw_bulkPrinting']?['commissionType'] as String?,
                                controller: _getController(size, 'bw_bulkPrinting'),
                                setPages: (bwBulkGlobal['setPages'] ?? widget.globalParams['bw_bulkPrinting']?['setPages']) as int?,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const Divider(),
              const SizedBox(height: 12),

              CheckboxListTile(
                value: _agreedToTerms,
                onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I accept the platform commission which will be paid by our service.',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  if (widget.existingShopConfig?['isEnabled'] == true && widget.pendingSizes == null) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading ? null : _disableService,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : const Text('Disable Service', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              widget.existingShopConfig?['isEnabled'] == true ? 'Save Changes' : 'Enable Now',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceInputField({
    required String label,
    required double commissionValue,
    String? commissionType,
    required TextEditingController controller,
    int? setPages,
  }) {
    final isPercent = commissionType == null || commissionType == 'percentage';
    final commissionText = isPercent
        ? '${commissionValue.toStringAsFixed(1)}% of fare'
        : '₹${commissionValue.toStringAsFixed(2)} fixed per page';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            prefixText: '₹ ',
            border: const OutlineInputBorder(),
            helperText: setPages != null
                ? 'Commission: $commissionText (Bulk threshold: $setPages pgs)'
                : 'Commission: $commissionText',
            helperStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return null; // Allow empty inputs
            }
            final amount = double.tryParse(value);
            if (amount == null) {
              return 'Please enter a valid numeric value';
            }
            if (amount < 0.0) {
              return 'Price must be non-negative';
            }
            return null;
          },
        ),
      ],
    );
  }
}
