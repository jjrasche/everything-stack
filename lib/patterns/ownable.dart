/// # Ownable
///
/// ## What it does
/// Adds ownership and sharing fields to entities. Enables multi-user
/// isolation - users see only their data unless explicitly shared.
///
/// ## What it enables
/// - Multi-user apps with data isolation
/// - Sharing specific items with specific users
/// - Public/private/shared visibility levels
/// - "My items" vs "Shared with me" views
///
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
/// ## Performance
/// - Index on ownerId for ownership queries
/// - sharedWith array queries may be slower at scale
/// - Consider denormalized "accessible by" for high-share scenarios
///
/// ## Testing approach
/// Isolation tests:
/// - Create entities owned by different users
/// - Verify User A cannot access User B's private items
/// - Verify shared items appear for both owner and sharee
/// - Verify public items accessible to all
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
