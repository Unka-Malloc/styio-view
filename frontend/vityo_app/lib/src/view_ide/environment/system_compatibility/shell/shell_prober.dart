import 'shell_facts.dart';

abstract class ShellProber {
  Future<ShellFacts> probe();
}

class StaticShellProber implements ShellProber {
  const StaticShellProber(this.facts);

  final ShellFacts facts;

  @override
  Future<ShellFacts> probe() async {
    return facts;
  }
}
