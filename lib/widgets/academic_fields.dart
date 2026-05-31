import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AcademicAutocompleteField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final List<String> suggestions;
  final bool isDark;
  final Function(String) onSelected;
  final String? subText;
  final Function(String)? onChanged;
  final bool showSuggestionsOnFocus;

  const AcademicAutocompleteField({
    super.key,
    required this.label,
    required this.controller,
    required this.suggestions,
    required this.isDark,
    required this.onSelected,
    this.subText,
    this.onChanged,
    this.showSuggestionsOnFocus = false,
  });

  @override
  State<AcademicAutocompleteField> createState() => _AcademicAutocompleteFieldState();
}

class _AcademicAutocompleteFieldState extends State<AcademicAutocompleteField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (widget.showSuggestionsOnFocus && _focusNode.hasFocus && widget.controller.text.isEmpty) {
      widget.controller.value = widget.controller.value.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => RawAutocomplete<String>(
            textEditingController: widget.controller,
            focusNode: _focusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return widget.showSuggestionsOnFocus ? widget.suggestions : const Iterable<String>.empty();
              }
              return widget.suggestions.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (val) {
              widget.onSelected(val);
              if (widget.onChanged != null) widget.onChanged!(val);
            },
            fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: TextField(
                  controller: textController,
                  focusNode: focusNode,
                  onTap: () {
                    if (widget.showSuggestionsOnFocus && textController.text.isEmpty) {
                      textController.value = textController.value.copyWith(
                        text: '',
                        selection: const TextSelection.collapsed(offset: 0),
                      );
                    }
                  },
                  onChanged: (val) {
                    if (widget.onChanged != null) widget.onChanged!(val);
                  },
                  style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: widget.isDark ? const Color(0xFF1F1F3D) : Colors.white,
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(
                            option,
                            style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontSize: 14),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.subText != null && widget.subText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              widget.subText!,
              style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          )
        else
          const SizedBox(height: 16),
      ],
    );
  }
}

class SmartPhoneField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final Function(String)? onChanged;
  final Function(bool)? onValidityChanged;
  final String? hintText;

  const SmartPhoneField({
    super.key,
    required this.label,
    required this.controller,
    required this.isDark,
    this.onChanged,
    this.onValidityChanged,
    this.hintText,
  });

  @override
  State<SmartPhoneField> createState() => _SmartPhoneFieldState();
}

class _SmartPhoneFieldState extends State<SmartPhoneField> {
  bool _isValid = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    _internalValidate(widget.controller.text, notify: false);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _formatOnBlur();
    } else {
      _unformatOnFocus();
    }
  }

  void _internalValidate(String value, {bool notify = true}) {
    final cleanValue = value.replaceAll('+254', '0').replaceAll(RegExp(r'\D'), '');
    final valid = cleanValue.length == 10 && (cleanValue.startsWith('07') || cleanValue.startsWith('01'));
    if (_isValid != valid) {
      setState(() {
        _isValid = valid;
      });
      if (notify && widget.onValidityChanged != null) {
        widget.onValidityChanged!(valid);
      }
    }
  }

  void _formatOnBlur() {
    String value = widget.controller.text;
    if (value.startsWith('07') && value.length == 10) {
      widget.controller.text = '+254${value.substring(1)}';
    } else if (value.startsWith('01') && value.length == 10) {
      widget.controller.text = '+254${value.substring(1)}';
    }
    if (widget.onChanged != null) widget.onChanged!(widget.controller.text);
    _internalValidate(widget.controller.text);
  }

  void _unformatOnFocus() {
    String value = widget.controller.text;
    if (value.startsWith('+254')) {
      widget.controller.text = '0${value.substring(4)}';
    }
    if (widget.onChanged != null) widget.onChanged!(widget.controller.text);
    _internalValidate(widget.controller.text);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.isDark ? Colors.white12 : Colors.grey.shade300),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.phone,
            onChanged: (val) {
              _internalValidate(val);
              if (widget.onChanged != null) widget.onChanged!(val);
            },
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              LengthLimitingTextInputFormatter(13),
            ],
            style: TextStyle(
              color: _isValid ? Colors.greenAccent : (widget.isDark ? Colors.redAccent : Colors.red),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: widget.hintText,
              hintStyle: TextStyle(color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.4), fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
