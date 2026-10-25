import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../models/address_model.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/product_model.dart';
import '../../../cart/presentation/providers/cart_lines.dart';
import '../../../orders/data/orders_repository.dart';
import '../../domain/checkout_rules.dart';

/// "Now" for the delivery-date rules — Iraq wall-clock time, as on the server
/// (a customer abroad still gets Iraq's dates and slots); overridden in tests.
final checkoutClockProvider = Provider<DateTime Function()>((ref) => AppDates.iraqNow);

/// What the customer picked on the Checkout page (SRS §5.11). Null address /
/// date / slot = "use the default" (default address, earliest date, first slot).
class CheckoutState {
  const CheckoutState({
    this.address,
    this.date,
    this.slotId,
    this.isGift = false,
    this.hidePrices = false,
    this.giftMessage = '',
    this.paymentMethod = PaymentMethod.cashOnDelivery,
    this.placing = false,
  });

  final AddressModel? address;
  final DateTime? date;
  final String? slotId;
  final bool isGift;
  final bool hidePrices;
  final String giftMessage;
  final PaymentMethod paymentMethod;
  final bool placing;

  CheckoutState copyWith({
    AddressModel? address,
    DateTime? date,
    String? slotId,
    bool clearSlot = false,
    bool? isGift,
    bool? hidePrices,
    String? giftMessage,
    PaymentMethod? paymentMethod,
    bool? placing,
  }) =>
      CheckoutState(
        address: address ?? this.address,
        date: date ?? this.date,
        slotId: clearSlot ? null : (slotId ?? this.slotId),
        isGift: isGift ?? this.isGift,
        hidePrices: hidePrices ?? this.hidePrices,
        giftMessage: giftMessage ?? this.giftMessage,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        placing: placing ?? this.placing,
      );
}

class CheckoutController extends StateNotifier<CheckoutState> {
  CheckoutController(this._orders, {String? clientRequestId})
      : clientRequestId = clientRequestId ?? const Uuid().v4(),
        super(const CheckoutState());

  final OrdersRepository _orders;

  /// One id per checkout visit: every retry of Place order sends the same id,
  /// so `placeOrder` can never create a second order (SRS §5.11, §6.7).
  final String clientRequestId;

  static const giftMessageMax = 200;

  void selectAddress(AddressModel address) => state = state.copyWith(address: address);
  void selectDate(DateTime date) => state = state.copyWith(date: date, clearSlot: true);
  void selectSlot(String slotId) => state = state.copyWith(slotId: slotId);
  void setGift(bool value) => state = state.copyWith(isGift: value);
  void setHidePrices(bool value) => state = state.copyWith(hidePrices: value);
  void setGiftMessage(String value) => state = state.copyWith(giftMessage: value);
  void setPaymentMethod(PaymentMethod method) => state = state.copyWith(paymentMethod: method);

  /// Throws [OrderFailure].
  Future<PlacedOrder> place({
    required String addressId,
    required DateTime date,
    String? slotId,
    PaymentMethod? paymentMethod,
    String? promoCode,
    bool useCredits = false,
  }) async {
    if (state.placing) throw const OrderFailure(OrderFailureReason.unknown, message: 'already placing');
    state = state.copyWith(placing: true);
    try {
      return await _orders.placeOrder(PlaceOrderRequest(
        clientRequestId: clientRequestId,
        addressId: addressId,
        deliveryDate: date,
        deliverySlot: slotId,
        isGift: state.isGift,
        giftMessage: state.isGift ? state.giftMessage : null,
        hidePrices: state.isGift && state.hidePrices,
        paymentMethod: paymentMethod ?? state.paymentMethod,
        promoCode: promoCode,
        useCredits: useCredits,
        useWallet: (paymentMethod ?? state.paymentMethod) == PaymentMethod.wallet,
      ));
    } finally {
      if (mounted) state = state.copyWith(placing: false);
    }
  }
}

final checkoutControllerProvider = StateNotifierProvider.autoDispose<CheckoutController, CheckoutState>(
  (ref) => CheckoutController(ref.read(ordersRepositoryProvider)),
);

/// The date row and slot chips for the current choice (SRS §5.11).
class DeliveryChoice {
  const DeliveryChoice({
    required this.dates,
    required this.slotsByDate,
    required this.date,
    required this.slots,
    required this.slot,
    required this.todayHasNoSlots,
  });

  final List<DateTime> dates;
  final Map<DateTime, List<DeliverySlot>> slotsByDate;

  /// Effective date (the pick, or the first date that still has a slot).
  final DateTime? date;
  final List<DeliverySlot> slots;
  final DeliverySlot? slot;

  /// The earliest date is today but every slot has started → "no slots today".
  final bool todayHasNoSlots;

  bool hasSlots(DateTime d) => (slotsByDate[d] ?? const []).isNotEmpty;

  static DeliveryChoice resolve({
    required DateTime now,
    required int maxPreparationDays,
    required GeneralSettings settings,
    DateTime? selectedDate,
    String? selectedSlotId,
  }) {
    final earliest = CheckoutRules.earliestDeliveryDate(
      now: now,
      maxPreparationDays: maxPreparationDays,
      sameDayCutoff: settings.sameDayCutoff,
    );
    final dates = CheckoutRules.deliveryDates(earliest);
    final slotsByDate = {for (final d in dates) d: CheckoutRules.availableSlots(d, now, settings.deliverySlots)};
    bool open(DateTime d) => (slotsByDate[d] ?? const []).isNotEmpty;
    final picked = selectedDate == null ? null : DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final date = (picked != null && open(picked)) ? picked : dates.where(open).firstOrNull;
    final slots = date == null ? const <DeliverySlot>[] : slotsByDate[date]!;
    final slot = slots.where((s) => s.id == selectedSlotId).firstOrNull ?? slots.firstOrNull;
    final today = DateTime(now.year, now.month, now.day);
    return DeliveryChoice(
      dates: dates,
      slotsByDate: slotsByDate,
      date: date,
      slots: slots,
      slot: slot,
      todayHasNoSlots: dates.first == today && !open(today),
    );
  }
}

/// Whether the address's city can receive this cart (SRS §4.3).
class CityCheck {
  const CityCheck({required this.city, required this.blockedLines});

  /// The active served city, or null when the address's city isn't served.
  final CityModel? city;

  /// Orderable lines that can't go to this city (all of them when unserved).
  final List<CartLine> blockedLines;

  bool get ok => city != null && blockedLines.isEmpty;
  int get deliveryFee => city?.deliveryFee ?? 0;

  static CityCheck resolve({
    required AddressModel address,
    required List<CityModel> cities,
    required CartSummary summary,
    required Map<String, ProductModel> products,
  }) {
    final city = cities.where((c) => c.id == address.city && c.isActive).firstOrNull;
    if (city == null) {
      return CityCheck(city: null, blockedLines: summary.lines.where((l) => l.counts).toList());
    }
    return CityCheck(city: city, blockedLines: CheckoutRules.cityConflicts(summary, products, city.id));
  }
}

/// Payment methods offered by `app_settings/payments`, and whether this
/// release can take them. "Wallet" pays with the balance after credits and
/// must cover the whole rest (SRS §5.18); ZainCash (Phase 9) pays the rest on
/// the gateway's page; card / FastPay have no gateway yet (shown disabled).
List<(PaymentMethod, bool usable)> offeredPaymentMethods(PaymentSettings settings) => [
      if (settings.cashOnDelivery) (PaymentMethod.cashOnDelivery, true),
      if (settings.wallet) (PaymentMethod.wallet, true),
      if (settings.zainCash) (PaymentMethod.zainCash, true),
      if (settings.card || settings.fastPay) (PaymentMethod.card, false),
    ];
