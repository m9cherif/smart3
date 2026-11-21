import 'package:flutter/material.dart';

import 'package:smart_student_ai/auth_service.dart';

/// Global XP leaderboard, ranked by total XP.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final AuthService _auth = AuthService.instance;

  List<LeaderboardEntry> _entries = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final entries = await _auth.fetchLeaderboard();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the leaderboard. Pull down to retry.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final myName = _auth.currentUser?.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(_error!, style: TextStyle(color: colorScheme.error)),
                      ),
                    ],
                  )
                : _entries.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No scores yet. Be the first!')),
                        ],
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            itemCount: _entries.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _buildPodium(_entries.take(3).toList(), colorScheme);
                              }
                              final entry = _entries[index - 1];
                              final isMe = myName != null && entry.name == myName;
                              return _buildRow(entry, isMe, colorScheme);
                            },
                          ),
                        ),
                      ),
      ),
    );
  }

  Widget _buildPodium(List<LeaderboardEntry> top, ColorScheme colorScheme) {
    if (top.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (top.length > 1) Expanded(child: _podiumTile(top[1], 2, colorScheme)),
        const SizedBox(width: 8),
        Expanded(child: _podiumTile(top[0], 1, colorScheme)),
        const SizedBox(width: 8),
        if (top.length > 2) Expanded(child: _podiumTile(top[2], 3, colorScheme)),
      ],
    );
  }

  Widget _podiumTile(LeaderboardEntry e, int place, ColorScheme colorScheme) {
    final (color, height) = switch (place) {
      1 => (const Color(0xFFFFC107), 130.0),
      2 => (const Color(0xFF90A4AE), 106.0),
      _ => (const Color(0xFFBCAAA4), 92.0),
    };
    final medal = place == 1 ? Icons.workspace_premium_rounded : Icons.military_tech_rounded;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.25),
          child: Icon(medal, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          e.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        Text('${e.xp} XP', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: Text('#$place', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ),
      ],
    );
  }

  Widget _buildRow(LeaderboardEntry e, bool isMe, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${e.rank}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: e.rank <= 3 ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? '${e.name} (you)' : e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Icon(Icons.local_fire_department_rounded, size: 16, color: Colors.orange.shade400),
          const SizedBox(width: 3),
          Text('${e.streak}', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Lv ${e.level}',
              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${e.xp} XP',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
