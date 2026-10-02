class MemberProgress {
  const MemberProgress({
    required this.userId,
    required this.email,
    this.percentage,
  });
  final String userId;
  final String email;
  final int? percentage;

  factory MemberProgress.fromJson(Map<String, dynamic> json) => MemberProgress(
    userId: json['userId'] as String,
    email: json['email'] as String,
    percentage: json['completionPercentage'] as int?,
  );
}

class SharedHabit {
  const SharedHabit({
    required this.id,
    required this.userId,
    required this.email,
    required this.name,
    this.description,
    this.schedule,
    this.checkIns,
  });
  final String id;
  final String userId;
  final String email;
  final String name;
  final String? description;
  final String? schedule;
  final List<String>? checkIns;

  factory SharedHabit.fromJson(Map<String, dynamic> json) => SharedHabit(
    id: json['id'] as String,
    userId: json['userId'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    schedule: json['schedule'] as String?,
    checkIns: (json['checkIns'] as List?)?.cast<String>(),
  );
}
