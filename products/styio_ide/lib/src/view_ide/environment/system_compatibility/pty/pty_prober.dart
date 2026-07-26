import 'pty_facts.dart';

abstract class PtyProber {
  Future<PtyFacts> probe();
}

class StaticPtyProber implements PtyProber {
  const StaticPtyProber(this.facts);

  final PtyFacts facts;

  @override
  Future<PtyFacts> probe() async {
    return facts;
  }
}
