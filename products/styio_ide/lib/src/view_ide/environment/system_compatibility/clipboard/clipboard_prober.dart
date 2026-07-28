import 'clipboard_facts.dart';

abstract class ClipboardProber {
  Future<ClipboardFacts> probe();
}

class StaticClipboardProber implements ClipboardProber {
  const StaticClipboardProber(this.facts);
  final ClipboardFacts facts;
  @override
  Future<ClipboardFacts> probe() async => facts;
}
