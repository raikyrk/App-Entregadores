import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class DashboardFilterModal extends StatelessWidget {
  final bool isDark;
  final String labelPeriodo;
  final DateTime startDate;
  final DateTime endDate;
  final Function(String, DateTime, DateTime) onApplyFilter;

  const DashboardFilterModal({
    super.key,
    required this.isDark,
    required this.labelPeriodo,
    required this.startDate,
    required this.endDate,
    required this.onApplyFilter,
  });

  static void show(
    BuildContext context, {
    required bool isDark,
    required String labelPeriodo,
    required DateTime startDate,
    required DateTime endDate,
    required Function(String, DateTime, DateTime) onApplyFilter,
  }) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DashboardFilterModal(
        isDark: isDark,
        labelPeriodo: labelPeriodo,
        startDate: startDate,
        endDate: endDate,
        onApplyFilter: onApplyFilter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Ver ganhos de:',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildFilterOption(context, 'Hoje', () {
                final now = DateTime.now();
                onApplyFilter('Hoje', DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
              }),
              _buildFilterOption(context, 'Ontem', () {
                final ontem = DateTime.now().subtract(const Duration(days: 1));
                onApplyFilter('Ontem', DateTime(ontem.year, ontem.month, ontem.day), DateTime(ontem.year, ontem.month, ontem.day, 23, 59, 59));
              }),
              _buildFilterOption(context, 'Esta Semana', () {
                final now = DateTime.now();
                int daysToSubtract = now.weekday - 1;
                final start = now.subtract(Duration(days: daysToSubtract));
                onApplyFilter('Esta Semana', DateTime(start.year, start.month, start.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
              }),
              _buildFilterOption(context, 'Este Mês', () {
                final now = DateTime.now();
                onApplyFilter('Este Mês', DateTime(now.year, now.month, 1), DateTime(now.year, now.month, now.day, 23, 59, 59));
              }),
              _buildFilterOption(context, 'Personalizado...', () async {
                Navigator.pop(context);
                HapticFeedback.lightImpact();

                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: DateTimeRange(start: startDate, end: endDate),
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  helpText: 'SELECIONE O PERÍODO',
                  cancelText: 'CANCELAR',
                  confirmText: 'CONFIRMAR',
                  saveText: 'SALVAR',
                  builder: (context, child) {
                    final brandOrange = const Color(0xFFF28C38);
                    return Theme(
                      data: ThemeData(
                        useMaterial3: true,
                        colorScheme: isDark
                            ? ColorScheme.dark(
                                primary: brandOrange,
                                onPrimary: Colors.white,
                                surface: const Color(0xFF1A1D24),
                                onSurface: Colors.white,
                                onSurfaceVariant: Colors.grey.shade400,
                              )
                            : ColorScheme.light(
                                primary: brandOrange,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: const Color(0xFF0F172A),
                                onSurfaceVariant: const Color(0xFF64748B),
                              ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: brandOrange,
                            textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  final finalDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
                  final DateFormat formatoLabel = DateFormat('dd/MM');
                  final String customLabel = '${formatoLabel.format(picked.start)} - ${formatoLabel.format(picked.end)}';
                  onApplyFilter(customLabel, picked.start, finalDate);
                }
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterOption(BuildContext context, String label, VoidCallback onTap) {
    final isSelected = labelPeriodo == label;
    final isCustom = label == 'Personalizado...';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          decoration: BoxDecoration(
            gradient: isSelected ? const LinearGradient(colors: [Color(0xFFF28C38), Color(0xFFE87A24)]) : null,
            color: isSelected ? null : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [BoxShadow(color: const Color(0xFFF28C38).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                : [],
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (isCustom ? const Color(0xFFF28C38).withOpacity(0.5) : (isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isCustom ? const Color(0xFFF28C38) : (isDark ? Colors.white : const Color(0xFF0F172A))),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22)
              else if (isCustom)
                Icon(Icons.calendar_month_rounded, color: const Color(0xFFF28C38).withOpacity(0.8), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}