/// # Timer
///
/// ## What it does
/// Represents a countdown timer set by the user via voice or text.
/// Persists across app restarts. Fires events when countdown completes.
///
/// ## Why persisted
/// - App may be killed during countdown
/// - Device may restart
/// - Timer should still fire (or show elapsed) when app returns
///
/// ## Invocable
/// Timers are created by the timer.set tool.
/// The Invocable mixin tracks which tool created it and with what parameters.
///
/// ## Usage
/// ```dart
/// final timer = Timer(
///   label: '5 minute break',
///   durationSeconds: 300,
///   setAt: DateTime.now(),
///   endsAt: DateTime.now().add(Duration(seconds: 300)),
/// );
///
/// // Mark creation by tool
/// timer.recordInvocation(
///   correlationId: event.correlationId,
///   toolName: 'timer.set',
///   params: {'label': '5 minute break', 'duration': 300},
///   confidence: 0.95,
/// );
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';
import '../../../patterns/invocable.dart';

@Entity()
class Timer extends BaseEntity with Invocable {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  @override
  @Unique()
  String uuid = '';

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Timer fields ============

  /// User-provided label for this timer
  /// e.g., "5 minute break", "pasta timer", "meeting reminder"
  String label;

  /// How long the timer runs for (in seconds)
  int durationSeconds;

  /// When the timer was set
  @Property(type: PropertyType.date)
  DateTime setAt;

  /// When the timer will end (setAt + duration)
  @Property(type: PropertyType.date)
  DateTime endsAt;

  /// Has this timer fired (completed)?
  bool fired;

  /// When did it fire? (null if not yet fired)
  @Property(type: PropertyType.date)
  DateTime? firedAt;

  // ============ Invocable mixin fields (stored) ============

  @override
  String? invocationCorrelationId;

  @override
  @Property(type: PropertyType.date)
  DateTime? invokedAt;

  @override
  String? invokedByTool;

  @override
  @Transient()
  Map<String, dynamic>? invocationParams;

  /// JSON string storage for invocationParams
  String? invocationParamsJson;

  @override
  double? invocationConfidence;

  @override
  String? invocationStatus;

  // ============ Constructor ============

  Timer({
    required this.label,
    required this.durationSeconds,
    required this.setAt,
    required this.endsAt,
    this.fired = false,
    this.firedAt,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  /// How many seconds remain?
  int get remainingSeconds {
    if (fired) return 0;
    final remaining = endsAt.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Is the timer still running?
  bool get isActive => !fired && remainingSeconds > 0;

  /// Has the timer expired but not yet been marked as fired?
  bool get hasExpired => !fired && remainingSeconds <= 0;

  // ============ Actions ============

  /// Mark timer as fired
  void fire() {
    if (!fired) {
      fired = true;
      firedAt = DateTime.now();
      touch();
    }
  }

  /// Cancel the timer before it fires
  void cancel() {
    fired = true;
    firedAt = null; // null firedAt with fired=true means cancelled
    touch();
  }

  /// Was this timer cancelled?
  bool get wasCancelled => fired && firedAt == null;

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'label': label,
        'durationSeconds': durationSeconds,
        'setAt': setAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'fired': fired,
        'firedAt': firedAt?.toIso8601String(),
        ...invocableToJson(),
      };

  factory Timer.fromJson(Map<String, dynamic> json) {
    final timer = Timer(
      label: json['label'] as String,
      durationSeconds: json['durationSeconds'] as int,
      setAt: DateTime.parse(json['setAt'] as String),
      endsAt: DateTime.parse(json['endsAt'] as String),
      fired: json['fired'] as bool? ?? false,
      firedAt: json['firedAt'] != null
          ? DateTime.parse(json['firedAt'] as String)
          : null,
    );
    timer.id = json['id'] as int? ?? 0;
    timer.uuid = json['uuid'] as String? ?? '';
    timer.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    timer.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    timer.syncId = json['syncId'] as String?;
    timer.invocableFromJson(json);
    return timer;
  }
}
