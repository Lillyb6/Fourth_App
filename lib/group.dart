class AccountabilityGroup {
  const AccountabilityGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.isOwner,
    this.inviteCode,
    this.pendingRequestCount = 0,
    this.ownershipChanged = false,
  });

  final String id;
  final String name;
  final int memberCount;
  final bool isOwner;
  final String? inviteCode;
  final int pendingRequestCount;
  final bool ownershipChanged;

  factory AccountabilityGroup.fromJson(Map<String, dynamic> json) =>
      AccountabilityGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        memberCount: json['memberCount'] as int,
        isOwner: json['isOwner'] as bool,
        inviteCode: json['inviteCode'] as String?,
        pendingRequestCount: json['pendingRequestCount'] as int? ?? 0,
        ownershipChanged: json['ownershipChanged'] as bool? ?? false,
      );
}

class GroupJoinRequest {
  const GroupJoinRequest({required this.userId, required this.email});

  final String userId;
  final String email;

  factory GroupJoinRequest.fromJson(Map<String, dynamic> json) =>
      GroupJoinRequest(
        userId: json['userId'] as String,
        email: json['email'] as String,
      );
}
