class AccountabilityGroup {
  AccountabilityGroup.fromJson(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      memberCount = data['memberCount'] as int,
      isOwner = data['isOwner'] == true,
      inviteCode = data['inviteCode'] as String?,
      pendingRequestCount = data['pendingRequestCount'] as int? ?? 0,
      ownershipChanged = data['ownershipChanged'] == true;
  final String id, name;
  final int memberCount, pendingRequestCount;
  final bool isOwner, ownershipChanged;
  final String? inviteCode;
}

class GroupJoinRequest {
  GroupJoinRequest.fromJson(Map<String, dynamic> data)
    : userId = data['userId'] as String,
      email = data['email'] as String;
  final String userId, email;
}
