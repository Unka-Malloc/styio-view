import 'process_facts.dart';

abstract class ProcessProber {
  Future<ProcessFacts> probe();
}

class StaticProcessProber implements ProcessProber {
  const StaticProcessProber(this.facts);
  final ProcessFacts facts;
  @override
  Future<ProcessFacts> probe() async => facts;
}
