library flutter_app_pay_api;

import 'package:meta/meta.dart';

/// Current version of the AppPay API contract.
/// Both the core library and provider plugins must support this version
/// (or a compatible range) to interoperate safely.
const int kAppPayApiVersion = 1;

// ─────────────────────────────────────────────────────────────────────────────
//                                 BASE TYPES
// ─────────────────────────────────────────────────────────────────────────────

/// Types of in-app products supported by providers.
enum ProductType {
  consumable,
  nonConsumable,
  subscription,
}

/// Possible statuses of a purchase event.
enum PurchaseStatus {
  pending,
  purchased,
  restored,
  canceled,
  expired,
  error,
}

/// Supported runtime platforms for providers.
enum ProviderPlatform {
  android,
  ios,
  any,
}

/// Metadata that describes a payment provider plugin.
///
/// This descriptor is used during provider registration to ensure compatibility
/// between the core library and the provider implementation.
@immutable
class ProviderDescriptor {
  /// Stable unique identifier of the provider, e.g. `pay.google` or `pay.rustore`.
  final String id;

  /// Default human-readable name, used for UI and logging.
  final String name;

  /// The runtime platform supported by this provider.
  final ProviderPlatform platform;

  /// Supported product types (e.g. subscriptions, consumables).
  final Set<ProductType> capabilities;

  /// Minimum API version supported by the provider.
  final int apiVersionMin;

  /// Maximum API version supported by the provider.
  final int apiVersionMax;

  const ProviderDescriptor({
    required this.id,
    required this.name,
    required this.platform,
    this.capabilities = const {},
    this.apiVersionMin = kAppPayApiVersion,
    this.apiVersionMax = kAppPayApiVersion,
  });

  /// Returns `true` if the given version is within the supported range.
  bool supports(int version) =>
      version >= apiVersionMin && version <= apiVersionMax;

  ProviderDescriptor copyWith({
    String? name,
    Set<ProductType>? capabilities,
    int? apiVersionMin,
    int? apiVersionMax,
  }) =>
      ProviderDescriptor(
        id: id,
        name: name ?? this.name,
        platform: platform,
        capabilities: capabilities ?? this.capabilities,
        apiVersionMin: apiVersionMin ?? this.apiVersionMin,
        apiVersionMax: apiVersionMax ?? this.apiVersionMax,
      );
}

/// Internal token returned when registering a provider.
/// Used by the core registry to uniquely track providers.
@immutable
class ProviderToken {
  final String registryKey;
  const ProviderToken(this.registryKey);
}

/// Product DTO shared between core and provider implementations.
@immutable
class ProductDto {
  /// Store-specific identifier (SKU).
  final String id;

  /// Localized product title.
  final String title;

  /// Localized product description.
  final String description;

  /// Localized price string, e.g. `"€3.99"` or `"₽199/month"`.
  final String priceLabel;

  /// Optional ISO 4217 currency code (e.g. `"EUR"`, `"RUB"`).
  final String? currencyCode;

  /// Type of the product.
  final ProductType type;

  /// Provider identifier (e.g. `"pay.google"`).
  final String providerId;

  /// Raw platform data as provided by the native SDK.
  final Map<String, Object?> raw;

  const ProductDto({
    required this.id,
    required this.title,
    required this.description,
    required this.priceLabel,
    required this.type,
    required this.providerId,
    this.currencyCode,
    this.raw = const {},
  });

  @override
  String toString() =>
      'ProductDto($id, $priceLabel, $type, provider=$providerId)';
}

/// Event representing the result of a purchase or restoration attempt.
@immutable
class PurchaseEventDto {
  /// Provider identifier.
  final String providerId;

  /// Product identifier (SKU).
  final String productId;

  /// Transaction identifier (may be empty for failed or canceled events).
  final String transactionId;

  /// Current status of the purchase.
  final PurchaseStatus status;

  /// Raw SDK response for debugging or server-side verification.
  final Map<String, Object?> raw;

  const PurchaseEventDto({
    required this.providerId,
    required this.productId,
    required this.transactionId,
    required this.status,
    this.raw = const {},
  });

  @override
  String toString() =>
      'PurchaseEventDto(status=$status, provider=$providerId, product=$productId, tx=$transactionId)';
}

/// Current runtime status of a provider plugin.
@immutable
class ProviderStatus {
  /// Whether the provider has completed initialization.
  final bool initialized;

  /// Whether the underlying SDK or store client is installed and available.
  final bool available;

  /// Whether the user is authorized in the store (if applicable).
  final bool userAuthorized;

  /// Additional diagnostic information.
  final Map<String, Object?> details;

  const ProviderStatus({
    required this.initialized,
    required this.available,
    required this.userAuthorized,
    this.details = const {},
  });

  /// Convenience flag indicating whether the provider is ready for purchases.
  bool get ready => initialized && available;

  ProviderStatus copyWith({
    bool? initialized,
    bool? available,
    bool? userAuthorized,
    Map<String, Object?>? details,
  }) =>
      ProviderStatus(
        initialized: initialized ?? this.initialized,
        available: available ?? this.available,
        userAuthorized: userAuthorized ?? this.userAuthorized,
        details: details ?? this.details,
      );

  @override
  String toString() =>
      'ProviderStatus(init=$initialized, available=$available, userAuth=$userAuthorized)';
}

/// Extension methods for more readable access to provider status.
extension ProviderStatusX on ProviderStatus {
  bool get isInitialized => initialized;
  bool get isAvailable => available;
  bool get isAuthorized => userAuthorized;
}

// ─────────────────────────────────────────────────────────────────────────────
//                           PROVIDER CONTRACT
// ─────────────────────────────────────────────────────────────────────────────

/// Factory function used to instantiate provider implementations.
typedef ProviderFactory = AppPayPlatform Function();

/// Strongly-typed interface that every provider plugin must implement.
///
/// Providers are free to use any underlying communication with native SDKs
/// (MethodChannel, Pigeon, direct FFI, etc.), as long as they satisfy this
/// interface contract.
abstract interface class AppPayPlatform {
  // Metadata
  String get providerId;
  Set<ProductType> get capabilities;

  // Lifecycle
  Future<void> init();
  Future<void> dispose();

  // Status
  ProviderStatus get statusSnapshot;
  Stream<ProviderStatus> get statusStream;
  Future<ProviderStatus> refreshStatus();

  // Purchase events
  Stream<PurchaseEventDto> get events;

  // Catalog & operations
  Future<List<ProductDto>> queryProducts(Set<String> ids);
  Future<void> buy(String productId, {String? offerId});
  Future<void> restore();
  Future<List<PurchaseEventDto>> getPurchases({
    ProductType? type,
    PurchaseStatus? status,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//                           CORE REGISTRATION HOOK
// ─────────────────────────────────────────────────────────────────────────────

/// Registration hook that allows providers to register themselves
/// without depending on the core library directly.
///
/// The core library (`flutter_app_pay`) sets this function during startup.
/// Provider plugins must call it to register their descriptor and factory.
abstract final class AppPayRegisterHook {
  static ProviderToken Function(
      ProviderDescriptor descriptor,
      ProviderFactory factory,
      )? register;
}