import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';

/// Tastierino numerico stile "calcolatrice": ogni cifra digitata entra da
/// destra nei centesimi (es. premendo 4-2-8-0 si ottiene 42,80 €).
///
/// Obiettivo di design (v. progettazione): 3-4 tap per inserire un importo.
/// Su desktop supporta anche la tastiera fisica (cifre della riga numerica
/// e del tastierino numerico, Backspace/Canc per cancellare).
class AmountKeypad extends StatefulWidget {
  const AmountKeypad({super.key, required this.onChanged, this.initialAmount});

  final ValueChanged<double> onChanged;

  /// Importo iniziale (es. in modifica di un'operazione esistente).
  final double? initialAmount;

  @override
  State<AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<AmountKeypad> {
  late String _cents;
  final _focusNode = FocusNode(debugLabel: 'AmountKeypad');

  @override
  void initState() {
    super.initState();
    final cents = ((widget.initialAmount ?? 0) * 100).round();
    _cents = cents <= 0 ? '0' : cents.toString();
  }

  static final _digitKeys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  double get _amount => int.parse(_cents) / 100;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final digit = _digitKeys[event.logicalKey];
    if (digit != null) {
      _pressDigit(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _pressDigit(String digit) {
    // Riporta il focus da tastiera sul keypad, utile se l'utente ha appena
    // toccato un pulsante a schermo dopo aver digitato in un altro campo.
    _focusNode.requestFocus();
    setState(() {
      // Limite: 999.999,99 € (7 cifre), più che sufficiente per finanze personali.
      if (_cents == '0') {
        _cents = digit;
      } else if (_cents.length < 8) {
        _cents += digit;
      }
    });
    widget.onChanged(_amount);
  }

  void _backspace() {
    _focusNode.requestFocus();
    setState(() {
      _cents = _cents.length > 1 ? _cents.substring(0, _cents.length - 1) : '0';
    });
    widget.onChanged(_amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      // I pulsanti a schermo non devono rubare il focus da tastiera: così
      // dopo un tap resta comunque possibile digitare con i tasti fisici.
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppFormatters.currency(_amount),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          _buildRow(['', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 72, height: 56);
        }
        if (key == 'back') {
          return _KeypadButton(
            onTap: _backspace,
            child: const Icon(Icons.backspace_outlined),
          );
        }
        return _KeypadButton(
          onTap: () => _pressDigit(key),
          child: Text(key, style: const TextStyle(fontSize: 22)),
        );
      }).toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}
