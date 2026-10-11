import 'package:flutter/material.dart';
import '../../features/inventory/presentation/controllers/inventory_notifier.dart';

/// InheritedWidget providing [InventoryNotifier] down the widget tree.
class InventoryProvider extends InheritedNotifier<InventoryNotifier> {
  const InventoryProvider({
    super.key,
    required InventoryNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static InventoryNotifier? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<InventoryProvider>();
    return provider?.notifier;
  }

  static InventoryNotifier of(BuildContext context) {
    final notifier = maybeOf(context);
    assert(notifier != null, 'No InventoryProvider found in context');
    return notifier!;
  }
}
