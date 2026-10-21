import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Entrada de código OTP de 6 casillas independientes (spec §6.9).
///
/// - 6 casillas de 44x54px con tipografía monoespaciada de 22px bold.
/// - Animación de sacudida lateral cuando el código es incorrecto.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final bool enabled;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _shakeController;
  bool _isShaking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _isShaking = false);
        }
      });
    _controller.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant OtpCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      _triggerShake();
    }
  }

  void _handleChanged() {
    final value = _controller.text;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _triggerShake() {
    if (_isShaking) return;
    setState(() => _isShaking = true);
    _shakeController.forward(from: 0);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final offset = _isShaking
            ? math.sin(_shakeController.value * math.pi * 6) * 8 *
                (1 - _shakeController.value)
            : 0.0;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(widget.length, (index) {
                    final char = index < _controller.text.length
                        ? _controller.text[index]
                        : '';
                    return _OtpBox(
                      digit: char,
                      isFocused: _focusNode.hasFocus && index == _controller.text.length,
                      hasError: widget.hasError,
                    );
                  }),
                ),
                // Campo invisible que captura la escritura real.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(widget.length),
                      ],
                      style: const TextStyle(color: Colors.transparent),
                      cursorColor: Colors.transparent,
                      onTapOutside: (_) => _focusNode.unfocus(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.digit,
    required this.isFocused,
    required this.hasError,
  });

  final String digit;
  final bool isFocused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.danger
        : isFocused
            ? AppColors.accent
            : AppColors.border;

    return Container(
      width: 44,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: borderColor, width: isFocused ? 1.5 : 1),
      ),
      child: Text(
        digit,
        style: AppTextStyles.mono(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: hasError ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
    );
  }
}
