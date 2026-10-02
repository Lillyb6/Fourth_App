class HabitShare {
  const HabitShare({
    this.description = false,
    this.schedule = false,
    this.checkIns = false,
  });
  final bool description;
  final bool schedule;
  final bool checkIns;

  factory HabitShare.fromJson(Map<String, dynamic> json) => HabitShare(
    description: json['shareDescription'] as bool,
    schedule: json['shareSchedule'] as bool,
    checkIns: json['shareCheckIns'] as bool,
  );

  Map<String, bool> toJson() => {
    'shareDescription': description,
    'shareSchedule': schedule,
    'shareCheckIns': checkIns,
  };

  HabitShare copyWith({bool? description, bool? schedule, bool? checkIns}) =>
      HabitShare(
        description: description ?? this.description,
        schedule: schedule ?? this.schedule,
        checkIns: checkIns ?? this.checkIns,
      );
}
