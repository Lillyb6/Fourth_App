class MemberProgress {
  MemberProgress.fromJson(Map<String, dynamic> data)
    : userId = data['userId'] as String,
      email = data['email'] as String,
      percentage = data['completionPercentage'] as int?;
  final String userId, email;
  final int? percentage;
}

class SharedHabit {
  SharedHabit.fromJson(Map<String, dynamic> data)
    : name = data['name'] as String,
      email = data['email'] as String,
      description = data['description'] as String?,
      schedule = data['schedule'] as String?,
      checkIns = (data['checkIns'] as List?)?.cast<String>();
  final String name, email;
  final String? description, schedule;
  final List<String>? checkIns;
}
