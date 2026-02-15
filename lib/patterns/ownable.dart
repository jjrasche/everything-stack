/// ## Schema addition
/// ```dart
/// String? ownerId;
/// List<String> sharedWith = [];
/// Visibility visibility = Visibility.private;
/// ```
///
/// ## Usage
/// ```dart
/// class Document extends BaseEntity with Ownable {
///   String title;
///   String content;
/// }
///
/// // Set owner on create
/// doc.ownerId = currentUser.id;
///
/// // Share with another user
/// doc.shareWith('user_456');
///
/// // Make public
/// doc.visibility = Visibility.public;
///
/// // Query user's accessible items
/// final myDocs = await docRepo.findAccessibleBy(currentUser.id);
/// ```
///
/// ## Integrates with
/// - Temporal: "My tasks due this week"
/// - Embeddable: Search only within accessible items
/// - Versionable: Track who made each change

mixin Ownable {
  /// User ID of owner
  String? ownerId;

  /// User IDs this is shared with
  List<String> sharedWith = [];

  /// Visibility level
  Visibility visibility = Visibility.private;

  /// Is this owned by the given user?
  bool isOwnedBy(String userId) => ownerId == userId;

  /// Is this accessible to the given user?
  bool isAccessibleBy(String userId) {
    // Owner always has access
    if (ownerId == userId) return true;

    // Public items accessible to all
    if (visibility == Visibility.public) return true;

    // Check if explicitly shared
    if (sharedWith.contains(userId)) return true;

    return false;
  }

  /// Share with another user
  void shareWith(String userId) {
    if (!sharedWith.contains(userId)) {
      sharedWith.add(userId);
    }
    // Upgrade visibility if private
    if (visibility == Visibility.private) {
      visibility = Visibility.shared;
    }
  }

  /// Remove sharing with user
  void unshareWith(String userId) {
    sharedWith.remove(userId);
    // Downgrade visibility if no more shares
    if (sharedWith.isEmpty && visibility == Visibility.shared) {
      visibility = Visibility.private;
    }
  }

  /// Make public
  void makePublic() {
    visibility = Visibility.public;
  }

  /// Make private (also clears shares)
  void makePrivate() {
    visibility = Visibility.private;
    sharedWith.clear();
  }
}

enum Visibility {
  private, // Only owner
  shared, // Owner + explicit shares
  public, // Everyone
}
