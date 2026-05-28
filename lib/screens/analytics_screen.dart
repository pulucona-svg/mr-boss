import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/usage_service.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UsageService(),
      builder: (context, child) {
        final service = UsageService();
        final totalTime = _formatDuration(service.totalAppSeconds);
        final dailyUsage = service.dailyUsage;
        
        // Prepare chart data (last 7 days)
        final List<BarChartGroupData> barGroups = [];
        final now = DateTime.now();
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final key = date.toIso8601String().split('T')[0];
          final seconds = dailyUsage[key] ?? 0;
          final mins = seconds / 60.0;
          
          barGroups.add(
            BarChartGroupData(
              x: 6 - i,
              barRods: [
                BarChartRodData(
                  toY: mins,
                  color: const Color(0xFF20C8FF),
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 60, // Max 60 mins for scale
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ],
            ),
          );
        }

        // Top 5 materials
        final sortedMaterials = service.materialStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top5 = sortedMaterials.take(5).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF070716),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('App Usage Analytics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total Time Card
                _buildSummaryCard('Total App Usage', totalTime, Icons.access_time_filled_rounded, const Color(0xFF7B5CFF)),
                const SizedBox(height: 24),

                // Streak Card
                _buildSummaryCard('Current Streak', '${service.streak} Days', Icons.local_fire_department_rounded, Colors.orange),
                const SizedBox(height: 24),

                // Usage Chart
                const Text('LAST 7 DAYS (Minutes)', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: BarChart(
                    BarChartData(
                      barGroups: barGroups,
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final date = now.subtract(Duration(days: 6 - value.toInt()));
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  DateFormat('E').format(date)[0],
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Top Materials
                const Text('TOP 5 MOST-USED MATERIALS', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 16),
                if (top5.isEmpty)
                  _emptyState('No reading data tracked yet')
                else
                  ...top5.map((e) => _materialUsageTile(e.key, e.value, service.totalAppSeconds)),

                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _materialUsageTile(String title, int seconds, int totalSeconds) {
    final percent = totalSeconds > 0 ? (seconds / totalSeconds * 100).toStringAsFixed(1) : '0';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Total Time: ${_formatDuration(seconds)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF00A85A).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$percent%', style: const TextStyle(color: Color(0xFF00A85A), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          const Icon(Icons.analytics_outlined, color: Colors.white12, size: 48),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white24)),
        ],
      ),
    );
  }
}
