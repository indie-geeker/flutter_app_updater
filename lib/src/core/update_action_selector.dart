import '../actions/update_action.dart';
import '../models/update_distribution_policy.dart';

final class UpdateActionSelector {
  final UpdateDistributionPolicy distributionPolicy;

  const UpdateActionSelector({
    this.distributionPolicy = UpdateDistributionPolicy.any,
  });

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
