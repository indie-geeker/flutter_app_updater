import '../actions/update_action.dart';
import '../models/update_distribution_policy.dart';

/// Filters ordered update actions by host policy and executor capability.
final class UpdateActionSelector {
  /// Distribution family restriction applied before capability checks.
  final UpdateDistributionPolicy distributionPolicy;

  /// Creates an action selector.
  const UpdateActionSelector({
    this.distributionPolicy = UpdateDistributionPolicy.any,
  });

  /// Returns allowed actions in their original manifest order.
  List<UpdateAction> supportedActions(
    List<UpdateAction> actions, {
    required bool Function(UpdateAction action) supports,
  }) {
    return actions
        .where(_isAllowedByDistribution)
        .where(supports)
        .toList(growable: false);
  }

  bool _isAllowedByDistribution(UpdateAction action) {
    final isStoreAction =
        action is OpenStoreAction || action is OpenAndroidMarketAction;
    return switch (distributionPolicy) {
      UpdateDistributionPolicy.any => true,
      UpdateDistributionPolicy.storeOnly => isStoreAction,
      UpdateDistributionPolicy.selfHostedOnly => !isStoreAction,
    };
  }
}
