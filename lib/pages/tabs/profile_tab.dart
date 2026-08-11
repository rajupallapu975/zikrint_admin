import 'package:admin_zikrint/services/auth_service.dart';
import '../zikrinter_services_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../services/notification_service.dart';
import '../../models/app_user.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io' show File;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../../utils/web_helpers/web_download.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/map_location_picker_sheet.dart';

class ProfileTab extends StatefulWidget {
  final AppUser user;
  final Map<String, dynamic>? shopData;

  const ProfileTab({super.key, required this.user, this.shopData});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ScreenshotController screenshotController = ScreenshotController();
  bool _imageError = false;
  bool _updatingGPS = false;

  Future<void> _updateGPSLocation(BuildContext context) async {
    setState(() => _updatingGPS = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled on your device.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final uid = widget.user.uid;
      await FirebaseFirestore.instance.collection('shops').doc(uid).set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'location': GeoPoint(pos.latitude, pos.longitude),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ GPS Coordinates updated: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("GPS Update Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingGPS = false);
    }
  }

  void _showEditShopDetailsDialog(BuildContext context) {
    final nameController = TextEditingController(text: widget.shopData?['shopName'] ?? '');
    final addressController = TextEditingController(text: widget.shopData?['address'] ?? '');
    final pincodeController = TextEditingController(text: widget.shopData?['pincode'] ?? '');
    final mobileController = TextEditingController(text: widget.shopData?['mobile'] ?? '');

    double? selectedLat = (widget.shopData?['latitude'] as num?)?.toDouble();
    double? selectedLng = (widget.shopData?['longitude'] as num?)?.toDouble();

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Edit Shop Profile & Address",
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        "Update your shop address and contact information",
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Shop Name
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Shop Name',
                          prefixIcon: const Icon(Icons.store_rounded, color: AppColors.primaryBlue),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Address
                      TextField(
                        controller: addressController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Full Address',
                          alignLabelWithHint: true,
                          prefixIcon: const Icon(Icons.location_on_rounded, color: AppColors.primaryBlue),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await MapLocationPickerSheet.show(
                              context,
                              initialLatitude: selectedLat,
                              initialLongitude: selectedLng,
                            );
                            if (result != null) {
                              setModalState(() {
                                selectedLat = result.latitude;
                                selectedLng = result.longitude;
                                addressController.text = result.address;
                                if (result.pincode.isNotEmpty) {
                                  pincodeController.text = result.pincode;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.map_rounded, color: AppColors.primaryBlue),
                          label: Text(
                            selectedLat != null ? "PIN SET ON MAP (TAP TO CHANGE)" : "SELECT LOCATION ON MAP 🗺️",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.primaryBlue),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: pincodeController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Pincode',
                                prefixIcon: const Icon(Icons.pin_drop_rounded, color: AppColors.primaryBlue),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: mobileController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Mobile Number',
                                prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primaryBlue),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (addressController.text.trim().isEmpty || nameController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Shop Name and Address cannot be empty")),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);
                                  try {
                                    final updatedData = <String, dynamic>{
                                      'shopName': nameController.text.trim(),
                                      'address': addressController.text.trim(),
                                      'pincode': pincodeController.text.trim(),
                                      'mobile': mobileController.text.trim(),
                                      if (selectedLat != null && selectedLng != null) ...{
                                        'latitude': selectedLat,
                                        'longitude': selectedLng,
                                        'location': GeoPoint(selectedLat!, selectedLng!),
                                      },
                                    };

                                    final uid = widget.user.uid;
                                    await FirebaseFirestore.instance.collection('shops').doc(uid).set(
                                      updatedData,
                                      SetOptions(merge: true),
                                    );

                                    try {
                                      final psfcApp = Firebase.app('psfc');
                                      final psfcFirestore = FirebaseFirestore.instanceFor(app: psfcApp);
                                      await psfcFirestore.collection('users').doc(uid).set(
                                        updatedData,
                                        SetOptions(merge: true),
                                      );
                                    } catch (_) {}

                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("✅ Shop address and details updated!"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                      setState(() {});
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Save Error: $e"), backgroundColor: Colors.red),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) setModalState(() => isSaving = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isSaving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  "SAVE CHANGES",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: 1),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadQR(BuildContext context) async {
    try {
      final Uint8List? imageBytes = await screenshotController.capture();
      if (imageBytes == null) return;

      if (kIsWeb) {
        downloadBytes(imageBytes, "shop_qr_${widget.user.uid.substring(0, 5)}.png");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("QR Code downloaded!"), backgroundColor: Colors.green),
          );
        }
        return;
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Gallery permission denied")),
          );
          return;
        }
      }

      await Gal.putImageBytes(imageBytes, name: "shop_qr_${widget.user.uid.substring(0, 5)}");
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("QR Code saved to Gallery!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareQR(BuildContext context) async {
    try {
      final image = await screenshotController.capture();
      if (image != null) {
        if (!context.mounted) return;
        if (kIsWeb) {
          await _downloadQR(context);
          return;
        }

        final directory = await getTemporaryDirectory();
        final imageFile = await File('${directory.path}/shop_qr.png').create();
        await imageFile.writeAsBytes(image);
        
        await Share.shareXFiles([XFile(imageFile.path)], text: 'Scan this to visit my shop on Zikrint: ${widget.shopData?['shopName']}');
      }
    } catch (e) {
      debugPrint("Error sharing QR: $e");
    }
  }

  void _showQRCode(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text("Shop QR Identity", style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
              Text("Contains your unique Shop ID", style: GoogleFonts.manrope(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 32),
              
              Screenshot(
                controller: screenshotController,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          QrImageView(
                            data: 'zikrint-shop:${widget.user.uid}',
                            version: QrVersions.auto,
                            size: 220.0,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                            gapless: false,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Text(
                                "Zikrint",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: Colors.black,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Text(widget.shopData?['shopName'] ?? "Zikrint Shop", style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Text("Zikrint Services", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text("Contact: 9391392506", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadQR(context),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text("Save to Phone"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareQR(context),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text("Share"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text("DONE", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _syncCaptainAlertToken();
  }

  Future<void> _syncCaptainAlertToken() async {
    // 🛡️ Only sync if this is the master email
    if (widget.user.email == "rajuvarmaprintassistant@gmail.com") {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('admin_settings').doc('payout_alerts').set({
            'captain_fcm': token,
            'updatedBy': widget.user.email,
            'lastVerified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint("📡 Admin App synced Captain FCM for Payments: $token");
        }
      } catch (e) {
        debugPrint("❌ Captain Sync Error in Admin App: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shop Profile', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            onPressed: () => AuthService().signOut(),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 54,
              backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
              backgroundImage: (widget.user.photoURL != null && !_imageError) 
                  ? NetworkImage(widget.user.photoURL!) 
                  : null,
              onBackgroundImageError: (widget.user.photoURL != null && !_imageError) ? (exception, stackTrace) {
                if (mounted) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imageError = true);
                   });
                }
              } : null,
              child: (widget.user.photoURL == null || _imageError) 
                  ? Text(
                      (widget.shopData?['shopName'] ?? widget.user.email ?? 'C').substring(0, 1).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 42, 
                        fontWeight: FontWeight.w900, 
                        color: AppColors.primaryBlue
                      ),
                    ) 
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.shopData?['shopName'] ?? 'Captain Shop',
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5),
            ),
            Text(widget.user.email ?? '', style: GoogleFonts.manrope(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 32),
            
            ElevatedButton.icon(
              onPressed: () => _showQRCode(context),
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text("VIEW SHOP QR IDENTITY", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showEditShopDetailsDialog(context),
              icon: const Icon(Icons.edit_location_alt_rounded),
              label: const Text("EDIT ADDRESS & SHOP DETAILS", style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue, width: 2),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
            
            _buildNotificationStatusTile(),
            const Divider(height: 60),
            
            _buildProfileItem(
              Icons.phone,
              'Mobile',
              () {
                final m = widget.shopData?['mobile']?.toString();
                if (m == null || m.isEmpty) return 'N/A (Tap to edit)';
                var c = m.trim();
                if (c.startsWith('0')) c = c.substring(1).trim();
                if (!c.startsWith('+')) return '+91 $c (Tap to edit)';
                return '$c (Tap to edit)';
              }(),
              onTap: () => _showEditShopDetailsDialog(context),
            ),
            _buildProfileItem(Icons.login, 'Opens', widget.shopData?['openingTime']?.toString() ?? 'N/A'),
            _buildProfileItem(Icons.logout, 'Closes', widget.shopData?['closingTime']?.toString() ?? 'N/A'),
            _buildProfileItem(
              Icons.pin_drop,
              'Pincode',
              '${widget.shopData?['pincode']?.toString() ?? 'N/A'} (Tap to edit)',
              onTap: () => _showEditShopDetailsDialog(context),
            ),
            _buildProfileItem(
              Icons.location_on,
              'Location Address',
              '${widget.shopData?['address']?.toString() ?? 'N/A'} (Tap to edit)',
              onTap: () => _showEditShopDetailsDialog(context),
            ),
            _buildProfileItem(
              Icons.my_location_rounded,
              'GPS Coordinates',
              _updatingGPS
                  ? 'Capturing high-accuracy GPS location...'
                  : (() {
                      final lat = widget.shopData?['latitude'];
                      final lng = widget.shopData?['longitude'];
                      if (lat != null && lng != null) {
                        return '$lat, $lng (Tap to update)';
                      }
                      final loc = widget.shopData?['location'];
                      if (loc is GeoPoint) {
                        return '${loc.latitude}, ${loc.longitude} (Tap to update)';
                      }
                      return 'Not set (Tap to update GPS location)';
                    })(),
              onTap: () => _updateGPSLocation(context),
            ),
            _buildProfileItem(
              Icons.print_rounded,
              'Zikrinter Services',
              'View active service catalogs',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ZikrinterServicesPage(shopId: widget.user.uid),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 32),
            _buildSupportCenter(),
            const SizedBox(height: 60),

            // 🚪 PROMINENT LOGOUT BUTTON
            OutlinedButton.icon(
              onPressed: () => _showLogoutConfirmation(context),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text("SIGN OUT OF SESSION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withOpacity(0.2)),
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text("Sign Out?", style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        content: const Text("Are you sure you want to exit your shop manager session?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              AuthService().signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("SIGN OUT"),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportCenter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
                child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                "Support Center", 
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary)
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Need help with your shop or printer? Contact our technical team.",
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          _buildSupportAction(
            Icons.mail_outline_rounded, 
            "rajupallapu975@gmail.com", 
            () => launchUrl(Uri.parse("mailto:rajupallapu975@gmail.com"))
          ),
          const SizedBox(height: 12),
          _buildSupportAction(
            Icons.phone_in_talk_rounded, 
            "+91 9391392506", 
            () => launchUrl(Uri.parse("tel:+919391392506"))
          ),
        ],
      ),
    );
  }

  Widget _buildSupportAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primaryBlue),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationStatusTile() {
    return StreamBuilder<NotificationSettings>(
      stream: FirebaseMessaging.instance.onTokenRefresh.map((e) => e).asyncMap((e) => FirebaseMessaging.instance.getNotificationSettings()),
      initialData: null,
      builder: (context, snapshot) {
        return FutureBuilder<NotificationSettings>(
          future: FirebaseMessaging.instance.getNotificationSettings(),
          builder: (context, futureSnapshot) {
            final settings = futureSnapshot.data;
            final isDenied = settings?.authorizationStatus == AuthorizationStatus.denied || settings?.authorizationStatus == AuthorizationStatus.notDetermined;
            final isAuthorized = settings?.authorizationStatus == AuthorizationStatus.authorized || settings?.authorizationStatus == AuthorizationStatus.provisional;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isAuthorized ? AppColors.success.withOpacity(0.05) : AppColors.error.withOpacity(0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isAuthorized ? AppColors.success.withOpacity(0.2) : AppColors.error.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                   Row(
                    children: [
                      Icon(isAuthorized ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, color: isAuthorized ? AppColors.success : AppColors.error),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(isAuthorized ? "Background Alerts: Active" : "Background Alerts: Disabled", style: TextStyle(fontWeight: FontWeight.w900, color: isAuthorized ? AppColors.success : AppColors.error)),
                             Text(isAuthorized ? "You are receiving real-time order alerts." : "Enable notifications to get orders when app is closed.", style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                   ),
                   if (isDenied) ...[
                     const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () async {
                           await GlobalNotificationService().init(context, widget.user.uid);
                           await _syncCaptainAlertToken(); // Sync captain token after permission
                           if (context.mounted) setState(() {});
                        },
                       style: ElevatedButton.styleFrom(
                         backgroundColor: AppColors.error,
                         foregroundColor: Colors.white,
                         minimumSize: const Size(double.infinity, 50),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                       ),
                       child: const Text("ASK FOR PERMISSION", style: TextStyle(fontWeight: FontWeight.bold)),
                     ),
                   ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileItem(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primaryBlue, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
