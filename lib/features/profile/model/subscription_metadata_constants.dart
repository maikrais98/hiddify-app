/// Synthetic stored value used by the subscription parser for an unbounded traffic quota.
const int subscriptionInfiniteTrafficThreshold = 1_099_511_627_776_000;

/// Sentinel written by older app versions for an unknown or unbounded traffic quota.
const int subscriptionLegacyInfiniteTrafficSentinel = 920_233_720_368;

/// Synthetic stored value used by the subscription parser when no finite expiration is available.
const int subscriptionInfiniteTimeThreshold = 92_233_720_368;
