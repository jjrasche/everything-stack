import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';

part 'proposition.g.dart';

@JsonSerializable()
class Proposition extends BaseEntity with Embeddable {
  @override
  int id = 0;

  @override
  String uuid = '';

  @override
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  /// Self-contained, decontextualized knowledge unit.
  String content;

  /// Temporal scope: 'session', 'project', 'life'
  String scope;

  /// Knowledge type: 'learning', 'project', 'exploration'
  String? type;

  /// Sentence IDs from segmentation (e.g. ["S1", "S2"]).
  /// Stored as comma-separated in ObjectBox.
  List<String> sourceIds;

  /// Turn identifier (e.g. "conv_abc12345_turn_0")
  String sourceTurnId;

  /// Episode identifier (e.g. "conv_abc12345")
  String sourceEpisodeId;

  /// Lifecycle status: 'active', 'archived', 'superseded'
  String status;

  /// UUID of the proposition that replaced this one (if superseded)
  String? supersededBy;

  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  @override
  List<double>? embedding;

  Proposition({
    required this.content,
    required this.scope,
    this.type,
    required this.sourceIds,
    required this.sourceTurnId,
    required this.sourceEpisodeId,
    this.status = 'active',
    this.supersededBy,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => _$PropositionToJson(this);
  factory Proposition.fromJson(Map<String, dynamic> json) =>
      _$PropositionFromJson(json);

  @override
  String toEmbeddingInput() => content;

  bool get isActive => status == 'active';
  bool get isSuperseded => status == 'superseded';
  bool get isArchived => status == 'archived';
}
