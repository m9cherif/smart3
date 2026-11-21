import 'package:flutter/material.dart';

import 'package:smart_student_ai/auth_service.dart';

/// A rich profile + statistics dashboard: XP, level, streaks, activity and
/// achievements, all pulled from the account backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _auth = AuthService.instance;

  CloudProgress? _progress;
  List<Achievement> _achievements = const [];
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
      await _auth.refresh();
      final achievements = await _auth.fetchAchievements();
      if (!mounted) return;
      setState(() {
        _progress = _auth.progress;
        _achievements = achievements;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your stats. Pull down to retry.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Stats'),
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
        child: _isLoading && _progress == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      if (user != null) _buildHeader(user, colorScheme),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _buildError(colorScheme),
                      ],
                      const SizedBox(height: 20),
                      if (_progress != null) ..._buildStats(_progress!, colorScheme),
                      const SizedBox(height: 24),
                      _buildAchievements(colorScheme),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(AuthUser user, ColorScheme colorScheme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: colorScheme.primary,
              child: Text(
                user.initials,
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pill(
                        'Verified',
                        Icons.verified_rounded,
                        Colors.green.shade600,
                      ),
                      if (_progress != null) ...[
                        const SizedBox(width: 8),
                        _pill(
                          'Level ${_progress!.level}',
                          Icons.military_tech_rounded,
                          colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStats(CloudProgress p, ColorScheme colorScheme) {
    return [
      Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level ${p.level}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${p.xpIntoLevel}/${p.xpPerLevel} XP',
                    style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p.levelProgress.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total XP: ${p.xp}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 100,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        children: [
          _statTile('Current Streak', '${p.streak} days', Icons.local_fire_department_rounded, Colors.orange),
          _statTile('Longest Streak', '${p.longestStreak} days', Icons.emoji_events_rounded, Colors.amber.shade700),
          _statTile('Today\'s XP', '${p.todayXp} / ${p.dailyGoal}', Icons.bolt_rounded, colorScheme.primary),
          _statTile('Best Score', '${p.bestScore}', Icons.workspace_premium_rounded, Colors.purple),
          _statTile('Revision Answers', '${p.revisionCount}', Icons.quiz_rounded, colorScheme.tertiary),
          _statTile('Dictation Sessions', '${p.dictationCount}', Icons.mic_rounded, colorScheme.secondary),
        ],
      ),
    ];
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements(ColorScheme colorScheme) {
    final unlocked = _achievements.where((a) => a.unlocked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Achievements',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '$unlocked/${_achievements.length}',
              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_achievements.isEmpty)
          Text(
            'Achievements will appear as you learn.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          )
        else
          ..._achievements.map((a) => _achievementTile(a, colorScheme)),
      ],
    );
  }

  Widget _achievementTile(Achievement a, ColorScheme colorScheme) {
    final color = a.unlocked ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: a.unlocked
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: a.unlocked
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              a.unlocked ? _iconFor(a.icon) : Icons.lock_outline_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: a.unlocked ? null : colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  a.description,
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (a.unlocked) Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: TextStyle(color: colorScheme.error))),
        ],
      ),
    );
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'spark':
        return Icons.auto_awesome_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'brain':
        return Icons.psychology_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'local_fire':
        return Icons.local_fire_department_rounded;
      case 'sunny':
        return Icons.wb_sunny_rounded;
      case 'flame':
        return Icons.whatshot_rounded;
      case 'crown':
        return Icons.workspace_premium_rounded;
      case 'quiz':
        return Icons.quiz_rounded;
      case 'mic':
        return Icons.mic_rounded;
      default:
        return Icons.star_rounded;
    }
  }
}
