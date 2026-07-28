class SelectionState {
  const SelectionState({
    required this.baseOffset,
    required this.extentOffset,
  });

  const SelectionState.collapsed(int offset)
      : baseOffset = offset,
        extentOffset = offset;

  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;
}
