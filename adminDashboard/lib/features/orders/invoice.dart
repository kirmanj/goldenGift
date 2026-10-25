import 'dart:convert';

import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/core/utils/currency_formatter.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/order_model.dart';

import '../../core/web/browser.dart';

/// Printable invoice / packing slip (SRS §9 Orders: "print invoice (hides
/// prices when hidePrices)"). Pure HTML string — unit-tested — plus a tiny
/// browser helper that opens it and triggers the print dialog.
String invoiceHtml(OrderModel order, {required String cityName, String storeName = 'Golden Gift'}) {
  final hide = order.hidePrices;
  const esc = HtmlEscape();
  String money(int v) => esc.convert(CurrencyFormatter.format(v));
  String selection(CartSelection s) {
    final value = s.valueLabel?.en ?? s.text ?? (s.date != null ? AppDates.display(s.date!) : null) ??
        (s.urls.isNotEmpty ? '${s.urls.length} photo(s)' : '');
    return '${esc.convert(s.label.en)}: ${esc.convert(value)}';
  }

  final rows = StringBuffer();
  for (final item in order.items) {
    final l = item.line;
    rows.write('<tr><td><strong>${esc.convert(l.titleSnapshot.en)}</strong>');
    if (l.selections.isNotEmpty) {
      rows.write('<div class="sel">${l.selections.map(selection).join(' · ')}</div>');
    }
    rows.write('</td><td class="num">${l.qty}</td>');
    if (!hide) rows.write('<td class="num">${money(l.unitPrice)}</td><td class="num">${money(l.lineTotal)}</td>');
    rows.write('</tr>');
  }
  final a = order.address;
  final totals = hide
      ? ''
      : '''
<table class="totals">
<tr><td>Subtotal</td><td class="num">${money(order.subtotal)}</td></tr>
${order.discount > 0 ? '<tr><td>Discount${order.promoCode == null ? '' : ' (${esc.convert(order.promoCode!)})'}</td><td class="num">−${money(order.discount)}</td></tr>' : ''}
<tr><td>Delivery</td><td class="num">${money(order.deliveryFee)}</td></tr>
${order.creditsUsed > 0 ? '<tr><td>Credits</td><td class="num">−${money(order.creditsUsed)}</td></tr>' : ''}
${order.walletUsed > 0 ? '<tr><td>Wallet</td><td class="num">−${money(order.walletUsed)}</td></tr>' : ''}
<tr class="grand"><td>Total (${esc.convert(order.paymentMethod.name)})</td><td class="num">${money(order.total)}</td></tr>
</table>''';
  return '''<!doctype html><html><head><meta charset="utf-8"><title>${esc.convert(order.orderNumber)}</title>
<style>
body{font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;margin:32px;color:#1E1E2A}
h1{margin:0;color:#9C7A14}.muted{color:#6B6F80}
table{width:100%;border-collapse:collapse;margin-top:16px}
th,td{padding:8px;border-bottom:1px solid #E6E3D8;text-align:start;vertical-align:top}
.num{text-align:end;white-space:nowrap}.sel{color:#6B6F80;font-size:12px;margin-top:4px}
.totals{width:320px;margin-inline-start:auto}.grand td{font-weight:700;border-top:2px solid #1E1E2A}
.gift{margin-top:16px;padding:12px;border:1px dashed #C9A227;border-radius:8px}
@media print{body{margin:12mm}}
</style></head><body>
<h1>${esc.convert(storeName)}</h1>
<p class="muted">${hide ? 'Packing slip' : 'Invoice'} · ${esc.convert(order.orderNumber)}${order.createdAt == null ? '' : ' · ${AppDates.display(order.createdAt!)}'}</p>
<h3>Deliver to</h3>
<p>${esc.convert(a?.name ?? '')} · ${esc.convert(a?.phone ?? '')}<br>${esc.convert(cityName)} — ${esc.convert(a?.oneLine ?? '')}${(a?.notes.isNotEmpty ?? false) ? '<br><em>${esc.convert(a!.notes)}</em>' : ''}</p>
<p class="muted">Delivery: ${order.deliveryDate == null ? '—' : AppDates.display(order.deliveryDate!)}${order.deliverySlot == null ? '' : ' · ${esc.convert(order.deliverySlot!)}'}</p>
<table><thead><tr><th>Item</th><th class="num">Qty</th>${hide ? '' : '<th class="num">Price</th><th class="num">Total</th>'}</tr></thead><tbody>$rows</tbody></table>
$totals
${order.isGift && (order.giftMessage?.isNotEmpty ?? false) ? '<div class="gift"><strong>Gift message</strong><br>${esc.convert(order.giftMessage!)}</div>' : ''}
<script>window.onload=function(){window.print();}</script>
</body></html>''';
}

/// Opens the invoice in a new tab and starts printing (web only).
void printInvoice(String html) => openHtmlInNewTab(html);
