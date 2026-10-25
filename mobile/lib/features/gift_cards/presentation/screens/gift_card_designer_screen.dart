import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/country_codes.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../../models/app_settings_model.dart';
import '../../../../models/gift_card_model.dart';
import '../../../../models/wallet_model.dart';
import '../../../addresses/data/address_repository.dart';
import '../../../addresses/presentation/widgets/address_card.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../auth/presentation/widgets/phone_field.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../checkout/presentation/providers/checkout_providers.dart' show checkoutClockProvider;
import '../../../checkout/presentation/widgets/checkout_options_sections.dart' show CheckoutErrorLine;
import '../../../orders/data/orders_repository.dart';
import '../../../orders/presentation/widgets/order_labels.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../product_details/domain/product_configuration.dart';
import '../../../special_requests/presentation/widgets/picked_photos_field.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../../data/gift_cards_repository.dart';
import '../widgets/gift_card_face.dart';

/// Scheduling bounds (SRS §5.22): from tomorrow up to one year ahead.
class GiftCardSchedule {
  GiftCardSchedule._();

  static DateTime firstDate(DateTime now) => DateTime(now.year, now.month, now.day + 1);
  static DateTime lastDate(DateTime now) => DateTime(now.year + 1, now.month, now.day);

  static bool allows(DateTime date, DateTime now) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(firstDate(now)) && !d.isAfter(lastDate(now));
  }

  /// The card goes out at 09:00 local time on the chosen day.
  static DateTime sendAt(DateTime date) => DateTime(date.year, date.month, date.day, 9);
}

/// Western digits only ("٢٥٠٠٠" → 25000; separators ignored); null when empty.
int? parseAmountInput(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    }
  }
  final digits = buffer.toString();
  if (digits.isEmpty || digits.length > 9) return digits.isEmpty ? null : -1;
  return int.parse(digits);
}

enum _F { amount, recipientName, contact, phone, email, schedule, address }

/// Gift Card Designer (SRS §5.22, "Design Your Gift Card — Make it personal"):
/// live preview, design (template colour), amount (presets or custom within
/// min / max), optional photo, message, recipient (name + phone or email),
/// send now or on a date, and payment — cash on delivery at the buyer's
/// address, or the wallet balance (credits can't buy gift cards). Buy calls
/// `purchaseGiftCard` with ONE clientRequestId per visit, so a retry can
/// never create a second order.
class GiftCardDesignerScreen extends ConsumerStatefulWidget {
  const GiftCardDesignerScreen({super.key, required this.templateId});
  final String templateId;

  @override
  ConsumerState<GiftCardDesignerScreen> createState() => _GiftCardDesignerScreenState();
}

class _GiftCardDesignerScreenState extends ConsumerState<GiftCardDesignerScreen> {
  final String _clientRequestId = const Uuid().v4();

  final _customAmount = TextEditingController();
  final _message = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientEmail = TextEditingController();
  CountryCode _country = CountryCodes.iraq;

  late String _templateId = widget.templateId;
  bool _amountInitialized = false;
  int? _preset;
  bool _custom = false;

  PickedPhoto? _photo;
  PickedPhoto? _uploadedPhoto;
  String? _photoUrl;
  double? _uploadProgress;

  bool _scheduled = false;
  DateTime? _sendDate;

  AddressModel? _address;
  PaymentMethod _method = PaymentMethod.cashOnDelivery;

  Map<_F, String?> _errors = const {};
  bool _paying = false;

  @override
  void dispose() {
    for (final c in [_customAmount, _message, _recipientName, _recipientPhone, _recipientEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear(_F field) {
    if (_errors[field] != null) setState(() => _errors = {..._errors, field: null});
  }

  void _initAmount(GiftCardTemplateModel t) {
    if (_amountInitialized) return;
    _amountInitialized = true;
    _preset = t.presetAmounts.firstOrNull;
    _custom = _preset == null && t.allowsCustomAmount;
  }

  void _selectTemplate(GiftCardTemplateModel t) {
    if (t.id == _templateId) return;
    setState(() {
      _templateId = t.id;
      if (_custom && !t.allowsCustomAmount) _custom = false;
      if (!_custom && !(t.presetAmounts.contains(_preset))) {
        _preset = t.presetAmounts.firstOrNull;
        _custom = _preset == null && t.allowsCustomAmount;
      }
      _errors = {..._errors, _F.amount: null};
    });
  }

  int? _amountFor(GiftCardTemplateModel t) {
    if (_custom) {
      final v = parseAmountInput(_customAmount.text);
      return v == null || v <= 0 ? null : v;
    }
    return _preset;
  }

  String? _amountError(AppLocalizations l10n, GiftCardTemplateModel t) {
    final amount = _amountFor(t);
    if (amount == null) return _custom ? l10n.giftCardAmountRequired : l10n.errorRequired;
    if (!t.accepts(amount)) {
      return l10n.giftCardAmountRange(CurrencyFormatter.format(t.minAmount), CurrencyFormatter.format(t.maxAmount));
    }
    return null;
  }

  Map<_F, String?> _validate(AppLocalizations l10n, GiftCardTemplateModel t, AddressModel? address, PaymentMethod? method,
      DateTime now) {
    final phone = _recipientPhone.text.trim();
    final email = _recipientEmail.text.trim();
    final errors = <_F, String?>{
      _F.amount: _amountError(l10n, t),
      _F.recipientName: l10n.validation(Validators.name(_recipientName.text)),
      _F.phone: phone.isEmpty ? null : l10n.validation(Validators.phone(phone, _country)),
      _F.email: email.isEmpty ? null : l10n.validation(Validators.email(email)),
      _F.contact: phone.isEmpty && email.isEmpty ? l10n.giftCardContactRequired : null,
      _F.schedule: !_scheduled
          ? null
          : (_sendDate == null
              ? l10n.giftCardScheduleRequired
              : (GiftCardSchedule.allows(_sendDate!, now) ? null : l10n.giftCardScheduleRange)),
      _F.address: method == PaymentMethod.cashOnDelivery && address == null ? l10n.giftCardAddressRequired : null,
    };
    return errors;
  }

  Future<void> _pickDate(DateTime now) async {
    final first = GiftCardSchedule.firstDate(now);
    final last = GiftCardSchedule.lastDate(now);
    final initial = _sendDate != null && GiftCardSchedule.allows(_sendDate!, now) ? _sendDate! : first;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      currentDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _sendDate = picked;
        _errors = {..._errors, _F.schedule: null};
      });
    }
  }

  Future<void> _changeAddress() async {
    if (!await requireSignIn(context, ref)) return;
    if (!mounted) return;
    final picked = await context.push<AddressModel>('${AppRoutes.addresses}?select=1');
    if (picked != null && mounted) {
      setState(() {
        _address = picked;
        _errors = {..._errors, _F.address: null};
      });
    }
  }

  Future<void> _addAddress() async {
    if (!await requireSignIn(context, ref)) return;
    if (!mounted) return;
    final saved = await context.push<AddressModel>(AppRoutes.addressForm);
    if (saved != null && mounted) {
      setState(() {
        _address = saved;
        _errors = {..._errors, _F.address: null};
      });
    }
  }

  Future<void> _buy({
    required GiftCardTemplateModel template,
    required AddressModel? address,
    required PaymentMethod? method,
    required DateTime now,
  }) async {
    if (_paying) return;
    final l10n = AppLocalizations.of(context)!;
    if (!await requireSignIn(context, ref)) return;
    if (!mounted) return;
    final errors = _validate(l10n, template, address, method, now);
    if (errors.values.any((e) => e != null) || method == null) {
      setState(() => _errors = errors);
      showOrderSnack(context, l10n.giftCardFixErrors);
      return;
    }
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final amount = _amountFor(template)!;
    final router = GoRouter.of(context);
    final analytics = ref.read(analyticsServiceProvider);
    setState(() {
      _errors = const {};
      _paying = true;
    });
    try {
      String? photoUrl;
      final photo = _photo;
      if (photo != null) {
        if (!identical(_uploadedPhoto, photo) || _photoUrl == null) {
          setState(() => _uploadProgress = 0);
          final urls = await ref.read(imageUploadServiceProvider).upload(
                'gift_cards/$uid/$_clientRequestId',
                [photo],
                onProgress: (p) {
                  if (mounted) setState(() => _uploadProgress = p);
                },
              );
          _uploadedPhoto = photo;
          _photoUrl = urls.firstOrNull;
        }
        photoUrl = _photoUrl;
      }
      if (mounted) setState(() => _uploadProgress = null);
      final phone = _recipientPhone.text.trim();
      final placed = await ref.read(giftCardsRepositoryProvider).purchase(GiftCardPurchase(
            clientRequestId: _clientRequestId,
            templateId: template.id,
            amount: amount,
            recipientName: _recipientName.text,
            recipientPhone: phone.isEmpty ? null : Validators.e164(phone, _country),
            recipientEmail: _recipientEmail.text,
            message: _message.text,
            photoUrl: photoUrl,
            scheduledAt: _scheduled && _sendDate != null ? GiftCardSchedule.sendAt(_sendDate!) : null,
            paymentMethod: method,
            addressId: method == PaymentMethod.cashOnDelivery ? address?.id : null,
          ));
      unawaited(analytics.log(AnalyticsEvents.purchase, {
        'currency': AppConstants.currencyCode,
        'value': placed.total,
        'transaction_id': placed.orderNumber.isEmpty ? placed.orderId : placed.orderNumber,
        'item_category': 'gift_card',
      }));
      router.go(AppRoutes.orderSuccessFor(placed.orderId));
    } on OrderFailure catch (failure) {
      if (!mounted) return;
      showOrderSnack(context, switch (failure.reason) {
        OrderFailureReason.unavailable => l10n.orderFailedUnavailable,
        OrderFailureReason.insufficientFunds => l10n.walletInsufficient,
        _ => l10n.somethingWentWrong,
      });
    } catch (_) {
      if (mounted) showOrderSnack(context, _uploadProgress != null ? l10n.photoUploadFailed : l10n.somethingWentWrong);
    } finally {
      if (mounted) {
        setState(() {
          _paying = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(giftCardTemplatesProvider);

    Widget body;
    Widget? bar;
    if (async.hasError && !async.hasValue) {
      body = CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(giftCardTemplatesProvider)));
    } else if (!async.hasValue) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: Column(
          children: [
            AspectRatio(aspectRatio: 1.6, child: SkeletonLoader.box(radius: AppRadius.lg)),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.box(height: 120, radius: AppRadius.lg),
          ],
        ),
      );
    } else {
      final templates = async.requireValue;
      final template = templates.where((t) => t.id == _templateId).firstOrNull;
      if (template == null) {
        body = CenteredScroll(
          child: EmptyState(
            key: const ValueKey('designer-not-found'),
            title: l10n.giftCardUnavailable,
            icon: Icons.card_giftcard_rounded,
            ctaLabel: l10n.giftCardShopTitle,
            onCta: () => context.pushReplacement(AppRoutes.giftCardsShop),
          ),
        );
      } else {
        _initAmount(template);
        final content = _content(context, l10n, templates, template);
        body = content.$1;
        bar = content.$2;
      }
    }

    return PopScope(
      canPop: !_paying,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: GGAppBar(title: l10n.giftCardDesignerTitle),
        body: body,
        bottomNavigationBar: bar,
      ),
    );
  }

  (Widget, Widget) _content(
    BuildContext context,
    AppLocalizations l10n,
    List<GiftCardTemplateModel> templates,
    GiftCardTemplateModel template,
  ) {
    final now = ref.watch(checkoutClockProvider)();
    final payments = ref.watch(paymentSettingsProvider).valueOrNull ?? const PaymentSettings();
    final wallet = ref.watch(walletProvider).valueOrNull ?? WalletModel.empty;
    final defaultAddress = ref.watch(defaultAddressProvider);
    final addresses = ref.watch(addressesProvider).valueOrNull ?? const <AddressModel>[];
    final cities = ref.watch(citiesProvider).valueOrNull ?? const <CityModel>[];

    final amount = _amountFor(template);
    final amountOk = amount != null && template.accepts(amount);
    final walletCovers = amountOk && wallet.balance >= amount;

    // Payment: cash on delivery and / or the wallet balance, as enabled in
    // app_settings/payments; the wallet only when its balance covers the card.
    final methods = [
      if (payments.cashOnDelivery) PaymentMethod.cashOnDelivery,
      if (payments.wallet) PaymentMethod.wallet,
    ];
    bool usable(PaymentMethod m) => m != PaymentMethod.wallet || walletCovers;
    final method = methods.contains(_method) && usable(_method) ? _method : methods.where(usable).firstOrNull;

    final picked = _address;
    final address = picked == null ? defaultAddress : (addresses.where((a) => a.id == picked.id).firstOrNull ?? picked);

    final name = template.name.of(context);
    final photo = _photo;

    final list = ListView(
      key: const ValueKey('designer-list'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.lg),
      children: [
        // Live preview.
        AnimatedBuilder(
          animation: Listenable.merge([_customAmount, _recipientName, _message]),
          builder: (context, _) {
            final a = _amountFor(template);
            return GiftCardFace(
              key: const ValueKey('designer-preview'),
              gradient: templateGradient(template),
              title: name.isEmpty ? l10n.giftCards : name,
              amount: a == null ? null : CurrencyFormatter.format(a),
              artworkUrl: template.artworkUrl,
              photo: photo == null ? null : MemoryImage(photo.bytes),
              recipient: _recipientName.text,
              message: _message.text,
            );
          },
        ),
        if (templates.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          _DesignSwatches(templates: templates, selectedId: template.id, onSelected: _selectTemplate),
        ],
        const SizedBox(height: AppSpacing.md),
        _amountSection(l10n, template),
        const SizedBox(height: AppSpacing.md),
        OrderSection(
          title: '${l10n.giftCardPhotoTitle} ${l10n.optionalLabel}',
          icon: Icons.photo_outlined,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: PickedPhotosField(
              keyPrefix: 'designer-photo',
              photos: [if (photo != null) photo],
              max: 1,
              enabled: !_paying,
              onAdd: (p) => setState(() => _photo = p),
              onRemove: (_) => setState(() => _photo = null),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OrderSection(
          title: l10n.giftCardMessageTitle,
          icon: Icons.edit_note_rounded,
          child: GGInput(
            key: const ValueKey('designer-message'),
            hint: l10n.giftMessageHint,
            controller: _message,
            multiline: true,
            minLines: 3,
            maxLines: 6,
            maxLength: GiftCardPurchase.maxMessage,
            showCounter: true,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _recipientSection(l10n),
        const SizedBox(height: AppSpacing.md),
        _whenSection(l10n, now),
        const SizedBox(height: AppSpacing.md),
        if (methods.isNotEmpty)
          _paymentSection(
            l10n,
            methods: methods,
            method: method,
            walletCovers: walletCovers,
            wallet: wallet,
            address: address,
            cityName: address == null ? '' : cityDisplayName(context, cities, address.city),
          ),
      ],
    );

    final bar = _BuyBar(
      total: amountOk ? amount : null,
      paying: _paying,
      uploadProgress: _uploadProgress,
      onPressed: () => _buy(template: template, address: address, method: method, now: now),
    );
    return (list, bar);
  }

  Widget _amountSection(AppLocalizations l10n, GiftCardTemplateModel t) {
    return OrderSection(
      title: l10n.giftCardAmountTitle,
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final a in t.presetAmounts)
                CategoryChip(
                  key: ValueKey('amount-chip-$a'),
                  label: CurrencyFormatter.format(a),
                  selected: !_custom && _preset == a,
                  onTap: () => setState(() {
                    _custom = false;
                    _preset = a;
                    _errors = {..._errors, _F.amount: null};
                  }),
                ),
              if (t.allowsCustomAmount)
                CategoryChip(
                  key: const ValueKey('amount-chip-custom'),
                  label: l10n.giftCardCustomAmount,
                  icon: Icons.edit_outlined,
                  selected: _custom,
                  onTap: () => setState(() {
                    _custom = true;
                    _errors = {..._errors, _F.amount: null};
                  }),
                ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            GGInput(
              key: const ValueKey('custom-amount'),
              hint: l10n.giftCardAmountHint(CurrencyFormatter.format(t.minAmount), CurrencyFormatter.format(t.maxAmount)),
              controller: _customAmount,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                LengthLimitingTextInputFormatter(9),
              ],
              suffix: Text(
                AppConstants.currencyCode,
                style: AppTextStyles.label.copyWith(color: AppColors.textMuted(context)),
              ),
              errorText: _errors[_F.amount],
              onChanged: (_) => _clear(_F.amount),
            ),
          ] else if (_errors[_F.amount] != null)
            CheckoutErrorLine(key: const ValueKey('amount-error'), message: _errors[_F.amount]!),
        ],
      ),
    );
  }

  Widget _recipientSection(AppLocalizations l10n) {
    return OrderSection(
      title: l10n.giftCardRecipientTitle,
      icon: Icons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GGInput(
            key: const ValueKey('recipient-name'),
            label: l10n.recipientName,
            hint: l10n.enterYourName,
            controller: _recipientName,
            textCapitalization: TextCapitalization.words,
            errorText: _errors[_F.recipientName],
            onChanged: (_) => _clear(_F.recipientName),
          ),
          const SizedBox(height: AppSpacing.md),
          PhoneField(
            key: const ValueKey('recipient-phone'),
            label: '${l10n.giftCardRecipientPhone} ${l10n.optionalLabel}',
            controller: _recipientPhone,
            country: _country,
            errorText: _errors[_F.phone],
            onCountryChanged: (c) => setState(() {
              _country = c;
              _errors = {..._errors, _F.phone: null};
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          GGInput(
            key: const ValueKey('recipient-email'),
            label: '${l10n.email} ${l10n.optionalLabel}',
            hint: l10n.enterYourEmail,
            controller: _recipientEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            errorText: _errors[_F.email],
            onChanged: (_) {
              _clear(_F.email);
              _clear(_F.contact);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_errors[_F.contact] != null)
            CheckoutErrorLine(key: const ValueKey('contact-error'), message: _errors[_F.contact]!)
          else
            Text(
              l10n.giftCardContactHint,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
            ),
        ],
      ),
    );
  }

  Widget _whenSection(AppLocalizations l10n, DateTime now) {
    final date = _sendDate;
    return OrderSection(
      title: l10n.giftCardWhenTitle,
      icon: Icons.schedule_send_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CategoryChip(
                key: const ValueKey('send-now'),
                label: l10n.giftCardSendNow,
                icon: Icons.send_rounded,
                selected: !_scheduled,
                onTap: () => setState(() {
                  _scheduled = false;
                  _errors = {..._errors, _F.schedule: null};
                }),
              ),
              CategoryChip(
                key: const ValueKey('send-scheduled'),
                label: l10n.giftCardSchedule,
                icon: Icons.event_outlined,
                selected: _scheduled,
                onTap: () {
                  final wasScheduled = _scheduled;
                  setState(() => _scheduled = true);
                  if (!wasScheduled && _sendDate == null) unawaited(_pickDate(now));
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          if (_scheduled)
            GGInput(
              key: ValueKey('schedule-date-${date == null ? '' : AppDates.isoDate(date)}'),
              label: l10n.giftCardSendOn,
              hint: l10n.selectADate,
              initialValue: date == null ? '' : AppDates.display(date),
              readOnly: true,
              onTap: () => _pickDate(now),
              errorText: _errors[_F.schedule],
              suffix: Icon(Icons.calendar_month_outlined, color: AppColors.gold(context)),
            )
          else
            Text(
              l10n.giftCardSendNowNote,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
            ),
        ],
      ),
    );
  }

  Widget _paymentSection(
    AppLocalizations l10n, {
    required List<PaymentMethod> methods,
    required PaymentMethod? method,
    required bool walletCovers,
    required WalletModel wallet,
    required AddressModel? address,
    required String cityName,
  }) {
    final muted = AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context));
    return OrderSection(
      title: l10n.paymentMethod,
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<PaymentMethod>(
            groupValue: method,
            onChanged: (m) {
              if (m != null) setState(() => _method = m);
            },
            child: Column(
              children: [
                for (final m in methods)
                  Opacity(
                    opacity: m == PaymentMethod.wallet && !walletCovers ? 0.5 : 1,
                    child: RadioListTile<PaymentMethod>(
                      key: ValueKey('payment-${m.name}'),
                      value: m,
                      enabled: m != PaymentMethod.wallet || walletCovers,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        m == PaymentMethod.wallet ? Icons.account_balance_wallet_outlined : Icons.payments_outlined,
                        color: AppColors.gold(context),
                      ),
                      title: Text(
                        m == PaymentMethod.wallet ? l10n.giftCardWalletBalance : paymentMethodLabel(l10n, m),
                        style: AppTextStyles.label.copyWith(fontSize: 15, color: AppColors.text(context)),
                      ),
                      subtitle: m == PaymentMethod.wallet
                          ? Text(
                              walletCovers
                                  ? l10n.giftCardWalletNote(CurrencyFormatter.format(wallet.balance))
                                  : l10n.giftCardWalletShort(CurrencyFormatter.format(wallet.balance)),
                              key: const ValueKey('wallet-note'),
                              style: muted,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          if (method == PaymentMethod.cashOnDelivery) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBanner(message: l10n.giftCardCodNote, icon: Icons.local_shipping_outlined),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            if (address == null)
              OutlineButton(
                key: const ValueKey('designer-add-address'),
                label: l10n.addAddress,
                icon: Icons.add_location_alt_outlined,
                onPressed: _addAddress,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AddressCard(
                      key: ValueKey('designer-address-${address.id}'),
                      address: address,
                      cityName: cityName,
                      outlined: false,
                      showDefaultChip: false,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('change-address'),
                    onPressed: _changeAddress,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.goldText(context),
                      minimumSize: const Size.square(AppSpacing.minTapTarget),
                    ),
                    child: Text(l10n.changeAddress),
                  ),
                ],
              ),
            if (_errors[_F.address] != null)
              CheckoutErrorLine(key: const ValueKey('address-error'), message: _errors[_F.address]!),
          ],
        ],
      ),
    );
  }
}

/// "Card design": one gradient circle per template.
class _DesignSwatches extends StatelessWidget {
  const _DesignSwatches({required this.templates, required this.selectedId, required this.onSelected});

  final List<GiftCardTemplateModel> templates;
  final String selectedId;
  final ValueChanged<GiftCardTemplateModel> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.giftCardDesignTitle, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            itemBuilder: (context, i) {
              final t = templates[i];
              final selected = t.id == selectedId;
              final gradient = templateGradient(t);
              return Semantics(
                button: true,
                selected: selected,
                label: t.name.of(context),
                excludeSemantics: true,
                child: InkResponse(
                  key: ValueKey('template-swatch-${t.id}'),
                  onTap: () => onSelected(t),
                  radius: 26,
                  child: Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.gold(context) : AppColors.line(context),
                        width: selected ? 2.4 : 1,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
                      child: selected
                          ? Icon(Icons.check_rounded, size: 22, color: giftCardForeground(gradient))
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BuyBar extends StatelessWidget {
  const _BuyBar({required this.total, required this.paying, required this.uploadProgress, required this.onPressed});

  final int? total;
  final bool paying;
  final double? uploadProgress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border(top: BorderSide(color: AppColors.line(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.sm + AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (uploadProgress != null) ...[
                UploadProgressLine(progress: uploadProgress!),
                const SizedBox(height: AppSpacing.xs),
              ] else if (total != null)
                AmountRow(label: l10n.total, amount: total!, emphasized: true),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                key: const ValueKey('designer-buy'),
                label: l10n.giftCardBuy,
                icon: Icons.card_giftcard_rounded,
                isLoading: paying,
                onPressed: onPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
