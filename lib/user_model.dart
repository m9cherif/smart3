/// Represents a user in the system with their profile details.
class UserModel {
  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;
  final int bestScore;
  final int xp;
  final int level;
  final int revisionCount;
  final int dictationCount;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
    this.bestScore = 0,
    this.xp = 0,
    this.level = 1,
    this.revisionCount = 0,
    this.dictationCount = 0,
  });

  /// Converts the model into a Map for local storage.
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
      'bestScore': bestScore,
      'xp': xp,
      'level': level,
      'revisionCount': revisionCount,
      'dictationCount': dictationCount,
    };
  }

  /// Creates a [UserModel] from a map.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      bestScore: map['bestScore'] ?? 0,
      xp: map['xp'] ?? 0,
      level: map['level'] ?? 1,
      revisionCount: map['revisionCount'] ?? 0,
      dictationCount: map['dictationCount'] ?? 0,
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : DateTime.now(),
    );
  }
}
