import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String? username;
  final String? usernameLower;
  final bool profileCompleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final UserProfile profile;
  final UserSocial social;

  const AppUser({
    required this.uid,
    required this.email,
    this.username,
    this.usernameLower,
    required this.profileCompleted,
    this.createdAt,
    this.updatedAt,
    required this.profile,
    required this.social,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: data['uid'] as String? ?? doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String?,
      usernameLower: data['usernameLower'] as String?,
      profileCompleted: data['profileCompleted'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      profile: UserProfile.fromMap(
        data['profile'] as Map<String, dynamic>? ?? {},
      ),
      social: UserSocial.fromMap(data['social'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'username': username,
    'usernameLower': usernameLower,
    'profileCompleted': profileCompleted,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    'profile': profile.toMap(),
    'social': social.toMap(),
  };

  AppUser copyWith({
    String? username,
    String? usernameLower,
    bool? profileCompleted,
    UserProfile? profile,
    UserSocial? social,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      username: username ?? this.username,
      usernameLower: usernameLower ?? this.usernameLower,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profile: profile ?? this.profile,
      social: social ?? this.social,
    );
  }
}

class UserProfile {
  final String? displayName;
  final String? about;
  final String? photoUrl;

  const UserProfile({this.displayName, this.about, this.photoUrl});

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    displayName: map['displayName'] as String?,
    about: map['about'] as String?,
    photoUrl: map['photoUrl'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'about': about,
    'photoUrl': photoUrl,
  };

  UserProfile copyWith({
    String? displayName,
    String? about,
    String? photoUrl,
  }) => UserProfile(
    displayName: displayName ?? this.displayName,
    about: about ?? this.about,
    photoUrl: photoUrl ?? this.photoUrl,
  );
}

class UserSocial {
  final String? github;
  final String? instagram;
  final String? linkedin;

  const UserSocial({this.github, this.instagram, this.linkedin});

  factory UserSocial.fromMap(Map<String, dynamic> map) => UserSocial(
    github: map['github'] as String?,
    instagram: map['instagram'] as String?,
    linkedin: map['linkedin'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'github': github,
    'instagram': instagram,
    'linkedin': linkedin,
  };

  UserSocial copyWith({String? github, String? instagram, String? linkedin}) =>
      UserSocial(
        github: github ?? this.github,
        instagram: instagram ?? this.instagram,
        linkedin: linkedin ?? this.linkedin,
      );
}
