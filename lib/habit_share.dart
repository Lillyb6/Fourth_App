class HabitShare {
  const HabitShare({
    this.description = false,
    this.schedule = false,
    this.checkIns = false,
  });
  factory HabitShare.fromJson(Map<String, dynamic> data) => HabitShare(
    description: data['shareDescription'] == true,
    schedule: data['shareSchedule'] == true,
    checkIns: data['shareCheckIns'] == true,
  );
  final bool description, schedule, checkIns;
  Map<String, dynamic> toJson() => {
    'shareDescription': description,
    'shareSchedule': schedule,
    'shareCheckIns': checkIns,
  };
}
