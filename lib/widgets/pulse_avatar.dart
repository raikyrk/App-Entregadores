import 'dart:io';
import 'package:flutter/material.dart';

class PulseAvatar extends StatelessWidget {
  final String initials;
  final bool isOnline;
  final bool isDark;
  final String? localPath;
  final String? remoteUrl;
  final VoidCallback onTap;

  const PulseAvatar({
    super.key,
    required this.initials,
    required this.isOnline,
    required this.isDark,
    this.localPath,
    this.remoteUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isOnline ? const Color(0xFF10B981) : Colors.grey.shade400;
    ImageProvider? profileImage;
    if (localPath != null && File(localPath!).existsSync()) {
      profileImage = FileImage(File(localPath!));
    } else if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      profileImage = NetworkImage(remoteUrl!);
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D24) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ],
              image: profileImage != null ? DecorationImage(image: profileImage, fit: BoxFit.cover) : null,
            ),
            child: profileImage == null
                ? Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  )
                : null,
          ),
          Positioned(
            bottom: 2,
            right: 0,
            child: Container(
              height: 16,
              width: 16,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F6F9),
                  width: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}