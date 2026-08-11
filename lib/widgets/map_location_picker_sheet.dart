import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_colors.dart';

class MapLocationPickerResult {
  final double latitude;
  final double longitude;
  final String address;
  final String pincode;

  MapLocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.pincode,
  });
}

class MapLocationPickerSheet extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const MapLocationPickerSheet({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  static Future<MapLocationPickerResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return showModalBottomSheet<MapLocationPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MapLocationPickerSheet(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
      ),
    );
  }

  @override
  State<MapLocationPickerSheet> createState() => _MapLocationPickerSheetState();
}

class _MapLocationPickerSheetState extends State<MapLocationPickerSheet> {
  late LatLng _selectedLocation;
  late MapController _mapController;
  bool _isLoading = true;
  bool _isGeocoding = false;
  String _address = "Locating address...";
  String _pincode = "";

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    
    // Default to Hyderabad or initial location
    final double defaultLat = widget.initialLatitude ?? 17.385044;
    final double defaultLng = widget.initialLongitude ?? 78.486671;
    _selectedLocation = LatLng(defaultLat, defaultLng);

    _initLocation();
  }

  Future<void> _initLocation() async {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      setState(() => _isLoading = false);
      _updateAddress(_selectedLocation);
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          _selectedLocation = LatLng(position.latitude, position.longitude);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
      _updateAddress(_selectedLocation);
    }
  }

  Future<void> _updateAddress(LatLng location) async {
    setState(() => _isGeocoding = true);
    try {
      if (!kIsWeb) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          final parts = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea
          ].where((p) => p != null && p.isNotEmpty).toList();

          if (mounted) {
            setState(() {
              _address = parts.join(', ');
              _pincode = place.postalCode ?? "";
              _isGeocoding = false;
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _address = "Coordinates: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}";
        _isGeocoding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: Colors.white,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.map_rounded, color: AppColors.primaryBlue, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECT SHOP LOCATION ON MAP',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Tap anywhere or drag the map to set your exact shop',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Map view
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _selectedLocation,
                          initialZoom: 16.5,
                          onTap: (tapPosition, point) {
                            setState(() => _selectedLocation = point);
                            _updateAddress(point);
                          },
                          onPositionChanged: (camera, hasGesture) {
                            if (hasGesture) {
                              setState(() => _selectedLocation = camera.center);
                            }
                          },
                          onMapEvent: (event) {
                            if (event is MapEventMoveEnd) {
                              _updateAddress(_selectedLocation);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.zikrint.admin',
                          ),
                        ],
                      ),

                      // Fixed Center Pin Marker
                      IgnorePointer(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlack,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                'SHOP PIN',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Icon(
                              Icons.location_on_rounded,
                              size: 48,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(height: 48), // Lift pin to point at exact center
                          ],
                        ),
                      ),

                      // Re-center My Location Floating Button
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.small(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryBlue,
                          elevation: 4,
                          onPressed: () async {
                            try {
                              Position pos = await Geolocator.getCurrentPosition(
                                desiredAccuracy: LocationAccuracy.high,
                              );
                              final newLoc = LatLng(pos.latitude, pos.longitude);
                              _mapController.move(newLoc, 17.0);
                              setState(() => _selectedLocation = newLoc);
                              _updateAddress(newLoc);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('GPS Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          },
                          child: const Icon(Icons.my_location_rounded),
                        ),
                      ),
                    ],
                  ),
          ),

          // Bottom Confirmation Panel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pin_drop_rounded, color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'LAT: ${_selectedLocation.latitude.toStringAsFixed(6)} | LNG: ${_selectedLocation.longitude.toStringAsFixed(6)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isGeocoding ? 'Detecting address details...' : _address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          MapLocationPickerResult(
                            latitude: _selectedLocation.latitude,
                            longitude: _selectedLocation.longitude,
                            address: _address,
                            pincode: _pincode,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                      label: Text(
                        'CONFIRM THIS SHOP LOCATION',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
